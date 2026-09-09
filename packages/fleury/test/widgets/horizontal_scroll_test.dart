import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';
import '../support/render_fixtures.dart';

MouseEvent mouse(MouseEventKind kind, int col, int row, {bool shift = false}) =>
    MouseEvent(
      kind: kind,
      button:
          [
            MouseEventKind.down,
            MouseEventKind.up,
            MouseEventKind.drag,
          ].contains(kind)
          ? MouseButton.left
          : MouseButton.none,
      col: col,
      row: row,
      modifiers: {if (shift) KeyModifier.shift},
    );
String line(CellBuffer buffer, [int row = 0]) => [
  for (var c = 0; c < buffer.size.cols; c++)
    buffer.atColRow(c, row).grapheme ?? ' ',
].join();

void main() {
  testWidgets(
    'horizontal document measures, clips, navigates and clamps on resize',
    (t) {
      final c = ScrollController(initialOffset: 3);
      t.pumpWidget(
        ScrollView(
          controller: c,
          scrollDirection: Axis.horizontal,
          autofocus: true,
          child: const Text('0123456789ABCDEF'),
        ),
      );
      expect(line(t.render()), '345678');
      expect((c.contentExtent, c.viewportExtent, c.maxOffset), (16, 6, 10));
      t.press(KeySequence.right);
      expect(line(t.render()), '456789');
      t.press(KeySequence.pageDown);
      expect(c.atEnd, isTrue);
      expect(line(t.render()), 'ABCDEF');
      t.press(KeySequence.home);
      t.pump();
      expect(c.atStart, isTrue);
      c.scrollToEnd();
      expect(line(t.render(size: const CellSize(12, 2))), '456789ABCDEF');
      expect(c.offset, 4);
      expect(
        line(t.render(size: const CellSize(20, 2))).trimRight(),
        '0123456789ABCDEF',
      );
      expect(c.maxOffset, 0);
    },
    viewportSize: const CellSize(6, 2),
  );

  testWidgets(
    'horizontal clipping preserves image source geometry',
    (t) {
      final c = ScrollController(initialOffset: 1);
      t.pumpWidget(
        ScrollView(
          controller: c,
          scrollDirection: Axis.horizontal,
          child: const Row(children: [ImageLeaf(), Text('after')]),
        ),
      );
      final placement = t.render().imagePlacements.single;
      expect(
        [placement.col, placement.row, placement.cols, placement.rows],
        [0, 0, 3, 2],
      );
      expect(
        [placement.boxCols, placement.boxRows, placement.boxOffsetCol],
        [4, 2, 1],
      );
      c.jumpTo(4);
      expect(t.render().imagePlacements, isEmpty);
    },
    viewportSize: const CellSize(3, 2),
  );

  testWidgets(
    'nested panes route each wheel axis without changing focus',
    (t) {
      final outer = ScrollController();
      final inner = ScrollController();
      final node = FocusNode();
      t.pumpWidget(
        ScrollView(
          controller: outer,
          focusNode: node,
          autofocus: true,
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: ScrollView(
                  controller: inner,
                  scrollDirection: Axis.horizontal,
                  edgeBehavior: EdgeBehavior.contain,
                  child: const Text('0123456789ABCDEFGHIJ'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
      t.sendMouse(mouse(MouseEventKind.scrollRight, 1, 0));
      t.pump();
      expect((inner.offset, outer.offset), (3, 0));
      expect(node.hasFocus, isTrue);
      t.sendMouse(mouse(MouseEventKind.scrollDown, 1, 0, shift: true));
      t.pump();
      expect((inner.offset, outer.offset), (6, 0));
      t.sendMouse(mouse(MouseEventKind.scrollDown, 1, 0));
      t.pump();
      expect((inner.offset, outer.offset), (6, 3));
      t.pumpWidget(const Text('done'));
      node.dispose();
    },
    viewportSize: const CellSize(8, 4),
  );

  testWidgets(
    'a horizontal list has a natural height without a gutter',
    (t) {
      t.pumpWidget(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListView(
              scrollDirection: Axis.horizontal,
              children: [Text('AAA'), Text('BBB')],
            ),
            Text('after'),
          ],
        ),
      );
      expect(line(t.render()).trimRight(), 'AAABBB');
      expect(line(t.render(), 1).trimRight(), 'after');
    },
    viewportSize: const CellSize(12, 4),
  );

  testWidgets('horizontal lists diagnose an unbounded width', (t) {
    expect(
      () => t.pumpWidget(
        const Row(
          children: [
            ListView(
              scrollDirection: Axis.horizontal,
              children: [Text('item')],
            ),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('bounded width'),
        ),
      ),
    );
  });

  testWidgets('horizontal scrollbar diagnoses an unbounded height', (t) {
    expect(
      () => t.pumpWidget(
        const Column(
          children: [
            ScrollView(
              scrollDirection: Axis.horizontal,
              scrollbar: true,
              child: Text('wide'),
            ),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('bounded height'),
        ),
      ),
    );
  });

  testWidgetsOnBothTextPolicies(
    'bottom gutter keeps whole glyphs and responds under padding',
    (t, policy) {
      final c = ScrollController();
      t.pumpWidget(
        Padding(
          padding: const EdgeInsets.all(1),
          child: ScrollView(
            controller: c,
            scrollDirection: Axis.horizontal,
            scrollbar: true,
            child: const Text('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'),
          ),
        ),
      );
      var buf = t.render();
      expect(buf.atColRow(1, 2).grapheme, '█');
      t.sendMouse(mouse(MouseEventKind.down, 10, 2));
      t.sendMouse(mouse(MouseEventKind.up, 10, 2));
      t.pump();
      expect(c.atEnd, isTrue);
      buf = t.render();
      expect(buf.atColRow(1, 2).grapheme, '─');
      expect(line(buf, 1).trim(), 'QRSTUVWXYZ');
      for (var col = 0; col < buf.size.cols; col++) {
        if (buf.atColRow(col, 2).role == CellRole.continuation) {
          expect(col, greaterThan(1));
          expect(buf.atColRow(col - 1, 2).role, CellRole.leading);
        }
      }
    },
    viewportSize: const CellSize(12, 4),
  );

  testWidgetsOnBothTextPolicies(
    'a minimum horizontal thumb remains visible at the end',
    (t, policy) {
      final c = ScrollController();
      t.pumpWidget(
        ScrollView(
          controller: c,
          scrollDirection: Axis.horizontal,
          scrollbar: true,
          child: Text('x' * 1000),
        ),
      );
      c.scrollToEnd();
      final buffer = t.render();
      expect(line(buffer, 1), contains('█'));
      final width = policy == TextPresentationPolicy.spec ? 1 : 2;
      final lastGlyphCol = (9 ~/ width - 1) * width;
      expect(buffer.atColRow(lastGlyphCol, 1).grapheme, '█');
    },
    viewportSize: const CellSize(9, 2),
  );

  for (final contain in [false, true]) {
    testWidgets(
      'horizontal edge $contain and cross-axis arrows escape',
      (t) {
        final c = ScrollController();
        final keys = <KeyCode>[];
        t.pumpWidget(
          KeyDetector(
            onKey: (e) => keys.add(e.code),
            child: ScrollView(
              controller: c,
              scrollDirection: Axis.horizontal,
              autofocus: true,
              edgeBehavior: contain
                  ? EdgeBehavior.contain
                  : EdgeBehavior.bubble,
              child: const Text('0123456789'),
            ),
          ),
        );
        t.press(KeySequence.end);
        t.pump();
        t.press(KeySequence.right);
        expect(keys.contains(KeyCode.arrowRight), !contain);
        t.press(KeySequence.down);
        expect(keys, contains(KeyCode.arrowDown));
      },
      viewportSize: const CellSize(6, 2),
    );
  }

  for (final lazy in [false, true]) {
    Widget subject(
      ListController c, {
      bool selectable = true,
      bool scrollbar = false,
      int count = 20,
      void Function(int)? onSelect,
      Axis direction = Axis.horizontal,
    }) {
      Widget item(int i) => SizedBox(width: 4, child: Text('$i...'));
      return lazy
          ? ListView.builder(
              controller: c,
              scrollDirection: direction,
              autofocus: true,
              selectable: selectable,
              scrollbar: scrollbar,
              itemCount: count,
              onSelect: onSelect,
              itemBuilder: (_, i, _) => item(i),
            )
          : ListView(
              controller: c,
              scrollDirection: direction,
              autofocus: true,
              selectable: selectable,
              scrollbar: scrollbar,
              onSelect: onSelect,
              children: [for (var i = 0; i < count; i++) item(i)],
            );
    }

    testWidgets(
      '${lazy ? 'lazy' : 'eager'} list initial item, navigation and scrolled click targets',
      (t) {
        final c = ListController(initialIndex: 4);
        final selected = <int>[];
        t.pumpWidget(subject(c, onSelect: selected.add));
        expect(c.visibleRange, (first: 2, last: 4));
        expect(line(t.render()), '2...3...4...');
        expect(t.render().atColRow(8, 0).style.inverse, isTrue);
        expect(selected, isEmpty);
        t.press(KeySequence.left);
        t.pump();
        expect(c.currentIndex, 3);
        t.press(KeySequence.enter);
        expect(selected, [3]);
        t.sendMouse(mouse(MouseEventKind.down, 1, 0));
        t.sendMouse(mouse(MouseEventKind.up, 1, 0));
        expect(selected, [3, 2]);
        c.jumpToIndex(10);
        t.pump();
        expect(c.currentIndex, 2);
        t.sendMouse(mouse(MouseEventKind.down, 5, 0));
        t.sendMouse(mouse(MouseEventKind.up, 5, 0));
        expect(selected.last, 11);
        t.press(KeySequence.end);
        t.pump();
        expect(c.currentIndex, 19);
        expect(c.atEnd, isTrue);
      },
      viewportSize: const CellSize(12, 2),
    );

    testWidgets(
      '${lazy ? 'lazy' : 'eager'} list partial items and horizontal scrollbar drag',
      (t) {
        final c = ListController();
        t.pumpWidget(subject(c, selectable: false, scrollbar: true));
        c.scrollBy(2);
        expect(line(t.render()), '..1...2...');
        expect(c.currentIndex, isNull);
        expect(line(t.render(), 2), contains('█'));
        t.sendMouse(mouse(MouseEventKind.down, 0, 2));
        t.sendMouse(mouse(MouseEventKind.drag, 30, 2));
        t.sendMouse(mouse(MouseEventKind.up, 30, 2));
        t.pump();
        expect(c.atEnd, isTrue);
        expect(c.visibleRange!.last, 19);
        t.press(KeySequence.home);
        t.pump();
        expect(c.atStart, isTrue);
        t.sendMouse(mouse(MouseEventKind.scrollRight, 1, 0));
        t.pump();
        expect(c.atStart, isFalse);
        t.press(KeySequence.end);
        t.pump();
        t.press(KeySequence.left);
        t.pump();
        expect(c.atEnd, isFalse);
      },
      viewportSize: const CellSize(10, 3),
    );

    testWidgets(
      '${lazy ? 'lazy' : 'eager'} switching axes keeps a visible current item in view',
      (t) {
        final c = ListController(initialIndex: 3);
        t.pumpWidget(subject(c, direction: Axis.vertical));
        expect(c.visibleRange, (first: 0, last: 3));
        t.pumpWidget(subject(c));
        expect(c.currentIndex, 3);
        expect(c.visibleRange!.first, lessThanOrEqualTo(3));
        expect(c.visibleRange!.last, greaterThanOrEqualTo(3));
        c.jumpToIndex(10);
        t.pump();
        t.pumpWidget(subject(c, direction: Axis.vertical));
        expect(
          c.visibleRange!.first,
          10,
          reason: 'an offscreen cursor does not override a deliberate scroll',
        );
      },
      viewportSize: const CellSize(12, 4),
    );

    testWidgets(
      '${lazy ? 'lazy' : 'eager'} list changing axis relayouts retained items',
      (t) {
        final c = ListController(initialIndex: 2);
        t.pumpWidget(subject(c));
        c.scrollBy(1);
        t.pump();
        t.pumpWidget(subject(c, direction: Axis.vertical));
        t.press(KeySequence.down);
        expect(c.currentIndex, 3);
        expect(t.renderToString(), contains('3...'));
        t.pumpWidget(subject(c));
        t.press(KeySequence.right);
        expect(c.currentIndex, 4);
        expect(t.renderToString(), contains('4...'));
      },
      viewportSize: const CellSize(10, 3),
    );
  }

  testWidgets(
    'horizontal separators and keyed reorder preserve the current item',
    (t) {
      final c = ListController(initialIndex: 1);
      var labels = ['AAA', 'BBBB', 'CC'];
      Widget build() => ListView.separated(
        controller: c,
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        itemKeyBuilder: (i) => labels[i],
        itemBuilder: (_, i, _) => Text(labels[i]),
        separatorBuilder: (_, _) => const Text('|'),
      );
      t.pumpWidget(build());
      expect(line(t.render()).trimRight(), 'AAA|BBBB|CC');
      labels = labels.reversed.toList();
      t.pumpWidget(build());
      expect(line(t.render()).trimRight(), 'CC|BBBB|AAA');
      expect(t.render().atColRow(3, 0).style.inverse, isTrue);
      expect(t.render().atColRow(7, 0).style.inverse, isFalse);
    },
    viewportSize: const CellSize(12, 2),
  );

  testWidgets(
    'horizontal lazy lists mount only the window on a distant jump',
    (t) {
      final c = ListController();
      final built = <int>{};
      t.pumpWidget(
        ListView.builder(
          controller: c,
          scrollDirection: Axis.horizontal,
          itemCount: 10000,
          itemBuilder: (_, i, _) {
            built.add(i);
            return SizedBox(width: 4 + i % 2, child: Text('$i'));
          },
        ),
      );
      expect(built.length, lessThan(10));
      built.clear();
      c.jumpToIndex(9000);
      t.pump();
      expect(built.length, lessThan(10));
      expect(c.visibleRange!.first, 9000);
    },
    viewportSize: const CellSize(12, 2),
  );

  for (final list in [false, true]) {
    testWidgetsOnBothTextPolicies(
      '${list ? 'ListView' : 'ScrollView'} clips wide graphemes at both horizontal edges',
      (t, _) {
        final scroll = ScrollController();
        final items = ListController();
        t.pumpWidget(
          list
              ? ListView(
                  children: const [Text('A界B界C界D')],
                  controller: items,
                  selectable: false,
                  scrollDirection: Axis.horizontal,
                )
              : ScrollView(
                  controller: scroll,
                  scrollDirection: Axis.horizontal,
                  child: const Text('A界B界C界D'),
                ),
        );
        for (var offset = 0; offset <= 6; offset++) {
          if (list) {
            items.jumpToIndex(0);
            items.scrollBy(offset);
          } else {
            scroll.jumpTo(offset);
          }
          final buf = t.render(size: const CellSize(4, 2));
          for (var col = 0; col < 4; col++) {
            final cell = buf.atColRow(col, 0);
            if (cell.role == CellRole.continuation) {
              expect(col, greaterThan(0));
              expect(buf.atColRow(col - 1, 0).role, CellRole.leading);
            }
            if (cell.role == CellRole.leading && cell.grapheme == '界') {
              expect(col, lessThan(3));
              expect(buf.atColRow(col + 1, 0).role, CellRole.continuation);
            }
          }
        }
      },
    );
  }
}
