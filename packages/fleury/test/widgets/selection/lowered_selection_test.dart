// RFC 0019 P2.4 — selection over lowered clusters answers from SOURCE.
//
// Decision 3/14 pinned here: a lowered group is atomic for selection (an
// endpoint inside it snaps outward; crossing any atom selects the whole
// logical cluster), painting highlights every atom, and copy returns the
// canonical joined cluster exactly once — even when a forced component break
// put a line break between atoms. The identity path (no lowering) is
// byte-identical to today's copy behaviour.

import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/rich_text.dart' show RenderRichText;
import 'package:test/test.dart';

import '../../support/harness.dart';

const _family = '\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}'; // 👨‍👩‍👦
const _split = TextPresentationPolicy(lowering: ClusterLowering.split);

MouseEvent _down(int col, int row) => MouseEvent(
  kind: MouseEventKind.down,
  button: MouseButton.left,
  col: col,
  row: row,
);
MouseEvent _drag(int col, int row) => MouseEvent(
  kind: MouseEventKind.drag,
  button: MouseButton.left,
  col: col,
  row: row,
);
MouseEvent _up(int col, int row) => MouseEvent(
  kind: MouseEventKind.up,
  button: MouseButton.left,
  col: col,
  row: row,
);

void main() {
  group('atomic lowered groups in a SelectionArea (e2e)', () {
    // Display: a ␣ 👨 👩 👦 ␣ b  → cells: a=0, sp=1, 👨=2-3, 👩=4-5,
    // 👦=6-7, sp=8, b=9.
    testWidgets('a drag inside the group copies the whole joined cluster', (
      tester,
    ) async {
      tester.pumpWidget(
        SelectionArea(
          copyOnRelease: true,
          child: Text('a $_family b', policy: _split),
        ),
      );
      tester.render(size: const CellSize(12, 1));

      tester.sendMouse(_down(4, 0)); // inside 👩
      tester.sendMouse(_drag(6, 0)); // into 👦
      tester.sendMouse(_up(6, 0));
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
        _family,
        reason: 'crossing any atoms selects the logical cluster; copy is the '
            'SOURCE, joiners included, exactly once',
      );
    });

    testWidgets('a drag from outside snaps its inner endpoint outward', (
      tester,
    ) async {
      tester.pumpWidget(
        SelectionArea(
          copyOnRelease: true,
          child: Text('a $_family b', policy: _split),
        ),
      );
      tester.render(size: const CellSize(12, 1));

      tester.sendMouse(_down(0, 0)); // 'a'
      // Col 4 is 👩's leading cell: the resolved offset lands between atoms —
      // strictly inside the group — and must snap to the group end. (A hit on
      // a continuation cell resolves to the boundary BEFORE its glyph, the
      // framework-wide wide-glyph convention, so col 2/3 would legitimately
      // exclude the group.)
      tester.sendMouse(_drag(4, 0));
      tester.sendMouse(_up(4, 0));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'a $_family');
    });

    testWidgets('painting highlights every atom of a snapped group', (
      tester,
    ) async {
      tester.pumpWidget(
        SelectionArea(child: Text('a $_family b', policy: _split)),
      );
      tester.render(size: const CellSize(12, 1));

      tester.sendMouse(_down(4, 0)); // 👩 leading → between atoms, inside
      tester.sendMouse(_drag(6, 0)); // 👦 leading → between atoms, inside
      tester.sendMouse(_up(6, 0));
      final buf = tester.render(size: const CellSize(12, 1));

      for (var col = 2; col <= 6; col += 2) {
        expect(
          buf.atColRow(col, 0).style.inverse,
          isTrue,
          reason: 'atom cell $col must be highlighted — no endpoint can rest '
              'inside the source cluster',
        );
      }
      expect(buf.atColRow(0, 0).style.inverse, isFalse, reason: "'a' outside");
      expect(buf.atColRow(9, 0).style.inverse, isFalse, reason: "'b' outside");
    });

    testWidgets('identity path: wrapped plain-text copy is unchanged', (
      tester,
    ) async {
      tester.pumpWidget(
        const SelectionArea(
          copyOnRelease: true,
          child: SizedBox(width: 5, child: Text('hello world')),
        ),
      );
      tester.render(size: const CellSize(5, 2));

      tester.sendMouse(_down(0, 0));
      tester.sendMouse(_drag(4, 1));
      tester.sendMouse(_up(4, 1));
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
        'hello\nworl',
        reason: 'no lowered groups → today\'s copy behaviour, byte-identical',
      );
    });
  });

  group('render-object level', () {
    test('a forced component break never leaks into the copied source', () {
      // 'x' + family at maxCols 4 wraps as 'x👨' / '👩👦' — the group's flat
      // range spans the inserted line break. The splice must yield the
      // joined source once, with no newline inside it.
      final t = RenderText(text: 'x$_family', textPolicy: _split)
        ..layout(const CellConstraints(maxCols: 4));
      final buf = CellBuffer(const CellSize(4, 2));
      t.paint(buf, CellOffset.zero);

      t.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      expect(t.getSelectedContent()!.plainText, 'x$_family');
    });

    test('RichText: a cross-span lowered group copies its joined source', () {
      final r = RenderRichText(
        span: const TextSpan(
          children: [
            TextSpan(text: 'x '),
            TextSpan(text: '\u{1F468}\u{200D}', style: CellStyle(bold: true)),
            TextSpan(text: '\u{1F469}\u{200D}\u{1F466}'),
          ],
        ),
        base: CellStyle.empty,
        textPolicy: _split,
      )..layout(const CellConstraints(maxCols: 10));
      final buf = CellBuffer(const CellSize(10, 1));
      r.paint(buf, CellOffset.zero);

      r.dispatchSelectionEvent(
        const SelectionGranularEvent(granularity: SelectionGranularity.all),
      );
      expect(r.getSelectedContent()!.plainText, 'x $_family');
    });

    test('semantics announce the logical text, not the display form', () {
      final tester = FleuryTester(viewportSize: const CellSize(12, 1));
      addTearDown(tester.dispose);
      tester.pumpWidget(Text(_family, policy: _split));
      tester.render();
      final snapshot = tester.semantics();
      expect(
        snapshot.single(label: _family).label,
        _family,
        reason: 'source is canonical for semantics (decision 3)',
      );
    });
  });
}
