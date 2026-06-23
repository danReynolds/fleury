@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

class _FakeFlush {
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

class _FakeClipboard extends Clipboard {
  String? lastWritten;

  @override
  String? readInProcess() => lastWritten;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    lastWritten = text;
    return ClipboardWriteReport(
      result: ClipboardWriteResult.inProcessOnly,
      resolution: const CapabilityResolution(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        state: CapabilityResolutionState.degraded,
        fallbackLabel: 'in-process register',
      ),
      policy: policy,
      payloadBytes: text.length,
      osc52EncodedLength: text.length,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}

void main() {
  test(
    'runTuiWebDom assembles retained DOM rendering and browser input',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);

      final hostElement = web.document.createElement('div');
      hostElement.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:240px;height:48px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      web.document.body!.appendChild(hostElement);
      addTearDown(() => hostElement.parentNode?.removeChild(hostElement));

      final controller = TextEditingController();
      final instrumentation = RecordingWebHostInstrumentation();
      final focusCoordinator = WebFocusCoordinator();
      final flush = _FakeFlush();
      final webClipboard = _FakeClipboard();
      await webClipboard.writeWithReport('fallback');
      final TuiSurfaceHost host = await runTuiWebDom(
        () => TextInput(controller: controller, autofocus: true),
        hostElement: hostElement,
        clipboard: webClipboard,
        flushScheduler: flush.schedule,
        instrumentation: instrumentation,
        focusCoordinator: focusCoordinator,
      );
      addTearDown(host.dispose);

      expect(hostElement.querySelector('.fleury-screen'), isNotNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNotNull);
      expect(hostElement.querySelector('textarea'), isNotNull);
      expect(flush.pending, isTrue);

      flush.fire();
      await host.awaitSemanticIdle();
      expect(instrumentation.frames, hasLength(1));
      expect(controller.text, isEmpty);
      final semanticsRoot = hostElement.querySelector('.fleury-semantics')!;
      final field =
          semanticsRoot.querySelector('[role="textbox"]')!
              as web.HTMLInputElement;
      expect(
        hostElement
            .querySelector('.fleury-screen')!
            .getAttribute('aria-hidden'),
        'true',
      );
      expect(semanticsRoot.getAttribute('aria-hidden'), isNull);
      expect(field.getAttribute('data-fleury-focused'), 'true');
      expect(field.value, isEmpty);
      expect(focusCoordinator.activeSemanticNode, isNotNull);
      expect(
        focusCoordinator.browserFocusTarget,
        WebFocusTarget.keyboardCapture,
      );

      final textArea =
          hostElement.querySelector('textarea') as web.HTMLTextAreaElement;
      final fallbackPaste = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(bubbles: true, cancelable: true),
      );
      textArea.dispatchEvent(fallbackPaste);

      expect(fallbackPaste.defaultPrevented, isTrue);
      expect(flush.pending, isTrue);
      flush.fire();
      await host.awaitSemanticIdle();
      expect(controller.text, 'fallback');
      expect(instrumentation.frames, hasLength(2));

      textArea.dispatchEvent(
        web.InputEvent(
          'input',
          web.InputEventInit(
            data: 'z',
            inputType: 'insertText',
            bubbles: true,
            cancelable: true,
          ),
        ),
      );

      expect(flush.pending, isTrue);
      expect(controller.text, 'fallback');

      flush.fire();
      await host.awaitSemanticIdle();

      expect(controller.text, 'fallbackz');
      expect(instrumentation.frames, hasLength(3));
      expect(
        instrumentation.summarize().timings['totalFrameMs']!.p95,
        greaterThanOrEqualTo(0),
      );
      expect(hostElement.textContent, contains('fallbackz'));
      expect(
        (semanticsRoot.querySelector('[role="textbox"]')!
                as web.HTMLInputElement)
            .value,
        'fallbackz',
      );

      await host.dispose();

