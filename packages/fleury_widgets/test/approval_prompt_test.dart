import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

ApprovalRequest _request() {
  return const ApprovalRequest(
    id: 'deploy.prod',
    title: 'Approve deploy?',
    message: 'Deploy build 42 to production.',
    subject: 'prod',
    details: ['branch main', '2 migrations'],
    severity: ApprovalSeverity.warning,
    confirmLabel: 'Deploy',
    cancelLabel: 'Hold',
  );
}

void main() {
  group('ApprovalPrompt', () {
    testWidgets('renders request content and action buttons', (tester) {
      tester.pumpWidget(
        ApprovalPrompt(request: _request(), onDecision: (_) {}),
      );

      final output = tester.renderToString(
        size: const CellSize(64, 11),
        emptyMark: ' ',
      );

      expect(output, contains('Approve deploy?'));
      expect(output, contains('Deploy build 42 to production.'));
      expect(output, contains('Subject: prod'));
      expect(output, contains('- branch main'));
      expect(output, contains('[ Deploy ]'));
      expect(output, contains('[ Hold ]'));
    });

    testWidgets('exposes approval semantics and accessibility state', (tester) {
      tester.pumpWidget(
        ApprovalPrompt(request: _request(), onDecision: (_) {}),
      );

      final node = tester.semantics().single(
        role: SemanticRole.approval,
        label: 'Approve deploy?',
        value: 'prod',
        action: SemanticAction.submit,
      );

      expect(node.actions, contains(SemanticAction.cancel));
      expect(node.state['approvalId'], 'deploy.prod');
      expect(node.state['severity'], 'warning');
      expect(node.state['approvalSubject'], 'prod');
      expect(node.state['detailCount'], 2);
      expect(node.state['confirmLabel'], 'Deploy');
      expect(node.state['cancelLabel'], 'Hold');

      final accessibility = tester.accessibilitySnapshot().single(
        role: SemanticRole.approval,
        label: 'Approve deploy?',
      );
      expect(accessibility.states, contains('severity warning'));
      expect(
        accessibility.states,
        contains(
          'approval id deploy.prod, subject prod, 2 details, '
          'approve Deploy, deny Hold',
        ),
      );
    });

    testWidgets('semantic submit approves the request', (tester) async {
      ApprovalDecision? decision;
      tester.pumpWidget(
        ApprovalPrompt(
          request: _request(),
          onDecision: (value) => decision = value,
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.submit,
        role: SemanticRole.approval,
        label: 'Approve deploy?',
      );

      expect(result.completed, isTrue);
      expect(decision, ApprovalDecision.approved);
    });

    testWidgets('semantic cancel denies the request', (tester) async {
      ApprovalDecision? decision;
      tester.pumpWidget(
        ApprovalPrompt(
          request: _request(),
          onDecision: (value) => decision = value,
        ),
      );

      final result = await tester.invokeSemanticAction(
        SemanticAction.cancel,
        role: SemanticRole.approval,
        label: 'Approve deploy?',
      );

      expect(result.completed, isTrue);
      expect(decision, ApprovalDecision.denied);
    });

    testWidgets('destructive request focuses Deny and warns; y/n decide', (
      tester,
    ) {
      ApprovalDecision? decision;
      tester.pumpWidget(
        ApprovalPrompt(
          request: const ApprovalRequest(
            id: 'rm.prod',
            title: 'Delete database?',
            message: 'This drops the production database.',
            severity: ApprovalSeverity.destructive,
            confirmLabel: 'Delete',
            cancelLabel: 'Cancel',
          ),
          onDecision: (value) => decision = value,
        ),
      );
      final output = tester.renderToString(
        size: const CellSize(64, 12),
        emptyMark: ' ',
      );
      expect(output, contains('Destructive'));

      // Enter activates the focused button — which must be Deny for a
      // destructive request, so a single Enter can't drop the database.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(decision, ApprovalDecision.denied);
    });

    testWidgets('y approves and n denies from a raw keypress', (tester) {
      ApprovalDecision? decision;
      tester.pumpWidget(
        ApprovalPrompt(
          request: _request(),
          onDecision: (value) => decision = value,
        ),
      );
      tester.sendKey(const KeyEvent(char: 'n'));
      expect(decision, ApprovalDecision.denied);
      tester.sendKey(const KeyEvent(char: 'y'));
      expect(decision, ApprovalDecision.approved);
    });
  });
}
