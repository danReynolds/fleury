import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('forms showcase completes its validated multi-screen flow', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 30);
    tester.pumpWidget(const FormsShowcaseApp());

    String rendered() =>
        tester.renderToString(size: const CellSize(84, 30), emptyMark: ' ');

    expect(rendered(), contains('Service details'));

    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(rendered(), contains('Enter a service name.'));

    await tester.field('Service name').fill('fleury');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump();
    expect(rendered(), contains('That service name is already in use.'));
    await tester.settle();
    expect(tester.checkbox('Private service'), isEnabled);

    await tester.field('Service name').fill('webhook-worker');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump(const Duration(milliseconds: 300));
    expect(rendered(), contains('Deployment'));

    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump(const Duration(milliseconds: 300));
    expect(rendered(), contains('Review'));
    expect(rendered(), contains('webhook-worker'));

    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(rendered(), contains('Confirm the production deployment.'));

    await tester.checkbox('I reviewed these settings').check();
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 470));
    tester.pump(const Duration(milliseconds: 300));
    expect(rendered(), contains('DEPLOYMENT COMPLETE'));
    expect(rendered(), contains('webhook-worker is live in Toronto.'));
  });

  testWidgets('pending submission keeps the validated details read-only', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 30);
    tester.pumpWidget(const FormsShowcaseApp());
    await tester.field('Service name').fill('webhook-worker');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(tester.button('Checking…'), isDisabled);

    await tester.field('Service name').focus();
    tester.press(KeySequence.ctrl.a);
    tester.sendKey(const KeyEvent(KeyCode.backspace));
    expect(tester.field('Service name'), hasValue('webhook-worker'));
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textArea, label: 'Description')
          .state['readOnly'],
      isTrue,
    );
    expect(tester.checkbox('Private service'), isDisabled);

    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.renderToString(size: const CellSize(84, 30)),
      contains('Choose where and how the service runs.'),
    );
    // The completed request must not leave the details locked when revisited.
    await tester.button('Back').press();
    tester.pump(const Duration(milliseconds: 300));
    await tester.field('Service name').fill('another-worker');
    expect(tester.field('Service name'), hasValue('another-worker'));
    expect(tester.checkbox('Private service'), isEnabled);
  });

  testWidgets('pending deployment blocks Escape as well as Back', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 30);
    tester.pumpWidget(const FormsShowcaseApp());
    await tester.field('Service name').fill('webhook-worker');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    tester.pump(const Duration(milliseconds: 300));
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump(const Duration(milliseconds: 300));
    await tester.checkbox('I reviewed these settings').check();
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(tester.button('Back'), isDisabled);

    final navigator =
        (tester.findOne(byType(Navigator)) as StatefulElement).state
            as NavigatorState;
    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump();
    expect(
      navigator.depth,
      3,
      reason: 'Escape must respect pending submission.',
    );
    expect(tester.checkbox('I reviewed these settings'), isDisabled);
    // Hold frame time while the request completes, covering delayed exits.
    await Future<void>.delayed(const Duration(milliseconds: 470));
    await tester.settle();
    expect(navigator.depth, 3);
    expect(
      tester.renderToString(size: const CellSize(84, 30)),
      contains('DEPLOYMENT COMPLETE'),
    );
    // The guard belongs to the review route; it must not trap the success page.
    tester.sendKey(const KeyEvent(KeyCode.escape));
    await tester.settle();
    expect(navigator.depth, 2);
  });
  testWidgets('Review then Escape before validation preserves deployment', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 30);
    tester.pumpWidget(const FormsShowcaseApp());
    await tester.field('Service name').fill('audit-worker');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    await tester.settle();
    await tester.button('Review').focus();
    final navigator =
        (tester.findOne(byType(Navigator)) as StatefulElement).state
            as NavigatorState;
    expect(navigator.depth, 2);
    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump();
    expect(navigator.depth, 2);
    await tester.settle();
    expect(navigator.depth, 3);
    expect(
      tester.renderToString(size: tester.viewportSize),
      contains('Confirm the complete deployment before it starts.'),
    );
  });

  testWidgets('Submit then Escape before validation stays on review', (
    tester,
  ) async {
    tester.viewportSize = const CellSize(84, 30);
    tester.pumpWidget(const FormsShowcaseApp());
    await tester.field('Service name').fill('audit-worker');
    await tester.target(role: SemanticRole.form).submit();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    await tester.settle();
    await tester.target(role: SemanticRole.form).submit();
    await tester.settle();
    await tester.checkbox('I reviewed these settings').check();
    await tester.button('Deploy service').focus();
    final navigator =
        (tester.findOne(byType(Navigator)) as StatefulElement).state
            as NavigatorState;
    expect(navigator.depth, 3);
    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump();
    final depthAfterBack = navigator.depth;
    // Deliberately delay rendering the exit animation while real work runs.
    await Future<void>.delayed(const Duration(milliseconds: 470));
    await tester.settle();
    final screen = tester.renderToString(size: tester.viewportSize);
    expect(
      depthAfterBack,
      3,
      reason: 'An accepted deployment must prevent Back from leaving review.',
    );
    expect(navigator.depth, 3);
    expect(screen, contains('DEPLOYMENT COMPLETE'));
  });
}
