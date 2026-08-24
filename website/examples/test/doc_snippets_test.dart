@TestOn('vm')
library;

import 'dart:io';

import 'package:fleury/fleury_core.dart'
    show SemanticAction, SemanticRole, Widget;
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../doc_snippets/filterable_list.dart' as tutorial;
import '../doc_snippets/forms.dart' as forms;
import '../doc_snippets/getting_started_app.dart' as getting_started;
import '../doc_snippets/layout_demo.dart' as layout;
import '../doc_snippets/list_demo.dart' as lists;
import '../doc_snippets/navigation_demo.dart' as navigation;
import '../doc_snippets/navigation_advanced_demos.dart' as navigation_advanced;
import '../doc_snippets/shared_state.dart' as state_management;
import '../doc_snippets/theming.dart' as theming;

/// Guards the compile-checked source behind the prose docs.
///
/// Every program under `doc_snippets/` is the real, finished code that a docs
/// page (tutorial, guide) walks through in steps. Analyzing the directory means
/// a hand-written doc can never drift to reference an API that no longer exists:
/// the moment a snippet stops compiling against the live framework, this test
/// fails. See `doc_snippets/README.md` for the convention.
void main() {
  test('doc_snippets analyze cleanly against the real API', () {
    final result = Process.runSync('dart', const [
      'analyze',
      'doc_snippets',
    ], workingDirectory: Directory.current.path);
    printOnFailure(result.stdout.toString());
    printOnFailure(result.stderr.toString());
    expect(
      result.exitCode,
      0,
      reason:
          'A docs code snippet no longer compiles. Update the program under '
          'doc_snippets/ AND the prose in website/src/content/docs that mirrors '
          'it.',
    );
  });

  testWidgets('final getting-started app renders against the real API', (
    tester,
  ) {
    tester.pumpWidget(const getting_started.MyApp());
    expect(tester.renderToString(emptyMark: ' '), contains('CPU'));
  });

  testWidgets('final tutorial app renders against the real API', (tester) {
    tester.pumpWidget(const tutorial.MyApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Dart'));
  });

  testWidgets('navigation guide app renders against the real API', (tester) {
    tester.pumpWidget(navigation.navigationDemoApp());
    final rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('HOME · STACK DEPTH 1'));
    expect(rendered, contains('Push details'));
  });

  testWidgets('navigation advanced guide demos render against the real API', (
    tester,
  ) {
    final demos = <(Widget Function(), String)>[
      (navigation_advanced.placementDemoApp, 'CHOOSE WHERE TO PRESENT'),
      (navigation_advanced.backGuardDemoApp, 'Edit draft'),
      (navigation_advanced.transitionDemoApp, 'ROUTE TRANSITIONS'),
      (navigation_advanced.nestedFlowDemoApp, 'Start setup'),
    ];
    for (final (build, expected) in demos) {
      tester.pumpWidget(build());
      expect(tester.renderToString(emptyMark: ' '), contains(expected));
    }
  });

  testWidgets('forms guide app renders against the real API', (tester) {
    tester.pumpWidget(forms.formsDemoApp());
    final rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('Create project'));
    expect(rendered, contains('Private project'));
  });

  testWidgets('state management guide local counter updates', (tester) async {
    tester.pumpWidget(state_management.localStateDemoApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 0'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Increment',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });

  testWidgets('state management guide shared counter updates its reader', (
    tester,
  ) async {
    tester.pumpWidget(state_management.sharedStateDemoApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 0'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Increment',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });

  testWidgets('state management guide value notifier updates its reader', (
    tester,
  ) async {
    tester.pumpWidget(state_management.valueNotifierDemoApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Offline'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Connect',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('Online'));
  });

  testWidgets('state management guide model updates its reader', (
    tester,
  ) async {
    tester.pumpWidget(state_management.stateManagementDemoApp());
    expect(
      tester.renderToString(emptyMark: ' '),
      allOf(contains('1 of 3 complete'), contains('Running')),
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Complete next',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('2 of 3 complete'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Pause',
    );
    tester.pump();
    expect(
      tester.renderToString(emptyMark: ' '),
      allOf(contains('2 of 3 complete'), contains('Paused')),
    );
  });

  testWidgets('state management guide inherited widget updates its reader', (
    tester,
  ) async {
    tester.pumpWidget(state_management.inheritedWidgetDemoApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 0'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Increment',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });

  testWidgets('state management guide inherited notifier updates its reader', (
    tester,
  ) async {
    tester.pumpWidget(state_management.inheritedNotifierDemoApp());
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 0'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Increment',
    );
    tester.pump();
    expect(tester.renderToString(emptyMark: ' '), contains('Count: 1'));
  });

  testWidgets('lists guide app renders against the real API', (tester) {
    tester.pumpWidget(lists.listsDemoApp());
    final rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('TASKS'));
    expect(rendered, contains('Task 0001'));
  });

  testWidgets('layout guide app renders against the real API', (tester) {
    tester.pumpWidget(layout.layoutDemoApp());
    final rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('WIDE · TWO PANES'));
    expect(rendered, contains('Preview'));
  });

  testWidgets('theming guide app renders against the real API', (tester) {
    tester.pumpWidget(theming.themingDemoApp());
    final rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('Service name'));
    expect(rendered, contains('Approved'));
    expect(rendered, contains('Deploy'));
    expect(rendered, contains('Queued'));
  });
}
