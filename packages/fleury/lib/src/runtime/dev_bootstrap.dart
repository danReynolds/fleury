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
// path. Under a serve/remote handle specifically, `InAppDevReload` provides
// save-to-reload from inside the app when the spawn command itself enabled
// the VM service — flag-origin only, for the same reason a child process
// exists at all (no restart there either: a respawned child would re-dial
// the handle's single-accept socket and wedge the session).
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
/// the belt to that suspender against flag-behavior drift across SDKs.
const String kDevSvcFileEnv = 'FLEURY_DEV_SVC_FILE';

/// The dev supervisor for one `dart run` session.
final class DevBootstrap {
  DevBootstrap._();

  /// Whether this process carries the supervised-child environment marker.
  ///
  /// An env var is a proxy, not proof of a live supervisor: it is inherited
  /// by any process the supervised app spawns, and it stays set if the
  /// supervisor dies. In those edges the restart affordance is a quiet no-op
  /// (the posted event has no subscriber) — accepted, since a fleury app
  /// spawning another fleury app onto the same tty is already out of scope,
  /// and a dead supervisor ends the session anyway (exit-code mirroring).
  static bool get isSupervisedChild =>
      Platform.environment[kDevSupervisorEnv] != null;

  /// Asks the supervisor for a hot restart — the same event
  /// `ext.fleury.restart` posts. Fire-and-forget: a no-op when nobody is
  /// listening (see [isSupervisedChild] for when that can happen; also the
  /// first ~100ms after a (re)spawn, before the supervisor's Extension
  /// subscription lands).
  static void requestRestartFromApp() =>
      developer.postEvent(kRestartRequestedEvent, const {});

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
    if (isSupervisedChild) return false;
    if (!stdout.hasTerminal || !stdin.hasTerminal) return false;
    // A serve/remote handle means a supervisor of a different kind owns this
    // process's lifecycle and its socket accepts exactly one connection.
    // (In-app reload still runs there; see InAppDevReload.)
    if (Platform.environment['FLEURY_HANDLE'] != null) return false;
    if (findImplicitFleuryHandle() != null) return false;
    // Respawning needs a re-runnable entrypoint script. Kernel/AOT
    // snapshots (`dart run app.dill`) are excluded: sources and compiled
    // code can disagree there, and it isn't the dev loop this serves.
    final script = Platform.script;
    if (script.scheme != 'file') return false;
    if (!script.path.endsWith('.dart')) return false;
    if (!File.fromUri(script).existsSync()) return false;
    return true;
  }

  /// Supervised-child side of the service handshake: report this process's
  /// flag-origin VM-service URI to the supervisor's info file.
  ///
  /// Called from runApp when [kDevSupervisorEnv]+[kDevSvcFileEnv] are set;
  /// fire-and-forget (the supervisor polls the file), so app startup is
  /// never delayed. The primary channel is the `--write-service-info` flag
  /// on the spawn; this write is the fallback against that flag's behavior
  /// drifting across SDKs. Deliberately NO `controlWebServer` self-enable
  /// here: if the spawn flags produced no service, a runtime-enabled one
  /// would put every reload on the broken path (see the file header) — a
  /// clean supervisor timeout into the classic no-reload run beats a session
  /// whose reloads crash the kernel service.
  static void maybeStartSupervisedChildHandshake() {
    if (!isSupervisedChild) return;
    final path = Platform.environment[kDevSvcFileEnv];
    if (path == null) return;
    unawaited(() async {
      try {
        final uri = (await developer.Service.getInfo()).serverUri;
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
          try {
            started = await supervisor._superviseFirstChild();
          } finally {
            // A throw above must still release the caller: un-started, it
            // falls through to the classic path (and _dispose reaps any
            // half-spawned child).
            startGate.complete();
          }
          if (!started) return;
          try {
            await supervisor._superviseForever();
          } catch (error, stack) {
            // The loop never returns normally; reaching here means the
            // supervisor itself broke while owning the session. Nobody else
            // watches the child now — end the session restored rather than
            // hang a terminal with no owner.
            _debugLog('supervisor loop died: $error\n$stack');
            final child = supervisor._child;
            if (child != null) {
              child.kill(ProcessSignal.sigkill);
              await child.exitCode;
            }
            await supervisor._emergencyTtyRestore();
            exit(70);
          }
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
      // Whichever child is current now owns the response. Same child: it
      // either handled its own tty copy (exited — kill is a no-op) or never
      // got one (direct kill — forward). Replaced child: the replacement
      // was spawned after the delivery, so it saw nothing — forward, or a
      // kill that raced a restart would be swallowed and the session would
      // outlive it.
      final target = _child;
      if (target == null) return;
      _debugLog('signal ${signal.name}: forwarding to child');
      target.kill(signal);
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
      if (code < 0) {
        // Died by signal (the restart escalation's SIGKILL, or an external
        // kill): raw mode and the alt screen died with it, unrestored.
        // Restore before the respawn so the exit sequences land on the old
        // screen, never on top of the new child's.
        await _emergencyTtyRestore();
      }
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
    final Directory infoDir;
    try {
      infoDir = Directory.systemTemp.createTempSync('fleury_dev_');
    } catch (error) {
      // Disk full / unwritable tmp: a throw here in the respawn path would
      // kill the supervise loop and orphan the session — degrade instead.
      _debugLog('service-info temp dir creation failed: $error');
      return false;
    }
    final infoFile = File('${infoDir.path}/svc.json');
    try {
      final spawned = await _spawnChildInto(infoFile);
      if (!spawned) {
        // Any failure after Process.start leaves a live child that owns the
        // terminal — reap it, or the fallback/exit path runs a second
        // full-screen app against the same tty (or orphans a raw-mode one).
        final child = _child;
        _child = null;
        if (child != null) {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          // It may have died owning raw mode / the alt screen; restore from
          // out here before whoever runs next (the classic fallback or a
          // respawn) touches the terminal.
          await _emergencyTtyRestore();
        }
        await _disconnectVm();
      }
      return spawned;
    } finally {
      // Both URI channels have served their purpose (or failed) by now. The
      // child's own fallback write may land after this; it is wrapped in a
      // best-effort catch on its side.
      try {
        infoDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<bool> _spawnChildInto(File infoFile) async {
    final Process child;
    try {
      child = await Process.start(
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
    _child = child;
    final uri = await _readServiceInfo(infoFile, child);
    if (uri == null) {
      _debugLog('child service info never appeared');
      return false;
    }
    try {
      final vm = await connectVmServiceAt(uri);
      _vm = vm;
      await vm.streamListen(EventStreams.kExtension);
      vm.onExtensionEvent.listen((event) => _onExtensionEvent(vm, event));
      _mainIsolateId = await _findMainIsolate(vm, child);
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
        // Re-check after the await: a respawn during the RPC would otherwise
        // mark the NEW session ready off the OLD isolate's registrations.
        if (!identical(vm, _vm)) return;
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

  Future<Uri?> _readServiceInfo(File infoFile, Process child) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var childExited = false;
    unawaited(child.exitCode.then((_) => childExited = true));
    while (DateTime.now().isBefore(deadline)) {
      // File first: a child that wrote the URI and then crashed still gets
      // its info read (the connect attempt then fails cleanly).
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
      // A child that died before writing the file never will — don't sit
      // out the full window against a corpse.
      if (childExited) {
        _debugLog('child exited before writing service info');
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<String?> _findMainIsolate(VmService vm, Process child) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var childExited = false;
    unawaited(child.exitCode.then((_) => childExited = true));
    while (DateTime.now().isBefore(deadline)) {
      if (childExited) {
        _debugLog('child exited while waiting for its main isolate');
        return null;
      }
      try {
        final isolates = (await vm.getVM()).isolates ?? const [];
        for (final ref in isolates) {
          if (ref.name == 'main') return ref.id;
        }
      } catch (_) {
        // Connection churn (child dying) — the exit check above ends this.
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
    final child = _child;
    if (child == null) {
      // Nothing to kill and no exit for the loop to pick up (a teardown
      // race); leaving the flag set would turn the next real quit into a
      // respawn.
      _restartInFlight = false;
      return;
    }
    // Ask the app to run its normal teardown (terminal restore, stdio
    // capture stop) and exit; _superviseForever picks the exit up and
    // respawns because _restartInFlight is set.
    var requested = false;
    if (vm != null && isolateId != null) {
      try {
        // A wedged child never answers — without the timeout this await
        // would hang the whole restart (flag included) and the kill
        // escalation below would never be reached.
        await vm
            .callServiceExtension('ext.fleury.shutdown', isolateId: isolateId)
            .timeout(const Duration(seconds: 5));
        requested = true;
      } catch (error) {
        _debugLog('restart: graceful request failed: $error');
      }
    }
    if (!requested) {
      _hardKillChild(child);
      return;
    }
    // The request landed but teardown can still stall; escalate. The kill
    // lands only if this exact child is still the live one at the deadline.
    unawaited(
      child.exitCode
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              _debugLog('restart: graceful timeout, killing');
              _hardKillChild(child);
              return -1;
            },
          )
          .then((_) {}),
    );
  }

  void _hardKillChild(Process child) {
    // Only the exact child this restart was driving: a racing respawn may
    // already have replaced it, and the replacement must not be shot.
    if (!identical(_child, child)) return;
    child.kill(ProcessSignal.sigkill);
    // It died raw (capture and termios state die with the process). The tty
    // restore is sequenced in _superviseForever before the respawn — doing
    // it here unawaited could land the exit sequences on top of the next
    // child's freshly entered alt screen.
  }

  // ── Extension events from the child ──────────────────────────────────────

  void _onExtensionEvent(VmService vm, Event event) {
    // Stragglers from a connection the loop already replaced must not drive
    // a restart against the wrong child (worst case: an exit-time event
    // re-arms _restartInFlight and turns the next real quit into a respawn).
    if (!identical(vm, _vm)) return;
    if (event.extensionKind == kRestartRequestedEvent) {
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
    // Normally already exited (loop paths) or never spawned (fall-through);
    // a non-null live child here means a throw interrupted startup — reap
    // it so the classic path doesn't share the tty with it.
    final child = _child;
    _child = null;
    if (child != null) {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
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
/// handle (`fleury serve --spawn`) whose spawn command itself enabled the VM
/// service (e.g. `dart --enable-vm-service=0 run bin/main.dart`). Reloads
/// then flow to the browser preview; a restart stays unavailable (a respawned
/// child would re-dial the handle's single-accept socket and wedge the
/// session).
///
/// Without such a flag there is deliberately no reload: self-enabling the
/// service via `Service.controlWebServer` would put every reload of changed
/// sources on the broken runtime-enabled-service path — kernel-service crash
/// plus an RPC that hangs forever (see the file header and
/// docs/implementation/vm-reload-bug-report-draft.md). No reload beats a
/// reload that wedges on first save.
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
    if (DevBootstrap.isSupervisedChild) return false;
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

    // Flag-origin service only — never controlWebServer (see the class
    // doc: a runtime-enabled service turns the first real save into a
    // kernel-service crash and a hung RPC).
    Uri? serverUri;
    try {
      serverUri = (await developer.Service.getInfo()).serverUri;
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
        // Same supervisor-sanity backstop as DevBootstrap._reload: a wedged
        // reload must not jam the save queue silently forever.
        final report = await vm
            .reloadSources(selfId!)
            .timeout(const Duration(seconds: 30));
        success = report.success ?? false;
        final json = report.json;
        final details = json == null ? null : json['details'];
        if (details is Map && details['loadedLibraryCount'] is int) {
          loadedCount = details['loadedLibraryCount'] as int;
        }
        if (!success && json != null) {
          message = DevBootstrap.rejectionMessage(json) ?? 'reload rejected';
        }
      } on TimeoutException {
        message = 'reload timed out after 30s';
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
