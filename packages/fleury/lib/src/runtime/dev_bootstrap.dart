// Dev supervisor: self-hosting hot reload + hot restart for plain `dart run`
// sessions — no editor, no CLI wrapper, no flags.
//
// Shape (the flutter_tools architecture, folded into the first process):
//
//   dart run bin/main.dart
//     └─ runApp() ─▶ [gate] ─▶ supervisor (this file, in the original process)
//                                ├─ re-spawns the SAME script as a child
//                                │  process with the VM service enabled
//                                │  (inheritStdio: the child owns the PTY)
//                                ├─ watches the package sources and calls
//                                │  reloadSources(child main isolate) on save
//                                └─ restarts by asking the child to tear down
//                                   gracefully, then respawning it — fresh
//                                   state, same terminal session
//
// The child re-enters runApp, sees a live VM service plus the supervisor
// marker, and proceeds as a normal single-isolate Fleury app — the exact
// battle-tested F5 shape, where reload means "reload the main isolate group
// of a plain app". That path is exercised daily by editors.
//
// Why a child PROCESS at all: reloadSources with actually-changed sources is
// broken whenever the VM service was enabled at runtime via
// Service.controlWebServer — the VM's kernel service crashes ("Bad state: No
// element" in lookupOrBuildNewIncrementalCompiler) and the reload RPC hangs
// forever (minimal plain-Dart repro, no Fleury involved; see
// docs/implementation/vm-reload-bug-report-draft.md, same crash signature as
// dart-lang/sdk#54905). A running process can never retroactively gain
// `--enable-vm-service` flags, so any in-process design (self-reload, or a
// child isolate — which shares the process's service) is unfixably on the
// broken path. Spawning a fresh process is precisely what makes flag-origin
// service — the working path — possible.
//
// Ownership rules (process edition):
//   - The child owns the terminal: raw mode, alt screen, stdin, stdio
//     capture, and SIGINT/SIGTERM/SIGWINCH handling.
//   - The supervisor swallows its own tty signal deliveries while the child
//     runs (both live in the foreground process group), writes nothing to
//     the terminal, and propagates the child's exit code as its own.
//   - After a hard kill (a wedged child), the child's dup2 capture and raw
//     mode die with its process, so the supervisor can safely restore the
//     terminal from outside and respawn.
//
// When the supervisor cannot run (Windows, AOT, no TTY, a serve/remote
// handle, an injected test driver, a pre-existing VM service — an editor or
// tool that owns reload), runApp falls through to the classic single-isolate
// path. Under a serve/remote handle specifically, `InAppDevReload` still
// provides save-to-reload from inside the app (no restart: a respawned child
// would re-dial the handle's single-accept socket and wedge the session).
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:vm_service/vm_service.dart' hide Isolate;

import '../terminal/terminal_driver.dart' show TerminalMode;
import '../terminal/terminal_sequences.dart';
import 'handle_discovery.dart';
import 'hot_reload.dart';
import 'source_watcher.dart';

/// Environment marker set for the supervised child so it can gate the
/// supervisor off synchronously (belt to the async VM-service check's
/// suspenders).
const String kDevSupervisorEnv = 'FLEURY_DEV_SUPERVISED';

/// Environment variable carrying the path where the supervised child
/// confirms its VM-service URI (JSON `{"uri": …}`). The primary channel is
/// the `--write-service-info` VM flag on the spawn; this child-side write is
/// the belt to that suspender (and self-enables via `controlWebServer` only
/// if the flag somehow produced no service).
const String kDevSvcFileEnv = 'FLEURY_DEV_SVC_FILE';

/// The dev supervisor for one `dart run` session.
final class DevBootstrap {
  DevBootstrap._();

  VmService? _vm;
  Process? _child;
  String? _mainIsolateId;
  SourceWatcher? _watcher;
  final List<StreamSubscription<ProcessSignal>> _signalSubs = [];
  bool _restartInFlight = false;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;
  // Reloading a child that is still starting up (terminal enter sequences,
  // probes, fd capture) can wedge the whole reload operation, so saves are
  // queued until the app's hot-reload extension appears — registered only
  // after the first frame is mounted. Also absorbs spurious watcher events
  // replayed at startup (FSEvents can deliver just-past history).
  bool _childReady = false;

