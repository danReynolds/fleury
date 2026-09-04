import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/fleury_example_console.dart';

SemanticNode _demoApp(FleuryTester tester) {
  return tester.semantics().single(
    role: SemanticRole.app,
    label: 'Fleury Demo Console',
  );
}

List<SemanticNode> _paletteCommandRows(FleuryTester tester) {
  return tester
      .semantics()
      .where(role: SemanticRole.command)
      .where((node) => node.state['rowIndex'] != null)
      .toList();
}

Future<void> _settleModal(FleuryTester tester) async {
  tester.pump(const Duration(milliseconds: 300));
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}

Future<void> _flushAsyncUi(FleuryTester tester) async {
  tester.pump();
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}

Future<CommandInvocationResult> _invoke(
  FleuryTester tester,
  CommandId command,
) async {
  final result = await tester.invokeCommand(command);
  await _flushAsyncUi(tester);
  tester.render(size: const CellSize(110, 32));
  return result;
}

CellStyle? _styleForRenderedText(
  FleuryTester tester,
  String needle, {
  CellSize size = const CellSize(90, 26),
}) {
  final buffer = tester.render(size: size);
  for (var row = 0; row < buffer.size.rows; row++) {
    for (var col = 0; col <= buffer.size.cols - needle.length; col++) {
      var matched = true;
      for (var i = 0; i < needle.length; i++) {
        final cell = buffer.atColRow(col + i, row);
        if (cell.grapheme != needle[i]) {
          matched = false;
          break;
        }
      }
      if (matched) return buffer.atColRow(col, row).style;
    }
  }
  return null;
}

