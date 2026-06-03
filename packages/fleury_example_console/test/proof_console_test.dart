import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

import '../lib/fleury_example_console.dart';

SemanticNode _proofApp(FleuryTester tester) {
  return tester.semantics().single(
    role: SemanticRole.app,
    label: 'Fleury Proof Console',
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
  return result;
}

Future<SemanticNode> _waitForTaskStatus(
  FleuryTester tester, {
  required String label,
  required String status,
}) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    tester.pump();
    final matches = tester.semantics().where(
      role: SemanticRole.task,
      label: label,
    );
    for (final node in matches) {
      if (node.state.taskStatus == status) return node;
    }
  }
  fail('Timed out waiting for task `$label` to reach `$status`.');
}

Future<SemanticNode> _waitForTaskProgress(
  FleuryTester tester, {
  required String label,
  required num current,
}) async {
  for (var attempt = 0; attempt < 25; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    tester.pump();
    final matches = tester.semantics().where(
      role: SemanticRole.task,
      label: label,
    );
    for (final node in matches) {
      if (node.state.progressCurrent == current) return node;
    }
  }
  final states = tester
      .semantics()
      .where(role: SemanticRole.task, label: label)
      .map((node) => node.state.values)
      .toList();
  fail(
    'Timed out waiting for task `$label` to report progress `$current`: '
    '$states',
  );
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
    tester.pumpWidget(const ProofConsoleApp());

    expect(tester.exists(text('Fleury Proof Console')), isTrue);
    expect(tester.exists(text('Overview')), isTrue);

    final app = _proofApp(tester);
    expect(app.state.screenCount, 13);
    expect(app.state.activeScreenId, 'overview');
    expect(app.state.commandCount, greaterThanOrEqualTo(8));
    expect(app.state.statusCount, 5);

    final navigation = tester.semantics().single(
      role: SemanticRole.navigation,
      label: 'Proof console navigation',
    );
    expect(navigation.state.screenCount, 13);
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
    expect(model.state.modelMode, 'proof');
    expect(model.state.modelLatencyMs, 42);
    expect(model.state.contextLimit, 128000);

    final workflow = tester.semantics().single(
      role: SemanticRole.region,
      label: 'Proof workflow snapshot',
    );
    expect(workflow.state.workflowHealth, 'needsAttention');
    expect(workflow.state['workflowId'], 'proof-console');
    expect(workflow.state.messageCount, 2);
    expect(workflow.state.toolCallCount, 1);
    expect(workflow.state.taskCount, 4);
    expect(workflow.state.contextItemCount, 4);
    expect(workflow.state.fileMentionCount, 4);
    expect(workflow.state.conversationCount, 4);
    expect(workflow.state.traceEventCount, 5);
    expect(workflow.state.patchFileCount, 1);

    final snapshot = tester.accessibilitySnapshot();
    final workflowFallback = snapshot.single(
      role: SemanticRole.region,
      label: 'Proof workflow snapshot',
    );
    final workflowFallbackState = workflowFallback.states.join('\n');
    expect(
      workflowFallbackState,
      contains('workflow id proof-console, title Fleury Proof Console'),
    );
    expect(workflowFallbackState, contains('health needsAttention'));
    expect(workflowFallbackState, contains('2 messages'));
    expect(workflowFallbackState, contains('1 active tool call'));
    expect(workflowFallbackState, contains('4 tasks'));
    expect(workflowFallbackState, contains('3 active tasks'));
    expect(workflowFallbackState, contains('4 context items'));
    expect(workflowFallbackState, contains('4 file mentions'));
    expect(workflowFallbackState, contains('4 conversations'));
    expect(workflowFallbackState, contains('1 unread conversation'));
    expect(workflowFallbackState, contains('5 trace events'));
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
    expect(status.states, contains('status 5 items'));
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
      label: 'Proof context',
    );
    expect(contextPanel.state['contextItemCount'], 4);
    expect(contextPanel.state['contextTokenCount'], greaterThan(2300));
    expect(contextPanel.state.contextLimit, 128000);
    expect(contextPanel.state.selectedContextItemId, 'ctx.proof-console');

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
      label: 'Proof workflow plan',
    );
    expect(plan.state['taskCount'], 4);
    expect(plan.state['succeededTaskCount'], 1);
    expect(plan.state['pendingTaskCount'], 3);
    expect(plan.actions, contains(SemanticAction.focus));
    expect(plan.actions, contains(SemanticAction.navigate));

    final focusedPlan = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.taskGraph,
      label: 'Proof workflow plan',
    );
    expect(focusedPlan.completed, isTrue);

    tester.render(size: const CellSize(90, 26));
    plan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Proof workflow plan',
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
      label: 'Proof workflow plan',
      focused: true,
    );
    expect(updatedPlan.state.selectedTaskId, 'diagnostics');
  });

  testWidgets('sidebar semantic navigation switches proof-app screens', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final runs = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.listItem,
      label: 'Runs',
    );
    expect(runs.completed, isTrue);
    expect(_proofApp(tester).state.activeScreenId, 'runs');
    expect(tester.exists(text('Runs')), isTrue);

    final overview = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.listItem,
      label: 'Overview',
    );
    expect(overview.completed, isTrue);
    expect(_proofApp(tester).state.activeScreenId, 'overview');
  });

  testWidgets('context panel selects proof context items', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());
    tester.render(size: const CellSize(110, 32));

    final contextPanel = tester.semantics().single(
      role: SemanticRole.contextPanel,
      label: 'Proof context',
      action: SemanticAction.focus,
    );
    expect(contextPanel.focused, isFalse);
    expect(contextPanel.actions, contains(SemanticAction.navigate));

    final focusResult = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.contextPanel,
      label: 'Proof context',
    );
    expect(focusResult.completed, isTrue);
    tester.render(size: const CellSize(110, 32));
    expect(
      tester
          .semantics()
          .single(
            role: SemanticRole.contextPanel,
            label: 'Proof context',
            focused: true,
          )
          .state
          .selectedContextItemId,
      'ctx.proof-console',
    );

    final item = tester.semantics().single(
      role: SemanticRole.contextItem,
      label: 'Proof console source',
      action: SemanticAction.activate,
    );
    expect(item.state.contextItemId, 'ctx.proof-console');
    expect(item.state.contextItemKind, 'file');
    expect(item.state.contextItemPriority, 'high');
    expect(item.state.contextItemTokenCount, 1200);
    expect(item.state['pinned'], isTrue);

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.contextItem,
      label: 'Proof console source',
    );
    expect(
      fallback.states,
      contains(
        'context id ctx.proof-console, kind file, 1200 tokens, priority high, '
        'pinned, source packages/fleury_example_console/lib/'
        'fleury_example_console.dart',
      ),
    );

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.contextItem,
      label: 'Proof console source',
    );
    expect(result.completed, isTrue);

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));
    expect(
      tester.exists(text('[log] context: selected ctx.proof-console')),
      isTrue,
    );
  });

  testWidgets('commands navigate and start the fake task', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());

    final nav = await _invoke(tester, proofCommandGoRuns);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_proofApp(tester).state.activeScreenId, 'runs');

    final task = await _invoke(tester, proofCommandStartTask);
    expect(task.status, CommandInvocationStatus.completed);
    expect(tester.exists(text('Task: running 15%')), isTrue);

    final app = _proofApp(tester);
    expect(app.state.lastCommandId, 'task.startFake');
    expect(app.state.lastCommandStatus, 'completed');

    final overview = await _invoke(tester, proofCommandGoOverview);
    expect(overview.status, CommandInvocationStatus.completed);

    final worker = tester.semantics().single(
      role: SemanticRole.task,
      label: 'Fake task',
      busy: true,
      action: SemanticAction.cancel,
    );
    expect(worker.state.taskId, 'fake-task');
    expect(worker.state.taskStatus, 'running');
    expect(worker.state.progressCurrent, 15);
    expect(worker.state.progressTotal, 100);
    expect(worker.state.outputCount, 1);
    expect(worker.state.taskEventCount, 3);
    expect(worker.state.lastTaskEventKind, 'output');
    expect(worker.state.source, 'worker');
    expect(worker.state.outputSanitized, isFalse);
    expect(worker.state.outputTruncated, isFalse);

    final diagnostics = await _invoke(tester, proofCommandGoDiagnostics);
    expect(diagnostics.status, CommandInvocationStatus.completed);
    tester.render(size: const CellSize(100, 50));

    final taskTimeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Proof trace timeline',
    );
    expect(taskTimeline.state.traceEventCount, greaterThan(5));

    final taskProgressEvent = tester.semantics().single(
      role: SemanticRole.traceEvent,
      label: 'Fake task progress',
    );
    expect(taskProgressEvent.state.traceKind, 'task');
    expect(taskProgressEvent.state.traceStatus, 'running');
    expect(taskProgressEvent.state.taskId, 'fake-task');
    expect(taskProgressEvent.state.taskRunId, 1);
    expect(taskProgressEvent.state.taskEventSequence, 2);
    expect(taskProgressEvent.state.taskEventKind, 'progress');
    expect(taskProgressEvent.state.taskStatus, 'running');
    expect(taskProgressEvent.state.progressCurrent, 15);
    expect(taskProgressEvent.state.progressTotal, 100);
    expect(taskProgressEvent.state.source, 'fake-task');

    final taskOutputEvent = tester.semantics().single(
      role: SemanticRole.traceEvent,
      label: 'Fake task output',
    );
    expect(taskOutputEvent.state.taskEventKind, 'output');
    expect(taskOutputEvent.state.taskOutputSource, 'worker');
    expect(taskOutputEvent.state.taskOutputSeverity, 'info');
    expect(taskOutputEvent.state.taskOutputSanitized, isFalse);
    expect(taskOutputEvent.state.taskOutputTruncated, isFalse);
    expect(taskOutputEvent.state.source, 'fake-task/worker');

    final taskOutputFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.traceEvent,
      label: 'Fake task output',
    );
    expect(
      taskOutputFallback.states.join('\n'),
      contains(
        'task event output, run 1, sequence 3, status running, '
        'output sequence 1, output source worker, severity info',
      ),
    );

    final overviewAgain = await _invoke(tester, proofCommandGoOverview);
    expect(overviewAgain.status, CommandInvocationStatus.completed);

    final plan = tester.semantics().single(
      role: SemanticRole.taskGraph,
      label: 'Proof workflow plan',
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

    final cancel = await _invoke(tester, proofCommandCancelTask);
    expect(cancel.status, CommandInvocationStatus.completed);

    final canceled = tester.semantics().single(
      role: SemanticRole.task,
      label: 'Fake task',
    );
    expect(canceled.value, 'canceled');
    expect(canceled.busy, isFalse);
    expect(canceled.state.taskStatus, 'canceled');
    expect(canceled.state.lastTaskEventKind, 'canceled');
    expect(tester.exists(text('Task: canceled')), isTrue);
  });

  testWidgets('command palette can drive app navigation', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandOpenPalette);
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

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _settleModal(tester);

    expect(_proofApp(tester).state.activeScreenId, 'diagnostics');
    expect(tester.exists(text('Diagnostics')), isTrue);
  });

  testWidgets('approval command opens a semantic approval prompt', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final opened = await _invoke(tester, proofCommandRequestApproval);
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

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(90, 28));
    expect(
      tester.exists(text('[log] approval: deploy approval granted')),
      isTrue,
    );
  });

  testWidgets('process screen runs native command through scoped commands', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final nav = await _invoke(tester, proofCommandGoProcess);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_proofApp(tester).state.activeScreenId, 'process');
    expect(tester.exists(text('Process')), isTrue);
    var toolCall = tester.semantics().single(
      role: SemanticRole.toolCall,
      label: 'Dart version command',
      action: SemanticAction.copy,
    );
    expect(toolCall.state['toolCallId'], 'process.dart-version');
    expect(toolCall.state['toolName'], contains('dart'));
    expect(toolCall.state['toolStatus'], 'queued');
    expect(toolCall.state['argumentCount'], 1);
    expect(toolCall.state['processCommandId'], proofCommandRunProcess.value);

    var runCommand = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Run Dart Version',
      action: SemanticAction.start,
    );
    var cancelCommand = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Cancel Dart Version',
      action: SemanticAction.cancel,
    );
    expect(runCommand.enabled, isTrue);
    expect(runCommand.state.commandId, 'process.dartVersion.start');
    expect(runCommand.state.commandCategory, 'Process');
    expect(cancelCommand.enabled, isFalse);

    final run = await _invoke(tester, proofCommandRunProcess);
    expect(run.status, CommandInvocationStatus.completed);

    final process = await _waitForTaskStatus(
      tester,
      label: 'Dart version',
      status: 'succeeded',
    );
    expect(process.state.taskId, 'dart-version');
    expect(process.state['command'], contains(' --version'));
    expect(process.state['exitCode'], 0);
    expect(process.state['processSucceeded'], isTrue);
    expect(process.state.outputCount, greaterThan(0));
    expect(tester.exists(text('Process: done')), isTrue);

    final processFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.task,
      label: 'Dart version',
    );
    expect(processFallback.states.join('\n'), contains('exit 0'));
    expect(processFallback.states.join('\n'), contains('process succeeded'));

    toolCall = tester.semantics().single(
      role: SemanticRole.toolCall,
      label: 'Dart version command',
      value: 'succeeded',
      action: SemanticAction.copy,
    );
    expect(toolCall.busy, isFalse);
    expect(toolCall.state['toolStatus'], 'succeeded');
    expect(toolCall.state.progressCurrent, 1);
    expect(toolCall.state.progressTotal, 1);

    final log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Dart version output',
    );
    expect(log.state.collectionRowCount, greaterThan(0));

    runCommand = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Run Dart Version',
    );
    cancelCommand = tester.semantics().single(
      role: SemanticRole.command,
      label: 'Cancel Dart Version',
    );
    expect(runCommand.enabled, isTrue);
    expect(cancelCommand.enabled, isFalse);
  });

  testWidgets('global search debounces query and activates result navigation', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final nav = await _invoke(tester, proofCommandGoSearch);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_proofApp(tester).state.activeScreenId, 'search');
    expect(tester.exists(text('Global Search')), isTrue);

    await _invoke(tester, proofCommandFocusSearch);
    tester.type('API deploy smoke');

    final task = await _waitForTaskStatus(
      tester,
      label: 'Global search',
      status: 'succeeded',
    );
    expect(task.state.progressLabel, '1 matches');
    expect(task.state.outputCount, 1);
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
    expect(_proofApp(tester).state.activeScreenId, 'runs');

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(90, 26));
    expect(tester.exists(text('[log] search: activated run.RUN-1002')), isTrue);
  });

  testWidgets('indexed logs build cooperative index and refresh appends', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final nav = await _invoke(tester, proofCommandGoIndex);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_proofApp(tester).state.activeScreenId, 'index');
    expect(tester.exists(text('Indexed Logs')), isTrue);

    final build = await _invoke(tester, proofCommandBuildLogIndex);
    expect(build.status, CommandInvocationStatus.completed);
    await _waitForTaskProgress(
      tester,
      label: 'Proof log index',
      current: proofIndexedLogInitialCount,
    );
    var task = await _waitForTaskStatus(
      tester,
      label: 'Proof log index',
      status: 'succeeded',
    );
    expect(task.state.taskStatus, 'succeeded');
    expect(task.state.progressCurrent, proofIndexedLogInitialCount);
    expect(task.state.progressLabel, 'index proof logs complete');
    expect(task.state.outputCount, 1);
    expect(task.state.source, 'index');
    expect(task.state.taskEventCount, greaterThan(4));

    await _invoke(tester, proofCommandFocusIndexFilter);
    tester.type('target:payment');
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(96, 28));

    var log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
      action: SemanticAction.focus,
    );
    expect(log.state.filterText, 'target:payment');
    expect(log.state.collectionRowCount, 48);
    expect(log.state['totalEntryCount'], proofIndexedLogInitialCount);
    expect(log.state.selectedKey, 'IDX-1000');

    final focusedLog = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.log,
      label: 'Indexed proof logs',
    );
    expect(focusedLog.completed, isTrue);
    tester.render(size: const CellSize(96, 28));
    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
      focused: true,
    );
    expect(log.state.selectedKey, 'IDX-1000');

    final logFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
    );
    expect(
      logFallback.states.any(
        (state) =>
            state.startsWith('log ') &&
            state.contains('$proofIndexedLogInitialCount entries') &&
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
      label: 'Indexed proof logs',
    );
    expect(log.state.selectedKey, 'IDX-1004');
    expect(log.state['selectedIndex'], 1);
    expect(log.state['followTail'], isFalse);
    expect(log.focused, isTrue);

    final append = await _invoke(tester, proofCommandAppendIndexedLogBurst);
    expect(append.status, CommandInvocationStatus.completed);
    await _waitForTaskProgress(
      tester,
      label: 'Proof log index',
      current: proofIndexedLogInitialCount + proofIndexedLogAppendCount,
    );
    task = await _waitForTaskStatus(
      tester,
      label: 'Proof log index',
      status: 'succeeded',
    );
    expect(task.state.taskStatus, 'succeeded');
    expect(
      task.state.progressCurrent,
      proofIndexedLogInitialCount + proofIndexedLogAppendCount,
    );
    expect(task.state.progressLabel, 'refresh proof logs complete');
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(96, 28));

    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Indexed proof logs',
    );
    expect(
      log.state['totalEntryCount'],
      proofIndexedLogInitialCount + proofIndexedLogAppendCount,
    );
    expect(log.state.collectionRowCount, 49);

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(96, 28));
    expect(
      tester.exists(text('[log] index: built 192 proof log rows')),
      isTrue,
    );
    expect(
      tester.exists(text('[log] index: refreshed 195 proof log rows')),
      isTrue,
    );
  });

  testWidgets('connection screen proves shared form semantics and submit', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    final nav = await _invoke(tester, proofCommandGoConnection);
    expect(nav.status, CommandInvocationStatus.completed);
    expect(_proofApp(tester).state.activeScreenId, 'connection');
    expect(tester.exists(text('Connection setup')), isTrue);

    tester.render(size: const CellSize(90, 28));
    var form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    expect(form.state['fieldCount'], 9);
    expect(form.state['visibleFieldCount'], 3);
    expect(form.state['layout'], 'wizard');
    expect(form.state['stepCount'], 3);
    expect(form.state['currentStepId'], 'connection-basics');
    expect(form.state['hasAsyncValidators'], isTrue);
    var fallbackForm = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    var fallbackState = fallbackForm.states.join('\n');
    expect(fallbackState, contains('layout wizard'));
    expect(fallbackState, contains('3 visible fields'));
    expect(fallbackState, contains('step 1 of 3'));
    expect(fallbackState, contains('current step Basics'));
    expect(fallbackState, contains('current step id connection-basics'));

    final project = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Project',
    );
    expect(project.state['hasAsyncValidator'], isTrue);
    expect(
      tester.semantics().where(role: SemanticRole.formField, label: 'Features'),
      isEmpty,
    );

    tester.type('dune');
    final basicsNext = await tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    expect(basicsNext.completed, isTrue);
    await _flushAsyncUi(tester);

    form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    expect(form.state['visibleFieldCount'], 4);
    expect(form.state['currentStepId'], 'connection-runtime');
    expect(form.actions, contains(SemanticAction.decrement));
    fallbackForm = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    fallbackState = fallbackForm.states.join('\n');
    expect(fallbackState, contains('4 visible fields'));
    expect(fallbackState, contains('step 2 of 3'));
    expect(fallbackState, contains('current step Runtime'));

    final features = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Features',
      value: 'Logs, Metrics',
    );
    expect(features.state['fieldType'], 'multiSelect');
    expect(features.state['selectedOptionCount'], 2);
    expect(features.state['maxSelected'], 3);

    final configPath = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Config path',
      value: 'config/proof.yaml',
    );
    expect(configPath.state['fieldType'], 'path');
    expect(configPath.state['pathKind'], 'file');
    expect(configPath.state['allowRelative'], isTrue);

    final retries = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Retry limit',
      value: '3',
    );
    expect(retries.state['fieldType'], 'number');
    expect(retries.state['max'], 10);

    final launchDate = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Launch date',
      value: '2026-01-15',
    );
    expect(launchDate.state['fieldType'], 'date');
    expect(launchDate.state['firstDate'], '2026-01-01');
    expect(launchDate.state['lastDate'], '2026-12-31');

    final runtimeNext = await tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    expect(runtimeNext.completed, isTrue);
    await _flushAsyncUi(tester);

    form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    expect(form.state['visibleFieldCount'], 2);
    expect(form.state['currentStepId'], 'connection-secret');
    fallbackForm = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    fallbackState = fallbackForm.states.join('\n');
    expect(fallbackState, contains('2 visible fields'));
    expect(fallbackState, contains('step 3 of 3'));
    expect(fallbackState, contains('current step Secret'));
    expect(fallbackState, contains('can go back'));

    final apiKey = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'API key',
    );
    expect(apiKey.value, isNull);
    expect(apiKey.state['redacted'], isTrue);

    await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.formField,
      label: 'API key',
    );
    tester.type('secret-token');
    await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.formField,
      label: 'I understand this changes remote state',
    );
    tester.type(' ');
    final submit = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    expect(submit.completed, isTrue);
    await _flushAsyncUi(tester);

    form = tester.semantics().single(role: SemanticRole.form);
    expect(form.state['submitted'], isTrue);
    expect(form.state['valid'], isTrue);
    expect(form.state['errorCount'], 0);

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(90, 28));
    expect(
      tester.exists(
        text(
          '[log] connection: configured dune dev us-east-1 '
          'features logs,metrics config config/proof.yaml 2026-01-15 '
          'retries 3',
        ),
      ),
      isTrue,
    );
  });

  testWidgets('runs screen filter narrows the table fixture', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoRuns);
    await _invoke(tester, proofCommandFocusRunsFilter);
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
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoRuns);
    await _invoke(tester, proofCommandFocusRunsTable);
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

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
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

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(80, 24));

    expect(
      tester.exists(text('[log] runs: selected run RUN-1002 failed')),
      isTrue,
    );
  });

  testWidgets('runs table copies the selected DataTable row', (tester) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      await _invoke(tester, proofCommandGoRuns);
      await _invoke(tester, proofCommandFocusRunsTable);
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.render(size: const CellSize(80, 24));

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(
        clipboard.lastWritten,
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
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('tree screen proves TreeTable navigation, semantics, and copy', (
    tester,
  ) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      final nav = await _invoke(tester, proofCommandGoTree);
      expect(nav.status, CommandInvocationStatus.completed);
      expect(_proofApp(tester).state.activeScreenId, 'tree');
      expect(tester.exists(text('Tree')), isTrue);

      await _invoke(tester, proofCommandFocusTreeTable);
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

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(
        clipboard.lastWritten,
        'Component\tStatus\tOwner\n'
        'Core Framework\tready\truntime',
      );
      tree = tester.semantics().single(
        role: SemanticRole.tree,
        label: 'Framework component tree',
        action: SemanticAction.copy,
      );
      expect(tree.state.clipboardPolicy, 'inProcessOnly');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      await _flushAsyncUi(tester);
      await _invoke(tester, proofCommandGoTranscript);
      tester.render(size: const CellSize(90, 24));
      expect(
        tester.exists(text('[log] tree: selected semantic-graph active')),
        isTrue,
      );
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('payload screen proves JsonView semantics and safe copy', (
    tester,
  ) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      final nav = await _invoke(tester, proofCommandGoPayload);
      expect(nav.status, CommandInvocationStatus.completed);
      expect(_proofApp(tester).state.activeScreenId, 'payload');
      expect(tester.exists(text('Payload')), isTrue);

      await _invoke(tester, proofCommandFocusPayload);
      final output = tester.renderToString(
        size: const CellSize(90, 26),
        emptyMark: ' ',
      );
      expect(output, contains('unsafeOutput: "bad'));
      expect(output, isNot(contains('token')));
      expect(output, isNot(contains('\x1b]52')));

      final json = tester.semantics().single(
        role: SemanticRole.json,
        label: 'Proof payload',
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

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(clipboard.lastWritten, contains('"jsonView": true'));
      expect(clipboard.lastWritten, isNot(contains('token')));
      expect(clipboard.lastWritten, isNot(contains('\x1b]52')));

      await _invoke(tester, proofCommandGoTranscript);
      tester.render(size: const CellSize(90, 26));
      expect(tester.exists(text(r'[log] payload: copied $')), isTrue);
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('changes screen proves DiffView semantics and safe hunk copy', (
    tester,
  ) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      final nav = await _invoke(tester, proofCommandGoChanges);
      expect(nav.status, CommandInvocationStatus.completed);
      expect(_proofApp(tester).state.activeScreenId, 'changes');
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

      await _invoke(tester, proofCommandFocusChanges);
      final output = tester.renderToString(
        size: const CellSize(90, 26),
        emptyMark: ' ',
      );
      expect(output, contains('Framework patch review: 1 files'));
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
      expect(patch.state.patchId, 'proof.framework.patch');
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
          .singleWhere(
            (node) => node.label!.contains('+  final note = \'safe'),
          );
      expect(unsafe.label, isNot(contains('token')));
      expect(unsafe.state.outputSanitized, isTrue);
      expect(unsafe.state['newLine'], 3);

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(clipboard.lastWritten, contains('@@ -1,4 +1,5 @@'));
      expect(clipboard.lastWritten, contains('+  final mode = \'reactive\';'));
      expect(clipboard.lastWritten, isNot(contains('token')));
      expect(clipboard.lastWritten, isNot(contains('\x1b]52')));

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

      await _invoke(tester, proofCommandGoTranscript);
      tester.render(size: const CellSize(90, 26));
      expect(
        tester.exists(
          text('[log] changes: copied lib/framework.dart addition'),
        ),
        isTrue,
      );
      expect(
        tester.exists(text('[log] patch: selected lib/framework.dart')),
        isTrue,
      );
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('source screen proves CodeView semantics and safe source copy', (
    tester,
  ) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      final nav = await _invoke(tester, proofCommandGoSource);
      expect(nav.status, CommandInvocationStatus.completed);
      expect(_proofApp(tester).state.activeScreenId, 'source');
      expect(tester.exists(text('Source')), isTrue);

      await _invoke(tester, proofCommandFocusSource);
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

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(clipboard.lastWritten, contains("return const Text('safe"));
      expect(clipboard.lastWritten, isNot(contains('token')));
      expect(clipboard.lastWritten, isNot(contains('\x1b]52')));

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

      await _invoke(tester, proofCommandGoTranscript);
      tester.render(size: const CellSize(90, 26));
      expect(
        tester.exists(text('[log] source: copied line 8 keyword')),
        isTrue,
      );
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('docs screen proves MarkdownView semantics and safe doc copy', (
    tester,
  ) async {
    final originalClipboard = Clipboard.instance;
    final clipboard = TestClipboard();
    Clipboard.instance = clipboard;
    try {
      tester.pumpWidget(const ProofConsoleApp());

      final nav = await _invoke(tester, proofCommandGoDocs);
      expect(nav.status, CommandInvocationStatus.completed);
      expect(_proofApp(tester).state.activeScreenId, 'docs');
      expect(tester.exists(text('Docs')), isTrue);

      await _invoke(tester, proofCommandFocusDocs);
      final output = tester.renderToString(
        size: const CellSize(90, 26),
        emptyMark: ' ',
      );
      expect(output, contains('Fleury Launch Notes'));
      expect(output, contains('docs (https://fleury.dev)'));
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
      expect(link.value, 'https://fleury.dev');
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

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await _flushAsyncUi(tester);

      expect(clipboard.lastWritten, contains('> unsafe safe'));
      expect(clipboard.lastWritten, isNot(contains('token')));
      expect(clipboard.lastWritten, isNot(contains('\x1b]52')));

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

      await _invoke(tester, proofCommandGoTranscript);
      tester.render(size: const CellSize(90, 26));
      expect(
        tester.exists(text('[log] docs: copied block 6 blockquote')),
        isTrue,
      );
    } finally {
      Clipboard.instance = originalClipboard;
    }
  });

  testWidgets('debug capture snapshot can seed a proof-app regression', (
    tester,
  ) async {
    final capture = DebugCaptureRecorder();
    void recordCommand(CommandId command) {
      capture.record(InputDebugEvent(kind: 'command', summary: command.value));
    }

    tester.pumpWidget(const ProofConsoleApp());
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
          dirtySources: ['build:ProofConsoleApp'],
          bufferSize: CellSize(80, 24),
        ),
      ),
    );

    recordCommand(proofCommandGoRuns);
    await _invoke(tester, proofCommandGoRuns);
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

    recordCommand(proofCommandStartTask);
    await _invoke(tester, proofCommandStartTask);
    recordCommand(proofCommandFocusRunsTable);
    await _invoke(tester, proofCommandFocusRunsTable);
    capture.record(const InputDebugEvent(kind: 'key', summary: 'arrowDown'));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    capture.record(const InputDebugEvent(kind: 'key', summary: 'enter'));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _flushAsyncUi(tester);
    recordCommand(proofCommandCaptureDebug);
    await _invoke(tester, proofCommandCaptureDebug);

    capture.recordOutputSummary(
      const DebugOutputSummary(
        source: 'proof-console-transcript',
        lineCount: 5,
      ),
    );

    expect(tester.exists(text('Debug: captures 1')), isTrue);
    expect(tester.exists(text('Task: running 15%')), isTrue);
    final tree = tester.semantics();
    final app = _proofApp(tester);
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
        'task.startFake',
        'runs.focusTable',
        'arrowDown',
        'enter',
        'debug.captureSnapshot',
      ]),
    );
    expect(
      artifact.hasInput(
        kind: 'command',
        summary: proofCommandCaptureDebug.value,
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
      artifact.outputSummariesFor(source: 'proof-console-transcript').single,
      containsPair('lineCount', 5),
    );

    final semantics = snapshotJson['semantics'] as Map<String, Object?>;
    expect(semantics['nodeCount'], greaterThan(40));
    final accessibility = snapshotJson['accessibility'] as Map<String, Object?>;
    expect(accessibility['nodeCount'], semantics['nodeCount']);
    expect(artifact.accessibilityPlainText, contains('Fleury Proof Console'));
    expect(artifact.accessibilityPlainText, contains('API deploy smoke'));
    expect(artifact.accessibilityPlainText, contains('running 15%'));
    final capturedApp = artifact.singleSemanticNode(
      role: 'app',
      label: 'Fleury Proof Console',
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
        label: 'Task',
        value: 'running 15%',
      ),
      isNotEmpty,
    );
  });

  testWidgets('composer submission and log burst update transcript', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
    await _invoke(tester, proofCommandFocusComposer);
    tester.type('operator note');

    var composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'operator note');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(80, 24));

    expect(tester.exists(text('[log] user: operator note')), isTrue);

    final burst = await _invoke(tester, proofCommandAppendLogBurst);
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

    await _invoke(tester, proofCommandToggleStream);
    final disabled = await _invoke(tester, proofCommandAppendLogBurst);
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
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
    await _invoke(tester, proofCommandAppendLogBurst);
    await _invoke(tester, proofCommandAppendLogBurst);
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

    await _invoke(tester, proofCommandGoOverview);
    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));

    selected = tester.semantics().single(
      role: SemanticRole.message,
      label: '[log] stream: burst 2.2',
      selected: true,
    );
    expect(selected.state.messageId, targetId);

    await _invoke(tester, proofCommandAppendLogBurst);
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
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
    await _invoke(tester, proofCommandFocusComposer);
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

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    await _flushAsyncUi(tester);
    tester.render(size: const CellSize(110, 32));

    expect(
      tester.exists(text('[log] user: /summarize deployment risk')),
      isTrue,
    );
  });

  testWidgets('composer history restores submitted notes', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
    await _invoke(tester, proofCommandFocusComposer);
    tester.type('first operator note');

    var composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'first operator note');
    expect(composer.state.historyCount, 0);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
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
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, 'first operator note');
    expect(composer.state.historyCount, 1);
    expect(composer.state.historyIndex, 0);
    expect(composer.state.historyBrowsing, isTrue);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
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
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
    composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
      focused: true,
    );
    expect(composer.value, '/');
    expect(composer.state.historyBrowsing, isFalse);
    final selectedCompletion = tester.semantics().single(
      role: SemanticRole.menuItem,
      label: '/run-task',
      selected: true,
    );
    expect(selectedCompletion.state.completionQuery, '/');
  });

  testWidgets('file mention picker inserts composer mentions', (tester) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
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
      label: 'Proof console app',
      action: SemanticAction.activate,
    );
    expect(mention.state.filePath, contains('fleury_example_console.dart'));
    expect(mention.state.fileLanguage, 'dart');
    expect(mention.state.mentionText, '@proof-console');

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.fileMention,
      label: 'Proof console app',
    );
    expect(result.completed, isTrue);

    final composer = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Type a note and press Enter',
    );
    expect(composer.value, '@proof-console');

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
      label: 'Proof console app',
    );
    expect(fallback.states.join('\n'), contains('mention @proof-console'));
  });

  testWidgets('conversation navigator selects proof conversations', (
    tester,
  ) async {
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(110, 32));

    var navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Proof conversations',
    );
    expect(navigator.state['totalConversationCount'], 4);
    expect(navigator.state['filteredConversationCount'], 4);
    expect(navigator.state.selectedConversationId, 'thread.transcript');
    expect(navigator.state['unreadConversationCount'], 1);
    expect(navigator.actions, contains(SemanticAction.focus));
    expect(navigator.actions, contains(SemanticAction.navigate));

    final focusedNavigator = await tester.invokeSemanticAction(
      SemanticAction.navigate,
      role: SemanticRole.conversationNavigator,
      label: 'Proof conversations',
    );
    expect(focusedNavigator.completed, isTrue);
    tester.render(size: const CellSize(110, 32));
    navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Proof conversations',
      focused: true,
    );
    expect(navigator.state.selectedConversationId, 'thread.transcript');

    final worker = tester.semantics().single(
      role: SemanticRole.conversation,
      label: 'Worker task',
      action: SemanticAction.activate,
    );
    expect(worker.state.conversationId, 'thread.worker');
    expect(worker.state.conversationStatus, 'idle');
    expect(worker.state.conversationMessageCount, 0);

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.conversation,
      label: 'Worker task',
    );
    expect(result.completed, isTrue);

    tester.render(size: const CellSize(110, 32));
    expect(
      tester.exists(text('[log] conversation: selected thread.worker')),
      isTrue,
    );
    navigator = tester.semantics().single(
      role: SemanticRole.conversationNavigator,
      label: 'Proof conversations',
      focused: true,
    );
    expect(navigator.state.selectedConversationId, 'thread.worker');

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.conversation,
      label: 'Worker task',
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
    tester.pumpWidget(const ProofConsoleApp());

    await _invoke(tester, proofCommandGoDiagnostics);
    await _invoke(tester, proofCommandCaptureDebug);

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
    expect(_proofApp(tester).state.lastCommandId, 'debug.captureSnapshot');

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
    expect(osc52.state.capabilityResolution, 'degraded');
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
      label: 'Proof trace timeline',
      action: SemanticAction.focus,
    );
    expect(timeline.state['traceEventCount'], 5);
    expect(timeline.state['runningTraceEventCount'], 1);
    expect(timeline.state.selectedTraceId, 'trace.boot');

    final focusedTimeline = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.traceTimeline,
      label: 'Proof trace timeline',
    );
    expect(focusedTimeline.completed, isTrue);
    tester.render(size: const CellSize(80, 24));
    var updatedTimeline = tester.semantics().single(
      role: SemanticRole.traceTimeline,
      label: 'Proof trace timeline',
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
      label: 'Proof trace timeline',
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

    await _invoke(tester, proofCommandGoTranscript);
    tester.render(size: const CellSize(80, 24));
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
