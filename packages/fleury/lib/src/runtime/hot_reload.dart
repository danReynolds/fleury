// Hot reload integration: registers the `ext.fleury.reassemble` service
// extension and (when --enable-vm-service is present) listens for
// `IsolateReload` events on the VM service. Either trigger calls
// `BuildOwner.reassembleApplication` and re-renders.
//
// The substrate this all rests on was validated by
// `tool/hot_reload_probe` before any framework code shipped. The
// framework piece is the tree walk in `BuildOwner.reassembleApplication`;
// this file is the glue that fires it.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// The service extension can only be registered ONCE per isolate. This
// mutable cell lets each controller be reachable via the same registered
// handler: `attach()` swaps the cell on entry and
// `dispose()` clears it, so a long-lived process with multiple
// successive runs (e.g. a test isolate) sees the right callback for
// the currently-attached controller.
HotReloadController? _activeController;
bool _extensionRegistered = false;

/// The `postEvent` kind that asks a listening dev supervisor for a hot
/// restart. Posted by `ext.fleury.restart` and by the debug shell's F5
/// action; matched by the supervisor's Extension-stream listener. One
/// constant — the match is a silent string compare, so a drifted literal
/// would turn the affordance into a no-op with no error anywhere.
const String kRestartRequestedEvent = 'fleury.restartRequested';

/// Outcome of one dev-tooling `reloadSources`, as delivered to the app via
/// the `ext.fleury.reloadReport` extension.
final class HotReloadReport {
  const HotReloadReport({
    required this.success,
    required this.elapsed,
    required this.loadedLibraryCount,
    this.message,
    this.restartRequired = false,
  });

  /// Whether the VM accepted the reload.
  final bool success;

  /// Wall time of the `reloadSources` call.
  final Duration elapsed;

  /// Libraries the VM re-loaded (0 when unknown or failed).
  final int loadedLibraryCount;

  /// Compile/rejection detail on failure.
  final String? message;

  /// The VM rejected a class migration that needs a fresh isolate.
  /// False for compiler errors and failures with no migration evidence.
  final bool restartRequired;

  /// Class migration notices identify their target class. Compiler diagnostics
  /// use the same notice type but have no class target, so do not infer recovery
  /// from a failed reload alone or from English error text.
  static bool requiresRestart(Map<String, Object?> json) {
    final notices = json['notices'];
    return json['success'] == false &&
        notices is List &&
        notices.isNotEmpty &&
        notices.every((notice) => notice is Map && notice['class'] is Map);
  }

  /// Actionable recovery followed by the original VM/compiler diagnostic.
  String failureDescription({required bool canRestart}) {
    final recovery = restartRequired
        ? canRestart
              ? 'Hot reload needs a restart. Ctrl+G, then F5 restarts the app '
                    'and resets its state.'
              : 'Hot reload needs a restart. Stop and rerun the app '
                    'to apply this change (resets state).'
        : 'Hot reload failed. Fix errors and save again; '
              'your app is still running.';
    final detail = message;
    return detail == null || detail.isEmpty ? recovery : '$recovery\n$detail';
  }
}

/// Connects a `package:vm_service` client to the VM service at [serverUri]
/// (the http(s) URI from `Service.getInfo()`), translating it to the
/// websocket endpoint. Shared by [HotReloadController] (in-app reassemble
/// listener) and the dev bootstrap (source-watcher reload trigger).
Future<VmService> connectVmServiceAt(Uri serverUri) {
  final wsUri = serverUri.replace(
    scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
    path: serverUri.path.endsWith('/')
        ? '${serverUri.path}ws'
        : '${serverUri.path}/ws',
  );
  return vmServiceConnectUri(wsUri.toString());
}

/// Owns the hot-reload integration for one TUI session.
///
/// Created by `runApp`; tests can create one against a stub reassemble
/// callback to assert the wiring without spinning up a real VM service
/// connection.
class HotReloadController {
  HotReloadController._({
    required this.onReassemble,
    required this.dev,
    void Function(HotReloadReport report)? onReloadReport,
    void Function()? onShutdownRequested,
  }) : _onReloadReport = onReloadReport,
       _onShutdownRequested = onShutdownRequested,
       _zone = Zone.current;

  final Zone _zone;
  final void Function(HotReloadReport report)? _onReloadReport;
  final void Function()? _onShutdownRequested;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  // Extensions are registered only once, in the first session's zone. Always
  // dispatch into the current controller's zone so session-bound operations
  // (notably exitApp) cannot accidentally target the first, expired app.
  // Guard synchronous callback failures too: letting them escape into the
  // registration zone can strand the RPC across distinct error-zone boundaries.
  void _reassemble() {
    if (!_disposed) _zone.runGuarded(onReassemble);
  }

