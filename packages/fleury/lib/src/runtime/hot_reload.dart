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
// mutable cell lets every controller's onReassemble be reachable via
// the same registered handler: `attach()` swaps the cell on entry and
// `dispose()` clears it, so a long-lived process with multiple
// successive runs (e.g. a test isolate) sees the right callback for
// the currently-attached controller.
void Function()? _activeOnReassemble;
void Function(HotReloadReport report)? _activeOnReloadReport;
void Function()? _activeOnShutdownRequested;
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
  });

  /// Whether the VM accepted the reload.
  final bool success;

  /// Wall time of the `reloadSources` call.
  final Duration elapsed;

  /// Libraries the VM re-loaded (0 when unknown or failed).
  final int loadedLibraryCount;

  /// Compile/rejection detail on failure.
  final String? message;
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
  HotReloadController._({required this.onReassemble, required this.dev});

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
    );

    _activeOnReassemble = onReassemble;
    _activeOnReloadReport = onReloadReport;
    _activeOnShutdownRequested = onShutdownRequested;
    if (!_extensionRegistered) {
      developer.registerExtension('ext.fleury.reassemble', (
        method,
        params,
      ) async {
        _activeOnReassemble?.call();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      developer.registerExtension('ext.fleury.reloadReport', (
        method,
        params,
      ) async {
        _activeOnReloadReport?.call(
          HotReloadReport(
            success: params['success'] == 'true',
            elapsed: Duration(
              milliseconds: int.tryParse(params['elapsedMs'] ?? '') ?? 0,
            ),
            loadedLibraryCount:
                int.tryParse(params['loadedLibraryCount'] ?? '') ?? 0,
            message: params['message'],
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
        _activeOnShutdownRequested?.call();
        return developer.ServiceExtensionResponse.result(
          jsonEncode({'ok': true}),
        );
      });
      developer.registerExtension('ext.fleury.restart', (
        method,
        params,
      ) async {
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
          onReassemble();
        }
      });
    } catch (_) {
      // Best-effort: the service extension still works even if the WS
      // connection failed.
    }
  }

  /// Releases VM service resources. Safe to call multiple times.
  Future<void> dispose() async {
    await _isolateEventSubscription?.cancel();
    _isolateEventSubscription = null;
    await _vm?.dispose();
    _vm = null;
    // Clear only when this controller is the current owner — a later
    // attach() may have already swapped the cells.
    if (identical(_activeOnReassemble, onReassemble)) {
      _activeOnReassemble = null;
      _activeOnReloadReport = null;
      _activeOnShutdownRequested = null;
    }
  }
}
