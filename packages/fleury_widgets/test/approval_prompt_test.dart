import 'dart:async';

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
        role: WidgetRoles.approval,
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
        role: WidgetRoles.approval,
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

      await tester
          .target(role: WidgetRoles.approval, label: 'Approve deploy?')
          .submit();

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

      await tester
          .target(role: WidgetRoles.approval, label: 'Approve deploy?')
          .perform(SemanticAction.cancel);

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
      tester.sendKey(const KeyEvent(KeyCode.enter));
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
      tester.sendKey(const KeyEvent(KeyCode.char('n')));
      expect(decision, ApprovalDecision.denied);
      tester.sendKey(const KeyEvent(KeyCode.char('y')));
      expect(decision, ApprovalDecision.approved);
    });

    testWidgets(
      'Esc in a presented prompt denies, and the decision closes it',
      (tester) async {
        // The documented idiom: the decision pops the prompt and becomes the
        // result of present. Esc must answer the request, not close the
        // dialog around a request that is then never answered.
        late BuildContext home;
        tester.pumpWidget(Navigator(home: _Home((context) => home = context)));
        ApprovalDecision? result;
        var closed = false;
        unawaited(
          home
              .present<ApprovalDecision>(
                ApprovalPrompt(request: _request(), onDecision: home.pop),
                transition: RouteTransition.none,
              )
              .then((decision) {
                result = decision;
                closed = true;
              }),
        );
        tester.pump();
        expect(tester.renderToString(), contains('Approve deploy?'));

        tester.sendKey(const KeyEvent(KeyCode.escape));
        await Future<void>.delayed(Duration.zero);
        tester.pump();

        expect(closed, isTrue);
        expect(result, ApprovalDecision.denied);
        expect(home.navigator.depth, 1);
      },
    );

    group('presented', () {
      ({
        List<ApprovalDecision> decisions,
        bool Function() closed,
        NavigatorState navigator,
      })
      present(FleuryTester tester, {required bool barrierDismissible}) {
        late BuildContext home;
        tester.pumpWidget(Navigator(home: _Home((context) => home = context)));
        final decisions = <ApprovalDecision>[];
        var closed = false;
        unawaited(
          home
              .present<ApprovalDecision>(
                ApprovalPrompt(
                  request: _request(),
                  onDecision: (decision) {
                    decisions.add(decision);
                    home.pop(decision);
                  },
                ),
                transition: RouteTransition.none,
                barrierDismissible: barrierDismissible,
              )
              .then((_) => closed = true),
        );
        tester.pump();
        return (
          decisions: decisions,
          closed: () => closed,
          navigator: home.navigator,
        );
      }

      testWidgets('by default, the route\'s semantic dismiss closes it '
          'unanswered', (tester) async {
        final prompt = present(tester, barrierDismissible: true);

        final result = await tester.invokeSemanticAction(
          SemanticAction.dismiss,
          role: SemanticRole.route,
          label: 'ApprovalPrompt',
        );
        await Future<void>.delayed(Duration.zero);
        tester.pump();

        expect(result.status, SemanticActionInvocationStatus.completed);
        expect(prompt.closed(), isTrue);
        expect(prompt.decisions, isEmpty);
      });

      testWidgets('with barrierDismissible false, only a decision closes it', (
        tester,
      ) async {
        final prompt = present(tester, barrierDismissible: false);

        final dismiss = await tester.invokeSemanticAction(
          SemanticAction.dismiss,
          role: SemanticRole.route,
          label: 'ApprovalPrompt',
          allowFailure: true,
        );
        expect(dismiss.status, isNot(SemanticActionInvocationStatus.completed));
        expect(prompt.navigator.maybePop(), isFalse, reason: 'nor a Back');
        expect(prompt.closed(), isFalse);
        tester.sendKey(const KeyEvent(KeyCode.escape)); // denies
        await Future<void>.delayed(Duration.zero);
        tester.pump();

        expect(prompt.decisions, [ApprovalDecision.denied]);
        expect(prompt.closed(), isTrue);
      });
    });
  });
}

class _Home extends StatelessWidget {
  const _Home(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('home');
  }
}
