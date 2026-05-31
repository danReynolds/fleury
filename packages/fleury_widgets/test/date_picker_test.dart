import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

void main() {
  group('DatePicker', () {
    testWidgets('renders the month / year header and day-of-week labels', (
      tester,
    ) {
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15), // Friday
          onChanged: (_) {},
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(24, 9),
        emptyMark: ' ',
      );
      expect(out.contains('March 2024'), isTrue);
      // Sun-first by default → Su should appear at the start of the
      // day-of-week row.
      expect(out.contains('Su Mo Tu We Th Fr Sa'), isTrue);
    });

    testWidgets('Mon-first opt-in puts Mo first', (tester) {
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          weekStartsOn: CalendarWeekStart.monday,
          onChanged: (_) {},
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(24, 9),
        emptyMark: ' ',
      );
      expect(out.contains('Mo Tu We Th Fr Sa Su'), isTrue);
    });

    testWidgets('Arrow Right moves the cursor by one day', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(selected, _d(2024, 3, 16));
    });

    testWidgets('Arrow Down moves the cursor by one week', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      expect(selected, _d(2024, 3, 22));
    });

    testWidgets('PageDown advances by one month, preserving the day', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
      expect(selected, _d(2024, 4, 15));
    });

    testWidgets('PageDown clamps the day if the next month is shorter', (
      tester,
    ) {
      DateTime? selected;
      // Jan 31 → Feb 29 in a leap year (clamps the day in).
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 1, 31),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.pageDown));
      expect(selected, _d(2024, 2, 29));
    });

    testWidgets(']  pages by one year', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.type(']');
      expect(selected, _d(2025, 3, 15));
    });

    testWidgets('respects firstDate / lastDate bounds — moves clamp', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 1),
          firstDate: _d(2024, 3, 1),
          lastDate: _d(2024, 3, 31),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      // Left from the first day: out of bounds → no callback.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowLeft));
      expect(selected, isNull);
      // Right works fine.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight));
      expect(selected, _d(2024, 3, 2));
    });

    testWidgets('Home / End jump within the month', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.home));
      expect(selected, _d(2024, 3, 1));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
      // March has 31 days.
      expect(selected, _d(2024, 3, 31));
    });

    testWidgets('the selected day cell is highlighted in the grid', (tester) {
      tester.pumpWidget(
        DatePicker(value: _d(2024, 3, 15), autofocus: true, onChanged: (_) {}),
      );
      final buf = tester.render(size: const CellSize(24, 9));
      // Scan for the cell containing '15' and verify its style isn't
      // the default empty style.
      var found = false;
      for (var r = 0; r < 9 && !found; r++) {
        for (var c = 0; c < 22 && !found; c++) {
          if (buf.atColRow(c, r).grapheme == '1' &&
              buf.atColRow(c + 1, r).grapheme == '5') {
            // Make sure both digits share a non-empty style (focus
            // highlight, since autofocus is true).
            expect(buf.atColRow(c, r).style, isNot(CellStyle.empty));
            expect(buf.atColRow(c + 1, r).style, isNot(CellStyle.empty));
            found = true;
          }
        }
      }
      expect(found, isTrue, reason: 'expected to find the selected "15"');
    });
  });
}