  /// Synchronous pre-gate: whether this run could possibly be a supervised
  /// dev session. MUST stay synchronous — runApp executes it before its
  /// first await, so every excluded run (tests with injected drivers, AOT,
  /// Windows, no TTY, serve handles, supervised children) keeps runApp's
  /// original synchronous prefix, microtask-for-microtask.
  ///
  /// Everything here must stay conservative: any "no" falls back to the
  /// classic, battle-tested single-isolate path.
  static bool shouldConsider({
    required bool driverInjected,
    required bool enableHotReload,
  }) {
    if (driverInjected || !enableHotReload) return false;
    if (const bool.fromEnvironment('dart.vm.product')) return false;
    if (Platform.isWindows) return false;
    if (Platform.environment['FLEURY_HOT_RELOAD'] == '0') return false;
    if (Platform.environment[kDevSupervisorEnv] != null) return false;
    if (!stdout.hasTerminal || !stdin.hasTerminal) return false;
    // A serve/remote handle means a supervisor of a different kind owns this
    // process's lifecycle and its socket accepts exactly one connection.
    // (In-app reload still runs there; see InAppDevReload.)
    if (Platform.environment['FLEURY_HANDLE'] != null) return false;
    if (findImplicitFleuryHandle() != null) return false;
    // Respawning needs a re-runnable entrypoint script.
    final script = Platform.script;
    if (script.scheme != 'file') return false;
    if (!File.fromUri(script).existsSync()) return false;
    return true;
  }

  /// Supervised-child side of the service handshake: silently self-enable
  /// the VM service and report its URI to the supervisor's info file.
  ///
  /// Called from runApp when [kDevSupervisorEnv]+[kDevSvcFileEnv] are set;
  /// fire-and-forget (the supervisor polls the file), so app startup is
  /// never delayed. Doing this child-side — instead of spawning with
  /// `--enable-vm-service` — keeps the VM's startup banner off the terminal
  /// entirely.
  static void maybeStartSupervisedChildHandshake() {
    if (Platform.environment[kDevSupervisorEnv] == null) return;
    final path = Platform.environment[kDevSvcFileEnv];
    if (path == null) return;
    unawaited(() async {
      try {
        var uri = (await developer.Service.getInfo()).serverUri;
        uri ??= (await developer.Service.controlWebServer(
          enable: true,
          silenceOutput: true,
        )).serverUri;
        if (uri == null) return;
        File(path).writeAsStringSync(jsonEncode({'uri': uri.toString()}));
      } catch (_) {
        // Best-effort: without the handshake the supervisor gives up after
        // its poll window and the app still runs (without reload).
      }
    }());
  }

  /// Runs the supervisor. Returns normally ONLY when this run turns out to
  /// be ineligible after the async checks or the first child could not be
  /// started (callers then proceed with the classic path); once supervision
  /// begins, this future never completes — the session ends via `exit()`
  /// with the child's exit code.
  static Future<void> runOrFallThrough() async {
    // A pre-existing VM service means an editor/debugger owns this run (F5,
    // `--enable-vm-service`): its reload/restart tooling is better placed
    // than ours, and a surprise child process would degrade its UX.
    try {
      final info = await developer.Service.getInfo();
      if (info.serverUri != null) return;
    } catch (_) {
      return;
    }

    final supervisor = DevBootstrap._();
    // The whole supervisor runs under one guarded zone: a bug in the dev
    // tooling must never take the session down un-restored.
    var started = false;
    final startGate = Completer<void>();
    unawaited(
      runZonedGuarded(
        () async {
          started = await supervisor._superviseFirstChild();
          startGate.complete();
          if (!started) return;
          await supervisor._superviseForever();
        },
        (error, stack) => _debugLog('uncaught: $error\n$stack'),
      ),
    );
    await startGate.future;
    if (!started) {
      await supervisor._dispose();
      return; // Classic path.
    }
    await Completer<void>().future; // Park the caller (user main) forever.
  }

