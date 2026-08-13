@TestOn('vm')
library;

import 'dart:io';

import 'package:fleury/fleury_core.dart' show Widget;
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../doc_snippets/filterable_list.dart' as tutorial;
import '../doc_snippets/forms.dart' as forms;
import '../doc_snippets/getting_started_app.dart' as getting_started;
import '../doc_snippets/layout_demo.dart' as layout;
import '../doc_snippets/list_demo.dart' as lists;
import '../doc_snippets/navigation_demo.dart' as navigation;
import '../doc_snippets/navigation_advanced_demos.dart' as navigation_advanced;

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
}
