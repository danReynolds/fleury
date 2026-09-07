@TestOn('browser')
library;

import 'dart:async';

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

final class _PaintObserver implements WebHostInstrumentation {
  final firstPaint = Completer<void>();
  final animatedPaints = Completer<void>();
  var paints = 0;

  @override
  void recordFrame(WebFrameInstrumentation frame) {
    if (frame.renderSkipped || frame.dirtyRowCount == 0) return;
    paints++;
    if (!firstPaint.isCompleted) firstPaint.complete();
    if (paints >= 3 && !animatedPaints.isCompleted) animatedPaints.complete();
  }

  @override
  void recordSemanticFlush(WebSemanticFlushInstrumentation flush) {}
}

void main() {
  for (final id in ['sparkline.basic', 'linechart.basic', 'barchart.basic']) {
    test('$id paints and animates through the real browser scheduler', () async {
      final info = exampleList.singleWhere((example) => example.id == id);
      final host = web.document.createElement('div');
      host.setAttribute(
        'style',
        'position:absolute;left:0;top:0;width:${info.cols}ch;'
            'height:${info.rows * 18}px;'
            'font-family:monospace;font-size:16px;line-height:18px;',
      );
      web.document.body!.appendChild(host);
      addTearDown(() => host.remove());
      final observer = _PaintObserver();
      // Use the production rAF scheduler: forcing a flush in the test would
      // conceal first-paint starvation while a ticker keeps requesting frames.
      final app = await mountApp(
        () => themedExampleRoot(
          examples[id]!,
          DocsExampleThemeController(DocsExampleStyle.dark),
        ),
        into: host,
        instrumentation: observer,
      );
      addTearDown(app.dispose);

      await observer.firstPaint.future.timeout(const Duration(seconds: 5));
      final screen = host.querySelector('.fleury-screen')!;
      expect(screen.querySelectorAll('.fleury-row').length, greaterThan(0));
      final initial = screen.innerHTML;
      await observer.animatedPaints.future.timeout(const Duration(seconds: 5));
      expect(screen.innerHTML, isNot(initial));
    });
  }
}
