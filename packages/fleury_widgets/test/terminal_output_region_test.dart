import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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
  });
}
