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

void main() {
  testWidgets('a mounted BoundsAnchor tracks bounds when layout moves them', (
    tester,
  ) {
    final chip = BoundsNotifier();
    final label = ValueNotifier<String>('ab');
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
        builder: (_) => BoundsAnchor(notifier: chip, child: const Text('¤')),
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
    testWidgets('BoundsAnchor hides while the anchor is clipped out of view', (
      tester,
    ) {
      final chip = BoundsNotifier();
      tester.pumpWidget(
        Stack(
          children: <Widget>[
            const Text('backdrop'),
            BoundsAnchor(notifier: chip, child: const Text('¤')),
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
      final show = ValueNotifier<bool>(true);
      tester.pumpWidget(
        ListenableBuilder(
          listenable: show,
          builder: (context, _) => Stack(
            children: <Widget>[
              BoundsObserver(notifier: chip, child: const Text('@')),
              if (show.value)
                BoundsAnchor(notifier: chip, child: const Text('¤')),
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
      final show = ValueNotifier<bool>(true);
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
    testWidgets('a genuine double-writer reports ONE error, not a second at '
        'teardown', (tester) {
      // The single-writer assert fires inside `createRenderObject`, so the
      // half-inflated element never got a render object. `unmount` used to
      // reach the throwing `renderObject` getter and pile a second, misleading
      // "has no render object" error on top of the real one.
      final chip = BoundsNotifier();
      Object? thrown;
      try {
        tester.pumpWidget(
          Stack(
            children: <Widget>[
              BoundsObserver(notifier: chip, child: const Text('a')),
              BoundsObserver(notifier: chip, child: const Text('b')),
            ],
          ),
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull, reason: 'the double writer still throws');
      expect(
        '$thrown',
        contains('already has a BoundsObserver'),
        reason: 'the reported failure is the real one, undiluted',
      );
      expect(
        '$thrown',
        isNot(contains('has no render object')),
        reason: 'teardown must not raise a second error on top of the first',
      );
    });

    testWidgets('swapping the notifier moves the subscription with it', (
      tester,
    ) {
      // The `notifier` setter unsubscribes from the old notifier and
      // subscribes to the new one — logic no other test exercises, and a leak
      // here would leave a float tracking bounds it no longer follows.
      final first = BoundsNotifier();
      final second = BoundsNotifier();
      final useSecond = ValueNotifier<bool>(false);

      tester.pumpWidget(
        ListenableBuilder(
          listenable: useSecond,
          builder: (context, _) => Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BoundsObserver(notifier: first, child: const Text('A')),
                  const Text('filler'),
                  BoundsObserver(notifier: second, child: const Text('B')),
                ],
              ),
              BoundsAnchor(
                notifier: useSecond.value ? second : first,
                child: const Text('¤'),
              ),
            ],
          ),
        ),
      );
      tester.render(size: _size);
      expect(first.hasListeners, isTrue, reason: 'subscribed to the first');
      expect(second.hasListeners, isFalse);

      final onFirst = _find(tester, '¤')!;
      final anchorB = _find(tester, 'B')!;

      useSecond.value = true;
      tester.pump();
      tester.render(size: _size);

      expect(
        first.hasListeners,
        isFalse,
        reason:
            'the old notifier was released — otherwise it leaks a '
            'listener and keeps waking a float that no longer follows it',
      );
      expect(second.hasListeners, isTrue, reason: 'moved to the new notifier');

      final onSecond = _find(tester, '¤')!;
      expect(onSecond.row, isNot(onFirst.row), reason: 'it actually moved');
      expect(
        onSecond.row,
        anchorB.row + 1,
        reason: 'now placed against the second observed widget',
      );
    });
  });
}
