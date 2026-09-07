@TestOn('browser')
library;

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_web/src/input/dom_input_source.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void pointer(web.Element host, String kind, {int x = 15, int buttons = 1}) {
  host.dispatchEvent(
    web.PointerEvent(
      kind,
      web.PointerEventInit(
        pointerId: 1,
        clientX: x,
        clientY: 10,
        button: 0,
        buttons: buttons,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

void main() {
  test(
    'characterizes cancellation delivery through real DOM source and router',
    () {
      final tester = FleuryTester(viewportSize: const CellSize(8, 3));
      var pressed = false;
      var taps = 0;
      tester.pumpWidget(
        GestureDetector(
          onTapDown: (_, _) => pressed = true,
          onTapUp: (_, _) => pressed = false,
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
      pointer(host, 'pointercancel', buttons: 0);
      print('cancel: pressed=$pressed (should clear)');
      expect(
        pressed,
        isTrue,
        reason: 'Records current bug, not desired contract',
      );
      pointer(host, 'pointerup', buttons: 0);
      print('cancel then late up: taps=$taps (should be 0)');
      expect(taps, 1, reason: 'Cancellation never reached core');
    },
  );

  test('characterizes hover leave delivery through DOM source', () {
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
    print('pointerleave: hovered=$hovered (should clear)');
    expect(hovered, isTrue, reason: 'Records missing surface-exit delivery');
  });

  test('checks click focus in the assembled browser host', () async {
    print('browser click-focus bestArea sentinel=${1 << 62}');
    final host = web.document.createElement('div');
    host.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:300px;'
          'height:96px;font-family:monospace;font-size:16px;line-height:16px;',
    );
    web.document.body!.appendChild(host);
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    final controller = TextEditingController(text: 'abcdef');
    void Function()? pending;
    FocusManager? manager;
    final mounted = await mountApp(
      () => _ProbeBuilder(
        builder: (context) {
          manager = Focus.maybeOf(context);
          return GestureDetector(
            onPointerDown: (event) {
              print(
                'browser routed down: ${event.button} ${event.col},${event.row}; b.rect=${b.rect}',
              );
              print(
                'absorbed=${PointerRouterScope.maybeOf(context)!.focusAbsorbedAt(event.col, event.row)}; nodes=${manager!.attachedNodes.map((node) => '${node.debugLabel}:${node.rect}:clickable=${manager!.isClickable(node)}').toList()}',
              );
            },
            child: Column(
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
          );
        },
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
    final row = screen.querySelector('[data-row="1"]')!;
    web.Element? textSpan;
    final spans = row.querySelectorAll('span');
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
    print(
      'browser before click: a=${a.rect}, b=${b.rect}, span=${textSpan.textContent}, bounds=$bounds, cellWidth=$cellWidth',
    );
    for (final kind in ['pointerdown', 'pointerup']) {
      screen.dispatchEvent(
        web.PointerEvent(
          kind,
          web.PointerEventInit(
            pointerId: 1,
            clientX: (bounds.left + cellWidth * 2.5).round(),
            clientY: (bounds.top + bounds.height / 2).round(),
            button: 0,
            buttons: kind == 'pointerdown' ? 1 : 0,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      flush();
      print(
        'after $kind: focused=${manager?.focusedNode?.debugLabel}, a=${a.hasFocus}, b=${b.hasFocus}',
      );
    }
    print(
      'assembled browser: clickedFieldFocused=${b.hasFocus}, caret=${controller.caretOffset}',
    );
    expect(b.hasFocus, isTrue);
    expect(
      controller.caretOffset,
      6,
      reason: 'Caret placement is still missing',
    );
  });
}

class _ProbeBuilder extends StatelessWidget {
  const _ProbeBuilder({required this.builder});
  final Widget Function(BuildContext) builder;
  @override
  Widget build(BuildContext context) => builder(context);
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
  void startObserving(void Function() callback) {}
  @override
  void markDirty() {}
  @override
  void dispose() {}
}
