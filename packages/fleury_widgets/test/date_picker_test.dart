import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

// A DST regression only manifests in a zone that observes the transition, so
// the guards below turn into a skip reason under a fixed-offset zone (where
// the buggy and fixed date math agree and the checks would be vacuous).
const _dstSkipReason = 'requires a DST timezone (run with TZ=America/New_York)';

// America/New_York: Nov 3 2024 is a 25h civil day, Mar 9 2025 a 23h one.
final Object _fallBackSkip =
    DateTime(2024, 11, 4).difference(DateTime(2024, 11, 3)).inHours == 25
    ? false
    : _dstSkipReason;
final Object _springForwardSkip =
    DateTime(2025, 3, 10).difference(DateTime(2025, 3, 9)).inHours == 23
    ? false
    : _dstSkipReason;

/// A full left-click (press + release) at one cell. Render first so the
/// pointer router has the current paint-time rects.
void _clickAt(FleuryTester tester, {required int col, required int row}) {
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.down,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.up,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
}

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
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
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
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selected, _d(2024, 3, 22));
    });

    testWidgets('clicking a day cell selects that day', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      // March 2024: day 1 renders in the grid's first row (render row 2) at
      // columns 15-17 (a Friday, with five leading blanks).
      tester.render(size: const CellSize(24, 9));
      _clickAt(tester, col: 16, row: 2);
      expect(selected, _d(2024, 3, 1));
    });

    testWidgets('clicking the > header arrow advances the month', (tester) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      // Header `< March 2024 >`: the › glyph sits at column 13, row 0.
      tester.render(size: const CellSize(24, 9));
      _clickAt(tester, col: 13, row: 0);
      expect(selected, _d(2024, 4, 15));
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
      tester.sendKey(const KeyEvent(KeyCode.pageDown));
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
      tester.sendKey(const KeyEvent(KeyCode.pageDown));
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

    testWidgets('PageUp from January goes to December of the previous year', (
      tester,
    ) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2026, 1, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.pageUp));
      expect(selected, _d(2025, 12, 15));
    });

    testWidgets('PageUp clamps the day if the previous month is shorter', (
      tester,
    ) {
      DateTime? selected;
      // Mar 31 → Feb 29 in a leap year (clamps the day in).
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 31),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.pageUp));
      expect(selected, _d(2024, 2, 29));
    });

    testWidgets('[  pages back one year from mid-year and from January', (
      tester,
    ) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2026, 6, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.type('[');
      expect(selected, _d(2025, 6, 15));

      selected = null;
      tester.pumpWidget(
        DatePicker(
          value: _d(2026, 1, 15),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      tester.type('[');
      expect(selected, _d(2025, 1, 15));
    });

    testWidgets('month/year paging is a no-op past firstDate / lastDate', (
      tester,
    ) {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          firstDate: _d(2024, 3, 1),
          lastDate: _d(2024, 12, 31),
          autofocus: true,
          onChanged: (d) => selected = d,
        ),
      );
      // Backward past firstDate: ignored.
      tester.sendKey(const KeyEvent(KeyCode.pageUp));
      expect(selected, isNull);
      tester.type('[');
      expect(selected, isNull);
      // Forward a year past lastDate: ignored.
      tester.type(']');
      expect(selected, isNull);
      // In-bounds paging still works.
      tester.sendKey(const KeyEvent(KeyCode.pageDown));
      expect(selected, _d(2024, 4, 15));
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
      tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      expect(selected, isNull);
      // Right works fine.
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      expect(selected, _d(2024, 3, 2));
    });

    testWidgets('arrow at a grid edge is unhandled so focus can leave', (
      tester,
    ) {
      // Boundary escape: an arrow stepping off the grid edge must NOT move the
      // selection (it bubbles to directional focus traversal). The DatePicker
      // is controlled, so re-pump per case rather than chaining moves.
      DateTime? selected;
      Widget cal(DateTime v) =>
          DatePicker(value: v, autofocus: true, onChanged: (d) => selected = d);

      // 2024-03-02 is a Saturday — the last column of a Sunday-start week.
      tester.pumpWidget(cal(_d(2024, 3, 2)));
      selected = null;
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      expect(selected, isNull, reason: 'Right at the last column bubbles out');
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selected, _d(2024, 3, 9), reason: 'Down stays inside the grid');

      // 2024-03-03 is a Sunday — the first column.
      selected = null;
      tester.pumpWidget(cal(_d(2024, 3, 3)));
      tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      expect(selected, isNull, reason: 'Left at the first column bubbles out');
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      expect(selected, _d(2024, 3, 4), reason: 'Right stays inside the grid');
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
      tester.sendKey(const KeyEvent(KeyCode.home));
      expect(selected, _d(2024, 3, 1));
      tester.sendKey(const KeyEvent(KeyCode.end));
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
            expect(buf.atColRow(c, r).style, isNot(CellStyle.none));
            expect(buf.atColRow(c + 1, r).style, isNot(CellStyle.none));
            found = true;
          }
        }
      }
      expect(found, isTrue, reason: 'expected to find the selected "15"');
    });

    testWidgets('null onChanged disables the date picker', (tester) async {
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          label: 'Due date',
          autofocus: true,
          onChanged: null,
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.datePicker,
        label: 'Due date',
        enabled: false,
      );
      expect(node.actions, isEmpty);
      expect(node.value, '2024-03-15');
      expect(node.state['canIncrement'], isFalse);
      expect(node.state['canDecrement'], isFalse);

      final buf = tester.render(size: const CellSize(24, 9));
      expect(buf.atColRow(2, 0).style.dim, isTrue, reason: 'month is muted');

      final result = await tester.invokeSemanticAction(
        SemanticAction.increment,
        node: node,
      );
      expect(result.status, SemanticActionInvocationStatus.disabled);
    });

    testWidgets('exposes date picker semantics and accessibility state', (
      tester,
    ) {
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          firstDate: _d(2024, 3, 1),
          lastDate: _d(2024, 3, 31),
          weekStartsOn: CalendarWeekStart.monday,
          label: 'Due date',
          onChanged: (_) {},
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.datePicker,
        label: 'Due date',
        value: '2024-03-15',
        action: SemanticAction.increment,
      );
      expect(node.actions, contains(SemanticAction.decrement));
      expect(node.state['selectedDate'], '2024-03-15');
      expect(node.state['visibleMonth'], '2024-03');
      expect(node.state['visibleYear'], 2024);
      expect(node.state['weekStartsOn'], 'monday');
      expect(node.state['firstDate'], '2024-03-01');
      expect(node.state['lastDate'], '2024-03-31');

      expect(
        tester
            .accessibilitySnapshot()
            .single(role: SemanticRole.datePicker, label: 'Due date')
            .states,
        contains(
          'selected date 2024-03-15, visible month 2024-03, '
          'visible year 2024, week starts monday, first date 2024-03-01, '
          'last date 2024-03-31',
        ),
      );
    });

    testWidgets('semantic increment and decrement move by one day and focus', (
      tester,
    ) async {
      final calls = <DateTime>[];
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          label: 'Due date',
          onChanged: calls.add,
        ),
      );

      final increment = await tester.invokeSemanticAction(
        SemanticAction.increment,
        role: SemanticRole.datePicker,
        label: 'Due date',
      );
      final decrement = await tester.invokeSemanticAction(
        SemanticAction.decrement,
        role: SemanticRole.datePicker,
        label: 'Due date',
      );

      expect(increment.completed, isTrue);
      expect(decrement.completed, isTrue);
      expect(calls, [_d(2024, 3, 16), _d(2024, 3, 14)]);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.datePicker, label: 'Due date')
            .focused,
        isTrue,
      );
    });

    testWidgets('omits bounded date picker semantic actions at limits', (
      tester,
    ) {
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 15),
          firstDate: _d(2024, 3, 15),
          lastDate: _d(2024, 3, 15),
          label: 'Due date',
          onChanged: (_) {},
        ),
      );

      final node = tester.semantics().single(
        role: SemanticRole.datePicker,
        label: 'Due date',
      );
      expect(node.actions, contains(SemanticAction.focus));
      expect(node.actions, isNot(contains(SemanticAction.increment)));
      expect(node.actions, isNot(contains(SemanticAction.decrement)));
      expect(node.state['canIncrement'], isFalse);
      expect(node.state['canDecrement'], isFalse);
      expect(
        tester
            .accessibilitySnapshot()
            .single(role: SemanticRole.datePicker, label: 'Due date')
            .states,
        contains(
          'selected date 2024-03-15, visible month 2024-03, '
          'visible year 2024, week starts sunday, first date 2024-03-15, '
          'last date 2024-03-15, cannot increment, cannot decrement',
        ),
      );
    });

    testWidgets('semantic setValue jumps to an exact ISO date (B4)', (
      tester,
    ) async {
      DateTime? selected;
      tester.pumpWidget(
        DatePicker(
          value: _d(2024, 3, 1),
          firstDate: _d(2024, 1, 1),
          lastDate: _d(2024, 12, 31),
          onChanged: (d) => selected = d,
        ),
      );
      expect(
        tester.semantics().single(role: SemanticRole.datePicker).actions,
        contains(SemanticAction.setValue),
      );

      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.datePicker,
        payload: '2024-07-04',
      );
      expect(selected, _d(2024, 7, 4));

      // Out of [firstDate, lastDate] is a no-op, not a clamp to a wrong date.
      selected = null;
      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.datePicker,
        payload: '2025-01-01',
      );
      expect(selected, isNull);

      // Unparseable date is a no-op.
      await tester.invokeSemanticAction(
        SemanticAction.setValue,
        role: SemanticRole.datePicker,
        payload: 'someday',
      );
      expect(selected, isNull);
    });

    // Cursor movement steps on the calendar lattice, not on absolute elapsed
    // time: a DST-transition civil day is 23h or 25h, so `+ Duration(days: 1)`
    // lands inside the same day (or on the right day at the wrong hour). Only
    // reproducible in a DST-observing zone; the dev tool pins
    // `TZ=America/New_York` for the fleury_widgets run (see
    // tool/fleury_dev.dart), so these execute locally and in CI. Under a
    // fixed-offset zone the buggy and fixed math agree, so skip rather than
    // assert nothing.
    group('DST civil-day stepping', () {
      /// Drives [times] presses of [code], feeding each emitted value back in
      /// as the controlled `value` — the real cursor-walk a user performs.
      DateTime walk(
        FleuryTester tester,
        DateTime start,
        KeyCode code, {
        int times = 1,
      }) {
        var value = start;
        for (var i = 0; i < times; i++) {
          DateTime? emitted;
          tester.pumpWidget(
            DatePicker(
              value: value,
              autofocus: true,
              onChanged: (d) => emitted = d,
            ),
          );
          tester.sendKey(KeyEvent(code));
          expect(emitted, isNotNull, reason: 'press ${i + 1} emitted nothing');
          value = emitted!;
        }
        return value;
      }

      testWidgets('Right walks off a 25h fall-back day', (tester) {
        // Nov 3 2024 is America/New_York's fall-back day (25h). Three Rights
        // must advance three civil days, each at local midnight.
        expect(
          walk(tester, _d(2024, 11, 3), KeyCode.arrowRight),
          _d(2024, 11, 4),
        );
        expect(
          walk(tester, _d(2024, 11, 3), KeyCode.arrowRight, times: 3),
          _d(2024, 11, 6),
        );
      }, skip: _fallBackSkip);

      testWidgets('Down crosses a 25h fall-back day by a full week', (tester) {
        expect(
          walk(tester, _d(2024, 11, 3), KeyCode.arrowDown),
          _d(2024, 11, 10),
        );
      }, skip: _fallBackSkip);

      testWidgets('Up crosses a 23h spring-forward day by a full week', (
        tester,
      ) {
        // Mar 9 2025 is the spring-forward day (23h); -7 from Mar 16.
        expect(walk(tester, _d(2025, 3, 16), KeyCode.arrowUp), _d(2025, 3, 9));
      }, skip: _springForwardSkip);

      testWidgets('Right off a 23h spring-forward day lands at midnight', (
        tester,
      ) {
        // The right civil day but the wrong hour is still wrong: every emitted
        // value is contractually a local midnight.
        final next = walk(tester, _d(2025, 3, 9), KeyCode.arrowRight);
        expect(next, _d(2025, 3, 10));
        expect(next.hour, 0);
      }, skip: _springForwardSkip);

      testWidgets('semantic increment/decrement step civil days', (
        tester,
      ) async {
        DateTime? selected;
        tester.pumpWidget(
          DatePicker(value: _d(2024, 11, 3), onChanged: (d) => selected = d),
        );
        await tester.invokeSemanticAction(
          SemanticAction.increment,
          role: SemanticRole.datePicker,
        );
        expect(selected, _d(2024, 11, 4));

        selected = null;
        tester.pumpWidget(
          DatePicker(value: _d(2025, 3, 10), onChanged: (d) => selected = d),
        );
        await tester.invokeSemanticAction(
          SemanticAction.decrement,
          role: SemanticRole.datePicker,
        );
        expect(selected, _d(2025, 3, 9));
      }, skip: _fallBackSkip);
    });
  });
}
