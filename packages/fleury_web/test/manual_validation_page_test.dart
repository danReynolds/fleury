@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../web/manual_validation.dart' as manual_validation;

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
  test('manual validation page readiness waits for first DOM frame', () async {
    final flush = _FakeFlush();
    final hostElement = web.document.createElement('div');
    hostElement.id = 'fleury-manual-validation-test';
    web.document.body!.appendChild(hostElement);

    final MountedApp host = await manual_validation.runManualValidation(
      hostElement: hostElement,
      flushScheduler: flush.schedule,
    );
    addTearDown(() async {
      await host.dispose();
      hostElement.parentNode?.removeChild(hostElement);
      _clearManualValidationBodyAttributes();
    });

    expect(
      web.document.body?.getAttribute('data-fleury-manual-validation'),
      'mounted',
    );
    expect(flush.pending, isTrue);

    flush.fire();

    await _waitFor(
      () =>
          web.document.body?.getAttribute('data-fleury-manual-validation') ==
          'ready',
      description: 'manual validation first retained DOM frame',
    );
    expect(
      hostElement.textContent,
      contains('Fleury retained DOM manual validation'),
    );
    expect(
      hostElement.querySelector('.fleury-screen')!.getAttribute('aria-hidden'),
      'true',
    );

    final semanticRoot = hostElement.querySelector('.fleury-semantics')!;
    expect(semanticRoot.getAttribute('data-fleury-semantic-root'), 'true');
    expect(semanticRoot.getAttribute('aria-hidden'), isNull);
    final body = web.document.body!;
    final browserVersion = body.getAttribute(
      'data-fleury-manual-browser-version',
    )!;
    expect(browserVersion, isNotEmpty);
    expect(
      browserVersion,
      anyOf(
        startsWith('HeadlessChrome/'),
        startsWith('Chrome/'),
        startsWith('Chromium/'),
        startsWith('CriOS/'),
        startsWith('Edg/'),
        'unknown',
      ),
    );
    expect(
      body.getAttribute('data-fleury-manual-platform'),
      web.window.navigator.platform,
    );
    expect(
      body.getAttribute('data-fleury-manual-user-agent'),
      web.window.navigator.userAgent,
    );
    expect(
      body.getAttribute('data-fleury-manual-page'),
      'manual_validation.html',
    );
    final textArea =
        hostElement.querySelector('textarea') as web.HTMLTextAreaElement;
    expect(textArea.getAttribute('data-fleury-caret-state'), 'positioned');
    expect(
      int.parse(textArea.getAttribute('data-fleury-caret-col')!),
      greaterThanOrEqualTo(0),
    );
    expect(
      int.parse(textArea.getAttribute('data-fleury-caret-row')!),
      greaterThanOrEqualTo(0),
    );
    expect(textArea.getAttribute('data-fleury-caret-width-cells'), '1');
    expect(textArea.getAttribute('data-fleury-caret-height-cells'), '1');
    expect(textArea.getAttribute('data-fleury-caret-css-left'), isNotNull);
    expect(textArea.getAttribute('data-fleury-caret-css-top'), isNotNull);
    expect(
      textArea.getAttribute('style'),
      allOf(
        contains('position:fixed'),
        isNot(contains('left:-10000px')),
        isNot(contains('top:-10000px')),
      ),
    );

    final textbox = semanticRoot.querySelector(
      '[role="textbox"][data-fleury-value="type with IME here"]',
    )!;
    expect(textbox.getAttribute('role'), 'textbox');
    expect(textbox.getAttribute('data-fleury-value'), 'type with IME here');

    final actionButton = semanticRoot.querySelector(
      '[data-fleury-semantic-id="manual-validation-action"]',
    )!;
    expect(actionButton.getAttribute('role'), 'button');
    expect(actionButton.getAttribute('data-fleury-primary-action'), 'activate');

    final safeLink = semanticRoot.querySelector(
      '[data-fleury-semantic-id="manual-validation-link"]',
    )!;
    expect(safeLink.getAttribute('role'), 'link');
    expect(
      safeLink.getAttribute('data-fleury-link-url'),
      'https://github.com/',
    );
    expect(safeLink.getAttribute('href'), 'https://github.com/');
    expect(safeLink.getAttribute('target'), '_blank');
    expect(safeLink.getAttribute('rel'), 'noopener noreferrer');

    String statusText() =>
        semanticRoot
            .querySelector(
              '[data-fleury-semantic-id="manual-validation-status"]',
            )
            ?.textContent ??
        '';

    expect(statusText(), contains('last action none | submissions 0'));
    final provenance = semanticRoot.querySelector(
      '[data-fleury-semantic-id="manual-validation-provenance"]',
    )!;
    expect(provenance.getAttribute('role'), 'status');
    expect(provenance.textContent, contains('Evidence browser:'));
    expect(provenance.textContent, contains(browserVersion));
    actionButton.dispatchEvent(
      web.Event('click', web.EventInit(bubbles: true, cancelable: true)),
    );
    expect(flush.pending, isTrue);

    await _pumpFramesUntil(
      flush,
      () => statusText().contains('last action semantic activate'),
      description: 'manual validation semantic action status update',
      debugState: statusText,
    );
  });

  test('manual validation page reaches ready without rAF', () async {
    final originalRequestAnimationFrame = web.window.getProperty<JSAny?>(
      'requestAnimationFrame'.toJS,
    );
    web.window.setProperty('requestAnimationFrame'.toJS, null);
    addTearDown(() {
      web.window.setProperty(
        'requestAnimationFrame'.toJS,
        originalRequestAnimationFrame,
      );
    });

    final hostElement = web.document.createElement('div');
    hostElement.id = 'fleury-manual-validation-no-raf-test';
    web.document.body!.appendChild(hostElement);

    final MountedApp host = await manual_validation.runManualValidation(
      hostElement: hostElement,
    );
    addTearDown(() async {
      await host.dispose();
      hostElement.parentNode?.removeChild(hostElement);
      _clearManualValidationBodyAttributes();
    });

    await _waitFor(
      () =>
          web.document.body?.getAttribute('data-fleury-manual-validation') ==
          'ready',
      description: 'manual validation ready fallback without rAF',
    );
    expect(
      hostElement.textContent,
      contains('Fleury retained DOM manual validation'),
    );
    expect(
      hostElement
          .querySelector('.fleury-semantics')!
          .getAttribute('data-fleury-semantic-root'),
      'true',
    );
    expect(
      (hostElement.querySelector('textarea') as web.HTMLTextAreaElement)
          .getAttribute('data-fleury-caret-state'),
      'positioned',
    );
    expect(
      web.document.body?.getAttribute('data-fleury-manual-browser-version'),
      isNotEmpty,
    );
  });
}

void _clearManualValidationBodyAttributes() {
  final body = web.document.body;
  if (body == null) return;
  for (final attribute in [
    'data-fleury-manual-validation',
    'data-fleury-manual-browser-version',
    'data-fleury-manual-platform',
    'data-fleury-manual-user-agent',
    'data-fleury-manual-page',
  ]) {
    body.removeAttribute(attribute);
  }
}

Future<void> _waitFor(
  bool Function() check, {
  required String description,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $description.');
}

Future<void> _pumpFramesUntil(
  _FakeFlush flush,
  bool Function() check, {
  required String description,
  String Function()? debugState,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    if (flush.pending) {
      flush.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      continue;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (check()) return;
  final suffix = debugState == null ? '' : ' Last state: ${debugState()}';
  fail('Timed out waiting for $description.$suffix');
}
