// Lock test: LogRegion must not crash on entry ids it does not control.
//
// LogEntry.id is a plain `Object?` documented as "stable identity used by
// semantics and copy callbacks" — nothing tells an app it must be unique, or
// that mixing null and non-null ids is unsafe. ListView treats a duplicate
// item key as fatal, so keying rows on `id ?? viewIndex` turned two entries
// sharing a subsystem id, or a null id next to an int id, into a StateError
// at mount for a widget that rendered them fine before.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('entries sharing an id still render', (tester) {
    tester.pumpWidget(
      const SizedBox(
        width: 30,
        height: 5,
        child: LogRegion(
          entries: [
            LogEntry(message: 'connect', id: 'net'),
            LogEntry(message: 'retry', id: 'net'),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(30, 5));

    expect(tester.renderToString(), contains('connect'));
    expect(tester.renderToString(), contains('retry'));
  });

  testWidgets('a null id beside an int id still renders', (tester) {
    tester.pumpWidget(
      const SizedBox(
        width: 30,
        height: 5,
        child: LogRegion(
          entries: [
            LogEntry(message: 'first', id: 1),
            LogEntry(message: 'second'),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(30, 5));

    expect(tester.renderToString(), contains('first'));
    expect(tester.renderToString(), contains('second'));
  });

  testWidgets('unique ids keep the cursor on the same logical row', (
    tester,
  ) async {
    final controller = LogRegionController();
    addTearDown(controller.dispose);
    Widget build(List<LogEntry> entries) => SizedBox(
      width: 30,
      height: 6,
      child: LogRegion(controller: controller, entries: entries),
    );

    tester.pumpWidget(
      build(const [
        LogEntry(message: 'aaa', id: 10),
        LogEntry(message: 'bbb', id: 11),
        LogEntry(message: 'ccc', id: 12),
        LogEntry(message: 'ddd', id: 13),
      ]),
    );
    tester.render(size: const CellSize(30, 6));
    controller.currentIndex = 1; // 'bbb'
    tester.pump();

    // Head trim of one: 'bbb' moves from index 1 to index 0. Positional
    // identity would leave the cursor on index 1, which is now 'ccc' — a
    // different logical line — and no clamp hides the difference because
    // both indices are still in range.
    tester.pumpWidget(
      build(const [
        LogEntry(message: 'bbb', id: 11),
        LogEntry(message: 'ccc', id: 12),
        LogEntry(message: 'ddd', id: 13),
      ]),
    );
    tester.render(size: const CellSize(30, 6));

    expect(
      controller.currentIndex,
      0,
      reason:
          'the cursor follows bbb to its new index; keying on the stable id '
          'is the whole point of itemKeyBuilder here',
    );
  });
}