      expect(hostElement.parentNode, isNotNull);
      expect(hostElement.querySelector('.fleury-screen'), isNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNull);
      expect(hostElement.querySelector('textarea'), isNull);
      expect(Clipboard.instance, same(previousClipboard));
      expect(focusCoordinator.browserFocusTarget, isNull);
    },
  );

  test(
    'runTuiWebDom disposes generated DOM roots after contained build errors',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);

      final hostElement = web.document.createElement('div');
      hostElement.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:240px;height:48px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      web.document.body!.appendChild(hostElement);
      addTearDown(() => hostElement.parentNode?.removeChild(hostElement));

      final error = StateError('root build failed');
      final flush = _FakeFlush();

      final host = await runTuiWebDom(
        () => throw error,
        hostElement: hostElement,
        clipboard: _FakeClipboard(),
        flushScheduler: flush.schedule,
      );

      expect(hostElement.querySelector('.fleury-screen'), isNotNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNotNull);
      expect(hostElement.querySelector('textarea'), isNotNull);
      expect(Clipboard.instance, isNot(same(previousClipboard)));

      flush.fire();
      await host.awaitSemanticIdle();
      expect(hostElement.textContent, contains('root build failed'));

      await host.dispose();

      expect(hostElement.parentNode, isNotNull);
      expect(hostElement.querySelector('.fleury-screen'), isNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNull);
      expect(hostElement.querySelector('textarea'), isNull);
      expect(Clipboard.instance, same(previousClipboard));
    },
  );

  test(
    'runTuiWebDom retains but clears caller-supplied visual and semantic roots',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);

      final hostElement = web.document.createElement('div');
      hostElement.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:240px;height:48px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      final surfaceElement = web.document.createElement('div');
      final semanticElement = web.document.createElement('div');
      web.document.body!.appendChild(hostElement);
      hostElement.appendChild(surfaceElement);
      hostElement.appendChild(semanticElement);
      addTearDown(() => hostElement.parentNode?.removeChild(hostElement));

      final flush = _FakeFlush();
      final host = await runTuiWebDom(
        () => const Text('supplied roots'),
        hostElement: hostElement,
        surfaceElement: surfaceElement,
        semanticElement: semanticElement,
        clipboard: _FakeClipboard(),
        flushScheduler: flush.schedule,
      );

      expect(hostElement.querySelector('.fleury-screen'), same(surfaceElement));
      expect(
        hostElement.querySelector('.fleury-semantics'),
        same(semanticElement),
      );
      expect(hostElement.querySelector('textarea'), isNotNull);

      flush.fire();
      await host.awaitSemanticIdle();
      expect(surfaceElement.textContent, contains('supplied roots'));
      expect(semanticElement.textContent, contains('supplied roots'));

      await host.dispose();

      expect(surfaceElement.parentNode, same(hostElement));
      expect(semanticElement.parentNode, same(hostElement));
      expect(surfaceElement.children.length, 0);
      expect(semanticElement.children.length, 0);
      expect(hostElement.querySelector('textarea'), isNull);
      expect(Clipboard.instance, same(previousClipboard));
    },
  );

  test(
    'runTuiWebDom rejects disabled semantics without diagnostics acknowledgement',
    () async {
      final hostElement = web.document.createElement('div');
      web.document.body!.appendChild(hostElement);
      addTearDown(() => hostElement.parentNode?.removeChild(hostElement));

      await expectLater(
        runTuiWebDom(
          () => const Text('inaccessible'),
          hostElement: hostElement,
          semanticsEnabled: false,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('allowInaccessibleDiagnostics'),
          ),
        ),
      );

      expect(hostElement.children.length, 0);
      expect(hostElement.querySelector('.fleury-screen'), isNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNull);
      expect(hostElement.querySelector('textarea'), isNull);

      final semanticElement = web.document.createElement('div');
      await expectLater(
        runTuiWebDom(
          () => const Text('inaccessible'),
          hostElement: hostElement,
          semanticElement: semanticElement,
          semanticsEnabled: false,
          allowInaccessibleDiagnostics: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(hostElement.children.length, 0);
    },
  );

  test(
    'runTuiWebDom allows disabled semantics only for acknowledged diagnostics',
    () async {
      final previousClipboard = _FakeClipboard();
      Clipboard.instance = previousClipboard;
      addTearDown(() => Clipboard.instance = previousClipboard);

      final hostElement = web.document.createElement('div');
      hostElement.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:240px;height:48px;'
            'font-family:monospace;font-size:16px;line-height:16px;',
      );
      web.document.body!.appendChild(hostElement);
      addTearDown(() => hostElement.parentNode?.removeChild(hostElement));

      final flush = _FakeFlush();
      final host = await runTuiWebDom(
        () => const Text('diagnostics only'),
        hostElement: hostElement,
        semanticsEnabled: false,
        allowInaccessibleDiagnostics: true,
        clipboard: _FakeClipboard(),
        flushScheduler: flush.schedule,
      );

      expect(hostElement.querySelector('.fleury-screen'), isNotNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNull);
      expect(hostElement.querySelector('textarea'), isNotNull);
      expect(
        hostElement
            .querySelector('.fleury-screen')!
            .getAttribute('aria-hidden'),
        'true',
      );

      flush.fire();
      await host.awaitSemanticIdle();
      expect(hostElement.textContent, contains('diagnostics only'));

      await host.dispose();

      expect(hostElement.querySelector('.fleury-screen'), isNull);
      expect(hostElement.querySelector('.fleury-semantics'), isNull);
      expect(hostElement.querySelector('textarea'), isNull);
      expect(Clipboard.instance, same(previousClipboard));
    },
  );
}
