import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<TraceTimelineEntry> _events() => [
  TraceTimelineEntry(
    id: 'trace.boot',
    label: 'Boot demo console',
    detail: 'App shell mounted',
    kind: TraceTimelineKind.app,
    status: TraceTimelineStatus.succeeded,
    source: 'app',
    timestamp: DateTime.utc(2026, 6, 1, 12),
    duration: const Duration(milliseconds: 12),
  ),
  const TraceTimelineEntry(
    id: 'trace.worker',
    label: 'Run fake worker',
    detail: 'Worker is active',
    kind: TraceTimelineKind.task,
    status: TraceTimelineStatus.running,
    source: 'fake-task',
    duration: Duration(milliseconds: 80),
  ),
  const TraceTimelineEntry(
    id: 'trace.diagnostics',
    label: 'Capture diagnostics',
    detail: 'Terminal fallback review',
    kind: TraceTimelineKind.diagnostic,
    status: TraceTimelineStatus.warning,
    source: 'diagnostics',
  ),
];

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('TraceTimeline', () {
    group('controller lifecycle', () {
      test('dispose is idempotent and keeps final readable state', () {
        final controller = TraceTimelineController(selectedIndex: 2);

        controller.dispose();
        controller.dispose();

        expect(controller.selectedIndex, 2);
        expect(controller.visibleRange, isNull);
      });

      test('mutating after dispose throws a lifecycle error', () {
        final controller = TraceTimelineController()..dispose();

        const message = 'TraceTimelineController has been disposed.';
        expect(() => controller.selectedIndex = 1, _stateError(message));
        expect(() => controller.jumpToIndex(1), _stateError(message));
      });
    });

    test(
      'exportTraceTimelineEntry sanitizes controls and respects options',
      () {
        final text = exportTraceTimelineEntry(
          const TraceTimelineEntry(
            id: 'unsafe',
            label: 'bad\x1b]52;c;secret\x07',
            detail: 'two\nlines',
            kind: TraceTimelineKind.process,
            status: TraceTimelineStatus.failed,
            source: 'runner',
            duration: Duration(milliseconds: 42),
          ),
        );

        expect(
          text,
          'bad$replacementCharacter | process | failed | 42ms | runner | '
          'two lines',
        );
        expect(text, isNot(contains('secret')));
        expect(text, isNot(contains('\x1b]52')));

        expect(
          exportTraceTimelineEntry(
            _events().first,
            options: const TraceTimelineCopyOptions(
              includeDetail: false,
              includeSource: false,
              includeTimestamp: false,
            ),
          ),
          'Boot demo console | app | succeeded | 12ms',
        );
      },
    );

    testWidgets('showTimestamp prefixes rows with the event clock', (tester) {
      tester.pumpWidget(
        TraceTimeline(
          label: 'Demo trace',
          events: _events(),
          showTimestamp: true,
        ),
      );
      final out = tester.renderToString(
        size: const CellSize(90, 5),
        emptyMark: ' ',
      );
      // First event's timestamp is 12:00:00 UTC; the third has none, so it
      // gets no clock prefix.
      expect(out, contains('12:00:00 [x] Boot demo console'));
      expect(out, contains('[*] Capture diagnostics'));
      expect(out, isNot(contains('00:00:00 [*]')));
    });

    testWidgets('renders a connecting timeline rail (first/middle/last)', (
      tester,
    ) {
      tester.pumpWidget(TraceTimeline(label: 'Demo trace', events: _events()));
      final out = tester.renderToString(
        size: const CellSize(90, 5),
        emptyMark: ' ',
      );
      // The rail glyphs share a leading column and sit just before each status
      // marker, so the events read as one connected sequence rather than a flat
      // list: ╭ (first) → ├ (middle) → ╰ (last).
      expect(out, contains('╭ [x] Boot demo console'));
      expect(out, contains('├ [>] Run fake worker'));
      expect(out, contains('╰ [*] Capture diagnostics'));
    });

    testWidgets('a lone trace event uses a rail stub, not a connector', (
      tester,
    ) {
      tester.pumpWidget(
        TraceTimeline(label: 'Demo trace', events: [_events().first]),
      );
      final out = tester.renderToString(
        size: const CellSize(90, 3),
        emptyMark: ' ',
      );
      expect(out, contains('─ [x] Boot demo console'));
      expect(out, isNot(contains('╭')));
    });

    testWidgets('selects and exposes trace semantics', (tester) async {
      TraceTimelineSelectResult? selected;
      tester.pumpWidget(
        TraceTimeline(
          label: 'Demo trace',
          events: _events(),
          autofocus: true,
          onSelect: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(90, 5));
      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(selected?.event.id, 'trace.boot');
      expect(selected?.eventIndex, 0);

      final timeline = tester.semantics().single(
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
      );
      expect(timeline.state['traceEventCount'], 3);
      expect(timeline.state['runningTraceEventCount'], 1);
      expect(timeline.state['warningTraceEventCount'], 1);
      expect(timeline.state.selectedTraceId, 'trace.boot');

      final event = tester.semantics().single(
        role: SemanticRole.traceEvent,
        label: 'Run fake worker',
      );
      expect(event.busy, isTrue);
      expect(event.actions, contains(SemanticAction.activate));
      expect(event.state.traceId, 'trace.worker');
      expect(event.state.traceKind, 'task');
      expect(event.state.traceStatus, 'running');
      expect(event.state.traceDurationMs, 80);
      expect(event.state.source, 'fake-task');

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.traceEvent,
        label: 'Run fake worker',
      );
      expect(
        fallback.states,
        contains(
          'trace id trace.worker, kind task, status running, 80ms, '
          'source fake-task',
        ),
      );
    });

    testWidgets('semantic focus and activation focus the timeline', (
      tester,
    ) async {
      final controller = TraceTimelineController();
      TraceTimelineSelectResult? selected;
      tester.pumpWidget(
        TraceTimeline(
          label: 'Demo trace',
          events: _events(),
          controller: controller,
          onSelect: (result) => selected = result,
        ),
      );

      tester.render(size: const CellSize(90, 5));
      var timeline = tester.semantics().single(
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
        action: SemanticAction.focus,
      );
      expect(timeline.focused, isFalse);
      expect(timeline.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(90, 5));
      timeline = tester.semantics().single(
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
        focused: true,
      );
      expect(timeline.state.selectedTraceId, 'trace.boot');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.traceEvent,
        label: 'Capture diagnostics',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 2);
      expect(selected?.event.id, 'trace.diagnostics');

      tester.render(size: const CellSize(90, 5));
      final event = tester.semantics().single(
        role: SemanticRole.traceEvent,
        label: 'Capture diagnostics',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(event.state.traceId, 'trace.diagnostics');

      timeline = tester.semantics().single(
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
        focused: true,
      );
      expect(timeline.state.selectedTraceId, 'trace.diagnostics');
      expect(timeline.state['selectedIndex'], 2);
    });

    testWidgets('preserves selected trace identity across event refresh', (
      tester,
    ) {
      final controller = TraceTimelineController(selectedIndex: 2);
      tester.pumpWidget(
        TraceTimeline(
          label: 'Demo trace',
          events: _events(),
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 5));

      tester.pumpWidget(
        TraceTimeline(
          label: 'Demo trace',
          events: [
            _events()[0],
            const TraceTimelineEntry(
              id: 'trace.inserted',
              label: 'Inserted event',
              kind: TraceTimelineKind.debug,
            ),
            _events()[1],
            const TraceTimelineEntry(
              id: 'trace.diagnostics',
              label: 'Capture diagnostics',
              detail: 'Updated detail',
              kind: TraceTimelineKind.diagnostic,
              status: TraceTimelineStatus.succeeded,
              source: 'diagnostics',
            ),
          ],
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 6));
      tester.pump();
      tester.render(size: const CellSize(90, 6));

      expect(controller.selectedIndex, 3);
      final timeline = tester.semantics().single(
        role: SemanticRole.traceTimeline,
        label: 'Demo trace',
      );
      expect(timeline.state.selectedTraceId, 'trace.diagnostics');

      final selected = tester.semantics().single(
        role: SemanticRole.traceEvent,
        label: 'Capture diagnostics',
        selected: true,
      );
      expect(selected.state.traceStatus, 'succeeded');
      expect(selected.hint, 'Updated detail');
    });

    testWidgets('semantic copy copies the selected trace event', (
      tester,
    ) async {
      TraceTimelineCopyResult? copied;
      try {
        tester.pumpWidget(
          TraceTimeline(
            events: _events(),
            copyOptions: const TraceTimelineCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
              includeTimestamp: false,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        tester.render(size: const CellSize(90, 5));
        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.traceEvent,
          label: 'Boot demo console',
        );

        expect(result.completed, isTrue);
        expect(
          tester.clipboard.readInProcess(),
          'Boot demo console | app | succeeded | 12ms | app | '
          'App shell mounted',
        );
        expect(copied?.eventIndex, 0);
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        // clipboard is tester-scoped; nothing to restore
      }
    });
  });
}