void main() {
  testWidgets('starts on overview and exposes app semantics', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    expect(tester.exists(text('Fleury Demo Console')), isTrue);
    expect(tester.exists(text('Overview')), isTrue);

    final app = _demoApp(tester);
    expect(app.state.screenCount, 12);
    expect(app.state.activeScreenId, 'overview');
    expect(app.state.commandCount, greaterThanOrEqualTo(8));
    expect(app.state.statusCount, 4);

    final navigation = tester.semantics().single(
      role: SemanticRole.navigation,
      label: 'Demo console navigation',
    );
    expect(navigation.state.screenCount, 12);
    expect(navigation.state.activeScreenId, 'overview');

    final overviewItem = tester.semantics().single(
      role: SemanticRole.listItem,
      label: 'Overview',
      selected: true,
      action: SemanticAction.navigate,
    );
    expect(overviewItem.state.screenId, 'overview');

    final model = tester.semantics().single(
      role: SemanticRole.modelStatus,
      label: 'Model status',
      value: 'ready',
    );
    expect(model.state.modelName, 'fleury-prover');
    expect(model.state.modelProvider, 'local');
    expect(model.state.modelMode, 'demo');
    expect(model.state.modelLatencyMs, 42);
    expect(model.state.contextLimit, 128000);

    final workflow = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Demo workflow snapshot',
    );
    expect(workflow.state.workflowHealth, 'needsAttention');
    expect(workflow.state['workflowId'], 'demo-console');
    expect(workflow.state.messageCount, 2);
    expect(workflow.state.toolCallCount, 0);
    expect(workflow.state.taskCount, 4);
    expect(workflow.state.contextItemCount, 4);
    expect(workflow.state.fileMentionCount, 4);
    expect(workflow.state.conversationCount, 3);
    expect(workflow.state.traceEventCount, 4);
    expect(workflow.state.patchFileCount, 1);

    final snapshot = tester.accessibilitySnapshot();
    final workflowFallback = snapshot.single(
      role: SemanticRole.region,
      label: 'Demo workflow snapshot',
    );
    final workflowFallbackState = workflowFallback.states.join('\n');
    expect(
      workflowFallbackState,
      contains('workflow id demo-console, title Fleury Demo Console'),
    );
    expect(workflowFallbackState, contains('health needsAttention'));
    expect(workflowFallbackState, contains('2 messages'));
    expect(workflowFallbackState, contains('0 tool calls'));
    expect(workflowFallbackState, contains('4 tasks'));
    expect(workflowFallbackState, contains('3 active tasks'));
    expect(workflowFallbackState, contains('4 context items'));
    expect(workflowFallbackState, contains('4 file mentions'));
    expect(workflowFallbackState, contains('3 conversations'));
    expect(workflowFallbackState, contains('1 unread conversation'));
    expect(workflowFallbackState, contains('4 trace events'));
    expect(workflowFallbackState, contains('1 active trace event'));
    expect(workflowFallbackState, contains('1 patch file'));
    expect(workflowFallbackState, contains('1 review issue'));

    final status = snapshot.single(role: SemanticRole.status, label: 'Status');
    final screenStatus = snapshot.single(
      role: SemanticRole.status,
      label: 'Screen',
    );
    final debugStatus = snapshot.single(
      role: SemanticRole.status,
      label: 'Debug',
    );
    expect(status.states, contains('status 4 items'));
    expect(screenStatus.states, contains('status id screen, severity info'));
    expect(debugStatus.value, 'captures 0');
    expect(debugStatus.states, contains('status id debug, severity info'));
    expect(debugStatus.states, contains('command debug.captureSnapshot'));
    expect(debugStatus.actions, contains(SemanticAction.activate));

    final token = tester.semantics().single(
      role: SemanticRole.tokenMeter,
      label: 'Context',
    );
    expect(token.state.contextUsed, greaterThan(2400));
    expect(token.state.contextRatioPercent, greaterThanOrEqualTo(1));

    final contextPanel = tester.semantics().single(
      role: SemanticRole.contextPanel,
      label: 'Demo context',
    );
    expect(contextPanel.state['contextItemCount'], 4);
    expect(contextPanel.state['contextTokenCount'], greaterThan(2300));
    expect(contextPanel.state.contextLimit, 128000);
    expect(contextPanel.state.selectedContextItemId, 'ctx.demo-console');

    final contextPressure = tester.semantics().single(
      role: SemanticRole.chart,
      label: 'Context pressure',
    );
    expect(contextPressure.state.chartType, 'gauge');
    expect(contextPressure.state.chartLatestValue, greaterThan(0));
    expect(contextPressure.state.progressTotal, 100);

    final transcriptTrend = tester.semantics().single(
      role: SemanticRole.chart,
      label: 'Transcript trend',
    );
    expect(transcriptTrend.state.chartType, 'sparkline');
    expect(transcriptTrend.state.chartPointCount, 2);
    expect(transcriptTrend.state.chartLatestValue, greaterThan(0));

    final activityMix = tester.semantics().single(
      role: SemanticRole.chart,
      label: 'Activity mix',
    );
    expect(activityMix.state.chartType, 'bar');
    expect(activityMix.state.chartBarCount, 3);
    expect(activityMix.state.chartSegmentCount, 3);

    final activityFallback = snapshot.single(
      role: SemanticRole.chart,
      label: 'Activity mix',
    );
    expect(
      activityFallback.states,
      contains('chart bar, 3 bars, 3 segments, min 0, max 8'),
    );

    var plan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Demo workflow plan',
    );
    expect(plan.state['taskCount'], 4);
    expect(plan.state['succeededTaskCount'], 1);
    expect(plan.state['pendingTaskCount'], 3);
    expect(plan.actions, contains(SemanticAction.focus));
    expect(plan.actions, contains(SemanticAction.navigate));

    final focusedPlan = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.taskGraph,
      label: 'Demo workflow plan',
    );
    expect(focusedPlan.completed, isTrue);

    tester.render(size: const CellSize(90, 26));
    plan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Demo workflow plan',
      focused: true,
    );
    expect(plan.state.selectedTaskId, 'setup');

    final selectedTask = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.task,
      label: 'Capture diagnostics',
    );
    expect(selectedTask.completed, isTrue);
    tester.render(size: const CellSize(90, 26));

    final diagnosticsTask = tester.semantics().single(
      role: SemanticRole.task,
      label: 'Capture diagnostics',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(diagnosticsTask.state.taskId, 'diagnostics');

    final updatedPlan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Demo workflow plan',
      focused: true,
    );
    expect(updatedPlan.state.selectedTaskId, 'diagnostics');
  });

  testWidgets('sidebar semantic navigation switches demo-app screens', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final runs = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.listItem,
      label: 'Runs',
    );
    expect(runs.completed, isTrue);
    expect(_demoApp(tester).state.activeScreenId, 'runs');
    expect(tester.exists(text('Runs')), isTrue);

    final overview = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.listItem,
      label: 'Overview',
    );
    expect(overview.completed, isTrue);
    expect(_demoApp(tester).state.activeScreenId, 'overview');
  });

  testWidgets('context panel selects demo context items', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());
    tester.render(size: const CellSize(110, 32));

    final contextPanel = tester.semantics().single(
      role: SemanticRole.contextPanel,
      label: 'Demo context',
      action: SemanticAction.focus,
    );
    expect(contextPanel.focused, isFalse);
    expect(contextPanel.actions, contains(SemanticAction.navigate));

    final focusResult = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.contextPanel,
      label: 'Demo context',
    );
    expect(focusResult.completed, isTrue);
    tester.render(size: const CellSize(110, 32));
    expect(
      tester
          .semantics()
          .single(
            role: SemanticRole.contextPanel,
            label: 'Demo context',
            focused: true,
          )
          .state
          .selectedContextItemId,
      'ctx.demo-console',
    );

    final item = tester.semantics().single(
      role: SemanticRole.contextItem,
      label: 'Demo console source',
      action: SemanticAction.activate,
    );
    expect(item.state.contextItemId, 'ctx.demo-console');
    expect(item.state.contextItemKind, 'file');
    expect(item.state.contextItemPriority, 'high');
    expect(item.state.contextItemTokenCount, 1200);
    expect(item.state['pinned'], isTrue);

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.contextItem,
      label: 'Demo console source',
    );
    expect(
      fallback.states,
      contains(
        'context id ctx.demo-console, kind file, 1200 tokens, priority high, '
        'pinned, source packages/fleury_example_console/lib/'
        'fleury_example_console.dart',
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.contextItem,
      label: 'Demo console source',
    );
    expect(result.completed, isTrue);

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));
    expect(
      tester.exists(text('[log] context: selected ctx.demo-console')),
      isTrue,
    );
  });

  testWidgets('commands navigate and update the fake worker', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoRuns);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'runs');

    final started = await _invoke(tester, demoCommandStartWorker);
    expect(started.status, CommandInvocationStatus.completed);
    expect(tester.exists(text('Worker: running 15%')), isTrue);

    final app = _demoApp(tester);
    expect(app.state.lastCommandId, 'worker.startFake');
    expect(app.state.lastCommandStatus, 'completed');

    final overview = await _invoke(tester, demoCommandGoOverview);
    expect(overview.status, CommandInvocationStatus.completed);

    final worker = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Fake worker',
      value: 'running',
    );
    expect(worker.state['workerStatus'], 'running');
    expect(worker.state.progressCurrent, 15);
    expect(worker.state.progressTotal, 100);

    final diagnostics = await _invoke(tester, demoCommandGoDiagnostics);
    expect(diagnostics.status, CommandInvocationStatus.completed);
    tester.render(size: const CellSize(100, 50));

    final taskTimeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Demo trace timeline',
    );
    expect(taskTimeline.state.traceEventCount, greaterThanOrEqualTo(4));

    final workerEvent = tester.semantics().single(
      role: SemanticRole.traceEvent,
      label: 'Fake worker',
    );
    expect(workerEvent.state.traceKind, 'task');
    expect(workerEvent.state.traceStatus, 'running');
    expect(workerEvent.state.source, 'fake-worker');
    expect(workerEvent.state['workerId'], 'fake-worker');

    final overviewAgain = await _invoke(tester, demoCommandGoOverview);
    expect(overviewAgain.status, CommandInvocationStatus.completed);

    final plan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Demo workflow plan',
    );
    expect(plan.state['runningTaskCount'], 1);

    final model = tester.semantics().single(
      role: SemanticRole.modelStatus,
      label: 'Model status',
      value: 'streaming',
      busy: true,
    );
    expect(model.state.modelName, 'fleury-prover');
    expect(model.state.modelQueueDepth, 1);
    expect(model.state.modelStatus, 'streaming');

    tester.render(size: const CellSize(90, 28));
    final planWorker = tester.semantics().single(
      role: SemanticRole.task,
      label: 'Run fake worker',
      busy: true,
    );
    expect(planWorker.state.taskId, 'worker');
    expect(planWorker.state.taskStatus, 'running');
    expect(planWorker.state.progressCurrent, 15);
    expect(planWorker.state.progressTotal, 100);

    final progress = tester.semantics().single(role: SemanticRole.progress);
    expect(progress.value, closeTo(0.15, 0.0001));
    expect(progress.state.progressLabel, '15%');

    final cancel = await _invoke(tester, demoCommandCancelWorker);
    expect(cancel.status, CommandInvocationStatus.completed);

    final canceled = tester.semantics().single(
      role: SemanticRole.status,
      label: 'Fake worker',
    );
    expect(canceled.value, 'canceled');
    expect(canceled.state['workerStatus'], 'canceled');
    expect(tester.exists(text('Worker: canceled')), isTrue);
  });

  testWidgets('command palette can drive app navigation', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandOpenPalette);
    tester.pump(const Duration(milliseconds: 300));
    tester.render(size: const CellSize(80, 24));

    final palette = tester.semantics().single(
      role: SemanticRole.commandPalette,
    );
    expect(palette.state.collectionRowCount, greaterThan(0));

    tester.type('screen.diagnostics');
    tester.pump();
    tester.render(size: const CellSize(80, 24));

    final commandRows = _paletteCommandRows(tester);
    final diagnostics = commandRows.singleWhere(
      (node) => node.label == 'Go to Diagnostics',
    );
    expect(diagnostics.state.commandId, 'screen.diagnostics');
    expect(diagnostics.state.shortcut, 'Ctrl+D');
    expect(diagnostics.state.commandCategory, 'Navigation');

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _settleModal(tester);

    expect(_demoApp(tester).state.activeScreenId, 'diagnostics');
    expect(tester.exists(text('Diagnostics')), isTrue);
  });

  testWidgets('approval command opens a semantic approval prompt', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final opened = await _invoke(tester, demoCommandRequestApproval);
    expect(opened.status, CommandInvocationStatus.completed);
    await _settleModal(tester);

    final approval = tester.semantics().single(
      role: SemanticRole.approval,
      label: 'Approve deploy?',
      value: 'prod',
      action: SemanticAction.submit,
    );
    expect(approval.actions, contains(SemanticAction.cancel));
    expect(approval.state['approvalId'], 'deploy.prod');
    expect(approval.state['severity'], 'warning');
    expect(approval.state['detailCount'], 2);

    final approved = await tester.invokeSemanticAction(
      SemanticAction.submit,
      node: approval,
    );
    expect(approved.completed, isTrue);
    await _settleModal(tester);

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 28));
    expect(
      tester.exists(text('[log] approval: deploy approval granted')),
      isTrue,
    );
  });

  testWidgets('global search debounces query and activates result navigation', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoSearch);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'search');
    expect(tester.exists(text('Global Search')), isTrue);

    await _invoke(tester, demoCommandFocusSearch);
    tester.type('API deploy smoke');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(90, 26));

    final panel = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    expect(panel.state.filterText, 'API deploy smoke');
    expect(panel.state.collectionRowCount, 1);
    expect(panel.state.selectedKey, 'run.RUN-1002');

    final searchFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    expect(
      searchFallback.states.any(
        (state) =>
            state.startsWith('search ') &&
            state.contains('1 filtered') &&
            state.contains('selected category Run') &&
            state.contains('selected source runs'),
      ),
      isTrue,
    );

    final row = tester.semantics().single(
      role: SemanticRole.listItem,
      label: 'API deploy smoke',
      action: SemanticAction.activate,
    );
    expect(row.state['runId'], 'RUN-1002');
    expect(row.state['screenId'], 'runs');

    final activated = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.listItem,
      label: 'API deploy smoke',
    );
    expect(activated.completed, isTrue);
    await _flushAsyncUi(tester);
    expect(_demoApp(tester).state.activeScreenId, 'runs');

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(tester.exists(text('[log] search: activated run.RUN-1002')), isTrue);
  });

  testWidgets('indexed logs build cooperative index and refresh appends', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoIndex);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'index');
    expect(tester.exists(text('Indexed Logs')), isTrue);

    final build = await _invoke(tester, demoCommandBuildLogIndex);
    expect(build.status, CommandInvocationStatus.completed);
    await _flushAsyncUi(tester);

    await _invoke(tester, demoCommandFocusIndexFilter);
    tester.type('target:payment');
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(96, 28));

    var log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed demo logs',
      action: SemanticAction.focus,
    );
    expect(log.state.filterText, 'target:payment');
    expect(log.state.collectionRowCount, 48);
    expect(log.state['totalEntryCount'], demoIndexedLogInitialCount);
    expect(log.state.selectedKey, 'IDX-1000');

    final focusedLog = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.log,
      label: 'Indexed demo logs',
    );
    expect(focusedLog.completed, isTrue);
    tester.render(size: const CellSize(96, 28));
    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed demo logs',
      focused: true,
    );
    expect(log.state.selectedKey, 'IDX-1000');

    final logFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.log,
      label: 'Indexed demo logs',
    );
    expect(
      logFallback.states.any(
        (state) =>
            state.startsWith('log ') &&
            state.contains('$demoIndexedLogInitialCount entries') &&
            state.contains('48 filtered') &&
            state.contains('selected index 0'),
      ),
      isTrue,
    );

    final firstRow = tester.semantics().single(
      role: SemanticRole.listItem,
      selected: true,
      action: SemanticAction.copy,
    );
    expect(firstRow.state['rowKey'], 'IDX-1000');
    expect(firstRow.label, contains('target:payment'));
    expect(firstRow.label, isNot(contains('secret')));

    final secondRow = tester
        .semantics()
        .where(role: SemanticRole.listItem)
        .singleWhere((node) => node.state['rowKey'] == 'IDX-1004');
    expect(secondRow.actions, contains(SemanticAction.activate));

    final selectedLogRow = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: secondRow,
    );
    expect(selectedLogRow.completed, isTrue);
    tester.render(size: const CellSize(96, 28));

    final selectedIndexedRow = tester.semantics().single(
      role: SemanticRole.listItem,
      selected: true,
      action: SemanticAction.copy,
    );
    expect(selectedIndexedRow.state['rowKey'], 'IDX-1004');

    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed demo logs',
    );
    expect(log.state.selectedKey, 'IDX-1004');
    expect(log.state['selectedIndex'], 1);
    expect(log.state['followTail'], isFalse);
    expect(log.focused, isTrue);

    final append = await _invoke(tester, demoCommandAppendIndexedLogBurst);
    expect(append.status, CommandInvocationStatus.completed);
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(96, 28));

    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed demo logs',
    );
    expect(
      log.state['totalEntryCount'],
      demoIndexedLogInitialCount + demoIndexedLogAppendCount,
    );
    expect(log.state.collectionRowCount, 49);

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(96, 28));
    expect(tester.exists(text('[log] index: built 192 demo log rows')), isTrue);
    expect(
      tester.exists(text('[log] index: refreshed 195 demo log rows')),
      isTrue,
    );
  });

  testWidgets('connection screen validates and submits app-owned values', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoConnection);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'connection');
    expect(tester.exists(text('CONNECTION SETUP')), isTrue);

    tester.render(size: const CellSize(90, 28));
    final form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    expect(form.busy, isFalse);
    final rejected = await tester.invokeSemanticAction(
      SemanticAction.submit,
      node: form,
    );
    expect(rejected.completed, isTrue);
    await _flushAsyncUi(tester);
    expect(tester.exists(text('Enter a project name.')), isTrue);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Project')
          .validationError,
      'Enter a project name.',
    );

    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.textField,
      label: 'Project',
      payload: 'dune',
    );
    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Environment',
      payload: 'prod',
    );
    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Region',
      payload: 'eu-west-1',
    );
    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.checkbox,
      label: 'I understand this changes remote state',
      payload: true,
    );
    final submit = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    expect(submit.completed, isTrue);
    await _flushAsyncUi(tester);

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 28));
    expect(
      tester.exists(text('[log] connection: configured dune prod eu-west-1')),
      isTrue,
    );
  });

  testWidgets('runs screen filter narrows the table fixture', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoRuns);
    await _invoke(tester, demoCommandFocusRunsFilter);
    tester.type('failed');
    tester.pump();

    tester.render(size: const CellSize(80, 24));
    final table = tester.semantics().single(role: SemanticRole.table);
    expect(table.state.collectionRowCount, 1);
    expect(table.state.filterText, 'failed');
    expect(tester.semantics().byLabel('API deploy smoke'), isNotEmpty);
    expect(tester.semantics().byLabel('Index workspace'), isEmpty);
  });

  testWidgets('runs table selection activates a transcript event', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoRuns);
    await _invoke(tester, demoCommandFocusRunsTable);
    tester.render(size: const CellSize(80, 24));
    expect(
      _styleForRenderedText(
        tester,
        'RUN-1001',
        size: const CellSize(80, 24),
      )?.foreground,
      const AnsiColor(14),
    );

    var table = tester.semantics().single(role: SemanticRole.table);
    expect(table.focused, isTrue);
    expect(table.state.selectedKey, 'RUN-1001');
    expect(table.state.collectionRowCount, 4);
    expect(table.state.collectionColumnCount, 5);

    var selectedCells = tester.semantics().where(
      role: SemanticRole.tableCell,
      selected: true,
    );
    expect(selectedCells, hasLength(5));
    expect(selectedCells.first.state['rowIndex'], 0);
    expect(selectedCells.first.state['rowKey'], 'RUN-1001');
    expect(selectedCells.first.state['columnIndex'], 0);

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.render(size: const CellSize(80, 24));
    table = tester.semantics().single(role: SemanticRole.table);
    expect(table.state.selectedKey, 'RUN-1002');
    selectedCells = tester.semantics().where(
      role: SemanticRole.tableCell,
      selected: true,
    );
    expect(selectedCells, hasLength(5));
    expect(selectedCells.first.state['rowIndex'], 1);
    expect(selectedCells.first.state['rowKey'], 'RUN-1002');

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 36));

    expect(
      tester.exists(text('[log] runs: selected run RUN-1002 failed')),
      isTrue,
    );
  });

  testWidgets('runs table copies the selected DataTable row', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoRuns);
    await _invoke(tester, demoCommandFocusRunsTable);
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.render(size: const CellSize(80, 24));

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(
      tester.clipboard.readInProcess(),
      'ID\tStatus\tTitle\tOwner\tProgress\n'
      'RUN-1002\tfailed\tAPI deploy smoke\tops\t100%',
    );
    final table = tester.semantics().single(
      role: SemanticRole.table,
      action: SemanticAction.copy,
    );
    expect(table.state.selectedKey, 'RUN-1002');
    expect(table.state['copyFormat'], 'tsv');
    expect(table.state.clipboardPolicy, 'standard');
  });

  testWidgets('tree screen proves TreeTable navigation, semantics, and copy', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoTree);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'tree');
    expect(tester.exists(text('Tree')), isTrue);

    await _invoke(tester, demoCommandFocusTreeTable);
    tester.render(size: const CellSize(90, 24));

    var tree = tester.semantics().single(
      role: SemanticRole.tree,
      label: 'Framework component tree',
    );
    expect(tree.focused, isTrue);
    expect(tree.state.collectionColumnCount, 3);
    expect(tree.state.selectedKey, 'core');
    expect(tree.state['expandedCount'], 1);

    final semanticGraph = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'Semantic Graph',
    );
    expect(semanticGraph.state['rowKey'], 'semantic-graph');
    expect(semanticGraph.state['depth'], 1);

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(
      tester.clipboard.readInProcess(),
      'Component\tStatus\tOwner\n'
      'Core Framework\tready\truntime',
    );
    tree = tester.semantics().single(
      role: SemanticRole.tree,
      label: 'Framework component tree',
      action: SemanticAction.copy,
    );
    expect(tree.state.clipboardPolicy, 'inProcessOnly');

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _flushAsyncUi(tester);
    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 24));
    expect(
      tester.exists(text('[log] tree: selected semantic-graph active')),
      isTrue,
    );
  });

  testWidgets('payload screen proves JsonView semantics and safe copy', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoPayload);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'payload');
    expect(tester.exists(text('Payload')), isTrue);

    await _invoke(tester, demoCommandFocusPayload);
    final output = tester.renderToString(
      size: const CellSize(90, 26),
      emptyMark: ' ',
    );
    expect(output, contains('unsafeOutput: "bad'));
    expect(output, isNot(contains('token')));
    expect(output, isNot(contains('\x1b]52')));

    final json = tester.semantics().single(
      role: SemanticRole.json,
      label: 'Demo payload',
      action: SemanticAction.copy,
    );
    expect(json.focused, isTrue);
    expect(json.state.collectionRowCount, 6);
    expect(json.state['rootType'], 'object');
    expect(json.state.selectedKey, '');
    expect(json.state['selectedPath'], r'$');
    expect(json.state.clipboardPolicy, 'inProcessOnly');

    final unsafe = tester.semantics().single(
      role: SemanticRole.jsonNode,
      label: 'unsafeOutput',
    );
    expect(unsafe.value, isNot(contains('token')));
    expect(unsafe.state.outputSanitized, isTrue);
    expect(unsafe.state['jsonPath'], r'$.unsafeOutput');

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(tester.clipboard.readInProcess(), contains('"jsonView": true'));
    expect(tester.clipboard.readInProcess(), isNot(contains('token')));
    expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(tester.exists(text(r'[log] payload: copied $')), isTrue);
  });

  testWidgets('changes screen proves DiffView semantics and safe hunk copy', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoChanges);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'changes');
    expect(tester.exists(text('Changes')), isTrue);

    tester.render(size: const CellSize(90, 26));
    final initialPatch = tester.semantics().single(
      role: SemanticRole.patchReview,
      label: 'Framework patch review',
      action: SemanticAction.focus,
    );
    expect(initialPatch.focused, isFalse);
    expect(initialPatch.actions, contains(SemanticAction.navigate));

    final focusPatch = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.patchReview,
      label: 'Framework patch review',
    );
    expect(focusPatch.completed, isTrue);
    tester.render(size: const CellSize(90, 26));
    expect(
      tester
          .semantics()
          .single(
            role: SemanticRole.patchReview,
            label: 'Framework patch review',
            focused: true,
          )
          .state
          .selectedPatchFilePath,
      'lib/framework.dart',
    );

    await _invoke(tester, demoCommandFocusChanges);
    final output = tester.renderToString(
      size: const CellSize(90, 26),
      emptyMark: ' ',
    );
    expect(output, contains('Framework patch review: 1 file'));
    expect(output, contains('+  final mode = \'reactive\';'));
    expect(output, contains('+  final note = \'safe'));
    expect(output, isNot(contains('token')));
    expect(output, isNot(contains('\x1b]52')));
    expect(
      _styleForRenderedText(
        tester,
        '+  final mode = \'reactive\';',
      )?.foreground,
      const AnsiColor(10),
    );

    final patch = tester.semantics().single(
      role: SemanticRole.patchReview,
      label: 'Framework patch review',
      action: SemanticAction.copy,
    );
    expect(patch.value, 'reviewing');
    expect(patch.state.patchId, 'demo.framework.patch');
    expect(patch.state.patchStatus, 'reviewing');
    expect(patch.state['patchFileCount'], 1);
    expect(patch.state['patchAdditionCount'], 2);
    expect(patch.state['patchDeletionCount'], 1);
    expect(patch.state.selectedPatchFilePath, 'lib/framework.dart');

    final patchFile = tester.semantics().single(
      role: SemanticRole.patchFile,
      label: 'lib/framework.dart',
      action: SemanticAction.activate,
    );
    expect(patchFile.value, 'reviewing');
    expect(patchFile.state.patchFilePath, 'lib/framework.dart');
    expect(patchFile.state.patchFileStatus, 'reviewing');
    expect(patchFile.state['patchFileAdditionCount'], 2);
    expect(patchFile.state['patchFileDeletionCount'], 1);

    final diff = tester.semantics().single(
      role: SemanticRole.diff,
      label: 'Framework patch review diff',
      action: SemanticAction.copy,
    );
    expect(diff.focused, isTrue);
    expect(diff.state.collectionRowCount, 10);
    expect(diff.state['fileCount'], 1);
    expect(diff.state['hunkCount'], 1);
    expect(diff.state['additionCount'], 2);
    expect(diff.state['deletionCount'], 1);
    expect(diff.state['selectedDiffKind'], 'addition');
    expect(diff.state['selectedFilePath'], 'lib/framework.dart');
    expect(diff.state['selectedNewLine'], 2);
    expect(diff.state.clipboardPolicy, 'inProcessOnly');

    final unsafe = tester
        .semantics()
        .where(role: SemanticRole.diffLine)
        .singleWhere((node) => node.label!.contains('+  final note = \'safe'));
    expect(unsafe.label, isNot(contains('token')));
    expect(unsafe.state.outputSanitized, isTrue);
    expect(unsafe.state['newLine'], 3);

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(tester.clipboard.readInProcess(), contains('@@ -1,4 +1,5 @@'));
    expect(
      tester.clipboard.readInProcess(),
      contains('+  final mode = \'reactive\';'),
    );
    expect(tester.clipboard.readInProcess(), isNot(contains('token')));
    expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));

    final deletedLine = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.diffLine,
      label: '-  final mode = \'legacy\';',
    );
    expect(deletedLine.completed, isTrue);
    tester.render(size: const CellSize(90, 26));

    final selectedDeletion = tester.semantics().single(
      role: SemanticRole.diffLine,
      label: '-  final mode = \'legacy\';',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(selectedDeletion.state['oldLine'], 2);

    final updatedDiff = tester.semantics().single(
      role: SemanticRole.diff,
      label: 'Framework patch review diff',
    );
    expect(updatedDiff.state['selectedDiffKind'], 'deletion');
    expect(updatedDiff.state['selectedOldLine'], 2);

    final selectPatch = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.patchFile,
      label: 'lib/framework.dart',
    );
    expect(selectPatch.completed, isTrue);

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(
      tester.exists(text('[log] changes: copied lib/framework.dart addition')),
      isTrue,
    );
    expect(
      tester.exists(text('[log] patch: selected lib/framework.dart')),
      isTrue,
    );
  });

  testWidgets('source screen proves CodeView semantics and safe source copy', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoSource);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'source');
    expect(tester.exists(text('Source')), isTrue);

    await _invoke(tester, demoCommandFocusSource);
    final output = tester.renderToString(
      size: const CellSize(90, 26),
      emptyMark: ' ',
    );
    expect(output, contains("return const Text('safe"));
    expect(output, isNot(contains('token')));
    expect(output, isNot(contains('\x1b]52')));

    final code = tester.semantics().single(
      role: SemanticRole.code,
      label: 'Framework source',
      action: SemanticAction.copy,
    );
    expect(code.focused, isTrue);
    expect(code.state.collectionRowCount, 10);
    expect(code.state['lineCount'], 10);
    expect(code.state['nonEmptyLineCount'], 8);
    expect(code.state['commentCount'], 0);
    expect(code.state['blankCount'], 2);
    expect(code.state['language'], 'dart');
    expect(code.state['filePath'], 'lib/launch_shell.dart');
    expect(code.state.selectedKey, 8);
    expect(code.state['selectedCodeLineKind'], 'keyword');
    expect(code.state.clipboardPolicy, 'inProcessOnly');

    final unsafe = tester.semantics().single(
      role: SemanticRole.codeLine,
      selected: true,
    );
    expect(unsafe.label, contains("return const Text('safe"));
    expect(unsafe.label, isNot(contains('token')));
    expect(unsafe.state.outputSanitized, isTrue);
    expect(unsafe.state['lineNumber'], 8);

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(
      tester.clipboard.readInProcess(),
      contains("return const Text('safe"),
    );
    expect(tester.clipboard.readInProcess(), isNot(contains('token')));
    expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));

    final classLine = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.codeLine,
      label: 'final class LaunchShell extends StatelessWidget {',
    );
    expect(classLine.completed, isTrue);
    tester.render(size: const CellSize(90, 26));

    final selectedClassLine = tester.semantics().single(
      role: SemanticRole.codeLine,
      label: 'final class LaunchShell extends StatelessWidget {',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(selectedClassLine.state['lineNumber'], 3);

    final updatedCode = tester.semantics().single(
      role: SemanticRole.code,
      label: 'Framework source',
    );
    expect(updatedCode.state.selectedKey, 3);
    expect(updatedCode.state['selectedCodeLineKind'], 'declaration');

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(tester.exists(text('[log] source: copied line 8 keyword')), isTrue);
  });

  testWidgets('docs screen proves MarkdownView semantics and safe doc copy', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    final nav = await _invoke(tester, demoCommandGoDocs);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_demoApp(tester).state.activeScreenId, 'docs');
    expect(tester.exists(text('Docs')), isTrue);

    await _invoke(tester, demoCommandFocusDocs);
    final output = tester.renderToString(
      size: const CellSize(90, 26),
      emptyMark: ' ',
    );
    expect(output, contains('Fleury Launch Notes'));
    expect(output, contains('(https://danreynolds.github.io/fleury/).'));
    expect(output, contains('• Semantic graph drives tests'));
    expect(output, contains('│ unsafe safe'));
    expect(output, isNot(contains('token')));
    expect(output, isNot(contains('\x1b]52')));
    expect(
      _styleForRenderedText(tester, 'Fleury Launch Notes')?.foreground,
      const AnsiColor(14),
    );

    final markdown = tester.semantics().single(
      role: SemanticRole.markdown,
      label: 'Launch docs',
      action: SemanticAction.copy,
    );
    expect(markdown.focused, isTrue);
    expect(markdown.state.collectionRowCount, 7);
    expect(markdown.state['blockCount'], 7);
    expect(markdown.state['headingCount'], 1);
    expect(markdown.state['listItemCount'], 2);
    expect(markdown.state['linkCount'], 1);
    expect(markdown.state['codeBlockCount'], 1);
    expect(markdown.state['codeLineCount'], 1);
    expect(markdown.state.selectedKey, 5);
    expect(markdown.state['selectedMarkdownBlockKind'], 'blockquote');
    expect(markdown.state.clipboardPolicy, 'inProcessOnly');

    final link = tester.semantics().single(
      role: SemanticRole.link,
      label: 'docs',
    );
    expect(link.value, 'https://danreynolds.github.io/fleury/');
    expect(link.state['markdownBlockIndex'], 2);
    expect(link.state.capabilityResolution, 'disabledByPolicy');
    expect(link.state.activeFallback, 'visible URL');

    final unsafe = tester.semantics().single(
      role: SemanticRole.markdownBlock,
      selected: true,
    );
    expect(unsafe.label, contains('unsafe safe'));
    expect(unsafe.label, isNot(contains('token')));
    expect(unsafe.state.outputSanitized, isTrue);
    expect(unsafe.state['markdownBlockKind'], 'blockquote');

    tester.sendKey(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await _flushAsyncUi(tester);

    expect(tester.clipboard.readInProcess(), contains('> unsafe safe'));
    expect(tester.clipboard.readInProcess(), isNot(contains('token')));
    expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));

    final capabilityBlock = tester.semantics().single(
      role: SemanticRole.markdownBlock,
      label: 'Capability policy guards output',
      action: SemanticAction.activate,
    );
    expect(capabilityBlock.selected, isFalse);

    final selectedBlock = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.markdownBlock,
      label: 'Capability policy guards output',
    );
    expect(selectedBlock.completed, isTrue);

    tester.render(size: const CellSize(90, 26));
    final selectedDocBlock = tester.semantics().single(
      role: SemanticRole.markdownBlock,
      label: 'Capability policy guards output',
      selected: true,
      action: SemanticAction.copy,
    );
    expect(selectedDocBlock.state['rowIndex'], 4);
    expect(selectedDocBlock.state['markdownBlockKind'], 'bullet');

    final selectedMarkdown = tester.semantics().single(
      role: SemanticRole.markdown,
      label: 'Launch docs',
    );
    expect(selectedMarkdown.focused, isTrue);
    expect(selectedMarkdown.state.selectedKey, 4);
    expect(selectedMarkdown.state['selectedIndex'], 4);
    expect(selectedMarkdown.state['selectedMarkdownBlockKind'], 'bullet');

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(
      tester.exists(text('[log] docs: copied block 6 blockquote')),
      isTrue,
    );
  });

  testWidgets('debug capture snapshot can seed a demo-app regression', (
    tester,
  ) async {
    final capture = DebugCaptureRecorder();
    void recordCommand(CommandId command) {
      capture.record(InputDebugEvent(kind: 'command', summary: command.value));
    }

    tester.pumpWidget(const DemoConsoleApp());
    tester.render(size: const CellSize(80, 24));
    capture.record(
      const FrameDebugEvent(
        FrameEvent(
          frameNumber: 1,
          reason: 'initial',
          build: Duration(microseconds: 100),
          layout: Duration(microseconds: 180),
          paint: Duration(microseconds: 140),
          diff: Duration(microseconds: 40),
          dirtyCells: 1920,
          dirtyBounds: CellRect(
            offset: CellOffset.zero,
            size: CellSize(80, 24),
          ),
          dirtySources: ['build:DemoConsoleApp'],
          bufferSize: CellSize(80, 24),
        ),
      ),
    );

    recordCommand(demoCommandGoRuns);
    await _invoke(tester, demoCommandGoRuns);
    capture.record(
      const InputDebugEvent(
        kind: 'resize',
        summary: '100x28',
        resizeSize: CellSize(100, 28),
      ),
    );
    tester.render(size: const CellSize(100, 28));
    capture.record(
      const FrameDebugEvent(
        FrameEvent(
          frameNumber: 2,
          reason: 'resize',
          build: Duration(microseconds: 80),
          layout: Duration(microseconds: 150),
          paint: Duration(microseconds: 120),
          diff: Duration(microseconds: 35),
          dirtyCells: 620,
          dirtyBounds: CellRect(
            offset: CellOffset.zero,
            size: CellSize(100, 28),
          ),
          dirtySources: ['paint:RenderDataTable'],
          bufferSize: CellSize(100, 28),
        ),
      ),
    );

    recordCommand(demoCommandStartWorker);
    await _invoke(tester, demoCommandStartWorker);
    recordCommand(demoCommandFocusRunsTable);
    await _invoke(tester, demoCommandFocusRunsTable);
    capture.record(const InputDebugEvent(kind: 'key', summary: 'arrowDown'));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    capture.record(const InputDebugEvent(kind: 'key', summary: 'enter'));
    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _flushAsyncUi(tester);
    recordCommand(demoCommandCaptureDebug);
    await _invoke(tester, demoCommandCaptureDebug);

    capture.recordOutputSummary(
      const DebugOutputSummary(source: 'demo-console-transcript', lineCount: 5),
    );

    expect(tester.exists(text('Debug: captures 1')), isTrue);
    expect(tester.exists(text('Worker: running 15%')), isTrue);
    final tree = tester.semantics();
    final app = _demoApp(tester);
    expect(app.state.activeScreenId, 'runs');
    expect(app.state.lastCommandId, 'debug.captureSnapshot');
    expect(app.state.lastCommandStatus, 'completed');

    final table = tree.single(role: SemanticRole.table, focused: true);
    expect(table.state.selectedKey, 'RUN-1002');
    expect(table.state.collectionRowCount, 4);
    expect(table.state.collectionColumnCount, 5);
    expect(tree.byLabel('API deploy smoke'), isNotEmpty);

    final snapshot = capture.snapshot(semanticTree: tree);
    final snapshotJson = snapshot.toJson();
    final artifact = DebugCaptureArtifact.fromSnapshot(snapshot);
    final inputs = snapshotJson['inputs'] as List<Object?>;
    expect(inputs, hasLength(7));
    expect(
      inputs.map((input) => (input as Map<String, Object?>)['summary']),
      containsAll(<String>[
        'screen.runs',
        '100x28',
        'worker.startFake',
        'runs.focusTable',
        'arrowDown',
        'enter',
        'debug.captureSnapshot',
      ]),
    );
    expect(
      artifact.hasInput(
        kind: 'command',
        summary: demoCommandCaptureDebug.value,
      ),
      true,
    );
    final frames = snapshotJson['frames'] as List<Object?>;
    expect(frames, hasLength(2));
    expect(
      artifact.hasFrame(reason: 'resize', dirtySource: 'paint:RenderDataTable'),
      true,
    );
    expect(
      artifact.outputSummariesFor(source: 'demo-console-transcript').single,
      containsPair('lineCount', 5),
    );

    final semantics = snapshotJson['semantics'] as Map<String, Object?>;
    expect(semantics['nodeCount'], greaterThan(40));
    final accessibility = snapshotJson['accessibility'] as Map<String, Object?>;
    expect(accessibility['nodeCount'], semantics['nodeCount']);
    expect(artifact.accessibilityPlainText, contains('Fleury Demo Console'));
    expect(artifact.accessibilityPlainText, contains('API deploy smoke'));
    expect(artifact.accessibilityPlainText, contains('running 15%'));
    final capturedApp = artifact.singleSemanticNode(
      role: 'app',
      label: 'Fleury Demo Console',
    );
    expect(capturedApp.state, containsPair('activeScreenId', 'runs'));
    expect(
      capturedApp.state,
      containsPair('lastCommandId', 'debug.captureSnapshot'),
    );
    final capturedTable = artifact.singleSemanticNode(role: 'table');
    expect(capturedTable.state, containsPair('selectedKey', 'RUN-1002'));
    expect(capturedTable.state, containsPair('collectionRowCount', 4));
    expect(
      artifact.semanticNodes(role: 'tableCell', label: 'API deploy smoke'),
      isNotEmpty,
    );
    expect(
      artifact.semanticNodes(
        role: 'status',
        label: 'Worker',
        value: 'running 15%',
      ),
      isNotEmpty,
    );
  });

  testWidgets('composer submission and log burst update transcript', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    await _invoke(tester, demoCommandFocusComposer);
    tester.type('operator note');

    var composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'operator note');

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(80, 24));

    expect(tester.exists(text('[log] user: operator note')), isTrue);

    final burst = await _invoke(tester, demoCommandAppendLogBurst);
    expect(burst.status, CommandInvocationStatus.completed);
    tester.render(size: const CellSize(80, 24));
    expect(tester.exists(text('[log] stream: burst 1.3')), isTrue);

    var log = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Transcript events',
    );
    expect(log.state.collectionRowCount, 6);
    expect(log.state['author'], 'stream');
    expect(log.actions, contains(SemanticAction.focus));
    expect(log.actions, contains(SemanticAction.navigate));

    final focusedTranscript = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.messageList,
      label: 'Transcript events',
    );
    expect(focusedTranscript.completed, isTrue);
    tester.render(size: const CellSize(80, 24));
    log = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Transcript events',
      focused: true,
    );
    expect(log.state['author'], 'stream');

    await _invoke(tester, demoCommandToggleStream);
    final disabled = await _invoke(tester, demoCommandAppendLogBurst);
    expect(disabled.status, CommandInvocationStatus.disabled);
    expect(tester.exists(text('[log] stream: burst 2.1')), isFalse);

    log = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Transcript events',
    );
    expect(log.state['author'], 'logs');

    final candidate = tester
        .semantics()
        .where(
          role: SemanticRole.message,
          selected: false,
          action: SemanticAction.activate,
        )
        .first;
    final candidateKey = candidate.state['rowKey'];
    final selected = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.message,
      label: candidate.label,
    );
    expect(selected.completed, isTrue);
    tester.render(size: const CellSize(80, 24));

    final selectedMessage = tester.semantics().single(
      role: SemanticRole.message,
      label: candidate.label,
      selected: true,
      action: SemanticAction.copy,
    );
    expect(selectedMessage.state['rowKey'], candidateKey);

    log = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Transcript events',
      focused: true,
    );
    expect(log.state.selectedKey, candidateKey);
    expect(log.state.selectedMessageId, candidateKey);
  });

  testWidgets('transcript selection preserves stable identity across appends', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    await _invoke(tester, demoCommandAppendLogBurst);
    await _invoke(tester, demoCommandAppendLogBurst);
    tester.render(size: const CellSize(110, 32));

    final target = tester.semantics().single(
      role: SemanticRole.message,
      label: '[log] stream: burst 2.2',
      action: SemanticAction.activate,
    );
    final targetId = target.state.messageId;
    expect(targetId, isNotNull);

    final activated = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: target,
    );
    expect(activated.completed, isTrue);
    tester.render(size: const CellSize(110, 32));

    var selected = tester.semantics().single(
      role: SemanticRole.message,
      label: '[log] stream: burst 2.2',
      selected: true,
    );
    expect(selected.state.messageId, targetId);

    await _invoke(tester, demoCommandGoOverview);
    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));

    selected = tester.semantics().single(
      role: SemanticRole.message,
      label: '[log] stream: burst 2.2',
      selected: true,
    );
    expect(selected.state.messageId, targetId);

    await _invoke(tester, demoCommandAppendLogBurst);
    tester.render(size: const CellSize(110, 32));

    selected = tester.semantics().single(
      role: SemanticRole.message,
      label: '[log] stream: burst 2.2',
      selected: true,
    );
    expect(selected.state.messageId, targetId);
    expect(selected.state['rowIndex'], 3);

    final log = tester.semantics().single(
      role: SemanticRole.messageList,
      label: 'Transcript events',
    );
    expect(log.state.collectionRowCount, 8);
    expect(log.state.selectedMessageId, targetId);
    expect(log.state['selectedIndex'], 3);
    expect(log.state['followTail'], isFalse);
  });

  testWidgets('composer completions accept slash commands semantically', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    await _invoke(tester, demoCommandFocusComposer);
    tester.type('/su');
    tester.render(size: const CellSize(110, 32));

    final menu = tester.semantics().single(
      role: SemanticRole.menu,
      label: 'Completions',
    );
    expect(menu.focused, isTrue);
    expect(menu.expanded, isTrue);
    expect(menu.state.filterText, '/su');
    expect(menu.state.collectionRowCount, 1);
    expect(menu.actions, contains(SemanticAction.close));

    final option = tester.semantics().single(
      role: SemanticRole.menuItem,
      label: '/summarize',
      action: SemanticAction.activate,
      selected: true,
    );
    expect(option.hint, 'Summarize the current transcript');
    expect(option.state.completionQuery, '/su');
    expect(option.state.menuItemPosition, 1);
    expect(option.state.menuItemCount, 1);

    final accepted = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: option,
    );
    expect(accepted.completed, isTrue);

    var composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, '/summarize ');
    expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);

    tester.type('deployment risk');
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, '/summarize deployment risk');

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(110, 32));

    expect(
      tester.exists(text('[log] user: /summarize deployment risk')),
      isTrue,
    );
  });

  testWidgets('composer history restores submitted notes', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    await _invoke(tester, demoCommandFocusComposer);
    tester.type('first operator note');

    var composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'first operator note');
    expect(composer.state.historyCount, 0);

    tester.sendKey(const KeyEvent(KeyCode.enter));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(110, 32));

    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, '');
    expect(composer.state.historyCount, 1);
    expect(composer.state.historyBrowsing, isFalse);
    expect(tester.exists(text('[log] user: first operator note')), isTrue);

    tester.type('draft follow-up');
    tester.sendKey(const KeyEvent(KeyCode.arrowUp));
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'first operator note');
    expect(composer.state.historyCount, 1);
    expect(composer.state.historyIndex, 0);
    expect(composer.state.historyBrowsing, isTrue);

    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'draft follow-up');
    expect(composer.state.historyBrowsing, isFalse);

    final cleared = await tester.invokeSemanticAction(
      SemanticAction.clear,
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
    );
    expect(cleared.completed, isTrue);

    tester.type('/');
    tester.render(size: const CellSize(110, 32));
    tester.sendKey(const KeyEvent(KeyCode.arrowUp));
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, '/');
    expect(composer.state.historyBrowsing, isFalse);
    final selectedCompletion = tester.semantics().single(
      role: SemanticRole.menuItem,
      label: '/run-worker',
      selected: true,
    );
    expect(selectedCompletion.state.completionQuery, '/');
  });

  testWidgets('file mention picker inserts composer mentions', (tester) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 30));

    var picker = tester.semantics().single(
      role: SemanticRole.fileMentionPicker,
      label: 'Composer file mentions',
    );
    expect(picker.state['totalMentionCount'], 4);
    expect(picker.state['filteredMentionCount'], 4);
    expect(
      picker.state.selectedFilePath,
      endsWith('fleury_example_console.dart'),
    );
    expect(picker.actions, contains(SemanticAction.focus));
    expect(picker.actions, contains(SemanticAction.navigate));

    final focusedPicker = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.fileMentionPicker,
      label: 'Composer file mentions',
    );
    expect(focusedPicker.completed, isTrue);
    tester.render(size: const CellSize(110, 30));
    picker = tester.semantics().single(
      role: SemanticRole.fileMentionPicker,
      label: 'Composer file mentions',
      focused: true,
    );
    expect(picker.state.mentionText, isNull);
    expect(
      picker.state.selectedFilePath,
      endsWith('fleury_example_console.dart'),
    );

    final mention = tester.semantics().single(
      role: SemanticRole.fileMention,
      label: 'Demo console app',
      action: SemanticAction.activate,
    );
    expect(mention.state.filePath, contains('fleury_example_console.dart'));
    expect(mention.state.fileLanguage, 'dart');
    expect(mention.state.mentionText, '@demo-console');

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.fileMention,
      label: 'Demo console app',
    );
    expect(result.completed, isTrue);

    final composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
    );
    expect(composer.value, '@demo-console');

    tester.render(size: const CellSize(110, 30));
    expect(
      tester.exists(
        text(
          '[log] composer: mentioned packages/fleury_example_console/lib/fleury_example_console.dart',
        ),
      ),
      isTrue,
    );
    picker = tester.semantics().single(
      role: SemanticRole.fileMentionPicker,
      label: 'Composer file mentions',
      focused: true,
    );
    expect(
      picker.state.selectedFilePath,
      endsWith('fleury_example_console.dart'),
    );

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.fileMention,
      label: 'Demo console app',
    );
    expect(fallback.states.join('\n'), contains('mention @demo-console'));
  });

  testWidgets('conversation navigator selects demo conversations', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));

    var navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Demo conversations',
    );
    expect(navigator.state['totalConversationCount'], 3);
    expect(navigator.state['filteredConversationCount'], 3);
    expect(navigator.state.selectedConversationId, 'thread.transcript');
    expect(navigator.state['unreadConversationCount'], 1);
    expect(navigator.actions, contains(SemanticAction.focus));
    expect(navigator.actions, contains(SemanticAction.navigate));

    final focusedNavigator = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.conversationNavigator,
      label: 'Demo conversations',
    );
    expect(focusedNavigator.completed, isTrue);
    tester.render(size: const CellSize(110, 32));
    navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Demo conversations',
      focused: true,
    );
    expect(navigator.state.selectedConversationId, 'thread.transcript');

    final worker = tester.semantics().single(
      role: SemanticRole.conversation,
      label: 'Worker activity',
      action: SemanticAction.activate,
    );
    expect(worker.state.conversationId, 'thread.worker');
    expect(worker.state.conversationStatus, 'idle');
    expect(worker.state.conversationMessageCount, 0);

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.conversation,
      label: 'Worker activity',
    );
    expect(result.completed, isTrue);

    tester.render(size: const CellSize(110, 32));
    expect(
      tester.exists(text('[log] conversation: selected thread.worker')),
      isTrue,
    );
    navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Demo conversations',
      focused: true,
    );
    expect(navigator.state.selectedConversationId, 'thread.worker');

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.conversation,
      label: 'Worker activity',
    );
    expect(
      fallback.states,
      contains(
        'conversation id thread.worker, status idle, 0 unread, 0 messages',
      ),
    );
  });

  testWidgets('diagnostics capture updates status and transcript state', (
    tester,
  ) async {
    tester.pumpWidget(const DemoConsoleApp());

    await _invoke(tester, demoCommandGoDiagnostics);
    await _invoke(tester, demoCommandCaptureDebug);

    expect(tester.exists(text('Debug captures: 1')), isTrue);
    expect(tester.exists(text('Debug: captures 1')), isTrue);
    expect(tester.exists(text('Diagnostics')), isTrue);
    tester.render(size: const CellSize(110, 36));

    final diagnostic = tester.semantics().single(
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
      action: SemanticAction.captureDebug,
    );
    expect(diagnostic.actions, contains(SemanticAction.diagnose));
    expect(diagnostic.state['terminalColorMode'], 'truecolor');
    expect(diagnostic.state['imageProtocol'], 'halfBlock');
    expect(diagnostic.state['capabilityRowCount'], 5);
    expect(diagnostic.state.clipboardPolicy, 'allowed');
    expect(diagnostic.state.clipboardCapability, 'clipboardWrite');
    expect(diagnostic.state.clipboardCapabilityResolution, 'available');
    expect(diagnostic.state['osc52Policy'], 'policyGated');
    expect(diagnostic.state['osc8Policy'], 'disabledByDefault');
    expect(diagnostic.state['debugCaptureCount'], 1);
    expect(diagnostic.state['streaming'], isTrue);

    final diagnosticFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
    );
    final diagnosticFallbackState = diagnosticFallback.states.join('\n');
    expect(diagnosticFallbackState, contains('color truecolor'));
    expect(diagnosticFallbackState, contains('images halfBlock'));
    expect(diagnosticFallbackState, contains('5 capability rows'));
    expect(diagnosticFallbackState, contains('debug captures 1'));
    expect(diagnosticFallbackState, contains('OSC 8 disabledByDefault'));

    final captureResult = await tester.invokeSemanticAction(
      SemanticAction.captureDebug,
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
    );
    expect(captureResult.completed, isTrue);
    await _flushAsyncUi(tester);
    expect(tester.exists(text('Debug captures: 2')), isTrue);
    expect(_demoApp(tester).state.lastCommandId, 'debug.captureSnapshot');

    final diagnoseResult = await tester.invokeSemanticAction(
      SemanticAction.diagnose,
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
    );
    expect(diagnoseResult.completed, isTrue);
    await _flushAsyncUi(tester);

    final images = tester.semantics().single(
      role: SemanticRole.diagnostic,
      label: 'Inline images',
    );
    expect(images.state.terminalCapability, 'inlineImages');
    expect(images.state.capabilityRequirement, 'preferred');
    expect(images.state.capabilityResolution, 'degraded');
    expect(images.state.activeFallback, 'glyph image');

    final links = tester.semantics().single(
      role: SemanticRole.diagnostic,
      label: 'Markdown links',
    );
    expect(links.state.terminalCapability, 'osc8Hyperlinks');
    expect(links.state.capabilityRequirement, 'prohibited');
    expect(links.state.capabilityResolution, 'disabledByPolicy');
    expect(links.state.activeFallback, 'visible URL');

    final clipboard = tester.semantics().single(
      role: SemanticRole.diagnostic,
      label: 'Clipboard write',
    );
    expect(clipboard.state.clipboardPolicy, 'allowed');
    expect(clipboard.state.clipboardCapability, 'clipboardWrite');
    expect(clipboard.state.clipboardCapabilityResolution, 'available');
    expect(clipboard.state.clipboardRedacted, isFalse);

    final osc52 = tester.semantics().single(
      role: SemanticRole.diagnostic,
      label: 'OSC 52 clipboard',
    );
    expect(osc52.state.terminalCapability, 'osc52Clipboard');
    expect(osc52.state.capabilityResolution, 'unverified');
    expect(osc52.state.activeFallback, 'in-process register');
    expect(osc52.state.clipboardTransport, 'osc52');

    final rowDiagnose = await tester.invokeSemanticAction(
      SemanticAction.diagnose,
      role: SemanticRole.diagnostic,
      label: 'Inline images',
    );
    expect(rowDiagnose.completed, isTrue);
    await _flushAsyncUi(tester);

    final timeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Demo trace timeline',
      action: SemanticAction.focus,
    );
    expect(timeline.state['traceEventCount'], 4);
    expect(timeline.state['runningTraceEventCount'], 1);
    expect(timeline.state.selectedTraceId, 'trace.boot');

    final focusedTimeline = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.traceTimeline,
      label: 'Demo trace timeline',
    );
    expect(focusedTimeline.completed, isTrue);
    tester.render(size: const CellSize(80, 24));
    var updatedTimeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Demo trace timeline',
      focused: true,
    );
    expect(updatedTimeline.state.selectedTraceId, 'trace.boot');

    final captureTrace = tester.semantics().single(
      role: SemanticRole.traceEvent,
      label: 'Diagnostics capture',
      action: SemanticAction.activate,
    );
    expect(captureTrace.state.traceId, 'trace.diagnostics');
    expect(captureTrace.state.traceKind, 'diagnostic');
    expect(captureTrace.state.traceStatus, 'succeeded');
    expect(captureTrace.state.source, 'diagnostics');

    final traceResult = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.traceEvent,
      label: 'Diagnostics capture',
    );
    expect(traceResult.completed, isTrue);
    tester.render(size: const CellSize(80, 24));
    updatedTimeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Demo trace timeline',
      focused: true,
    );
    expect(updatedTimeline.state.selectedTraceId, 'trace.diagnostics');

    final traceFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.traceEvent,
      label: 'Diagnostics capture',
    );
    expect(
      traceFallback.states.join('\n'),
      contains('trace id trace.diagnostics, kind diagnostic, status succeeded'),
    );

    await _invoke(tester, demoCommandGoTranscript);
    tester.render(size: const CellSize(110, 36));
    expect(
      tester.exists(
        text('[log] diagnose: terminal profile: ansi-256, mouse pending'),
      ),
      isTrue,
    );
    expect(
      tester.exists(text('[log] trace: selected trace.diagnostics')),
      isTrue,
    );
  });
}
