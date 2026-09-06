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
}
