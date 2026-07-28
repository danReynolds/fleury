// The bounds-observation system: BoundsObserver publishes its child's
// painted screen-space bounds into a BoundsNotifier; consumers react.
//
// The regression this file guards is invisible to a whole-tree re-pump
// (which repaints consumers too): the anchor must move WITHOUT the
// consumer's subtree being dirtied — the live shape of a flyout pinned to
// a chip in a header that reflows underneath it.

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
/// ValueNotifier), so a change can relayout the observed widget WITHOUT
/// touching any consumer's subtree.
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

void main() {
  testWidgets('a mounted BoundsFollower tracks bounds when layout moves them', (
    tester,
  ) {
    final chip = BoundsNotifier();
    final label = _Value<String>('ab');
    tester.pumpWidget(
      ListenableBuilder(
        listenable: label,
        builder: (context, _) => Row(
          children: <Widget>[
            Text(label.value),
            BoundsObserver(notifier: chip, child: const Text('@')),
          ],
        ),
      ),
    );
    tester.render(size: _size);

    // The float lives in its own overlay entry: rebuilding the header
    // never dirties this subtree.
    tester.overlay.insert(
      OverlayEntry(
        builder: (_) => BoundsFollower(notifier: chip, child: const Text('¤')),
      ),
    );
    tester.pump();

    final anchor0 = _find(tester, '@');
    final float0 = _find(tester, '¤');
    expect(anchor0, isNotNull);
    expect(float0!.col, anchor0!.col, reason: 'starts under the anchor');

    label.value = 'abcdefghij'; // the anchor slides right
    tester.pump();

    final anchor1 = _find(tester, '@');
    final float1 = _find(tester, '¤');
    expect(anchor1!.col, greaterThan(anchor0.col), reason: 'anchor moved');
    expect(
      float1!.col,
      anchor1.col,
      reason: 'the float tracked it instead of staying at the old column',
    );
  });

  group('BoundsNotifier semantics', () {
    test('publishing a different value notifies; an equal one does not', () {
      final chip = BoundsNotifier();
      var notifications = 0;
      chip.addListener(() => notifications++);

      chip.publish(
        const CellRect(offset: CellOffset(3, 2), size: CellSize(4, 1)),
      );
      expect(notifications, 1, reason: 'first paint published bounds');

      // A static widget re-publishes identical bounds every paint — that
      // must stay free, or every frame would invalidate every consumer.
      chip.publish(
        const CellRect(offset: CellOffset(3, 2), size: CellSize(4, 1)),
      );
      expect(notifications, 1, reason: 'equal observation dropped');

      chip.publish(
        const CellRect(offset: CellOffset(14, 2), size: CellSize(4, 1)),
      );
      expect(notifications, 2, reason: 'the widget moved');

      chip.publish(null);
      expect(notifications, 3, reason: 'the widget left the tree');
      expect(chip.bounds, isNull);
      expect(chip.visibleBounds, isNull);
    });

    test('visibleBounds is the clip intersection; null when clipped out', () {
      final chip = BoundsNotifier();
      const full = CellRect(offset: CellOffset(10, 2), size: CellSize(8, 1));

      chip.publish(
        full,
        clip: const CellRect(offset: CellOffset(0, 0), size: CellSize(14, 8)),
      );
      expect(chip.bounds, full, reason: 'full bounds always kept');
      expect(
        chip.visibleBounds,
        const CellRect(offset: CellOffset(10, 2), size: CellSize(4, 1)),
        reason: 'visible portion is the intersection',
      );

      // Scrolled entirely out of the clip: visible goes null, full stays.
      chip.publish(
        full,
        clip: const CellRect(offset: CellOffset(0, 4), size: CellSize(40, 4)),
      );
      expect(chip.bounds, full);
      expect(chip.visibleBounds, isNull);
    });

    test('a second writer claim throws in debug; release frees it', () {
      final chip = BoundsNotifier();
      final a = Object();
      final b = Object();

      chip.claimWriter(a);
      expect(
        () => chip.claimWriter(b),
        throwsStateError,
        reason: 'a notifier carries ONE widget\'s bounds',
      );

      chip.releaseWriter(b);
      expect(
        () => chip.claimWriter(b),
        throwsStateError,
        reason: 'releasing from a non-owner is a no-op',
      );

      chip.releaseWriter(a);
      chip.claimWriter(b); // freed → a new observer may claim
    });
  });

  group('consumers', () {
    testWidgets('BoundsFollower hides while the anchor is clipped out of view', (
      tester,
    ) {
      final chip = BoundsNotifier();
      tester.pumpWidget(
        Stack(
          children: <Widget>[
            const Text('backdrop'),
            BoundsFollower(notifier: chip, child: const Text('¤')),
          ],
        ),
      );

      // Drive the notifier directly: visible → the float paints.
      chip.publish(
        const CellRect(offset: CellOffset(2, 0), size: CellSize(4, 1)),
      );
      expect(_find(tester, '¤'), isNotNull, reason: 'visible anchor → float');

      // Same bounds, but fully outside the clip → the float disappears.
      chip.publish(
        const CellRect(offset: CellOffset(2, 0), size: CellSize(4, 1)),
        clip: const CellRect(offset: CellOffset(0, 6), size: CellSize(40, 2)),
      );
      expect(
        _find(tester, '¤'),
        isNull,
        reason: 'clipped-out anchor → nothing to attach to → hidden',
      );
    });

    testWidgets('a consumer stops listening when it leaves the tree', (tester) {
      final chip = BoundsNotifier();
      final show = _Value<bool>(true);
      tester.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (context, _) => Stack(
            children: <Widget>[
              BoundsObserver(notifier: chip, child: const Text('@')),
              if (show.value) BoundsFollower(notifier: chip, child: const Text('¤')),
            ],
          ),
        ),
      );
      tester.render(size: _size);
      expect(chip.hasListeners, isTrue, reason: 'the float subscribed');

      show.value = false;
      tester.pump();
      tester.render(size: _size);
      expect(
        chip.hasListeners,
        isFalse,
        reason: 'unmounting released it — the notifier outlives consumers',
      );
    });

    testWidgets('an unmounting observer clears the observation', (tester) {
      final chip = BoundsNotifier();
      final show = _Value<bool>(true);
      tester.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (context, _) => Stack(
            children: <Widget>[
              if (show.value)
                BoundsObserver(notifier: chip, child: const Text('@')),
              const Text('backdrop'),
            ],
          ),
        ),
      );
      tester.render(size: _size);
      expect(chip.bounds, isNotNull, reason: 'observed while mounted');

      show.value = false;
      tester.pump();
      tester.render(size: _size);
      expect(
        chip.bounds,
        isNull,
        reason:
            'the widget is gone, so the observation is too — and the '
            'writer claim is released for a future observer',
      );

      // A NEW observer may now claim the same notifier without asserting.
      show.value = true;
      tester.pump();
      tester.render(size: _size);
      expect(chip.bounds, isNotNull);
    });
  });
}
