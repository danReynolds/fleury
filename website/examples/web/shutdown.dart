// Real widget mounts and cleanup; only the signal delivery is simulated.
import 'dart:async';
import 'dart:js_interop';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_host.dart' show FrameFlushScheduler;
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;
import '../doc_snippets/shutdown/demo_work.dart';

final _demos = <web.Element, _ShutdownDemo>{};

void mountShutdownDemos(FrameFlushScheduler flushScheduler) {
  for (final root in _demos.keys.toList()) {
    if (!root.isConnected) unawaited(_demos.remove(root)!.dispose());
  }
  final roots = web.document.querySelectorAll('[data-shutdown-demo]');
  for (var i = 0; i < roots.length; i++) {
    final root = roots.item(i)! as web.HTMLElement;
    _demos.putIfAbsent(root, () => _ShutdownDemo(root, flushScheduler));
  }
}

class _ShutdownDemo {
  _ShutdownDemo(this.root, this.flushScheduler) {
    start.addEventListener('click', ((web.Event _) => unawaited(_run())).toJS);
    policy.addEventListener(
      'change',
      ((web.Event _) => unawaited(_run())).toJS,
    );
    for (final button in signals) {
      button.addEventListener(
        'click',
        ((web.Event _) {
          final signal =
              button.getAttribute('data-shutdown-signal') == 'interrupt'
              ? AppSignal.interrupt
              : AppSignal.terminate;
          unawaited(_finish(signal));
        }).toJS,
      );
    }
    unawaited(_run(focus: false));
  }

  final web.HTMLElement root;
  final FrameFlushScheduler flushScheduler;
  late final surface =
      root.querySelector('[data-shutdown-surface]')! as web.HTMLElement;
  late final output =
      root.querySelector('[data-shutdown-output]')! as web.HTMLElement;
  late final status =
      root.querySelector('[data-shutdown-status]')! as web.HTMLElement;
  late final start =
      root.querySelector('[data-shutdown-start]')! as web.HTMLButtonElement;
  late final policy =
      root.querySelector('[data-shutdown-policy]')! as web.HTMLSelectElement;
  late final signals = [
    for (final name in ['interrupt', 'terminate'])
      root.querySelector('[data-shutdown-signal="$name"]')!
          as web.HTMLButtonElement,
  ];
  Future<MountedApp>? _mount;
  DemoWork? _work;
  bool _busy = false;
  bool _disposed = false;

  void _controls({required bool busy, required bool running}) {
    start.disabled = busy;
    policy.disabled = busy;
    for (final button in signals) {
      button.disabled = busy || !running;
    }
  }

  Future<void> _run({bool focus = true}) async {
    if (_disposed || _busy) return;
    _busy = true;
    _controls(busy: true, running: false);
    try {
      await _close();
      if (_disposed) return;
      output.textContent = '';
      status.textContent = 'UI running';
      surface.hidden = false.toJS;
      final work = _work = DemoWork();
      _mount = mountApp(
        () => Theme(
          data: const ThemeData(),
          child: FocusTraversalGroup(
            child: ShutdownPanel(
              work: work,
              onFinish: () => unawaited(_finish(null)),
            ),
          ),
        ),
        into: surface,
        flushScheduler: flushScheduler,
      );
      await _mount;
      if (!_disposed && focus) {
        (surface.querySelector('textarea') as web.HTMLElement?)?.focus();
      }
    } catch (_) {
      await _close();
      if (!_disposed) status.textContent = 'Could not start. Try again.';
    } finally {
      _busy = false;
      if (!_disposed) _controls(busy: false, running: _mount != null);
    }
  }

  Future<void> _finish(AppSignal? signal) async {
    if (_disposed || _busy || _mount == null) return;
    _busy = true;
    _controls(busy: true, running: true);
    try {
      final waitForWork = policy.value == 'finish';
      if (waitForWork) {
        status.textContent = 'Finishing work…';
        await _work!.finish();
      }
      await _close();
      if (_disposed) return;
      final reason = signal == null ? 'Finished' : 'Interrupted';
      output.textContent =
          '${waitForWork ? 'Current item finished.\n' : ''}'
          'UI closed. Resources closed.\n'
          '$reason · exit code ${signalExitCode(signal)}\n\n\$ ▌';
      status.textContent = 'Command ended';
      start.focus();
    } finally {
      _busy = false;
      if (!_disposed) _controls(busy: false, running: false);
    }
  }

  Future<void> _close() async {
    final mount = _mount;
    final work = _work;
    _mount = null;
    _work = null;
    try {
      if (mount != null) await (await mount).dispose();
    } finally {
      await work?.close();
      surface.hidden = true.toJS;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _close();
  }
}
