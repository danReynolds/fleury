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
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

// The service extension can only be registered ONCE per isolate. This
// mutable cell lets every controller's onReassemble be reachable via
// the same registered handler: `attach()` swaps the cell on entry and
// `dispose()` clears it, so a long-lived process with multiple
// successive runs (e.g. a test isolate) sees the right callback for
// the currently-attached controller.
void Function()? _activeOnReassemble;
bool _extensionRegistered = false;

/// Owns the hot-reload integration for one TUI session.
///
/// Created by `runTui`; tests can create one against a stub reassemble
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
  StreamSubscription<ProcessSignal>? _sigusrSubscription;

  /// Attaches reload handlers to the current isolate.
  ///
  /// Always registers the `ext.fleury.reassemble` extension so an
  /// external tool can trigger a reassemble. If the VM service is
  /// available, also subscribes to the Isolate stream and reassembles
  /// on `IsolateReload` events.
  static Future<HotReloadController> attach({
    required void Function() onReassemble,
  }) async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    final dev = serverUri != null;

    final controller = HotReloadController._(
      onReassemble: onReassemble,
      dev: dev,
    );

    _activeOnReassemble = onReassemble;
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
      _extensionRegistered = true;
    }

    if (dev) {
      await controller._connectVmService(serverUri);
    }

    // SIGUSR1 is the editor-agnostic trigger: a file watcher (entr,
    // inotifywait, fswatch, a Make recipe, etc.) can `kill -SIGUSR1
    // <pid>` after recompiling and fleury reassembles. Mirrors Flutter
    // `flutter run --pid-file` semantics. Windows has no SIGUSR1, so
    // this no-ops there — the VM-service path covers VS Code.
    if (!Platform.isWindows) {
      try {
        controller._sigusrSubscription = ProcessSignal.sigusr1.watch().listen(
          (_) => onReassemble(),
        );
      } catch (_) {
        // Some embedders (zero-tty pipelines, isolates without signal
        // permission) refuse to install the handler. Best-effort.
      }
    }

    return controller;
  }

  Future<void> _connectVmService(Uri serverUri) async {
    final wsUri = serverUri.replace(
      scheme: serverUri.scheme == 'https' ? 'wss' : 'ws',
      path: serverUri.path.endsWith('/')
          ? '${serverUri.path}ws'
          : '${serverUri.path}/ws',
    );
    try {
      _vm = await vmServiceConnectUri(wsUri.toString());
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
    await _sigusrSubscription?.cancel();
    _sigusrSubscription = null;
    await _vm?.dispose();
    _vm = null;
    // Clear only when this controller is the current owner — a later
    // attach() may have already swapped the cell.
    if (identical(_activeOnReassemble, onReassemble)) {
      _activeOnReassemble = null;
    }
  }
}
