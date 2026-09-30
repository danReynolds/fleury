@TestOn('vm')
library;

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/flutter_map.dart' as demo;

String _screen(FleuryTester tester) =>
    tester.renderToString(size: const CellSize(50, 18), emptyMark: ' ');

void main() {
  testWidgets('the counter counts up from the keyboard', (tester) {
    tester.pumpWidget(const demo.Counter());
    expect(_screen(tester), contains('Count: 0'));

    tester.press(KeySequence.enter);
    tester.press(KeySequence.enter);
    expect(_screen(tester), contains('Count: 2'));
  });

  testWidgets('Ctrl+S and Esc reach the bindings from the focused field', (
    tester,
  ) {
    tester.pumpWidget(const demo.EditorShortcuts());
    tester.type('draft');
    expect(_screen(tester), contains('draft'));

    tester.press(KeySequence.ctrl.s);
    expect(_screen(tester), contains('Saved'));

    tester.press(KeySequence.escape);
    expect(_screen(tester), contains('Changes discarded'));
    expect(_screen(tester), contains('Save'), reason: 'hint bar lists it');
  });

  testWidgets('AnimationBuilder settles on the new target', (tester) {
    tester.pumpWidget(const demo.SelectionMeter());
    expect(_screen(tester), contains('selected: 0.00'));

    tester.press(KeySequence.enter);
    tester.pumpAndSettle();
    expect(_screen(tester), contains('selected: 1.00'));
    expect(_screen(tester), contains('Deselect'));
  });

  testWidgets('push, pop, and popUntil move through the stack', (tester) {
    tester.pumpWidget(
      Navigator(
        transition: RouteTransition.none,
        home: const demo.HomeScreen(),
      ),
    );
    expect(_screen(tester), contains('Open atlas'));

    tester.press(KeySequence.enter); // Open atlas
    expect(_screen(tester), contains('Project atlas'));
    tester.press(KeySequence.enter); // Open settings
    expect(_screen(tester), contains('Project atlas/settings'));

    tester.button('Back').press();
    tester.pumpAndSettle();
    expect(_screen(tester), contains('Project atlas'));
    expect(_screen(tester), isNot(contains('atlas/settings')));

    tester.press(KeySequence.enter); // Open settings again

    tester.button('All projects').press();
    tester.pumpAndSettle();
    expect(_screen(tester), contains('Projects'));
    expect(_screen(tester), isNot(contains('Project atlas')));
  });

  testWidgets('a 2.0 aspect ratio box is half as tall as a 1.0 box', (tester) {
    tester.pumpWidget(const demo.CellBoxes());
    final rows = _screen(tester).split('\n');
    // Side rows plus the top and bottom border rows.
    int heightOf(int column) =>
        rows.where((row) => row.length > column && row[column] == '│').length +
        2;
    expect(heightOf(0), 12);
    expect(heightOf(12), 6);
  });
}
