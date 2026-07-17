import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('LogRegionController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = LogRegionController(
        selectedIndex: 2,
        followTail: false,
      );

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.followTail, isFalse);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = LogRegionController(followTail: true)..dispose();

      const message = 'LogRegionController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.followTail = false, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
      expect(() => controller.scrollToBottom(), _stateError(message));
    });
  });

  testWidgets('renders visible entries with sanitized semantic state', (
    tester,
  ) {
    final controller = LogRegionController(followTail: false);
    tester.pumpWidget(
      LogRegion(
        controller: controller,
        entries: const [
          LogEntry(
            id: 'a',
            severity: LogSeverity.info,
            source: 'system',
            message: 'booted',
          ),
          LogEntry(
            id: 'b',
            severity: LogSeverity.error,
            source: 'worker',
            message: 'bad\x1b]52;c;secret\x07\nline',
          ),
        ],
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(60, 4),
      emptyMark: ' ',
    );

    expect(output, contains('[INFO system] booted'));
    expect(output, contains('[ERROR worker] bad'));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('\x1b]52')));

    final tree = tester.semantics();
    final log = tree.single(role: SemanticRole.log);
    expect(log.state.collectionRowCount, 2);
    expect(log.state['followTail'], isFalse);
    expect(log.state['copyEnabled'], isTrue);

    final row = tree
        .byRole(SemanticRole.listItem)
        .singleWhere((node) => node.state['rowKey'] == 'b');
    expect(row.label, contains(replacementCharacter));
    expect(row.label, contains('line'));
    expect(row.selected, isFalse);
    expect(row.state['rowKey'], 'b');
    expect(row.state['severity'], 'error');
    expect(row.state.source, 'worker');
    expect(row.state.outputSanitized, isTrue);
  });

  testWidgets('semantic focus focuses the log region', (tester) async {
    final controller = LogRegionController(followTail: false);
    tester.pumpWidget(
      LogRegion(
        semanticLabel: 'Runtime logs',
        controller: controller,
        entries: const [
          LogEntry(id: 'boot', message: 'booted'),
          LogEntry(id: 'ready', message: 'ready'),
        ],
      ),
    );

    tester.render(size: const CellSize(60, 4));
    var log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Runtime logs',
      action: SemanticAction.focus,
    );
    expect(log.focused, isFalse);
    expect(log.actions, contains(SemanticAction.navigate));

    final result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.log,
      label: 'Runtime logs',
    );

    expect(result.completed, isTrue);
    tester.render(size: const CellSize(60, 4));
    log = tester.semantics().single(
      role: SemanticRole.log,
      label: 'Runtime logs',
      focused: true,
    );
    expect(log.state.selectedKey, 'boot');
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected log entry', (tester) async {
      final controller = LogRegionController(
        selectedIndex: 1,
        followTail: false,
      );
      LogRegionCopyResult? copied;
      tester.pumpWidget(
        LogRegion(
          controller: controller,
          autofocus: true,
          entries: const [
            LogEntry(
              severity: LogSeverity.info,
              source: 'system',
              message: 'a',
            ),
            LogEntry(
              id: 'run-2',
              severity: LogSeverity.warning,
              source: 'worker',
              message: 'needs attention',
            ),
          ],
          copyOptions: const LogRegionCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 4));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '[WARN worker] needs attention');
      expect(copied, isNotNull);
      expect(copied!.entryIndex, 1);
      expect(copied!.viewIndex, 1);
      expect(copied!.entry.id, 'run-2');
      expect(copied!.report.policy.name, 'inProcessOnly');

      final selected = tester.semantics().single(
        role: SemanticRole.listItem,
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selected.state['rowKey'], 'run-2');
    });

    testWidgets('semantic copy copies the selected log entry', (tester) async {
      final controller = LogRegionController(
        selectedIndex: 1,
        followTail: false,
      );
      LogRegionCopyResult? copied;
      tester.pumpWidget(
        LogRegion(
          controller: controller,
          entries: const [
            LogEntry(message: 'alpha'),
            LogEntry(
              id: 'run-2',
              severity: LogSeverity.warning,
              source: 'worker',
              message: 'needs attention',
            ),
          ],
          copyOptions: const LogRegionCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(60, 4));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.listItem,
        selected: true,
      );

      expect(result.completed, isTrue);
      expect(tester.clipboard.readInProcess(), '[WARN worker] needs attention');
      expect(copied?.entryIndex, 1);
      expect(copied?.viewIndex, 1);
    });

    testWidgets('semantic activate selects a visible log entry', (
      tester,
    ) async {
      final controller = LogRegionController(followTail: true);
      tester.pumpWidget(
        LogRegion(
          controller: controller,
          entries: const [
            LogEntry(id: 'first', message: 'first row'),
            LogEntry(id: 'middle', message: 'middle row'),
            LogEntry(id: 'last', message: 'last row'),
          ],
          copyOptions: const LogRegionCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      tester.render(size: const CellSize(60, 5));
      var row = tester.semantics().single(
        role: SemanticRole.listItem,
        label: 'middle row',
        action: SemanticAction.activate,
      );
      expect(row.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.listItem,
        label: 'middle row',
      );

      expect(result.completed, isTrue);
      expect(controller.followTail, isFalse);
      expect(controller.selectedIndex, 1);

      tester.render(size: const CellSize(60, 5));
      row = tester.semantics().single(
        role: SemanticRole.listItem,
        label: 'middle row',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state['rowKey'], 'middle');

      final log = tester.semantics().single(role: SemanticRole.log);
      expect(log.state.selectedKey, 'middle');
      expect(log.state['selectedIndex'], 1);
      expect(log.state['followTail'], isFalse);
      expect(log.focused, isTrue);
    });

    test('exportLogEntries sanitizes, truncates, and preserves order', () {
      final result = exportLogEntries(
        const [
          LogEntry(severity: LogSeverity.info, message: 'alpha'),
          LogEntry(
            severity: LogSeverity.error,
            source: 'task',
            message: 'abcdef\nx',
          ),
          LogEntry(severity: LogSeverity.debug, message: 'gamma'),
        ],
        options: const LogRegionExportOptions(
          startIndex: 1,
          maxEntries: 1,
          maxLineLength: 5,
        ),
      );

      expect(result.text, '[ERROR task] abcde');
      expect(result.entryCount, 1);
      expect(result.startIndex, 1);
      expect(result.truncated, isTrue);
    });

    testWidgets('filter narrows rows while copy returns source index', (
      tester,
    ) async {
      final controller = LogRegionController(
        selectedIndex: 0,
        followTail: false,
      );
      LogRegionCopyResult? copied;
      tester.pumpWidget(
        LogRegion(
          controller: controller,
          autofocus: true,
          filter: const LogRegionFilterDescriptor(
            query: 'deploy',
            severities: {LogSeverity.error},
          ),
          entries: const [
            LogEntry(
              id: 'a',
              severity: LogSeverity.info,
              source: 'worker',
              message: 'deploy started',
            ),
            LogEntry(
              id: 'b',
              severity: LogSeverity.error,
              source: 'build',
              message: 'compile failed',
            ),
            LogEntry(
              id: 'c',
              severity: LogSeverity.error,
              source: 'worker',
              message: 'deploy failed',
            ),
          ],
          copyOptions: const LogRegionCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(60, 4),
        emptyMark: ' ',
      );

      expect(output, contains('[ERROR worker] deploy failed'));
      expect(output, isNot(contains('deploy started')));
      expect(output, isNot(contains('compile failed')));

      final log = tester.semantics().single(role: SemanticRole.log);
      expect(log.state.collectionRowCount, 1);
      expect(log.state['totalEntryCount'], 3);
      expect(log.state['filteredEntryCount'], 1);
      expect(log.state.filterText, 'deploy');
      expect(log.state['filterActive'], isTrue);
      expect(log.state['filterSeverities'], 'error');

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.log,
      );
      expect(
        fallback.states,
        contains(
          'log 3 entries, 1 filtered, filter active, severities error, '
          'copy includes prefix, selected index 0, last c',
        ),
      );

      final row = tester.semantics().single(role: SemanticRole.listItem);
      expect(row.state['rowIndex'], 2);
      expect(row.state['viewIndex'], 0);
      expect(row.state['rowKey'], 'c');

      final rowFallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.listItem,
      );
      expect(rowFallback.states, contains('row 2, view row 0, row key c'));

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), '[ERROR worker] deploy failed');
      expect(copied, isNotNull);
      expect(copied!.entryIndex, 2);
      expect(copied!.viewIndex, 0);
    });

    test('filter and export operate on sanitized searchable text', () {
      final entries = const [
        LogEntry(
          id: 'unsafe',
          severity: LogSeverity.error,
          message: 'bad\x1b]52;c;secret\x07 payload',
        ),
        LogEntry(id: 'safe', message: 'visible deploy payload'),
      ];

      expect(
        buildLogRegionEntryOrder(
          entries,
          filter: const LogRegionFilterDescriptor(query: 'secret'),
        ),
        isEmpty,
      );

      final result = exportLogEntries(
        entries,
        filter: const LogRegionFilterDescriptor(query: 'deploy'),
      );

      expect(result.text, '[INFO] visible deploy payload');
      expect(result.entryCount, 1);
      expect(result.truncated, isFalse);
    });

    testWidgets(
      'search index accelerates filtered views and refreshes appends',
      (tester) {
        final controller = LogRegionController(followTail: false);
        final entries = <LogEntry>[
          const LogEntry(
            id: 'run-100',
            severity: LogSeverity.info,
            source: 'worker',
            message: 'deploy queued',
          ),
          const LogEntry(
            id: 'run-200',
            severity: LogSeverity.error,
            source: 'worker',
            message: 'bad\x1b]52;c;secret\x07 payload',
          ),
        ];
        final index = LogRegionSearchIndex(entries);

        tester.pumpWidget(
          LogRegion(
            controller: controller,
            entries: entries,
            searchIndex: index,
            filter: const LogRegionFilterDescriptor(query: 'run-2'),
          ),
        );
        tester.render(size: const CellSize(60, 4));

        var tree = tester.semantics();
        expect(tree.single(role: SemanticRole.log).state.collectionRowCount, 1);
        expect(
          tree.single(role: SemanticRole.listItem).state['rowKey'],
          'run-200',
        );

        entries.add(
          const LogEntry(
            id: 'run-201',
            severity: LogSeverity.success,
            source: 'worker',
            message: 'deploy finished',
          ),
        );
        index.refresh();
        tester.pumpWidget(
          LogRegion(
            controller: controller,
            entries: entries,
            searchIndex: index,
            filter: const LogRegionFilterDescriptor(query: 'run-20'),
          ),
        );
        tester.render(size: const CellSize(60, 4));

        tree = tester.semantics();
        expect(tree.single(role: SemanticRole.log).state.collectionRowCount, 2);
        expect(
          tree
              .byRole(SemanticRole.listItem)
              .map((node) => node.state['rowKey']),
          containsAll(['run-200', 'run-201']),
        );
      },
    );

    test('search index can build and refresh cooperatively', () async {
      final entries = <LogEntry>[
        const LogEntry(id: 'run-100', message: 'queued'),
        const LogEntry(id: 'run-200', message: 'deploy failed'),
        const LogEntry(id: 'run-300', message: 'deploy passed'),
      ];
      final controller = TaskController<LogRegionSearchIndex>(id: 'log-index');

      final result = await controller.start(
        (context) => LogRegionSearchIndex.buildCooperatively(
          entries,
          context: context,
          yieldPolicy: const TaskYieldPolicy(
            itemBudget: 1,
            elapsedBudget: Duration(days: 1),
          ),
          progressLabel: 'index logs',
        ),
      );

      expect(result.succeeded, isTrue);
      final index = result.value!;
      expect(index.length, 3);
      expect(controller.progress?.label, 'index logs complete');
      expect(
        controller.events.where(
          (event) => event.kind == TaskEventKind.progress,
        ),
        hasLength(greaterThanOrEqualTo(3)),
      );
      expect(
        index.entryOrder(const LogRegionFilterDescriptor(query: 'run-2')),
        [1],
      );

      entries.add(const LogEntry(id: 'run-201', message: 'deploy retried'));
      final refresh = await controller.start((context) async {
        await index.refreshCooperatively(
          context: context,
          yieldPolicy: const TaskYieldPolicy(
            itemBudget: 1,
            elapsedBudget: Duration(days: 1),
          ),
          progressLabel: 'refresh logs',
        );
        return index;
      });

      expect(refresh.succeeded, isTrue);
      expect(index.length, 4);
      expect(controller.progress?.label, 'refresh logs complete');
      expect(
        index.entryOrder(const LogRegionFilterDescriptor(query: 'run-20')),
        [1, 3],
      );

      controller.dispose();
    });
  });

  testWidgets('followTail advances selection when entries append', (tester) {
    final controller = LogRegionController(followTail: true);
    tester.pumpWidget(
      LogRegion(
        controller: controller,
        entries: const [
          LogEntry(message: 'one'),
          LogEntry(message: 'two'),
        ],
      ),
    );
    tester.render(size: const CellSize(40, 3));

    expect(controller.selectedIndex, 1);

    tester.pumpWidget(
      LogRegion(
        controller: controller,
        entries: const [
          LogEntry(message: 'one'),
          LogEntry(message: 'two'),
          LogEntry(message: 'three'),
        ],
      ),
    );
    tester.render(size: const CellSize(40, 3));

    expect(controller.selectedIndex, 2);
    expect(
      tester.semantics().single(role: SemanticRole.log).state['selectedIndex'],
      2,
    );
  });
}
