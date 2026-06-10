@TestOn('browser')
library;

import 'dart:async';

import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../web/dom_demo.dart' as dom_demo;

final class _FakeFlush {
  void Function()? _pending;

  bool get pending => _pending != null;

  void schedule(Duration delay, void Function() flush) {
    _pending = flush;
  }

  void fire() {
    final flush = _pending;
    if (flush == null) throw StateError('No pending frame flush.');
    _pending = null;
    flush();
  }
}

void main() {
  test('retained DOM demo renders and handles browser input', () async {
    final flush = _FakeFlush();
    final hostElement = web.document.createElement('div');
    hostElement.id = 'fleury-dom-demo-test';
    hostElement.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:96ch;height:420px;'
          'font-family:monospace;font-size:16px;line-height:18px;'
          'overflow:hidden;background:#050505;color:#f5f5f5;',
    );
    web.document.body!.appendChild(hostElement);

    final TuiSurfaceHost host = await dom_demo.runDomDemo(
      hostElement: hostElement,
      flushScheduler: flush.schedule,
    );
    addTearDown(() async {
      await host.dispose();
      hostElement.parentNode?.removeChild(hostElement);
      web.document.body?.removeAttribute('data-fleury-dom-demo');
    });

    expect(web.document.body?.getAttribute('data-fleury-dom-demo'), 'mounted');
    expect(flush.pending, isTrue);
    flush.fire();
    await _waitFor(
      () => web.document.body?.getAttribute('data-fleury-dom-demo') == 'ready',
      description: 'first retained DOM demo frame',
    );
    expect(hostElement.textContent, contains('Fleury retained DOM'));

    expect(hostElement.querySelector('.fleury-screen'), isNotNull);
    expect(
      hostElement.querySelector('.fleury-screen')!.getAttribute('aria-hidden'),
      'true',
    );
    expect(hostElement.querySelector('.fleury-semantics'), isNotNull);
    expect(hostElement.querySelector('textarea'), isNotNull);
    expect(
      hostElement.querySelectorAll('.fleury-semantics [role]').length,
      greaterThanOrEqualTo(3),
    );

    final textArea =
        hostElement.querySelector('textarea') as web.HTMLTextAreaElement;
    textArea.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'abc',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );

    expect(flush.pending, isTrue);
    flush.fire();
    expect(hostElement.textContent, contains('draft length  3'));

    textArea.dispatchEvent(
      web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(key: 'Enter', bubbles: true, cancelable: true),
      ),
    );

    expect(flush.pending, isTrue);
    flush.fire();
    expect(hostElement.textContent, contains('counter  1'));
    expect(hostElement.textContent, contains('last submit  abc'));
    expect(hostElement.textContent, contains('draft length  0'));
  });
}

Future<void> _waitFor(
  bool Function() check, {
  required String description,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $description.');
}
