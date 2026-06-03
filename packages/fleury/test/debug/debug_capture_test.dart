import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  test('capture snapshot serializes frame, input, and redacted semantics', () {
    final snapshot = DebugCaptureSnapshot(
      frames: [
        FrameEvent(
          frameNumber: 1,
          reason: 'key:enter',
          build: const Duration(microseconds: 10),
          layout: const Duration(microseconds: 20),
          paint: const Duration(microseconds: 30),
          diff: const Duration(microseconds: 40),
          dirtyCells: 2,
          dirtyBounds: CellRect.fromLTWH(1, 2, 3, 4),
          dirtySources: const ['build:SecretField/_SecretFieldState'],
          layoutStats: const RenderLayoutFrameStats(
            performedCount: 8,
            skippedCount: 3,
          ),
          repaintBoundaries: const RepaintBoundaryFrameStats(
            boundaryCount: 2,
            repaintedCount: 1,
            cachedCount: 1,
            emptyCount: 0,
            copiedCellCount: 12,
          ),
          bufferSize: const CellSize(80, 24),
        ),
      ],
      inputs: const [
        InputDebugEvent(kind: 'key', summary: 'enter'),
        InputDebugEvent(
          kind: 'resize',
          summary: '120x40',
          resizeSize: CellSize(120, 40),
        ),
      ],
      outputSummaries: const [
        DebugOutputSummary(
          source: 'task',
          lineCount: 3,
          sanitizedCount: 1,
          truncatedCount: 1,
        ),
      ],
      timeMarkers: const [
        DebugTimeMarker(
          label: 'fake-start',
          source: 'proof-clock',
          sequence: 1,
        ),
        DebugTimeMarker(
          label: 'after-debounce\x1b]52;c;secret-token\x07',
          source: 'proof-clock',
          elapsed: Duration(milliseconds: 250),
          sequence: 2,
        ),
      ],
      taskEvents: [
        DebugTaskEventSummary.fromTaskEvent(
          const TaskEvent<String>(
            sequence: 1,
            runId: 7,
            kind: TaskEventKind.progress,
            status: TaskStatus.running,
            progress: TaskProgress(
              current: 1,
              total: 4,
              label: 'scan\x1b]52;c;secret-token\x07',
            ),
          ),
          source: 'indexer',
        ),
        DebugTaskEventSummary.fromTaskEvent(
          const TaskEvent<String>(
            sequence: 2,
            runId: 7,
            kind: TaskEventKind.output,
            status: TaskStatus.running,
            output: TaskOutput(
              sequence: 1,
              text: 'secret-token',
              source: 'worker',
              severity: TaskOutputSeverity.warning,
              sanitized: true,
              truncated: true,
              originalLength: 128,
            ),
          ),
          source: 'indexer',
        ),
        DebugTaskEventSummary.fromTaskEvent(
          TaskEvent<String>(
            sequence: 3,
            runId: 7,
            kind: TaskEventKind.failed,
            status: TaskStatus.failed,
            error: StateError('secret-token failed'),
          ),
          source: 'indexer',
        ),
      ],
      semanticTree: const SemanticTree(
        root: SemanticNode(
          id: SemanticNodeId('root'),
          role: SemanticRole.app,
          children: [
            SemanticNode(
              id: SemanticNodeId('field:api-key'),
              role: SemanticRole.textField,
              label: 'API key',
              value: 'secret-token',
              focused: true,
              validationError: 'secret-token rejected',
              state: SemanticState({
                'redactedValue': true,
                'text': 'secret-token',
                'apiToken': 'secret-token',
                'clipboardRedacted': true,
                'historyCount': 2,
              }),
            ),
          ],
        ),
      ),
    );

    final json = snapshot.toJson();

    expect(json['schemaVersion'], 1);
    expect(json.toString(), isNot(contains('secret-token')));
    final inputs = json['inputs'] as List<Object?>;
    expect(inputs, hasLength(2));
    expect(inputs.last, containsPair('size', {'cols': 120, 'rows': 40}));
    final frames = json['frames'] as List<Object?>;
    expect(frames.single, containsPair('reason', 'key:enter'));
    final frame = frames.single as Map<String, Object?>;
    expect(frame['layoutStats'], containsPair('skippedCount', 3));
    expect(frame['repaintBoundaries'], containsPair('repaintedCount', 1));
    final outputs = json['outputSummaries'] as List<Object?>;
    expect(outputs.single, containsPair('sanitizedCount', 1));
    final timeMarkers = json['timeMarkers'] as List<Object?>;
    expect(timeMarkers, hasLength(2));
    final delayedMarker = timeMarkers.last as Map<String, Object?>;
    expect(delayedMarker['label'], contains(replacementCharacter));
    expect(delayedMarker['source'], 'proof-clock');
    expect(delayedMarker['elapsedMicros'], 250000);
    expect(delayedMarker['sequence'], 2);
    expect(delayedMarker['fakeTime'], isTrue);
    final taskEvents = json['taskEvents'] as List<Object?>;
    expect(taskEvents, hasLength(3));
    final progress = taskEvents.first as Map<String, Object?>;
    expect(progress['source'], 'indexer');
    expect(progress['kind'], 'progress');
    expect(progress['progressCurrent'], 1);
    expect(progress['progressTotal'], 4);
    expect(progress['progressLabel'], contains(replacementCharacter));
    final output = taskEvents[1] as Map<String, Object?>;
    expect(output['outputSource'], 'worker');
    expect(output['outputSeverity'], 'warning');
    expect(output['outputSanitized'], isTrue);
    expect(output['outputTruncated'], isTrue);
    expect(output['outputOriginalLength'], 128);
    final failure = taskEvents[2] as Map<String, Object?>;
    expect(failure['errorType'], 'StateError');
    expect(failure, isNot(containsPair('error', anything)));
    expect(output, isNot(containsPair('text', anything)));

    final semantics = json['semantics'] as Map<String, Object?>;
    expect(semantics['schemaVersion'], 1);
    expect(semantics['nodeCount'], 2);
    expect(semantics['focusedNodeId'], 'field:api-key');
    expect(semantics['roleCounts'], containsPair('app', 1));
    expect(semantics['roleCounts'], containsPair('textField', 1));
    expect(semantics['actionCount'], 0);
    final root = semantics['root'] as Map<String, Object?>;
    final children = root['children'] as List<Object?>;
    final field = children.single as Map<String, Object?>;
    expect(field['value'], '<redacted>');
    expect(field['validationError'], '<redacted>');
    final state = field['state'] as Map<String, Object?>;
    expect(state['text'], '<redacted>');
    expect(state['apiToken'], '<redacted>');
    expect(state['redactedValue'], isTrue);
    expect(state['historyCount'], 2);

    final accessibility = json['accessibility'] as Map<String, Object?>;
    expect(accessibility['nodeCount'], 2);
    final accessibilitySummary =
        accessibility['summary'] as Map<String, Object?>;
    expect(accessibilitySummary['nodeCount'], 2);
    expect(accessibilitySummary['focusedNodeId'], 'field:api-key');
    expect(accessibilitySummary['redactedValueCount'], 1);
    expect(accessibilitySummary['roleCounts'], containsPair('textField', 1));
    expect(accessibility['plainText'], isNot(contains('secret-token')));
    expect(accessibility['plainText'], contains('value redacted'));
    final accessibilityRoot = accessibility['root'] as Map<String, Object?>;
    final accessibilityChildren =
        accessibilityRoot['children'] as List<Object?>;
    final accessibilityField =
        accessibilityChildren.single as Map<String, Object?>;
    expect(accessibilityField['value'], isNull);
    expect(accessibilityField['validationError'], isNull);
    expect(
      accessibilityField['states'],
      containsAll(<String>['focused', 'value redacted']),
    );
  });

  test('capture snapshot can serialize an explicit accessibility snapshot', () {
    final semanticTree = const SemanticTree(
      root: SemanticNode(
        id: SemanticNodeId('root'),
        role: SemanticRole.app,
        children: [
          SemanticNode(
            id: SemanticNodeId('field:project'),
            role: SemanticRole.formField,
            label: 'Project',
            value: 'dune',
            selected: true,
            state: SemanticState({
              'required': true,
              'activePrompt': true,
              'promptPosition': 1,
              'promptCount': 2,
            }),
          ),
        ],
      ),
    );
    final snapshot = DebugCaptureSnapshot(
      accessibilitySnapshot: semanticTree.toAccessibilitySnapshot(),
    );

    final json = snapshot.toJson();

    expect(json, isNot(containsPair('semantics', anything)));
    final accessibility = json['accessibility'] as Map<String, Object?>;
    final summary = accessibility['summary'] as Map<String, Object?>;
    expect(summary['selectedCount'], 1);
    expect(summary['roleCounts'], containsPair('formField', 1));
    expect(accessibility['plainText'], contains('Project'));
    expect(accessibility['plainText'], contains('active prompt'));
    expect(accessibility['plainText'], contains('prompt 1 of 2'));
  });

  test('capture artifact indexes snapshot facts for regression assertions', () {
    final artifact = DebugCaptureArtifact.fromSnapshot(
      DebugCaptureSnapshot(
        frames: [
          FrameEvent(
            frameNumber: 1,
            reason: 'key:enter',
            build: const Duration(microseconds: 10),
            layout: const Duration(microseconds: 20),
            paint: const Duration(microseconds: 30),
            diff: const Duration(microseconds: 40),
            dirtyCells: 2,
            dirtyBounds: CellRect.fromLTWH(1, 2, 3, 4),
            dirtySources: const ['paint:RenderDataTable'],
            bufferSize: const CellSize(80, 24),
          ),
        ],
        inputs: const [
          InputDebugEvent(kind: 'command', summary: 'runs.focusTable'),
          InputDebugEvent(kind: 'key', summary: 'enter'),
        ],
        outputSummaries: const [
          DebugOutputSummary(source: 'task', lineCount: 3, sanitizedCount: 1),
        ],
        timeMarkers: const [
          DebugTimeMarker(
            label: 'after-search',
            source: 'proof-clock',
            elapsed: Duration(milliseconds: 250),
            sequence: 2,
          ),
        ],
        taskEvents: [
          DebugTaskEventSummary.fromTaskEvent(
            const TaskEvent<void>(
              sequence: 1,
              runId: 1,
              kind: TaskEventKind.started,
              status: TaskStatus.running,
            ),
            source: 'global-search',
          ),
          DebugTaskEventSummary.fromTaskEvent(
            const TaskEvent<void>(
              sequence: 2,
              runId: 1,
              kind: TaskEventKind.succeeded,
              status: TaskStatus.succeeded,
            ),
            source: 'global-search',
          ),
        ],
        semanticTree: const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            label: 'App',
            children: [
              SemanticNode(
                id: SemanticNodeId('table:runs'),
                role: SemanticRole.table,
                label: 'Runs',
                focused: true,
                selected: true,
                actions: {SemanticAction.copy},
                state: SemanticState({
                  'selectedKey': 'RUN-1002',
                  'collectionRowCount': 4,
                }),
              ),
            ],
          ),
        ),
      ),
    );

    expect(artifact.schemaVersion, 1);
    expect(
      artifact.hasInput(kind: 'command', summary: 'runs.focusTable'),
      true,
    );
    expect(artifact.hasInput(kind: 'key', summary: 'enter'), true);
    expect(
      artifact.hasFrame(
        reason: 'key:enter',
        dirtySource: 'paint:RenderDataTable',
      ),
      true,
    );
    expect(
      artifact.outputSummariesFor(source: 'task').single,
      containsPair('sanitizedCount', 1),
    );
    expect(
      artifact.hasTaskEvent(
        source: 'global-search',
        kind: 'started',
        status: 'running',
      ),
      isTrue,
    );
    expect(
      artifact.taskEventsFor(source: 'global-search').map((event) {
        return event['kind'];
      }),
      ['started', 'succeeded'],
    );
    expect(
      artifact.hasTimeMarker(source: 'proof-clock', label: 'after-search'),
      isTrue,
    );
    expect(
      artifact.timeMarkersFor(source: 'proof-clock').single,
      containsPair('elapsedMicros', 250000),
    );
    expect(artifact.semanticNodeCount, 2);
    expect(artifact.semanticRoleCount('table'), 1);
    expect(artifact.semanticRoleCount('button'), 0);
    expect(artifact.semanticActionCount, 1);
    final inspection = artifact.semanticInspectionSnapshot;
    expect(inspection, isNotNull);
    expect(inspection!.schemaVersion, 1);
    expect(inspection.single(role: 'table', action: 'copy').id, 'table:runs');
    expect(artifact.accessibilityPlainText, contains('Runs'));
    expect(artifact.accessibilityNodeCount, 2);
    expect(artifact.focusedAccessibilityNodeId, 'table:runs');
    expect(artifact.accessibilityRoleCount('table'), 1);
    expect(artifact.accessibilityRoleCount('button'), 0);
    expect(artifact.accessibilityActionCount, 1);
    expect(artifact.accessibilityRedactedValueCount, 0);

    final table = artifact.singleSemanticNode(
      role: 'table',
      label: 'Runs',
      focused: true,
      selected: true,
      action: 'copy',
      stateContains: const {'selectedKey': 'RUN-1002', 'collectionRowCount': 4},
    );
    expect(table.id, 'table:runs');
    expect(table.enabled, isTrue);
    expect(table.state['selectedKey'], 'RUN-1002');
  });

  test('capture recorder stores bounded safe task event summaries', () {
    final recorder = DebugCaptureRecorder(maxTaskEvents: 2);

    recorder.recordTaskEvents('worker', const [
      TaskEvent<void>(
        sequence: 1,
        runId: 1,
        kind: TaskEventKind.started,
        status: TaskStatus.running,
      ),
      TaskEvent<void>(
        sequence: 2,
        runId: 1,
        kind: TaskEventKind.output,
        status: TaskStatus.running,
        output: TaskOutput(sequence: 1, text: 'secret-token', sanitized: true),
      ),
      TaskEvent<void>(
        sequence: 3,
        runId: 1,
        kind: TaskEventKind.succeeded,
        status: TaskStatus.succeeded,
      ),
    ]);

    final artifact = DebugCaptureArtifact.fromSnapshot(recorder.snapshot());

    expect(artifact.taskEvents.map((event) => event['sequence']), [2, 3]);
    expect(artifact.json.toString(), isNot(contains('secret-token')));
    expect(artifact.hasTaskEvent(source: 'worker', kind: 'output'), isTrue);
    expect(artifact.hasTaskEvent(source: 'worker', kind: 'started'), isFalse);
  });

  test('capture recorder stores bounded deterministic time markers', () {
    final clock = FakeClock();
    final recorder = DebugCaptureRecorder(maxTimeMarkers: 2);

    recorder.recordTimeMarker(
      DebugTimeMarker.fromClock(
        label: 'start',
        source: 'proof-clock',
        clock: clock,
        sequence: 1,
      ),
    );
    clock.advance(const Duration(milliseconds: 100));
    recorder.recordTimeMarker(
      DebugTimeMarker.fromClock(
        label: 'after-input',
        source: 'proof-clock',
        clock: clock,
        sequence: 2,
      ),
    );
    clock.advance(const Duration(milliseconds: 150));
    recorder.recordTimeMarker(
      DebugTimeMarker.fromClock(
        label: 'after-worker',
        source: 'proof-clock',
        clock: clock,
        sequence: 3,
      ),
    );

    final artifact = DebugCaptureArtifact.fromSnapshot(recorder.snapshot());

    expect(artifact.timeMarkers.map((marker) => marker['label']), [
      'after-input',
      'after-worker',
    ]);
    expect(artifact.timeMarkers.map((marker) => marker['elapsedMicros']), [
      100000,
      250000,
    ]);
    expect(
      artifact.hasTimeMarker(source: 'proof-clock', label: 'start'),
      isFalse,
    );
    expect(
      artifact.hasTimeMarker(
        source: 'proof-clock',
        label: 'after-worker',
        fakeTime: true,
      ),
      isTrue,
    );
  });

  test(
    'capture recorder disposal is idempotent and keeps snapshots readable',
    () async {
      final recorder = DebugCaptureRecorder()
        ..record(const InputDebugEvent(kind: 'key', summary: 'enter'))
        ..recordOutputSummary(
          const DebugOutputSummary(source: 'task', lineCount: 2),
        )
        ..recordTimeMarker(const DebugTimeMarker(label: 'before-dispose'));

      await recorder.dispose();
      await recorder.dispose();

      final snapshot = recorder.snapshot();
      expect(snapshot.inputs, hasLength(1));
      expect(snapshot.outputSummaries.single.lineCount, 2);
      expect(snapshot.timeMarkers.single.label, 'before-dispose');
    },
  );

  test('capture recorder rejects post-dispose capture mutation', () async {
    final recorder = DebugCaptureRecorder()
      ..record(const InputDebugEvent(kind: 'key', summary: 'enter'));
    await recorder.dispose();

    const message = 'DebugCaptureRecorder has been disposed.';
    expect(() => recorder.attach(), throwsA(_stateError(message)));
    expect(
      () => recorder.record(const InputDebugEvent(kind: 'key', summary: 'tab')),
      throwsA(_stateError(message)),
    );
    expect(
      () => recorder.recordOutputSummary(
        const DebugOutputSummary(source: 'task', lineCount: 1),
      ),
      throwsA(_stateError(message)),
    );
    expect(
      () => recorder.recordTaskEvent(
        'worker',
        const TaskEvent<void>(
          sequence: 1,
          runId: 1,
          kind: TaskEventKind.started,
          status: TaskStatus.running,
        ),
      ),
      throwsA(_stateError(message)),
    );
    expect(
      () => recorder.recordTaskEvents('worker', const <TaskEvent<void>>[]),
      throwsA(_stateError(message)),
    );
    expect(
      () => recorder.recordTimeMarker(const DebugTimeMarker(label: 'late')),
      throwsA(_stateError(message)),
    );

    expect(recorder.snapshot().inputs.single.summary, 'enter');
  });
}

Matcher _stateError(String message) =>
    isA<StateError>().having((error) => error.message, 'message', message);
