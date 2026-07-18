import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalOutputRegion', () {
    test('maps captured output to structured log entries', () {
      final entries = buildTerminalOutputLogEntries(const [
        LogLine('ok', LogSource.stdout),
        LogLine('bad', LogSource.stderr),
      ]);

      expect(entries, hasLength(2));
      expect(entries.first.id, 0);
      expect(entries.first.source, 'stdout');
      expect(entries.first.severity, LogSeverity.info);
      expect(entries.first.metadata['terminalOutputIndex'], 0);
      expect(entries.last.id, 1);
      expect(entries.last.source, 'stderr');
      expect(entries.last.severity, LogSeverity.error);
      expect(entries.last.metadata['terminalOutputSource'], 'stderr');
    });

    testWidgets('renders scoped captured output with log semantics', (tester) {
      final buffer = LogBuffer()
        ..add(const LogLine('booted', LogSource.stdout))
        ..add(
          const LogLine('bad\x1b]52;c;secret\x07 payload', LogSource.stderr),
        );

      tester.pumpWidget(
        LogBufferScope(
          buffer: buffer,
          child: const SizedBox(
            width: 80,
            height: 4,
            child: TerminalOutputRegion(),
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 4),
        emptyMark: ' ',
      );

      expect(output, contains('[INFO stdout] booted'));
      expect(output, contains('[ERROR stderr] bad'));
      expect(output, isNot(contains('secret')));

      final log = tester.semantics().single(role: SemanticRole.log);
      expect(log.label, 'Terminal output');
      expect(log.state.collectionRowCount, 2);
      expect(log.state.source, 'stderr');
      expect(log.state['copyEnabled'], isTrue);

      final stderr = tester
          .semantics()
          .byRole(SemanticRole.listItem)
          .singleWhere((node) => node.state.source == 'stderr');
      expect(stderr.state['terminalOutputIndex'], 1);
      expect(stderr.state.outputSanitized, isTrue);
    });

    testWidgets('rebuilds when captured output arrives', (tester) {
      final buffer = LogBuffer();
      tester.pumpWidget(
        SizedBox(
          width: 60,
          height: 3,
          child: TerminalOutputRegion(buffer: buffer),
        ),
      );

      expect(
        tester.renderToString(size: const CellSize(60, 3)).trim(),
        isEmpty,
      );

      buffer.add(const LogLine('live line', LogSource.stdout));
      tester.pump();

      expect(
        tester.renderToString(size: const CellSize(60, 3)),
        contains('[INFO stdout] live line'),
      );
    });

    testWidgets('filters output and copies selected visible line', (
      tester,
    ) async {
      final buffer = LogBuffer()
        ..add(const LogLine('compile ok', LogSource.stdout))
        ..add(const LogLine('deploy failed', LogSource.stderr));
      final controller = LogRegionController(
        selectedIndex: 0,
        followTail: false,
      );
      LogRegionCopyResult? copied;

      tester.pumpWidget(
        SizedBox(
          width: 70,
          height: 4,
          child: TerminalOutputRegion(
            buffer: buffer,
            controller: controller,
            autofocus: true,
            filter: const LogRegionFilterDescriptor(query: 'deploy'),
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(70, 4),
        emptyMark: ' ',
      );

      expect(output, contains('[ERROR stderr] deploy failed'));
      expect(output, isNot(contains('compile ok')));

      final log = tester.semantics().single(role: SemanticRole.log);
      expect(log.state.collectionRowCount, 1);
      expect(log.state.filterText, 'deploy');

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '[ERROR stderr] deploy failed');
      expect(copied, isNotNull);
      expect(copied!.entryIndex, 1);
      expect(copied!.viewIndex, 0);
    });

    testWidgets('semantic activate selects a terminal output row', (
      tester,
    ) async {
      final buffer = LogBuffer()
        ..add(const LogLine('compile ok', LogSource.stdout))
        ..add(const LogLine('deploy failed', LogSource.stderr));
      final controller = LogRegionController(
        selectedIndex: 0,
        followTail: false,
      );

      tester.pumpWidget(
        SizedBox(
          width: 70,
          height: 4,
          child: TerminalOutputRegion(
            buffer: buffer,
            controller: controller,
            copyOptions: const LogRegionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
          ),
        ),
      );

      tester.render(size: const CellSize(70, 4));
      var row = tester.semantics().single(
        role: SemanticRole.listItem,
        label: 'deploy failed',
        action: SemanticAction.activate,
      );
      expect(row.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.listItem,
        label: 'deploy failed',
      );

      expect(result.completed, isTrue);
      expect(controller.followTail, isFalse);
      expect(controller.selectedIndex, 1);

      tester.render(size: const CellSize(70, 4));
      row = tester.semantics().single(
        role: SemanticRole.listItem,
        label: 'deploy failed',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state['terminalOutputIndex'], 1);
      expect(row.state.source, 'stderr');

      final log = tester.semantics().single(
        role: SemanticRole.log,
        label: 'Terminal output',
        focused: true,
      );
      expect(log.state.selectedKey, 1);
      expect(log.state['selectedIndex'], 1);
      expect(log.state['selectedSource'], 'stderr');
    });

    testWidgets(
      'a scrollback trim keeps a scrolled-up selection on the same logical '
      'line instead of shifting it onto different content',
      (tester) {
        final buffer = LogBuffer(capacity: 4)
          ..add(const LogLine('L0', LogSource.stdout))
          ..add(const LogLine('L1', LogSource.stdout))
          ..add(const LogLine('L2', LogSource.stdout))
          ..add(const LogLine('L3', LogSource.stdout));
        // A reader scrolled up and parked their selection on 'L1'.
        final controller = LogRegionController(
          selectedIndex: 1,
          followTail: false,
        );

        tester.pumpWidget(
          SizedBox(
            width: 60,
            height: 6,
            child: TerminalOutputRegion(
              buffer: buffer,
              controller: controller,
            ),
          ),
        );
        tester.render(size: const CellSize(60, 6));
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.listItem, selected: true)
              .label,
          'L1',
        );

        // At capacity, one more captured line trims the head ('L0') while the
        // length stays constant, so no count-change/clamp fires.
        buffer.add(const LogLine('L4', LogSource.stdout));
        tester.pump();
        tester.render(size: const CellSize(60, 6));

        // The selection must still describe the same logical line ('L1',
        // re-anchored down one row), not silently become 'L2'.
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.listItem, selected: true)
              .label,
          'L1',
        );
      },
      // The root-cause fix needs a stable logical id that survives a head
      // trim. LogBuffer (packages/fleury/lib/src/runtime/output_capture.dart)
      // exposes no monotonic base/total-added, and its LogLine carries no
      // sequence, so buildTerminalOutputLogEntries can only key on the list
      // index — which is exactly what shifts under a trim. Re-anchoring in the
      // widget alone (delta-tracking or LogLine-instance keys) is a band-aid
      // that misses the null-controller path and const-canonicalized dup
      // lines. Unskip once LogBuffer carries a monotonic offset and the id is
      // base+index. See audit finding terminal_output_region.dart:11.
      skip: 'Blocked on LogBuffer monotonic base offset (core, out of scope).',
    );
  });
}
