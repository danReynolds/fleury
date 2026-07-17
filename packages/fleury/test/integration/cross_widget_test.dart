// Cross-widget integration tests.
//
// These exercise paths that touch two or more subsystems
// (modal + focus + text editing, overlay z-ordering, resize-driven
// layout, hot reload + animation) and were impractical to write
// before FleuryTester landed. Per-widget unit tests cover each
// subsystem in isolation; this file pins down the seams.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

class _CaptureContext extends StatelessWidget {
  const _CaptureContext({required this.sink, required this.child});
  final void Function(BuildContext) sink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    sink(context);
    return child;
  }
}

/// Reads a animation's value (implicit reactivity) so it attaches and
/// animates.
class _Show extends StatelessWidget {
  const _Show(this.animation);
  final Animation<Object?> animation;
  @override
  Widget build(BuildContext context) => Text('${animation.value}');
}

void main() {
  group('TextInput inside Modal', () {
    testWidgets('focus restoration after modal close returns to the '
        'underlying TextInput and preserves its controller', (tester) async {
      BuildContext? appCtx;
      final inputFocus = FocusNode(debugLabel: 'app-input');
      final controller = TextEditingController(text: 'partial');

      tester.pumpWidget(
        Navigator(
          home: _CaptureContext(
            sink: (c) => appCtx = c,
            child: TextInput(
              controller: controller,
              focusNode: inputFocus,
              autofocus: true,
            ),
          ),
        ),
      );
      tester.render();
      expect(
        inputFocus.hasFocus,
        isTrue,
        reason: 'underlying TextInput claims focus on first build',
      );

      // Present a modal — its autofocus should steal focus from the
      // TextInput.
      final modal = Navigator.of(appCtx!).present<bool>(
        const Focus(
          autofocus: true,
          debugLabel: 'modal-body',
          child: Text('confirm?'),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));
      tester.render();
      expect(inputFocus.hasFocus, isFalse, reason: 'modal grabbed focus');

      // Dismiss with Esc; focus returns to the TextInput synchronously —
      // pop() lifts the revealed route's ExcludeFocus eagerly, so the
      // restore does not wait for the reveal frame.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      await modal;
      expect(
        inputFocus.hasFocus,
        isTrue,
        reason: 'modal close restored focus to the TextInput',
      );

      // Controller state must have survived the modal lifecycle.
      expect(controller.text, 'partial');

      // The TextInput should still accept keystrokes.
      tester.type('!');
      expect(controller.text, 'partial!');
    });
  });

  group('Overlay z-ordering', () {
    testWidgets('non-opaque entries layer over the base content without '
        'erasing it', (tester) async {
      BuildContext? ctx;
      tester.pumpWidget(
        _CaptureContext(
          sink: (c) => ctx = c,
          child: const Text('background-text'),
        ),
      );
      tester.render();

      // Insert a non-opaque overlay entry that paints in the
      // top-left corner only. The base text below should still show
      // through in the cells the entry doesn't touch.
      final entry = OverlayEntry(
        builder: (_) =>
            const Align(alignment: Alignment.topLeft, child: Text('AA')),
      );
      Overlay.of(ctx!).insert(entry);
      tester.pump();

      final rendered = tester.renderToString(size: const CellSize(20, 1));
      // 'AA' covers cells 0-1 (replacing 'ba'); cells 2-14 still
      // show 'ckground-text' from the base layer.
      expect(
        rendered,
        'AAckground-text\n',
        reason: 'overlay covers cells 0-1, base shows through 2-14',
      );

      entry.remove();
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(20, 1)),
        'background-text\n',
        reason: 'after removal, only base content remains',
      );
    });

    testWidgets('opaque entries hide everything below them', (tester) async {
      BuildContext? ctx;
      tester.pumpWidget(
        _CaptureContext(sink: (c) => ctx = c, child: const Text('hidden')),
      );
      tester.render();

      final entry = OverlayEntry(
        opaque: true,
        builder: (_) => const Text('top'),
      );
      Overlay.of(ctx!).insert(entry);
      tester.pump();

      // Opaque entry suppresses painting of every entry below. The
      // base 'hidden' subtree stays mounted (its state survives),
      // but its build collapses to EmptyBox so no cells are drawn.
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        'top\n',
        reason: 'opaque entry fully covered cells 0-2; nothing else paints',
      );
      entry.remove();

      // Removing the opaque entry should restore the base layer's
      // visibility — its subtree was kept mounted, so this is just
      // a re-show, not a re-mount.
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(10, 1)),
        'hidden\n',
        reason: 'after the opaque entry is removed, base re-shows',
      );
    });
  });

  group('Resize handling', () {
    testWidgets('layout re-computes when the viewport size changes', (tester) {
      tester.pumpWidget(
        const Align(alignment: Alignment.bottomRight, child: Text('X')),
      );

      // Empty cells render as '·' by default; the 'X' sits at the
      // bottom-right corner of each viewport. The assertion shape
      // tracks layout, not glyph choice.
      expect(
        tester.renderToString(size: const CellSize(3, 2)),
        '\n··X\n',
        reason: 'narrow viewport: bottomRight is (2, 1)',
      );

      expect(
        tester.renderToString(size: const CellSize(6, 3)),
        '\n\n·····X\n',
        reason: 'wider viewport: bottomRight is (5, 2)',
      );

      // Narrower viewport — layout adapts down rather than staying
      // stuck on the larger size.
      expect(
        tester.renderToString(size: const CellSize(2, 1)),
        '·X\n',
        reason: 'narrowed viewport: bottomRight is (1, 0)',
      );
    });
  });

  group('Hot reload + animation', () {
    testWidgets('reassemble settles a running animation and clears its '
        'in-flight future', (tester) async {
      final m = Animation(0.0);
      tester.pumpWidget(_Show(m));

      final future = m.to(
        1.0,
        curve: Curves.linear,
        duration: const Duration(milliseconds: 200),
      );
      tester.pump(const Duration(milliseconds: 80));
      expect(m.value, greaterThan(0.0));

      // Simulate the runtime's hot-reload hook order.
      tester.owner.reassembleApplication();
      tester.binding.tickerScheduler.reassemble();

      expect(m.value, 1.0, reason: 'reassemble settles at the target');
      expect(m.isMoving, isFalse);
      await expectLater(future.orCancel, throwsA(isA<TickerCanceled>()));
    });
  });
}