  // ── Child lifecycle ──────────────────────────────────────────────────────

  Future<bool> _superviseFirstChild() async {
    final spawned = await _spawnChild();
    if (!spawned) return false;
    // Signal ownership. Two delivery shapes reach the supervisor:
    //   - tty-generated (Ctrl+C): the line discipline signals the whole
    //     foreground group, so the child got its own copy — the supervisor
    //     must NOT forward (the driver's second-same-signal contract is an
    //     immediate force-exit, so a duplicate would skip the graceful
    //     path).
    //   - a direct `kill <supervisor-pid>` (scripts, service managers, the
    //     PTY test harness): the child got nothing — the supervisor MUST
    //     forward or the session outlives the kill.
    // The source isn't observable in-process, so infer by outcome: give the
    // child a short grace to exit on its own tty copy; forward only if it's
    // still the same live child afterwards. Cost: a direct kill takes
    // ~300ms longer; a tty Ctrl+C on an app slower than the grace gets the
    // driver's force path (restore + exit 130) instead of app-level
    // teardown — still restored, still the conventional code.
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      try {
        _signalSubs.add(
          signal.watch().listen((_) => _forwardSignalAfterGrace(signal)),
        );
      } catch (_) {}
    }
    final roots = DevSourceRoots.resolve();
    _debugLog('watch roots: ${roots?.directories}');
    if (roots != null && roots.directories.isNotEmpty) {
      _watcher = SourceWatcher(
        roots: roots,
        onChanged: (paths) {
          _debugLog('watcher fired: $paths');
          _reload();
        },
      )..start();
    }
    return true;
  }

  void _forwardSignalAfterGrace(ProcessSignal signal) {
    final childAtDelivery = _child;
    if (childAtDelivery == null) return;
    _debugLog('signal ${signal.name}: delivered, grace started');
    Timer(const Duration(milliseconds: 300), () {
      // Forward only when the exact child from delivery time is still the
      // live one (not exited, not respawned by a racing restart).
      if (!identical(_child, childAtDelivery)) return;
      _debugLog('signal ${signal.name}: forwarding to child');
      childAtDelivery.kill(signal);
    });
  }

  Future<void> _superviseForever() async {
    while (true) {
      final child = _child!;
      final code = await child.exitCode;
      _debugLog('child exited code=$code restart=$_restartInFlight');
      await _disconnectVm();
      if (!_restartInFlight) {
        // A real end of session (quit, Ctrl+C handled by the child, crash):
        // the child restored the terminal on its way out; mirror its code.
        // Death-by-signal surfaces as a negative code from Process.exitCode;
        // translate to the conventional 128+n so callers see e.g. 130, and a
        // signal-killed child may have died raw — restore before leaving.
        await _dispose();
        if (code < 0) {
          await _emergencyTtyRestore();
          exit(128 - code);
        }
        exit(code);
      }
      _restartInFlight = false;
      final spawned = await _spawnChild();
      if (!spawned) {
        await _emergencyTtyRestore();
        await _dispose();
        exit(70);
      }
    }
  }

  Future<bool> _spawnChild() async {
    _childReady = false;
    final infoFile = File(
      '${Directory.systemTemp.createTempSync('fleury_dev_').path}/svc.json',
    );
    try {
      _child = await Process.start(
        Platform.resolvedExecutable,
        [
          // The service MUST come from VM flags: under a runtime-enabled
          // service (`Service.controlWebServer`) any reload of changed
          // sources crashes the VM's kernel service and hangs the RPC — see
          // the file-header note and
          // docs/implementation/vm-reload-bug-report-draft.md. The flag path
          // is what every editor session exercises daily. The cost is the
          // VM's one-line startup banner, which the alt screen hides.
          '--enable-vm-service=0',
          '--no-serve-devtools',
          '--write-service-info=${infoFile.uri}',
          Platform.script.toFilePath(),
          // The original CLI arguments of main() are not recoverable from
          // inside the process; dev respawns re-run the entrypoint without
          // them. (An app that must re-see argv can set FLEURY_HOT_RELOAD=0.)
        ],
        mode: ProcessStartMode.inheritStdio,
        environment: {
          ...Platform.environment,
          kDevSupervisorEnv: '1',
          // Fallback URI channel: the child confirms its service here too
          // (see maybeStartSupervisedChildHandshake), guarding against
          // --write-service-info behavior drift across SDKs.
          kDevSvcFileEnv: infoFile.path,
        },
      );
    } catch (error) {
      _debugLog('spawn failed: $error');
      return false;
    }
    final uri = await _readServiceInfo(infoFile);
    if (uri == null) {
      _debugLog('child service info never appeared');
      return false;
    }
    try {
      final vm = await connectVmServiceAt(uri);
      _vm = vm;
      await vm.streamListen(EventStreams.kExtension);
      vm.onExtensionEvent.listen(_onExtensionEvent);
      _mainIsolateId = await _findMainIsolate(vm);
      _debugLog('child up: service=$uri main=$_mainIsolateId');
      if (_mainIsolateId == null) return false;
      unawaited(_awaitChildReady(vm, _mainIsolateId!));
      return true;
    } catch (error) {
      _debugLog('child service connect failed: $error');
      return false;
    }
  }

  /// Marks the child reload-ready once `ext.fleury.reassemble` is
  /// registered — which happens only after the app's first frame is
  /// mounted — then releases any queued save.
  Future<void> _awaitChildReady(VmService vm, String isolateId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (!identical(vm, _vm)) return; // Superseded by a respawn.
      try {
        final isolate = await vm.getIsolate(isolateId);
        final rpcs = isolate.extensionRPCs ?? const [];
        if (rpcs.contains('ext.fleury.reassemble')) {
          _childReady = true;
          _debugLog('child ready (hot-reload extension registered)');
          if (_reloadQueued) {
            _reloadQueued = false;
            unawaited(_reload());
          }
          return;
        }
      } catch (_) {
        // Transient (isolate mid-boot) — keep polling until the deadline.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _debugLog('child never became reload-ready');
  }

  Future<Uri?> _readServiceInfo(File infoFile) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      if (infoFile.existsSync()) {
        try {
          final decoded =
              jsonDecode(infoFile.readAsStringSync()) as Map<String, Object?>;
          final uri = decoded['uri'];
          if (uri is String) return Uri.parse(uri);
        } catch (_) {
          // Partially written — retry.
        }
      }
      // A child that died before writing the file will never write it.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<String?> _findMainIsolate(VmService vm) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      final isolates = (await vm.getVM()).isolates ?? const [];
      for (final ref in isolates) {
        if (ref.name == 'main') return ref.id;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _disconnectVm() async {
    final vm = _vm;
    _vm = null;
    _mainIsolateId = null;
    if (vm != null) {
      try {
        await vm.dispose();
      } catch (_) {}
    }
  }

  // ── Reload ───────────────────────────────────────────────────────────────

  Future<void> _reload() async {
    if (_restartInFlight) return;
    if (!_childReady || _reloadInFlight) {
      _reloadQueued = true; // Coalesce; released on readiness/completion.
      return;
    }
    final isolateId = _mainIsolateId;
    final vm = _vm;
    if (isolateId == null || vm == null) return;
    _reloadInFlight = true;
    _debugLog('reload: starting (isolate $isolateId)');
    final stopwatch = Stopwatch()..start();
    var success = false;
    var loadedCount = 0;
    String? message;
    try {
      // The timeout is a supervisor-sanity backstop: a reload should take
      // well under a second, and a wedged one must not jam the save queue
      // forever (a hot restart can then heal the session).
      final report = await vm
          .reloadSources(isolateId)
          .timeout(const Duration(seconds: 30));
      success = report.success ?? false;
      final json = report.json;
      final details = json == null ? null : json['details'];
      if (details is Map && details['loadedLibraryCount'] is int) {
        loadedCount = details['loadedLibraryCount'] as int;
      }
      if (!success && json != null) {
        message = rejectionMessage(json) ?? 'reload rejected by the VM';
      }
    } on TimeoutException {
      message = 'reload timed out after 30s';
    } on RPCError catch (error) {
      message = error.details?.toString() ?? error.message;
    } catch (error) {
      message = error.toString();
    } finally {
      stopwatch.stop();
      _reloadInFlight = false;
    }
    _debugLog(
      'reload: done success=$success loaded=$loadedCount '
      'elapsedMs=${stopwatch.elapsedMilliseconds} message=$message',
    );
    // Deliver the outcome to the app for the debug shell (Logs on success,
    // Errors on failure). Best-effort: the app may be mid-teardown.
    try {
      await vm.callServiceExtension(
        'ext.fleury.reloadReport',
        isolateId: isolateId,
        args: <String, String>{
          'success': '$success',
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          'loadedLibraryCount': '$loadedCount',
          'message': ?message,
        },
      );
    } catch (_) {}
    if (_reloadQueued) {
      _reloadQueued = false;
      unawaited(_reload());
    }
  }

  /// The VM reports rejection detail under `notices[].message`.
  static String? rejectionMessage(Map<String, Object?> json) {
    final notices = json['notices'];
    if (notices is List) {
      final parts = <String>[
        for (final n in notices)
          if (n is Map && n['message'] is String) n['message'] as String,
      ];
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return null;
  }

  // ── Restart ──────────────────────────────────────────────────────────────

  Future<void> _restart() async {
    if (_restartInFlight) return;
    _restartInFlight = true;
    _debugLog('restart: requested');
    final vm = _vm;
    final isolateId = _mainIsolateId;
    // Ask the app to run its normal teardown (terminal restore, stdio
    // capture stop) and exit; _superviseForever picks the exit up and
    // respawns because _restartInFlight is set.
    var requested = false;
    if (vm != null && isolateId != null) {
      try {
        await vm.callServiceExtension(
          'ext.fleury.shutdown',
          isolateId: isolateId,
        );
        requested = true;
      } catch (error) {
        _debugLog('restart: graceful request failed: $error');
      }
    }
    if (!requested) {
      _hardKillChild();
      return;
    }
    // A wedged child never exits; escalate. The kill lands only if the
    // graceful path stalled — a prompt exit cancels this timer via respawn
    // (which replaces _child) or session end (process gone).
    final child = _child;
    unawaited(
      child?.exitCode
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              _debugLog('restart: graceful timeout, killing');
              _hardKillChild();
              return -1;
            },
          )
          .then((_) {}),
    );
  }

  void _hardKillChild() {
    final child = _child;
    if (child == null) return;
    child.kill(ProcessSignal.sigkill);
    // The child died raw: its capture and termios state died with it. The
    // supervisor's own stdout IS the terminal — restore from here before the
    // respawn re-enters raw mode.
    unawaited(_emergencyTtyRestore());
  }

  // ── Extension events from the child ──────────────────────────────────────

  void _onExtensionEvent(Event event) {
    if (event.extensionKind == 'fleury.restartRequested') {
      unawaited(_restart());
    }
  }

  // ── Emergency restore (POSIX) ────────────────────────────────────────────

  Future<void> _emergencyTtyRestore() async {
    try {
      stdout.write(buildTerminalExitSequences(TerminalMode.interactive));
      await stdout.flush();
    } catch (_) {}
    try {
      final proc = await Process.start(
        'stty',
        const ['sane'],
        mode: ProcessStartMode.inheritStdio,
      );
      await proc.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _dispose() async {
    await _watcher?.dispose();
    _watcher = null;
    for (final sub in _signalSubs) {
      await sub.cancel();
    }
    _signalSubs.clear();
    await _disconnectVm();
  }

  /// Appends to `FLEURY_DEV_BOOTSTRAP_LOG` when set — the supervisor can
  /// never write to the terminal (the app's frames own it), so diagnosis of
  /// the dev tooling itself goes to a side file.
  static void _debugLog(String message) {
    final path = Platform.environment['FLEURY_DEV_BOOTSTRAP_LOG'];
    if (path == null) return;
    try {
      File(path).writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}

/// In-app save-to-reload for sessions where the supervisor must not run but a
/// developer is still iterating — today: apps spawned under a serve/remote
/// handle (`fleury serve --spawn`), where reloads flow to the browser preview
/// but a restart would wedge the single-accept handle socket.
final class InAppDevReload {
  InAppDevReload._(this._vm, this._watcher);

  final VmService _vm;
  final SourceWatcher _watcher;

  /// Synchronous pre-gate — see [DevBootstrap.shouldConsider] for why this
  /// must not suspend: ineligible runs (every test, every non-supervised
  /// session) keep the startup sequence's exact microtask ordering.
  static bool shouldConsider({required bool enableHotReload}) {
    if (!enableHotReload) return false;
    if (const bool.fromEnvironment('dart.vm.product')) return false;
    if (Platform.environment['FLEURY_HOT_RELOAD'] == '0') return false;
    // The supervisor owns reloads for its child.
    if (Platform.environment[kDevSupervisorEnv] != null) return false;
    return Platform.environment['FLEURY_HANDLE'] != null ||
        findImplicitFleuryHandle() != null;
  }

  /// Starts in-app reload when this session qualifies; null otherwise.
  /// Callers gate on [shouldConsider] first.
  static Future<InAppDevReload?> maybeStart({
    required void Function(HotReloadReport report) onReport,
  }) async {
    final roots = DevSourceRoots.resolve();
    if (roots == null || roots.directories.isEmpty) return null;

    Uri? serverUri;
    try {
      serverUri =
          (await developer.Service.getInfo()).serverUri ??
          (await developer.Service.controlWebServer(
            enable: true,
            silenceOutput: true,
          )).serverUri;
    } catch (_) {
      return null;
    }
    if (serverUri == null) return null;

    final VmService vm;
    try {
      vm = await connectVmServiceAt(serverUri);
    } catch (_) {
      return null;
    }
    final String? selfId;
    try {
      selfId = await _mainIsolateIdOf(vm);
    } catch (_) {
      await vm.dispose();
      return null;
    }
    if (selfId == null) {
      await vm.dispose();
      return null;
    }

    var inFlight = false;
    var queued = false;
    Future<void> reload() async {
      if (inFlight) {
        queued = true;
        return;
      }
      inFlight = true;
      final stopwatch = Stopwatch()..start();
      var success = false;
      var loadedCount = 0;
      String? message;
      try {
        final report = await vm.reloadSources(selfId!);
        success = report.success ?? false;
        final json = report.json;
        final details = json == null ? null : json['details'];
        if (details is Map && details['loadedLibraryCount'] is int) {
          loadedCount = details['loadedLibraryCount'] as int;
        }
        if (!success && json != null) {
          message = DevBootstrap.rejectionMessage(json) ?? 'reload rejected';
        }
      } on RPCError catch (error) {
        message = error.details?.toString() ?? error.message;
      } catch (error) {
        message = error.toString();
      } finally {
        stopwatch.stop();
        inFlight = false;
      }
      onReport(
        HotReloadReport(
          success: success,
          elapsed: stopwatch.elapsed,
          loadedLibraryCount: loadedCount,
          message: message,
        ),
      );
      if (queued) {
        queued = false;
        unawaited(reload());
      }
    }

    final watcher = SourceWatcher(roots: roots, onChanged: (_) => reload())
      ..start();
    return InAppDevReload._(vm, watcher);
  }

  /// The current isolate's service id, via the service's own VM listing
  /// (an in-process client can't assume its `Isolate.current` maps 1:1 when
  /// helper isolates share the name — match the actual main isolate).
  static Future<String?> _mainIsolateIdOf(VmService vm) async {
    final isolates = (await vm.getVM()).isolates ?? const [];
    for (final ref in isolates) {
      if (ref.name == 'main') return ref.id;
    }
    return isolates.isEmpty ? null : isolates.first.id;
  }

  Future<void> dispose() async {
    await _watcher.dispose();
    await _vm.dispose();
  }
}
