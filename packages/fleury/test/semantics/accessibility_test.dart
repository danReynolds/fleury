import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('accessibility snapshot redacts secret text values', (tester) {
    final controller = TextEditingController(text: 'super-secret');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        placeholder: 'Token',
        obscureText: true,
      ),
    );

    final snapshot = tester.accessibilitySnapshot();
    final field = snapshot.single(role: SemanticRole.textField, label: 'Token');
    final text = snapshot.toPlainText();

    expect(field.value, isNull);
    expect(field.valueRedacted, isTrue);
    expect(field.states, contains('value redacted'));
    expect(field.states, contains('focused'));
    expect(field.toJson(), containsPair('valueRedacted', true));
    expect(text, contains('value redacted'));
    expect(text, isNot(contains('super-secret')));
  });

  testWidgets('accessibility snapshot describes validation and actions', (
    tester,
  ) {
    final controller = TextEditingController(text: 'deploy');
    tester.pumpWidget(
      TextInput(
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
        validationError: 'Command unavailable',
        onSubmit: (_) {},
      ),
    );

    final field = tester.accessibilitySnapshot().single(
      role: SemanticRole.textField,
      label: 'Command',
    );

    expect(field.value, 'deploy');
    expect(field.validationError, 'Command unavailable');
    expect(field.states, contains('focused'));
    expect(
      field.actions,
      containsAll(<SemanticAction>[
        SemanticAction.clear,
        SemanticAction.focus,
        SemanticAction.submit,
      ]),
    );
    expect(field.announcement, contains('error: Command unavailable'));
    expect(
      field.announcement,
      contains('actions: clear, focus, setValue, submit'),
    );
  });

  testWidgets('accessibility snapshot exposes typed query fields', (tester) {
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            role: SemanticRole.button,
            label: 'Deploy',
            enabled: false,
            actions: {SemanticAction.activate},
            child: Text('Deploy'),
          ),
          Semantics(
            role: SemanticRole.treeItem,
            label: 'Runs',
            selected: true,
            expanded: true,
            child: Text('Runs'),
          ),
          Semantics(
            role: SemanticRole.progress,
            label: 'Index',
            busy: true,
            child: Text('Index'),
          ),
        ],
      ),
    );

    final snapshot = tester.accessibilitySnapshot();
    final disabled = snapshot.single(
      role: SemanticRole.button,
      enabled: false,
      action: SemanticAction.activate,
    );
    final selected = snapshot.single(
      role: SemanticRole.treeItem,
      selected: true,
      expanded: true,
    );
    final busy = snapshot.single(role: SemanticRole.progress, busy: true);

    expect(disabled.label, 'Deploy');
    expect(disabled.enabled, isFalse);
    expect(disabled.toJson(), containsPair('enabled', false));
    expect(selected.label, 'Runs');
    expect(selected.selected, isTrue);
    expect(selected.expanded, isTrue);
    expect(selected.toJson(), containsPair('selected', true));
    expect(selected.toJson(), containsPair('expanded', true));
    expect(busy.label, 'Index');
    expect(busy.busy, isTrue);
    expect(busy.toJson(), containsPair('busy', true));
    expect(snapshot.where(selected: true), contains(selected));
  });

  testWidgets('accessibility snapshot summarizes adapter-facing state', (
    tester,
  ) {
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            id: SemanticNodeId('command:deploy'),
            role: SemanticRole.button,
            label: 'Deploy',
            focused: true,
            actions: {SemanticAction.activate},
            child: Text('Deploy'),
          ),
          Semantics(
            id: SemanticNodeId('field:token'),
            role: SemanticRole.textField,
            label: 'Token',
            value: 'secret-token',
            validationError: 'Required',
            state: SemanticState({'redactedValue': true}),
            child: Text('token'),
          ),
          Semantics(
            id: SemanticNodeId('task:index'),
            role: SemanticRole.task,
            label: 'Index',
            enabled: false,
            selected: true,
            busy: true,
            actions: {SemanticAction.cancel},
            child: Text('index'),
          ),
        ],
      ),
    );

    final snapshot = tester.accessibilitySnapshot();
    final summary = snapshot.summary;

    expect(summary.nodeCount, 7);
    expect(summary.roleCount(SemanticRole.button), 1);
    expect(summary.roleCount(SemanticRole.textField), 1);
    expect(summary.roleCount(SemanticRole.text), 3);
    expect(summary.focusedNodeId, const SemanticNodeId('command:deploy'));
    expect(summary.focusedLabel, 'Deploy');
    expect(summary.selectedCount, 1);
    expect(summary.disabledCount, 1);
    expect(summary.busyCount, 1);
    expect(summary.validationErrorCount, 0);
    expect(summary.redactedValueCount, 1);
    expect(summary.actionableNodeCount, 2);
    expect(summary.actionCount, 2);
    expect(snapshot.focusedNode!.label, 'Deploy');
    expect(
      snapshot.nodeBySourceId(const SemanticNodeId('field:token'))!.label,
      'Token',
    );
    expect(snapshot.actionableNodes.map((node) => node.label), [
      'Deploy',
      'Index',
    ]);
    expect(snapshot.validationErrorNodes, isEmpty);
    expect(snapshot.redactedValueNodes.single.label, 'Token');

    final json = snapshot.toJson();
    final jsonSummary = json['summary'] as Map<String, Object?>;
    expect(jsonSummary['focusedNodeId'], 'command:deploy');
    expect(jsonSummary['redactedValueCount'], 1);
    expect(
      jsonSummary['roleCounts'],
      containsPair(SemanticRole.textField.name, 1),
    );
  });

  testWidgets('accessibility snapshot surfaces capability fallbacks', (tester) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.image,
        label: 'Preview',
        state: SemanticState({
          'terminalCapability': 'inlineImages',
          'capabilityResolution': 'degraded',
          'activeFallback': 'glyph',
        }),
        child: Text('preview unavailable'),
      ),
    );

    final image = tester.accessibilitySnapshot().single(
      role: SemanticRole.image,
      label: 'Preview',
    );

    expect(
      image.states,
      contains('capability inlineImages degraded fallback glyph'),
    );
    expect(
      image.toJson()['states'],
      contains('capability inlineImages degraded fallback glyph'),
    );
  });

  testWidgets('accessibility snapshot includes collection and progress state', (
    tester,
  ) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.progress,
        label: 'Indexing',
        busy: true,
        state: SemanticState({
          'progressCurrent': 25,
          'progressTotal': 100,
          'collectionRowCount': 100000,
          'collectionColumnCount': 4,
          'visibleRangeStart': 40,
          'visibleRangeEnd': 63,
        }),
        child: Text('indexing'),
      ),
    );

    final progress = tester.accessibilitySnapshot().single(
      role: SemanticRole.progress,
      label: 'Indexing',
    );

    expect(progress.states, contains('busy'));
    expect(progress.states, contains('progress 25 of 100'));
    expect(progress.states, contains('100000 rows, 4 columns, visible 40-63'));
  });

  testWidgets('accessibility snapshot describes chart state', (tester) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.chart,
        label: 'Latency chart',
        actions: {SemanticAction.focus, SemanticAction.increment},
        state: SemanticState({
          'chartType': 'line',
          'chartSeriesCount': 2,
          'chartPointCount': 120,
          'chartXMin': 0,
          'chartXMax': 60,
          'chartYMin': 10,
          'chartYMax': 250,
          'chartReferenceCount': 1,
          'chartInteractive': true,
          'chartCursorIndex': 4,
          'chartCursorCount': 12,
          'chartCursorX': 20,
        }),
        child: Text('chart'),
      ),
    );

    final chart = tester.accessibilitySnapshot().single(
      role: SemanticRole.chart,
      label: 'Latency chart',
      action: SemanticAction.increment,
    );

    expect(
      chart.states,
      contains(
        'chart line, 2 series, 120 points, x 0-60, y 10-250, '
        '1 reference, interactive, cursor 5 of 12, cursor x 20',
      ),
    );
    expect(chart.roleLabel, 'chart');
  });

  testWidgets('accessibility snapshot describes wizard form state', (tester) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.form,
        label: 'Connection setup',
        actions: {SemanticAction.increment},
        state: SemanticState({
          'fieldCount': 9,
          'visibleFieldCount': 3,
          'layout': 'wizard',
          'stepCount': 3,
          'currentStepPosition': 1,
          'currentStepId': 'connection-basics',
          'currentStepTitle': 'Basics',
          'canGoBack': false,
          'canGoForward': true,
          'hasAsyncValidators': true,
        }),
        child: Text('connection setup'),
      ),
    );

    final form = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    final stateText = form.states.join('\n');

    expect(stateText, contains('9 fields'));
    expect(stateText, contains('3 visible fields'));
    expect(stateText, contains('layout wizard'));
    expect(stateText, contains('step 1 of 3'));
    expect(stateText, contains('current step Basics'));
    expect(stateText, contains('current step id connection-basics'));
    expect(stateText, contains('can go forward'));
    expect(stateText, isNot(contains('can go back')));
    expect(stateText, contains('async validation'));
  });

  testWidgets('accessibility snapshot describes workflow summary state', (
    tester,
  ) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.region,
        label: 'Workflow',
        state: SemanticState({
          'workflowId': 'ops',
          'workflowTitle': 'Ops Console',
          'workflowHealth': 'needsAttention',
          'messageCount': 5,
          'activeMessageCount': 2,
          'failedMessageCount': 1,
          'toolCallCount': 3,
          'activeToolCallCount': 1,
          'failedToolCallCount': 1,
          'approvalCount': 1,
          'taskCount': 4,
          'activeTaskCount': 2,
          'failedTaskCount': 1,
          'modelStatus': 'degraded',
          'modelBusy': true,
          'contextItemCount': 6,
          'contextTokenCount': 3200,
          'fileMentionCount': 2,
          'conversationCount': 3,
          'unreadConversationCount': 1,
          'traceEventCount': 7,
          'activeTraceEventCount': 1,
          'failedTraceEventCount': 1,
          'warningTraceEventCount': 2,
          'patchFileCount': 2,
          'reviewIssueCount': 1,
          'logEntryCount': 9,
          'warningLogEntryCount': 2,
          'errorLogEntryCount': 1,
        }),
        child: Text('workflow'),
      ),
    );

    final workflow = tester.accessibilitySnapshot().single(
      role: SemanticRole.region,
      label: 'Workflow',
    );

    expect(
      workflow.states,
      contains(
        'workflow id ops, title Ops Console, health needsAttention, '
        '5 messages, 2 active messages, 1 failed message, 3 tool calls, '
        '1 active tool call, 1 failed tool call, 1 approval, 4 tasks, '
        '2 active tasks, 1 failed task, model degraded, model busy, '
        '6 context items, 3200 context tokens, 2 file mentions, '
        '3 conversations, 1 unread conversation, 7 trace events, '
        '1 active trace event, 1 failed trace event, 2 trace warnings, '
        '2 patch files, 1 review issue, 9 log entries, 2 log warnings, '
        '1 log error',
      ),
    );
  });

  testWidgets(
    'accessibility snapshot describes app, command, task, and view state',
    (tester) {
      tester.pumpWidget(
        const Column(
          children: [
            Semantics(
              role: SemanticRole.app,
              label: 'Demo App',
              state: SemanticState({
                'screenCount': 11,
                'activeScreenId': 'runs',
                'commandCount': 9,
                'lastCommandId': 'debug.captureSnapshot',
                'lastCommandStatus': 'completed',
              }),
              child: Text('app'),
            ),
            Semantics(
              role: SemanticRole.command,
              label: 'Run Doctor',
              state: SemanticState({
                'commandId': 'process.doctor.start',
                'commandCategory': 'Process',
                'shortcut': 'Ctrl+R',
              }),
              child: Text('command'),
            ),
            Semantics(
              role: SemanticRole.task,
              label: 'Indexer',
              busy: true,
              state: SemanticState({
                'taskId': 'indexer',
                'taskStatus': 'running',
                'taskEventCount': 4,
                'lastTaskEventKind': 'output',
                'outputCount': 2,
                'source': 'worker',
                'command': 'dart --version',
                'exitCode': 1,
                'processSucceeded': false,
                'canCancel': true,
                'outputSanitized': true,
                'outputTruncated': true,
                'outputOriginalLength': 9000,
              }),
              child: Text('task'),
            ),
            Semantics(
              role: SemanticRole.table,
              label: 'Runs',
              state: SemanticState({
                'collectionRowCount': 100000,
                'collectionColumnCount': 5,
                'visibleRangeStart': 40,
                'visibleRangeEnd': 63,
                'selectedKey': 'RUN-1002',
                'filterText': 'failed',
                'sortColumn': 'duration',
                'sortDirection': 'desc',
              }),
              child: Text('table'),
            ),
          ],
        ),
      );

      final snapshot = tester.accessibilitySnapshot();
      final app = snapshot.single(role: SemanticRole.app, label: 'Demo App');
      final command = snapshot.single(
        role: SemanticRole.command,
        label: 'Run Doctor',
      );
      final task = snapshot.single(role: SemanticRole.task, label: 'Indexer');
      final table = snapshot.single(role: SemanticRole.table, label: 'Runs');

      expect(
        app.states,
        contains(
          '11 screens, active screen runs, 9 commands, last command debug.captureSnapshot completed',
        ),
      );
      expect(
        command.states,
        contains('command process.doctor.start, Process, Ctrl+R'),
      );
      expect(task.states, contains('busy'));
      expect(
        task.states,
        contains(
          'task indexer, running, 4 events, last output, 2 outputs, '
          'command dart --version, exit 1, process failed, can cancel, '
          'source worker',
        ),
      );
      expect(
        task.states,
        contains('output sanitized, truncated, original 9000 chars'),
      );
      expect(table.states, contains('100000 rows, 5 columns, visible 40-63'));
      expect(
        table.states,
        contains('selected RUN-1002, filter "failed", sort duration desc'),
      );
    },
  );

  testWidgets('accessibility snapshot describes app status state', (tester) {
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            role: SemanticRole.status,
            label: 'Status',
            state: SemanticState({'statusCount': 2}),
            child: Text('status'),
          ),
          Semantics(
            role: SemanticRole.status,
            label: 'Debug',
            value: 'captures 2',
            actions: {SemanticAction.activate},
            state: SemanticState({
              'statusId': 'debug',
              'severity': 'info',
              'commandId': 'debug.captureSnapshot',
            }),
            child: Text('debug'),
          ),
        ],
      ),
    );

    final snapshot = tester.accessibilitySnapshot();
    final root = snapshot.single(role: SemanticRole.status, label: 'Status');
    final debug = snapshot.single(role: SemanticRole.status, label: 'Debug');

    expect(root.states, contains('status 2 items'));
    expect(debug.value, 'captures 2');
    expect(debug.states, contains('status id debug, severity info'));
    expect(debug.states, contains('command debug.captureSnapshot'));
    expect(debug.actions, contains(SemanticAction.activate));
  });

  testWidgets('accessibility snapshot describes search and log state', (
    tester,
  ) {
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            role: SemanticRole.region,
            label: 'Global search',
            state: SemanticState({
              'filterText': 'deploy',
              'collectionRowCount': 2,
              'totalResultCount': 3,
              'filteredResultCount': 2,
              'selectedIndex': 0,
              'selectedKey': 'deploy.prod',
              'selectedCategory': 'Runbook',
              'selectedSource': 'ops',
            }),
            child: Text('search'),
          ),
          Semantics(
            role: SemanticRole.log,
            label: 'Logs',
            state: SemanticState({
              'collectionRowCount': 1,
              'totalEntryCount': 3,
              'filteredEntryCount': 1,
              'filterActive': true,
              'filterText': 'deploy',
              'filterSources': 'worker',
              'filterSeverities': 'error',
              'filterCaseSensitive': true,
              'followTail': true,
              'copyIncludesPrefix': true,
              'selectedIndex': 0,
              'lastKey': 'c',
            }),
            child: Text('logs'),
          ),
          Semantics(
            role: SemanticRole.listItem,
            label: 'Deploy production',
            state: SemanticState({
              'rowIndex': 1,
              'viewIndex': 0,
              'rowKey': 'deploy.prod',
              'resultCategory': 'Runbook',
              'resultSource': 'ops',
            }),
            child: Text('row'),
          ),
        ],
      ),
    );

    final snapshot = tester.accessibilitySnapshot();
    final search = snapshot.single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    final log = snapshot.single(role: SemanticRole.log, label: 'Logs');
    final row = snapshot.single(
      role: SemanticRole.listItem,
      label: 'Deploy production',
    );

    expect(search.states, contains('2 rows'));
    expect(search.states, contains('selected deploy.prod, filter "deploy"'));
    expect(
      search.states,
      contains(
        'search 3 results, 2 filtered, selected index 0, '
        'selected category Runbook, selected source ops',
      ),
    );
    expect(log.states, contains('1 rows'));
    expect(log.states, contains('filter "deploy"'));
    expect(
      log.states,
      contains(
        'log 3 entries, 1 filtered, filter active, sources worker, '
        'severities error, case sensitive, follow tail, copy includes prefix, '
        'selected index 0, last c',
      ),
    );
    expect(row.states, contains('row 1, view row 0, row key deploy.prod'));
    expect(row.states, contains('search category Runbook, source ops'));
  });

  testWidgets('accessibility snapshot describes diagnostic state', (tester) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.diagnostic,
        label: 'Terminal diagnostics',
        state: SemanticState({
          'terminalColumns': 120,
          'terminalRows': 32,
          'terminalColorMode': 'truecolor',
          'imageProtocol': 'halfBlock',
          'fallbackCount': 1,
          'warningCount': 2,
          'unsupportedFeatureCount': 3,
          'capabilityRowCount': 5,
          'debugCaptureCount': 4,
          'streaming': true,
          'osc52Policy': 'policyGated',
          'osc8Policy': 'disabledByDefault',
        }),
        child: Text('diagnostics'),
      ),
    );

    final diagnostic = tester.accessibilitySnapshot().single(
      role: SemanticRole.diagnostic,
      label: 'Terminal diagnostics',
    );

    expect(
      diagnostic.states,
      contains(
        'diagnostic 120x32, color truecolor, images halfBlock, '
        '5 capability rows, 1 fallbacks, 2 warnings, 3 unsupported, '
        'debug captures 4, streaming, OSC 52 policyGated, '
        'OSC 8 disabledByDefault',
      ),
    );
    expect(
      tester.accessibilitySnapshot().toPlainText(),
      contains('debug captures 4'),
    );
  });

  testWidgets('accessibility snapshot describes developer document state', (
    tester,
  ) {
    tester.pumpWidget(
      const Column(
        children: [
          Semantics(
            role: SemanticRole.json,
            label: 'Payload',
            state: SemanticState({
              'collectionRowCount': 6,
              'rootType': 'object',
              'selectedPath': r'$.runs[0]',
            }),
            child: Text('json'),
          ),
          Semantics(
            role: SemanticRole.diff,
            label: 'Changes',
            state: SemanticState({
              'fileCount': 1,
              'hunkCount': 2,
              'additionCount': 7,
              'deletionCount': 3,
              'selectedDiffKind': 'addition',
              'selectedFilePath': 'lib/main.dart',
              'selectedNewLine': 42,
            }),
            child: Text('diff'),
          ),
          Semantics(
            role: SemanticRole.code,
            label: 'Source',
            state: SemanticState({
              'language': 'dart',
              'filePath': 'lib/app.dart',
              'lineCount': 80,
              'nonEmptyLineCount': 70,
              'commentCount': 5,
              'blankCount': 10,
              'selectedCodeLineKind': 'keyword',
            }),
            child: Text('code'),
          ),
          Semantics(
            role: SemanticRole.markdown,
            label: 'Guide',
            state: SemanticState({
              'blockCount': 9,
              'headingCount': 2,
              'listItemCount': 3,
              'linkCount': 1,
              'codeBlockCount': 1,
              'codeLineCount': 4,
              'selectedMarkdownBlockKind': 'blockquote',
            }),
            child: Text('markdown'),
          ),
          Semantics(
            role: SemanticRole.treeItem,
            label: 'core',
            state: SemanticState({
              'rowIndex': 2,
              'rowKey': 'core',
              'depth': 1,
              'isBranch': true,
            }),
            child: Text('tree item'),
          ),
        ],
      ),
    );

    final snapshot = tester.accessibilitySnapshot();

    expect(
      snapshot.single(role: SemanticRole.json, label: 'Payload').states,
      contains('json root object, selected path \$.runs[0]'),
    );
    expect(
      snapshot.single(role: SemanticRole.diff, label: 'Changes').states,
      contains(
        '1 files, 2 hunks, 7 additions, 3 deletions, selected addition, selected file lib/main.dart, new line 42',
      ),
    );
    expect(
      snapshot.single(role: SemanticRole.code, label: 'Source').states,
      contains(
        'language dart, file lib/app.dart, 80 lines, 70 non-empty, 5 comments, 10 blanks, selected keyword',
      ),
    );
    expect(
      snapshot.single(role: SemanticRole.markdown, label: 'Guide').states,
      contains(
        '9 blocks, 2 headings, 3 list items, 1 links, 1 code blocks, 4 code lines, selected blockquote',
      ),
    );
    expect(
      snapshot.single(role: SemanticRole.treeItem, label: 'core').states,
      contains('row 2, row key core, depth 1, branch'),
    );
  });

  testWidgets('accessibility snapshot omits selected keys on redacted nodes', (
    tester,
  ) {
    tester.pumpWidget(
      const Semantics(
        role: SemanticRole.tableRow,
        label: 'Secret row',
        value: 'secret-token',
        state: SemanticState({
          'redactedValue': true,
          'selectedKey': 'secret-run',
          'rowKey': 'secret-row',
          'rowIndex': 4,
        }),
        child: Text('redacted'),
      ),
    );

    final row = tester.accessibilitySnapshot().single(
      role: SemanticRole.tableRow,
      label: 'Secret row',
    );
    final text = row.announcement;

    expect(row.value, isNull);
    expect(row.states, contains('value redacted'));
    expect(row.states, contains('row 4'));
    expect(text, isNot(contains('secret-token')));
    expect(text, isNot(contains('secret-run')));
    expect(text, isNot(contains('secret-row')));
  });
}
