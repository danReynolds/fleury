// Lock test: when LogBuffer hits capacity and trims its head, a scrolled-up
// selection parked on a logical line must stay on that line. Today
// buildTerminalOutputLogEntries keys entries by list index only, and LogBuffer
// exposes no monotonic base/totalAdded, so a head trim silently shifts the
// selection onto different content (L1 → L2) while the count stays constant.
// See the skipped twin in terminal_output_region_test.dart.
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'scrollback trim keeps selection on the same logical line',
    (tester) {
      final buffer = LogBuffer(capacity: 4)
        ..add(const LogLine('L0', LogSource.stdout))
        ..add(const LogLine('L1', LogSource.stdout))
        ..add(const LogLine('L2', LogSource.stdout))
        ..add(const LogLine('L3', LogSource.stdout));
      final controller = LogRegionController(
        initialIndex: 1,
        followTail: false,
      );

      tester.pumpWidget(
        SizedBox(
          width: 60,
          height: 6,
          child: TerminalOutputRegion(buffer: buffer, controller: controller),
        ),
      );
      tester.render(size: const CellSize(60, 6));
      expect(
        tester.semantics()
            .single(role: SemanticRole.listItem, selected: true)
            .label,
        'L1',
      );

      buffer.add(const LogLine('L4', LogSource.stdout));
      tester.pump();
      tester.render(size: const CellSize(60, 6));

      expect(
        tester.semantics()
            .single(role: SemanticRole.listItem, selected: true)
            .label,
        'L1',
        reason:
            'trimming L0 must re-anchor the selection onto L1 (now at index '
            '0), not leave currentIndex=1 pointing at L2',
      );
    },
  );
}
