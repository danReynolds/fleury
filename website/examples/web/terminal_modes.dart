// Browser host for the terminal-modes guide. Forms are real Fleury mounts;
// shell output and the between-session prompt belong to the HTML host.
// Native runApp / terminal ownership are exercised by the runnable samples.
import 'dart:async';
import 'dart:js_interop';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_host.dart' show FrameFlushScheduler;
import 'package:fleury_samples/samples.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

final _demos = <web.Element, _TerminalDemo>{};

void mountTerminalDemos(FrameFlushScheduler flushScheduler) {
  for (final root in _demos.keys.toList()) {
    if (!root.isConnected) {
      unawaited(_demos.remove(root)!.dispose());
    }
  }
  final roots = web.document.querySelectorAll('[data-terminal-demo]');
  for (var i = 0; i < roots.length; i++) {
    final root = roots.item(i)! as web.HTMLElement;
    _demos.putIfAbsent(root, () => _TerminalDemo(root, flushScheduler));
  }
}

class _TerminalDemo {
  _TerminalDemo(this.root, this.flushScheduler) {
    reset.addEventListener(
      'click',
      ((web.Event _) {
        unawaited(_reset());
      }).toJS,
    );
    prompt.addEventListener(
      'submit',
      ((web.Event event) {
        event.preventDefault();
        if (_busy || prompt.hasAttribute('hidden')) return;
        final reply = answer.value.trim().toLowerCase();
        _append('Open setup again? [y/N] $reply\n');
        prompt.hidden = true.toJS;
        if (reply == 'y') {
          unawaited(_start());
        } else {
          shell.hidden = false.toJS;
          status.textContent = 'Command finished';
          reset.focus();
        }
      }).toJS,
    );
    // Resize starts in a live form; repeat begins at the command boundary.
    if (!repeat) unawaited(_reset(focus: false));
  }

  final web.HTMLElement root;
  final FrameFlushScheduler flushScheduler;
  late final surface =
      root.querySelector('[data-terminal-surface]')! as web.HTMLElement;
  late final history =
      root.querySelector('[data-terminal-history]')! as web.HTMLElement;
  late final prompt =
      root.querySelector('[data-terminal-prompt]')! as web.HTMLFormElement;
  late final answer = prompt.querySelector('input')! as web.HTMLInputElement;
  late final reset =
      root.querySelector('[data-terminal-reset]')! as web.HTMLButtonElement;
  late final shell =
      root.querySelector('[data-terminal-shell]')! as web.HTMLElement;
  late final status =
      root.querySelector('[data-terminal-status]')! as web.HTMLElement;
  bool get repeat => root.getAttribute('data-terminal-demo') == 'repeat';
  Future<MountedApp>? _mount;
  var _busy = false;
  var _disposed = false;
  var _session = 0;

  void _append(String value) {
    history.textContent = '${history.textContent}$value';
    history.scrollTop = history.scrollHeight.toDouble();
  }

  void _resize(InlineSetupStep step) {
    surface.style.height = '${step.rows * 1.25}em';
    status.textContent = repeat
        ? 'UI · session $_session'
        : '${step.rows} rows';
  }

  Future<void> _reset({bool focus = true}) async {
    if (_busy || _disposed) return;
    _busy = true;
    reset.disabled = true;
    try {
      await _close();
      if (_disposed) return;
      history.textContent = '';
      _session = 0;
    } finally {
      _busy = false;
    }
    await _start(focus: focus);
  }

  Future<void> _start({bool focus = true}) async {
    if (_busy || _disposed) return;
    _busy = true;
    reset.disabled = true;
    prompt.hidden = true.toJS;
    shell.hidden = true.toJS;
    surface.hidden = false.toJS;
    _session++;
    _resize(InlineSetupStep.configure);
    try {
      _mount = mountApp(
        () => SampleScaffold(
          child: FocusTraversalGroup(
            child: InlineSetup(
              onStepChanged: _resize,
              onComplete: (result) => unawaited(_finish(result)),
            ),
          ),
        ),
        into: surface,
        flushScheduler: flushScheduler,
      );
      await _mount;
      if (!_disposed) {
        reset.textContent = 'Reset demo';
        // Widget autofocus controls Fleury focus; the browser also needs the
        // mounted input element to receive keyboard events.
        if (focus) {
          (surface.querySelector('textarea') as web.HTMLElement?)?.focus();
        }
      }
    } catch (_) {
      _mount = null;
      status.textContent = 'Could not start the demo. Try resetting.';
      surface.hidden = true.toJS;
    } finally {
      _busy = false;
      reset.disabled = false;
    }
  }

  Future<void> _finish(InlineSetupResult? result) async {
    if (_busy || _disposed) return;
    _busy = true;
    reset.disabled = true;
    try {
      // Dispose fully before printing the result or exposing host input.
      await _close();
      if (_disposed) return;
      _append('${result?.summary ?? 'Setup cancelled.'}\n\n');
      if (repeat && result != null) {
        status.textContent = 'CLI · awaiting input';
        prompt.hidden = false.toJS;
        answer.value = '';
        answer.focus();
      } else {
        status.textContent = 'Command finished';
        shell.hidden = false.toJS;
        reset.focus();
      }
    } finally {
      _busy = false;
      reset.disabled = false;
    }
  }

  Future<void> _close() async {
    final pending = _mount;
    _mount = null;
    if (pending != null) await (await pending).dispose();
    surface.hidden = true.toJS;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _close();
  }
}
