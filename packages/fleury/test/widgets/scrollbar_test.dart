import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

String _col(CellBuffer buf, int col) {
  final sb = StringBuffer();
  for (var r = 0; r < buf.size.rows; r++) {
    final cell = buf.atColRow(col, r);
    sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
  }
  return sb.toString();
}

void main() {
  testWidgets('thumb reflects position and shrinks with content', (tester) {
    final sc = ScrollController();
    Widget tree() => Scrollbar(
      controller: sc,
      child: ScrollView(
        controller: sc,
        child: Column(children: [for (var i = 0; i < 10; i++) Text('row$i')]),
      ),
    );
    tester.pumpWidget(tree());
    // 6 wide → 5 for content + 1 gutter; 4 tall viewport, 10 rows content.
    var buf = tester.render(size: const CellSize(6, 4));
    // thumb = round(4*4/10)=2 rows, at top (offset 0).
    expect(_col(buf, 5), '██││', reason: 'thumb at top, 2 of 4 rows');

    sc.offset = sc.maxOffset; // scroll to bottom
    buf = tester.render(size: const CellSize(6, 4));
    expect(_col(buf, 5), '││██', reason: 'thumb at bottom');
  });

  testWidgets('fills the track when everything fits', (tester) {
    final sc = ScrollController();
    tester.pumpWidget(
      Scrollbar(
        controller: sc,
        child: ScrollView(
          controller: sc,
          child: const Column(children: [Text('a'), Text('b')]),
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(6, 4));
    expect(_col(buf, 5), '████', reason: 'content fits → full thumb');
  });

  testWidgets('reserves a gutter without painting over content', (tester) {
    final sc = ScrollController();
    tester.pumpWidget(
      Scrollbar(
        controller: sc,
        child: ScrollView(
          controller: sc,
          child: const Column(children: [Text('hello')]),
        ),
      ),
    );
    final buf = tester.render(size: const CellSize(8, 2));
    // 'hello' fits in cols 0-6 (7 content cols), gutter at col 7.
    expect(buf.atColRow(0, 0).grapheme, 'h');
    expect(buf.atColRow(7, 0).grapheme, isNot('o'), reason: 'gutter, not text');
  });

  testWidgets('dragging the bar scrolls the controller', (tester) {
    final sc = ScrollController();
    tester.pumpWidget(
      Scrollbar(
        controller: sc,
        child: ScrollView(
          controller: sc,
          child: Column(children: [for (var i = 0; i < 10; i++) Text('row$i')]),
        ),
      ),
    );
    tester.render(size: const CellSize(6, 4)); // populate metrics + geometry
    expect(sc.offset, 0);

    // Press on the gutter (col 5), then drag to the bottom row.
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 5,
        row: 0,
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.drag,
        button: MouseButton.left,
        col: 5,
        row: 3,
      ),
    );
    tester.render(size: const CellSize(6, 4));
    expect(sc.offset, sc.maxOffset, reason: 'dragged to the bottom');
  });

  testWidgets('clicking the track jumps toward that position', (tester) {
    final sc = ScrollController();
    tester.pumpWidget(
      Scrollbar(
        controller: sc,
        child: ScrollView(
          controller: sc,
          child: Column(children: [for (var i = 0; i < 10; i++) Text('row$i')]),
        ),
      ),
    );
    tester.render(size: const CellSize(6, 4));
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 5,
        row: 3,
      ),
    );
    tester.render(size: const CellSize(6, 4));
    expect(sc.offset, greaterThan(0), reason: 'tapped lower → scrolled down');
  });

  testWidgets('Scrollbar.list reflects the visible item range', (tester) {
    final lc = ListController(selectedIndex: 0);
    tester.pumpWidget(
      Scrollbar.list(
        controller: lc,
        child: ListView(
          controller: lc,
          children: [for (var i = 0; i < 12; i++) Text('item$i')],
        ),
      ),
    );
    var buf = tester.render(size: const CellSize(8, 4));
    // 12 items, ~4 visible → thumb ≈ 1-2 rows near top.
    expect(_col(buf, 7).contains('█'), isTrue);
    expect(_col(buf, 7).startsWith('█'), isTrue, reason: 'thumb at top');

    lc.selectedIndex = 11; // jump to end → viewport follows
    buf = tester.render(size: const CellSize(8, 4));
    expect(_col(buf, 7).endsWith('█'), isTrue, reason: 'thumb at bottom');
  });

  group('scrollbar: true opt-in (F6)', () {
    testWidgets('ListView(scrollbar: true) pairs a gutter with no manual '
        'wiring', (tester) {
      // No explicit controller, no Scrollbar wrapper — just the flag.
      tester.pumpWidget(
        ListView.builder(
          scrollbar: true,
          itemCount: 20,
          itemBuilder: (c, i, sel) => Text('r$i'),
        ),
      );
      // 8 wide → 7 content + 1 gutter; 4-row viewport over 20 items.
      final buf = tester.render(size: const CellSize(8, 4));
      // 4 of 20 visible → thumb round(4*4/20)=1 row, pinned to the top.
      expect(_col(buf, 7), '█│││', reason: 'thumb (1 of 4) at top over 20');
    });

    testWidgets('the opt-in gutter follows keyboard scrolling', (tester) {
      tester.pumpWidget(
        ListView.builder(
          scrollbar: true,
          autofocus: true,
          itemCount: 20,
          itemBuilder: (c, i, sel) => Text('r$i'),
        ),
      );
      tester.render(size: const CellSize(8, 4));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end)); // → last item
      final buf = tester.render(size: const CellSize(8, 4));
      expect(
        _col(buf, 7).endsWith('█'),
        isTrue,
        reason: 'thumb reaches the bottom when scrolled to the last item',
      );
    });

    testWidgets('no gutter by default (backward compatible)', (tester) {
      tester.pumpWidget(
        ListView.builder(
          itemCount: 20,
          itemBuilder: (c, i, sel) => Text('r$i'),
        ),
      );
      final lastCol = _col(tester.render(size: const CellSize(8, 4)), 7);
      expect(lastCol.contains('│'), isFalse);
      expect(lastCol.contains('█'), isFalse);
    });

    testWidgets('ScrollView(scrollbar: true) pairs a gutter with no manual '
        'wiring', (tester) {
      tester.pumpWidget(
        ScrollView(
          scrollbar: true,
          child: Column(children: [for (var i = 0; i < 10; i++) Text('row$i')]),
        ),
      );
      // 10 rows content, 4-row viewport → thumb round(4*4/10)=2 at the top.
      final buf = tester.render(size: const CellSize(6, 4));
      expect(_col(buf, 5), '██││', reason: 'thumb (2 of 4) at top over 10 rows');
    });
  });
}
