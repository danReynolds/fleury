// Visual regression fence for the public widget surface.
//
// One golden per widget × canonical configuration. The goal is
// "any paint-method change that wasn't intentional shows up as a
// diff in PR review." It is NOT exhaustive parameter coverage —
// edge cases get dedicated tests in their per-widget file.
//
// Add a golden when:
//   - a new public widget lands
//   - a public widget grows a paint-affecting flag worth pinning
//
// Update goldens with:
//
//     FLEURY_UPDATE_GOLDENS=1 dart test test/goldens_test.dart
//
// Review every diff before committing.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Captures the current rendered tree into a string, optionally
/// sized smaller than the default 80x24 viewport.
String _render(FleuryTester tester, {CellSize? size}) =>
    tester.renderToString(size: size);

void main() {
  group('Text', () {
    testWidgets('renders ASCII flush left-top', (tester) {
      tester.pumpWidget(const Text('hello'));
      expect(
        _render(tester, size: const CellSize(20, 3)),
        matchesGolden('text/ascii.txt'),
      );
    });

    testWidgets('wraps when content exceeds width', (tester) {
      tester.pumpWidget(const Text('the quick brown fox'));
      expect(
        _render(tester, size: const CellSize(10, 4)),
        matchesGolden('text/wrapped.txt'),
      );
    });
  });

  group('Container with border', () {
    testWidgets('single-line border with padded text', (tester) {
      tester.pumpWidget(
        const Container(
          border: BoxBorder(style: BorderStyle.single),
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text('hi'),
        ),
      );
      expect(
        _render(tester, size: const CellSize(12, 5)),
        matchesGolden('container/single_border.txt'),
      );
    });

    testWidgets('rounded border', (tester) {
      tester.pumpWidget(
        const Container(
          border: BoxBorder(style: BorderStyle.rounded),
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text('hi'),
        ),
      );
      expect(
        _render(tester, size: const CellSize(12, 5)),
        matchesGolden('container/rounded_border.txt'),
      );
    });

    testWidgets('double border', (tester) {
      tester.pumpWidget(
        const Container(
          border: BoxBorder(style: BorderStyle.double),
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text('hi'),
        ),
      );
      expect(
        _render(tester, size: const CellSize(12, 5)),
        matchesGolden('container/double_border.txt'),
      );
    });

    testWidgets('ascii border', (tester) {
      tester.pumpWidget(
        const Container(
          border: BoxBorder(style: BorderStyle.ascii),
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text('hi'),
        ),
      );
      expect(
        _render(tester, size: const CellSize(12, 5)),
        matchesGolden('container/ascii_border.txt'),
      );
    });
  });

  group('Padding', () {
    testWidgets('all-around padding', (tester) {
      tester.pumpWidget(
        const Padding(padding: EdgeInsets.all(2), child: Text('x')),
      );
      expect(
        _render(tester, size: const CellSize(8, 5)),
        matchesGolden('padding/all.txt'),
      );
    });
  });

  group('Align', () {
    testWidgets('topLeft (no-op against a top-left widget)', (tester) {
      tester.pumpWidget(
        const Align(alignment: Alignment.topLeft, child: Text('A')),
      );
      expect(
        _render(tester, size: const CellSize(5, 3)),
        matchesGolden('align/top_left.txt'),
      );
    });

    testWidgets('center', (tester) {
      tester.pumpWidget(const Align(child: Text('C')));
      expect(
        _render(tester, size: const CellSize(5, 3)),
        matchesGolden('align/center.txt'),
      );
    });

    testWidgets('bottomRight', (tester) {
      tester.pumpWidget(
        const Align(alignment: Alignment.bottomRight, child: Text('R')),
      );
      expect(
        _render(tester, size: const CellSize(5, 3)),
        matchesGolden('align/bottom_right.txt'),
      );
    });
  });

  group('Row / Column', () {
    testWidgets('Row with three text children', (tester) {
      tester.pumpWidget(const Row(children: [Text('a'), Text('b'), Text('c')]));
      expect(
        _render(tester, size: const CellSize(6, 1)),
        matchesGolden('flex/row.txt'),
      );
    });

    testWidgets('Column with three text children', (tester) {
      tester.pumpWidget(
        const Column(children: [Text('a'), Text('b'), Text('c')]),
      );
      expect(
        _render(tester, size: const CellSize(3, 4)),
        matchesGolden('flex/column.txt'),
      );
    });

    testWidgets('Row with Expanded child', (tester) {
      tester.pumpWidget(
        const Row(
          children: [
            Text('a'),
            Expanded(child: Text('mid')),
            Text('c'),
          ],
        ),
      );
      expect(
        _render(tester, size: const CellSize(12, 1)),
        matchesGolden('flex/row_expanded.txt'),
      );
    });
  });

  group('Stack', () {
    testWidgets('three layered children with positioning', (tester) {
      tester.pumpWidget(
        const Stack(
          children: [
            Text('background here'),
            Positioned(left: 2, top: 0, child: Text('FG')),
          ],
        ),
      );
      expect(
        _render(tester, size: const CellSize(20, 2)),
        matchesGolden('stack/positioned.txt'),
      );
    });
  });

  group('SizedBox', () {
    testWidgets('SizedBox of explicit size', (tester) {
      tester.pumpWidget(const SizedBox(width: 5, height: 2, child: Text('x')));
      expect(
        _render(tester, size: const CellSize(10, 4)),
        matchesGolden('sized_box/explicit.txt'),
      );
    });
  });

  group('ListView', () {
    testWidgets('three items selected at index 0', (tester) {
      tester.pumpWidget(
        ListView.builder(
          itemCount: 3,
          itemBuilder: (_, i, sel) => Text(sel ? '> Item $i' : '  Item $i'),
          autofocus: true,
        ),
      );
      expect(
        _render(tester, size: const CellSize(15, 5)),
        matchesGolden('list_view/selected_first.txt'),
      );
    });
  });

  group('Modal (present)', () {
    testWidgets('centered dialog with rounded border', (tester) async {
      tester.pumpWidget(Navigator(home: const Text('app body')));
      final nav = tester.binding.rootNavigator!;

      // Present a framed dialog but don't await — snapshot the open
      // state. present() supplies no chrome, so the border is ours.
      unawaited(
        nav.present<void>(
          const Container(
            border: BoxBorder(style: BorderStyle.rounded),
            padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Text('confirm?'),
          ),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      expect(
        _render(tester, size: const CellSize(30, 7)),
        matchesGolden('modal/centered.txt'),
      );

      // Cleanup so the test doesn't dangle on a pending future.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    });
  });

  group('Spinner', () {
    testWidgets('frame 0 of braille style', (tester) {
      tester.pumpWidget(const Spinner(style: SpinnerStyle.braille));
      expect(
        _render(tester, size: const CellSize(2, 1)),
        matchesGolden('spinner/braille_frame_0.txt'),
      );
    });
  });

  group('BlinkingCursor', () {
    testWidgets('on phase shows the cell', (tester) {
      tester.pumpWidget(const BlinkingCursor());
      expect(
        _render(tester, size: const CellSize(2, 1)),
        matchesGolden('blinking_cursor/on.txt'),
      );
    });
  });
}

/// `await`-suppressor for tests that intentionally fire-and-forget
/// a Future (e.g. opening a modal we'll snapshot then dismiss).
void unawaited(Future<void> _) {}
