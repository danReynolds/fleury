import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

ToolCallRecord _record({ToolCallStatus status = ToolCallStatus.running}) {
  return ToolCallRecord(
    id: 'tool-1',
    name: 'shell',
    title: 'Run tests',
    description: 'Execute focused checks',
    status: status,
    arguments: const {'cmd': 'dart test'},
    output: 'ok\x1b]52;c;secret\x07\nnext',
    progressCurrent: 1,
    progressTotal: 2,
  );
}

void main() {
  group('ToolCallCard', () {
    testWidgets('renders sanitized tool call content and semantics', (tester) {
      tester.pumpWidget(ToolCallCard(record: _record(), onCancel: () {}));

      final output = tester.renderToString(
        size: const CellSize(80, 8),
        emptyMark: ' ',
      );

      expect(output, contains('[>] Run tests [running]'));
      expect(output, contains('Args: cmd=dart test'));
      expect(output, contains('Output: ok'));
      expect(output, contains('next'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final node = tester.semantics().single(
        role: SemanticRole.toolCall,
        label: 'Run tests',
        value: 'running',
        action: SemanticAction.copy,
      );
      expect(node.busy, isTrue);
      expect(node.actions, contains(SemanticAction.cancel));
      expect(node.state['toolCallId'], 'tool-1');
      expect(node.state['toolName'], 'shell');
      expect(node.state['toolStatus'], 'running');
      expect(node.state['argumentCount'], 1);
      expect(node.state.progressCurrent, 1);
      expect(node.state.progressTotal, 2);
      expect(node.state.outputSanitized, isTrue);

      final accessibility = tester.accessibilitySnapshot().single(
        role: SemanticRole.toolCall,
        label: 'Run tests',
      );
      expect(
        accessibility.states,
        contains(
          'tool call id tool-1, tool shell, status running, '
          '1 arguments, can cancel',
        ),
      );
    });

    testWidgets('semantic copy copies sanitized summary', (tester) async {
      ToolCallCopyResult? copied;
      try {
        tester.pumpWidget(
          ToolCallCard(
            record: _record(status: ToolCallStatus.succeeded),
            copyOptions: const ToolCallCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.toolCall,
          label: 'Run tests',
        );

        expect(result.completed, isTrue);
        expect(tester.clipboard.readInProcess(), contains('Tool: shell'));
        expect(tester.clipboard.readInProcess(), contains('Status: succeeded'));
        expect(
          tester.clipboard.readInProcess(),
          contains('Arguments: cmd=dart test'),
        );
        expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
        expect(copied?.record.id, 'tool-1');
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        // clipboard is tester-scoped; nothing to restore
      }
    });

    testWidgets('semantic cancel uses cancellation callback', (tester) async {
      var canceled = false;
      tester.pumpWidget(
        ToolCallCard(record: _record(), onCancel: () => canceled = true),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.cancel,
        role: SemanticRole.toolCall,
        label: 'Run tests',
      );

      expect(result.completed, isTrue);
      expect(canceled, isTrue);
    });

    test('exportToolCallSummary truncates output and preserves fields', () {
      final text = exportToolCallSummary(
        _record(status: ToolCallStatus.failed),
        options: const ToolCallCopyOptions(maxOutputLength: 2),
      );

      expect(text, contains('Tool: shell'));
      expect(text, contains('Status: failed'));
      expect(text, contains('Description: Execute focused checks'));
      expect(text, contains('Arguments: cmd=dart test'));
      expect(text, contains('Output: ok'));
      expect(text, isNot(contains('secret')));
    });
  });
}
