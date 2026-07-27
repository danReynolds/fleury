// A Follower must track its Anchor when layout moves the anchor while the
// follower stays mounted.
//
// The regression this guards is invisible to a whole-tree re-pump (which
// dirties the follower too, hiding the bug). These tests move the anchor by
// rebuilding ONLY the header — the follower lives in a separate overlay entry
// whose subtree never changes — which is exactly the live shape: a flyout
// pinned to a chip in a header that reflows underneath it.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

const _size = CellSize(40, 8);

({int col, int row})? _find(FleuryTester tester, String glyph) {
  final buf = tester.render(size: _size);
  for (var r = 0; r < _size.rows; r++) {
    for (var c = 0; c < _size.cols; c++) {
      if (buf.atColRow(c, r).grapheme == glyph) return (col: c, row: r);
    }
  }
  return null;
}

/// Minimal external state holder (this framework has ChangeNotifier, not
/// ValueNotifier), so a change can relayout the anchor WITHOUT touching the
/// follower's subtree.
class _Value<T> with ChangeNotifier {
  _Value(this._value);
  T _value;
  T get value => _value;
  set value(T next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }
}

/// A header whose label length is driven from outside the widget tree, so a
/// change relayouts the anchor WITHOUT touching the follower's subtree.
class _Header extends StatefulWidget {
  const _Header({required this.label, required this.link});

  final _Value<String> label;
  final AnchorLink link;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.label,
    builder: (context, _) => Row(
      children: <Widget>[
        Text(widget.label.value),
        Anchor(link: widget.link, child: const Text('@')),
      ],
    ),
  );
}

void main() {
  testWidgets('a mounted Follower tracks its Anchor when layout moves it', (
    tester,
  ) {
    final link = AnchorLink();
    final label = _Value<String>('ab');
    tester.pumpWidget(_Header(label: label, link: link));
    tester.render(size: _size);

    // The follower lives in its own overlay entry: rebuilding the header
    // never dirties this subtree.
    tester.overlay.insert(
      OverlayEntry(
        builder: (_) => Follower(link: link, child: const Text('¤')),
      ),
    );
    tester.pump();

    final anchor0 = _find(tester, '@');
    final follow0 = _find(tester, '¤');
    expect(anchor0, isNotNull);
    expect(follow0!.col, anchor0!.col, reason: 'starts under the anchor');

    // Grow the label — the anchor slides right. The follower's own subtree
    // is untouched.
    label.value = 'abcdefghij';
    tester.pump();

    final anchor1 = _find(tester, '@');
    final follow1 = _find(tester, '¤');
    expect(
      anchor1!.col,
      greaterThan(anchor0.col),
      reason: 'the anchor actually moved',
    );
    expect(
      follow1!.col,
      anchor1.col,
      reason: 'the follower tracked it instead of staying at the old column',
    );
  });

  testWidgets('a Follower tracks an Anchor that moves rows', (tester) {
    final link = AnchorLink();
    final lines = _Value<int>(0);
    tester.pumpWidget(
      ListenableBuilder(
        listenable: lines,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < lines.value; i++) const Text('filler'),
            Anchor(link: link, child: const Text('@')),
          ],
        ),
      ),
    );
    tester.render(size: _size);
    tester.overlay.insert(
      OverlayEntry(
        builder: (_) => Follower(link: link, child: const Text('¤')),
      ),
    );
    tester.pump();

    final before = _find(tester, '¤')!;
    lines.value = 3; // push the anchor down three rows
    tester.pump();

    final anchor = _find(tester, '@')!;
    final after = _find(tester, '¤')!;
    expect(anchor.row, greaterThan(0), reason: 'the anchor moved down');
    expect(
      after.row,
      greaterThan(before.row),
      reason: 'the follower followed it down',
    );
    expect(after.row, anchor.row + 1, reason: 'still just below the anchor');
  });
  // The two tests above exercise the end-to-end placement, but a full
  // re-render repaints the follower regardless — so they would pass even
  // without the fix. These pin the MECHANISM the live path depends on: the
  // link telling a clean follower that it has to repaint.
  group('the link notifies so a cached follower repaints', () {
    test('assigning a different rect notifies; an equal one does not', () {
      final link = AnchorLink();
      var notifications = 0;
      link.addListener(() => notifications++);

      link.rect = const CellRect(
        offset: CellOffset(3, 2),
        size: CellSize(4, 1),
      );
      expect(notifications, 1, reason: 'first paint published bounds');

      // A static anchor re-records identical bounds every paint — that must
      // stay free, or every frame would invalidate every follower.
      link.rect = const CellRect(
        offset: CellOffset(3, 2),
        size: CellSize(4, 1),
      );
      expect(notifications, 1, reason: 'equal rect is dropped');

      link.rect = const CellRect(
        offset: CellOffset(14, 2),
        size: CellSize(4, 1),
      );
      expect(notifications, 2, reason: 'the anchor moved');

      link.rect = null;
      expect(notifications, 3, reason: 'the anchor left the tree');
    });

    testWidgets('a follower stops listening when it leaves the tree', (tester) {
      final link = AnchorLink();
      final show = _Value<bool>(true);
      tester.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (context, _) => Stack(
            children: <Widget>[
              Anchor(link: link, child: const Text('@')),
              if (show.value) Follower(link: link, child: const Text('¤')),
            ],
          ),
        ),
      );
      tester.render(size: _size);
      expect(link.hasListeners, isTrue, reason: 'the follower subscribed');

      show.value = false;
      tester.pump();
      tester.render(size: _size);
      expect(
        link.hasListeners,
        isFalse,
        reason: 'unmounting released it — the link outlives any one follower',
      );
    });
  });
}
