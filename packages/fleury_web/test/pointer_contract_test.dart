@TestOn('browser')
library;

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/input/dom_input_source.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void pointer(
  web.Element host,
  String kind, {
  int x = 15,
  int y = 10,
  int buttons = 1,
}) {
  host.dispatchEvent(
    web.PointerEvent(
      kind,
      web.PointerEventInit(
        pointerId: 1,
        clientX: x,
        clientY: y,
        button: 0,
        buttons: buttons,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

void main() {
  test('cursor hints survive the wire and yield to a child control', () async {
    final tester = FleuryTester(viewportSize: const CellSize(20, 3));
    final root = web.document.createElement('div');
    final presenter = SemanticDomPresenter(root: root);
    addTearDown(tester.dispose);
    addTearDown(presenter.dispose);
    tester.pumpWidget(
      MouseRegion(
        cursor: MouseCursor.resizeLeftRight,
        child: SizedBox(
          width: 10,
          height: 1,
          child: Row(
            children: [
              Semantics(
                role: SemanticRole.button,
                label: 'Open',
                actions: const {SemanticAction.activate},
                child: const Text('Open'),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
    // The served client sees this decoded tree, not the widget objects.
    final encoded = SemanticsWireEncoder().encodeTree(tester.semantics());
    final decoded = SemanticsWireDecoder().apply(encoded!);
    presenter.present(decoded!);
    expect(presenter.mouseCursorAt(const CellOffset(1, 0)), 'pointer');
    expect(presenter.mouseCursorAt(const CellOffset(8, 0)), 'ew-resize');
    expect(presenter.mouseCursorAt(const CellOffset(12, 0)), isNull);
  });

  test(
    'resize cursor stays with capture and clears on release or cancellation',
    () {
      final host = web.document.createElement('div') as web.HTMLElement;
      web.document.body!.appendChild(host);
      var available = true;
      final source = DomInputSource(
        hostElement: host,
        cellMetrics: const _Metrics(),
        mouseCursorResolver: (cell) =>
            available && cell.col == 1 ? 'ew-resize' : null,
      );
      addTearDown(() {
        source.dispose();
        host.remove();
      });
      source.start((_) {});
      pointer(host, 'pointermove', buttons: 0);
      expect(host.style.cursor, 'ew-resize');
      available = false;
      source.refreshPointerCursor();
      expect(
        host.style.cursor,
        isEmpty,
        reason: 'stationary cursor follows a removed region',
      );
      available = true;
      pointer(host, 'pointerdown');
      pointer(host, 'pointermove', x: 85);
      expect(
        host.style.cursor,
        'ew-resize',
        reason: 'keep the press owner outside its bounds',
      );
      pointer(host, 'pointerup', x: 85, buttons: 0);
      expect(host.style.cursor, isEmpty);
      pointer(host, 'pointerdown');
      pointer(host, 'pointercancel', buttons: 0);
      expect(host.style.cursor, isEmpty);
      pointer(host, 'pointermove', buttons: 0);
      expect(host.style.cursor, 'ew-resize');
      pointer(host, 'pointerleave', buttons: 0);
      expect(host.style.cursor, isEmpty);
    },
  );

  for (final end in ['pointercancel', 'lostpointercapture', 'blur']) {
    test('$end cancels a live core press and prevents a late tap', () {
      final tester = FleuryTester(viewportSize: const CellSize(8, 3));
      var pressed = false;
      var taps = 0;
      tester.pumpWidget(
        GestureDetector(
          onTapDown: (_) => pressed = true,
          onTapUp: (_) => pressed = false,
          onTapCancel: () => pressed = false,
          onTap: () => taps++,
          child: const SizedBox(width: 5, height: 1),
        ),
      );
      final host = web.document.createElement('div');
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        cellMetrics: const _Metrics(),
      );
      addTearDown(() {
        source.dispose();
        tester.dispose();
        host.remove();
      });
      source.start((event) {
        if (event is MouseEvent) tester.sendMouse(event);
      });
      pointer(host, 'pointerdown');
      expect(pressed, isTrue);
      if (end == 'blur') {
        host
            .querySelector('textarea')!
            .dispatchEvent(web.FocusEvent('focusout'));
      } else {
        pointer(host, end, buttons: 0);
      }
      expect(pressed, isFalse);
      pointer(host, 'pointerup', buttons: 0);
      host.dispatchEvent(
        web.MouseEvent(
          'click',
          web.MouseEventInit(
            button: 0,
            detail: 1,
            clientX: 15,
            clientY: 10,
            bubbles: true,
          ),
        ),
      );
      expect(taps, 0);
    });
  }
  test(
    'DOM surface leave clears hover and allows re-entry at the same cell',
    () {
      final tester = FleuryTester(viewportSize: const CellSize(8, 3));
      var hovered = false;
      tester.pumpWidget(
        MouseRegion(
          onEnter: () => hovered = true,
          onExit: () => hovered = false,
          child: const SizedBox(width: 5, height: 1),
        ),
      );
      final host = web.document.createElement('div');
      web.document.body!.appendChild(host);
      final source = DomInputSource(
        hostElement: host,
        cellMetrics: const _Metrics(),
      );
      addTearDown(() {
        source.dispose();
        tester.dispose();
        host.remove();
      });
      source.start((event) {
        if (event is MouseEvent) tester.sendMouse(event);
      });
      pointer(host, 'pointermove', buttons: 0);
      expect(hovered, isTrue);
      pointer(host, 'pointerleave', x: 95, buttons: 0);
      expect(hovered, isFalse);
      pointer(host, 'pointermove', buttons: 0);
      expect(hovered, isTrue);
    },
  );
  test(
    'assembled mountApp focuses and places the caret in the clicked field',
    () async {
      final host = web.document.createElement('div')
        ..setAttribute(
          'style',
          'position:absolute;left:0;top:0;width:300px;height:96px;font-family:monospace;font-size:16px;line-height:16px;',
        );
      web.document.body!.appendChild(host);
      final a = FocusNode();
      final b = FocusNode();
      final controller = TextEditingController(text: 'abcdef');
      void Function()? pending;
      final mounted = await mountApp(
        () => Column(
          children: [
            SizedBox(
              width: 20,
              child: TextInput(focusNode: a, autofocus: true),
            ),
            SizedBox(
              width: 20,
              child: TextInput(focusNode: b, controller: controller),
            ),
          ],
        ),
        into: host,
        flushScheduler: (_, callback) {
          pending = callback;
          return () {
            if (identical(pending, callback)) pending = null;
          };
        },
      );
      addTearDown(() async {
        await mounted.dispose();
        a.dispose();
        b.dispose();
        controller.dispose();
        host.remove();
      });
      void flush() {
        final work = pending;
        pending = null;
        work?.call();
      }

      flush();
      await mounted.awaitSemanticIdle();
      final screen = host.querySelector('.fleury-screen')!;
      final spans = screen
          .querySelector('[data-row="1"]')!
          .querySelectorAll('span');
      web.Element? textSpan;
      for (var i = 0; i < spans.length; i++) {
        final span = spans.item(i) as web.Element;
        if (span.textContent?.startsWith('abcdef') ?? false) {
          textSpan = span;
          break;
        }
      }
      expect(textSpan, isNotNull);
      final bounds = textSpan!.getBoundingClientRect();
      final cellWidth = bounds.width / textSpan.textContent!.length;
      for (final kind in ['pointerdown', 'pointerup']) {
        pointer(
          screen,
          kind,
          x: (bounds.left + cellWidth * 2.5).round(),
          y: (bounds.top + bounds.height / 2).round(),
          buttons: kind == 'pointerdown' ? 1 : 0,
        );
        flush();
      }
      expect(b.hasFocus, isTrue);
      expect(a.hasFocus, isFalse);
      expect(controller.caretOffset, 2);
      final capture = host.querySelector('textarea') as web.HTMLTextAreaElement;
      capture.value = 'X';
      capture.dispatchEvent(
        web.InputEvent(
          'input',
          web.InputEventInit(data: 'X', inputType: 'insertText', bubbles: true),
        ),
      );
      flush();
      expect(controller.text, 'abXcdef');
    },
  );
}

class _Metrics implements CellMetrics {
  const _Metrics();
  @override
  MeasuredCellBox get cachedMeasurement => const MeasuredCellBox(
    cssCellWidth: 10,
    cssCellHeight: 20,
    cssCanvasWidth: 80,
    cssCanvasHeight: 60,
    devicePixelRatio: 1,
    cols: 8,
    rows: 3,
  );
  @override
  MeasuredCellBox measure() => cachedMeasurement;
  @override
  CellOffset cellForPoint(double x, double y) =>
      CellOffset((x / 10).floor(), (y / 20).floor());
  @override
  CellOffset cellForViewportPoint(double x, double y) => cellForPoint(x, y);
  @override
  void startObserving(void Function() onMetricsDirty) {}
  @override
  void markDirty() {}
  @override
  void dispose() {}
}
