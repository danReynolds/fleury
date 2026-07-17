// Smoke tests for the motion_recipes example — confirms the trickier
// recipes actually animate as described (not just compile).

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

import '../../example/animation_recipes.dart';

void main() {
  testWidgets('AnimatedCounter springs toward a new value', (tester) {
    var value = 0;
    tester.pumpWidget(AnimatedCounter(value: value));
    expect(tester.renderToString(size: const CellSize(6, 1)), '0\n');

    value = 100;
    tester.pumpWidget(AnimatedCounter(value: value));
    // didUpdateWidget retargets; mid-flight it's between 0 and 100.
    tester.pump(const Duration(milliseconds: 60));
    final mid = int.parse(
      tester.renderToString(size: const CellSize(6, 1)).trim(),
    );
    expect(mid, inExclusiveRange(0, 100));
    tester.pump(const Duration(seconds: 1));
    expect(tester.renderToString(size: const CellSize(6, 1)), '100\n');
  });

  testWidgets('Toast plays slide-in / hold / slide-out then fires '
      'onDismissed', (tester) async {
    var dismissed = false;
    tester.pumpWidget(
      Toast(message: 'hi', onDismissed: () => dismissed = true),
    );

    // Deferred run plays on first display: slides to column 0.
    tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.renderToString(size: const CellSize(10, 1)),
      'hi\n',
      reason: 'slid in to the left edge',
    );
    expect(dismissed, isFalse, reason: 'still in the hold');

    // Through the 2s hold and the slide-out.
    tester.pump(const Duration(seconds: 2));
    tester.pump(const Duration(milliseconds: 300));
    await Future<void>.delayed(Duration.zero);
    expect(dismissed, isTrue, reason: 'sequence finished → onDismissed');
  });

  testWidgets('SelectableRow derives indent + glyph from one driver', (tester) {
    tester.pumpWidget(const SelectableRow(label: 'Inbox', selected: false));
    expect(
      tester.renderToString(size: const CellSize(12, 1), emptyMark: ' '),
      '  Inbox\n',
    );

    tester.pumpWidget(const SelectableRow(label: 'Inbox', selected: true));
    tester.pump(const Duration(seconds: 1));
    // Selected: indented two (empty) cells, with the marker glyph.
    expect(
      tester.renderToString(size: const CellSize(12, 1), emptyMark: ' '),
      '  › Inbox\n',
    );
  });

  testWidgets('BadgeFlash returns to its base color after flashing', (tester) {
    tester.pumpWidget(const BadgeFlash(count: 0));
    final base = tester
        .render(size: const CellSize(4, 1))
        .atColRow(0, 0)
        .style
        .background;

    tester.pumpWidget(const BadgeFlash(count: 1)); // triggers the flash run
    tester.pump(const Duration(milliseconds: 120));
    final flashing = tester
        .render(size: const CellSize(4, 1))
        .atColRow(0, 0)
        .style
        .background;
    expect(flashing, isNot(equals(base)), reason: 'flashed to a new color');

    tester.pump(const Duration(seconds: 1));
    final settled = tester
        .render(size: const CellSize(4, 1))
        .atColRow(0, 0)
        .style
        .background;
    expect(settled, base, reason: 'settled back to base');
  });
}
