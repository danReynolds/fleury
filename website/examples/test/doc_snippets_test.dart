@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury_core.dart'
    show AsyncSnapshot, ConnectionState, SemanticAction, SemanticRole, Widget;
import 'package:fleury_test/fleury_test.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import '../doc_snippets/animation.dart' as animation;
import '../doc_snippets/filterable_list.dart' as tutorial;
import '../doc_snippets/forms.dart' as forms;
import '../doc_snippets/getting_started_app.dart' as getting_started;
import '../doc_snippets/layout_demo.dart' as layout;
import '../doc_snippets/list_demo.dart' as lists;
import '../doc_snippets/loading_data.dart' as loading_data;
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

  testWidgets('animation guide trigger demo replays feedback', (tester) async {
    tester.pumpWidget(const animation.ValidationFeedback());
    expect(tester.renderToString(emptyMark: ' '), contains('pilot name'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Validate pilot',
    );
    tester.pump();
    expect(
      tester.renderToString(emptyMark: ' '),
      isNot(contains('Enter any non-empty name')),
      reason: 'the changed feedback should begin fully concealed',
    );
    final field = tester.accessibilitySnapshot().single(
      role: SemanticRole.textField,
      label: 'Pilot name',
    );
    expect(field.states, contains('focused'));
    expect(
      tester.scheduler.activeTickerCount,
      2,
      reason: 'feedback and the refocused text caret should both be active',
    );
    tester.pump(const Duration(milliseconds: 650));
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('Enter any non-empty name'),
    );

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.textField,
      label: 'Pilot name',
      payload: 'River',
    );
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Validate pilot',
    );
    tester.pump();
    tester.pump(const Duration(milliseconds: 650));
    expect(tester.renderToString(emptyMark: ' '), contains('River is cleared'));
  });

  testWidgets('animation guide effect picker changes both lifecycle effects', (
    tester,
  ) async {
    tester.pumpWidget(const animation.EffectPicker());
    tester.pump(const Duration(milliseconds: 700));
    var rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('Fade in'));
    expect(rendered, contains('Fade out'));
    expect(rendered, contains('DEPLOY PREVIEW'));

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Entrance effect',
      payload: 'Wipe in',
    );
    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Exit effect',
      payload: 'Shrink',
    );
    tester.pump();
    rendered = tester.renderToString(emptyMark: ' ');
    expect(rendered, contains('Wipe in'));
    expect(rendered, contains('Shrink'));

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Hide sample',
    );
    tester.pump();
    expect(tester.scheduler.activeTickerCount, 1);
    tester.pump(const Duration(milliseconds: 700));
    expect(
      tester.renderToString(emptyMark: ' '),
      isNot(contains('DEPLOY PREVIEW')),
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Show sample',
    );
    tester.pump(const Duration(milliseconds: 800));
    expect(tester.renderToString(emptyMark: ' '), contains('DEPLOY PREVIEW'));
  });

  testWidgets('animation guide progress demo exposes a double', (tester) async {
    tester.pumpWidget(const animation.ProgressDemo());
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('progress is a double'),
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Send to station',
    );
    tester.pump(const Duration(milliseconds: 550));
    expect(tester.scheduler.activeTickerCount, 1);
  });

  testWidgets('animation guide raw animation can delay and be retargeted', (
    tester,
  ) async {
    tester.pumpWidget(const animation.ManualRoute());
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('progress.value is a double'),
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Run route',
    );
    tester.pump(const Duration(milliseconds: 700));
    expect(tester.scheduler.activeTickerCount, 1);
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('Package position: 24'),
    );

    tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('Package position: 24'),
      reason: 'the chained delay keeps the package at the station',
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Return now',
    );
    tester.pump(const Duration(milliseconds: 250));
    expect(tester.scheduler.activeTickerCount, 1);
    expect(
      tester.renderToString(emptyMark: ' '),
      isNot(contains('Package position: 24')),
    );
  });

  testWidgets('animation guide launch reaches orbit without changing height', (
    tester,
  ) async {
    tester.pumpWidget(const animation.MissionLaunch());
    final idleHeight = tester.renderToString(emptyMark: ' ').split('\n').length;

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Launch',
    );
    tester.pump(const Duration(milliseconds: 350));
    expect(tester.renderToString(emptyMark: ' '), contains('1/4 IGNITION'));

    for (var second = 0; second < 6; second++) {
      tester.pump(const Duration(seconds: 1));
    }

    expect(tester.renderToString(emptyMark: ' '), contains('4/4 DELIVERY'));
    expect(
      tester.renderToString(emptyMark: ' ').split('\n').length,
      idleHeight,
    );
  });

  testWidgets('animation guide frame demo stops and restarts from frame zero', (
    tester,
  ) async {
    tester.pumpWidget(const animation.PacketTransferFrames());
    tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('authored frame 2/6'),
    );

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Pause',
    );
    tester.pump();
    expect(tester.scheduler.activeTickerCount, 0);

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Resume',
    );
    tester.pump();
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('authored frame 1/6'),
    );
    expect(tester.scheduler.activeTickerCount, 1);
  });

  testWidgets('animation guide ticker demo advances and pauses', (
    tester,
  ) async {
    tester.pumpWidget(const animation.TickerSimulation());
    tester.pump(const Duration(milliseconds: 500));
    expect(tester.renderToString(emptyMark: ' '), contains('6.0'));
    expect(tester.scheduler.activeTickerCount, 1);

    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Pause simulation',
    );
    tester.pump();
    expect(tester.scheduler.activeTickerCount, 0);
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

  testWidgets('loading data guide snapshot explorer starts in waiting', (
    tester,
  ) {
    tester.pumpWidget(const loading_data.SnapshotExplorer());
    expect(tester.renderToString(emptyMark: ' '), contains('Loading files…'));
  });

  testWidgets('loading data guide snapshot card distinguishes every outcome', (
    tester,
  ) {
    final cases = <(AsyncSnapshot<List<String>>, String)>[
      (const AsyncSnapshot<List<String>>.nothing(), 'DISCONNECTED'),
      (const AsyncSnapshot<List<String>>.waiting(), 'LOADING'),
      (
        AsyncSnapshot<List<String>>.withError(
          ConnectionState.done,
          StateError('Connection lost'),
        ),
        'ERROR',
      ),
      (
        const AsyncSnapshot<List<String>>.withData(
          ConnectionState.done,
          <String>[],
        ),
        'EMPTY',
      ),
      (
        const AsyncSnapshot<List<String>>.withData(
          ConnectionState.done,
          <String>['alpha.log'],
        ),
        'READY',
      ),
    ];

    for (final (snapshot, label) in cases) {
      tester.pumpWidget(loading_data.AsyncStateCard(snapshot: snapshot));
      expect(tester.renderToString(emptyMark: ' '), contains(label));
    }

    tester.pumpWidget(
      const loading_data.AsyncStateCard(
        snapshot: AsyncSnapshot<List<String>>.withData(
          ConnectionState.waiting,
          <String>['stale.log'],
        ),
      ),
    );
    expect(tester.renderToString(emptyMark: ' '), isNot(contains('stale.log')));
  });

  testWidgets('loading data guide photo viewer renders a decoded image', (
    tester,
  ) async {
    final photo = Completer<img.Image>();
    tester.pumpWidget(loading_data.PhotoViewer(loadPhoto: () => photo.future));
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('Loading a photo from the web…'),
    );

    photo.complete(img.Image(width: 2, height: 2));
    await tester.settle();
    expect(tester.renderToString(emptyMark: ' '), contains('Load another'));
  });

  testWidgets('loading data guide stream grows and completes', (tester) async {
    tester.pumpWidget(const loading_data.TransmissionView());
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('CONNECTING · 0/5 packets'),
    );

    for (var packet = 1; packet <= 5; packet++) {
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Next packet',
      );
      await tester.settle();
    }
    expect(
      tester.renderToString(emptyMark: ' '),
      contains('COMPLETE · 5/5 packets'),
    );
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