  void _report(HotReloadReport report) {
    final callback = _onReloadReport;
    if (!_disposed && callback != null) _zone.runUnaryGuarded(callback, report);
  }

  void _shutdown() {
    final callback = _onShutdownRequested;
    if (!_disposed && callback != null) _zone.runGuarded(callback);
  }

  /// Called when a reassemble has been requested (either via the
  /// `ext.fleury.reassemble` service extension or via an
  /// `IsolateReload` event on the VM service stream).
  final void Function() onReassemble;

  /// Whether this controller is running in dev mode (VM service
  /// available). False when --enable-vm-service was not passed.
  final bool dev;

  VmService? _vm;
  StreamSubscription<Event>? _isolateEventSubscription;

  /// Attaches reload handlers to the current isolate.
  ///
  /// Always registers the `ext.fleury.reassemble` extension so an
  /// external tool can trigger a reassemble. If the VM service is
  /// available, also subscribes to the Isolate stream and reassembles
  /// on `IsolateReload` events.
  ///
  /// [onReloadReport] receives dev-tooling reload outcomes (the
  /// `ext.fleury.reloadReport` extension, invoked by the dev bootstrap after
  /// each `reloadSources`) so the runtime can surface "Reloaded N libraries
  /// in Xms" and compile errors in the debug shell. [onShutdownRequested]
  /// backs `ext.fleury.shutdown` — a graceful exit request used by the dev
  /// bootstrap to tear this session down before a hot restart.
  static Future<HotReloadController> attach({
    required void Function() onReassemble,
    void Function(HotReloadReport report)? onReloadReport,
    void Function()? onShutdownRequested,
  }) async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    final dev = serverUri != null;

    final controller = HotReloadController._(
      onReassemble: onReassemble,
      dev: dev,
      onReloadReport: onReloadReport,
      onShutdownRequested: onShutdownRequested,
    );

    _activeController = controller;
    if (!_extensionRegistered) {
      developer.registerExtension('ext.fleury.reassemble', (
        method,
        params,
      ) async {
        _activeController?._reassemble();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      developer.registerExtension('ext.fleury.reloadReport', (
        method,
        params,
      ) async {
        _activeController?._report(
          HotReloadReport(
            success: params['success'] == 'true',
            elapsed: Duration(
              milliseconds: int.tryParse(params['elapsedMs'] ?? '') ?? 0,
            ),
            loadedLibraryCount:
                int.tryParse(params['loadedLibraryCount'] ?? '') ?? 0,
            message: params['message'],
            restartRequired: params['restartRequired'] == 'true',
          ),
        );
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      developer.registerExtension('ext.fleury.shutdown', (
        method,
        params,
      ) async {
        _activeController?._shutdown();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      developer.registerExtension('ext.fleury.restart', (method, params) async {
        // Invoked on the app; relayed as an event so the dev bootstrap (a
        // service client) can orchestrate the teardown + respawn. A no-op
        // without a bootstrap session.
        developer.postEvent(kRestartRequestedEvent, const {});
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      _extensionRegistered = true;
    }

    if (dev) {
      await controller._connectVmService(serverUri);
    }

    return controller;
  }

  Future<void> _connectVmService(Uri serverUri) async {
    try {
      _vm = await connectVmServiceAt(serverUri);
      await _vm!.streamListen(EventStreams.kIsolate);
      _isolateEventSubscription = _vm!.onIsolateEvent.listen((event) {
        if (event.kind == EventKind.kIsolateReload) {
          // Reload events are delivered on both success and failure;
          // on failure the existing code remains live, so calling
          // reassemble is a no-op cost (a tree walk that re-invokes
          // unchanged build methods) rather than a correctness issue.
          // When richer failure handling lands we can surface
          // event.reloadResult to the dev overlay.
          _reassemble();
        }
      });
    } catch (_) {
      // Best-effort: the service extension still works even if the WS
      // connection failed.
    }
  }

  /// Releases VM service resources. Safe to call multiple times.
  Future<void> dispose() {
    _disposed = true;
    // Unpublish before any asynchronous cleanup; queued VM events also check
    // _disposed. An older controller cannot clear a newer registration.
    if (identical(_activeController, this)) _activeController = null;
    return _disposeFuture ??= _disposeResources();
  }

  Future<void> _disposeResources() async {
    try {
      await _isolateEventSubscription?.cancel();
    } finally {
      _isolateEventSubscription = null;
      final vm = _vm;
      _vm = null;
      await vm?.dispose();
    }
  }
}
