import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  List<SearchResult> results() => const [
    SearchResult(
      id: 'build.local',
      title: 'Build local package',
      subtitle: 'dart test packages/fleury',
      category: 'Task',
      source: 'workspace',
    ),
    SearchResult(
      id: 'deploy.prod',
      title: 'Deploy production',
      subtitle: 'Promote the latest release',
      category: 'Runbook',
      source: 'ops',
    ),
    SearchResult(
      id: 'logs.deploy',
      title: 'Open deploy logs',
      subtitle: 'Filtered failures',
      category: 'Logs',
      source: 'observability',
    ),
  ];

  test('buildSearchResultOrder ranks default matches by quality', () {
    const rankedResults = [
      SearchResult(id: 'logs.deploy', title: 'Open deploy logs'),
      SearchResult(id: 'screen.deploy', title: 'Deploy'),
      SearchResult(id: 'deploy.prod', title: 'Deploy production'),
      SearchResult(id: 'fuzzy', title: 'Do extra process logging over yonder'),
    ];

    expect(buildSearchResultOrder(rankedResults, query: 'deploy'), [
      1,
      2,
      0,
      3,
    ]);
  });

  test('SearchResultIndex searches sanitized metadata', () {
    final index = SearchResultIndex([
      const SearchResult(
        id: 'unsafe',
        title: 'bad\x1b]52;c;secret\x07',
        metadata: {'kind': 'audit trail'},
      ),
    ]);

    expect(index.length, 1);
    expect(index.order(query: 'audit'), [0]);
    expect(index.order(query: 'secret'), isEmpty);
  });

  test('custom matchers keep source-order filtering semantics', () {
    final order = buildSearchResultOrder(
      results(),
      query: 'deploy',
      matcher: (result, _) => result.category == 'Logs' || result.id == 'x',
    );

    expect(order, [2]);
  });

  testWidgets('filters results and activates the selected source result', (
    tester,
  ) async {
    SearchResult? activated;
    int? activatedIndex;
    tester.pumpWidget(
      SearchPanel(
        results: results(),
        autofocus: true,
        onActivate: (result, index) {
          activated = result;
          activatedIndex = index;
        },
      ),
    );

    tester.type('deploy');
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

    expect(activated?.id, 'deploy.prod');
    expect(activatedIndex, 1);
  });

  testWidgets('arrow navigation moves selection before activation', (
    tester,
  ) async {
    SearchResult? activated;
    tester.pumpWidget(
      SearchPanel(
        results: results(),
        autofocus: true,
        onActivate: (result, _) => activated = result,
      ),
    );

    tester.type('deploy');
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

    expect(activated?.id, 'logs.deploy');
  });

  group('copy/export', () {
    late Clipboard originalClipboard;
    late TestClipboard clipboard;

    setUp(() {
      originalClipboard = Clipboard.instance;
      clipboard = TestClipboard();
      Clipboard.instance = clipboard;
    });

    tearDown(() {
      Clipboard.instance = originalClipboard;
    });

    testWidgets('Ctrl+C copies selected result and reports source index', (
      tester,
    ) async {
      final query = TextEditingController(text: 'deploy');
      SearchPanelCopyResult? copied;
      tester.pumpWidget(
        SearchPanel(
          results: results(),
          queryController: query,
          autofocus: true,
          copyOptions: const SearchPanelCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 6));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(
        clipboard.lastWritten,
        'Deploy production | Promote the latest release | Runbook | ops',
      );
      expect(copied, isNotNull);
      expect(copied!.resultIndex, 1);
      expect(copied!.viewIndex, 0);
      expect(copied!.result.id, 'deploy.prod');
      expect(copied!.report.policy.name, 'inProcessOnly');
    });

    testWidgets('semantic copy copies selected result', (tester) async {
      final query = TextEditingController(text: 'deploy');
      SearchPanelCopyResult? copied;
      tester.pumpWidget(
        SearchPanel(
          results: results(),
          queryController: query,
          copyOptions: const SearchPanelCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 6));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.listItem,
        label: 'Deploy production',
      );

      expect(result.completed, isTrue);
      expect(
        clipboard.lastWritten,
        'Deploy production | Promote the latest release | Runbook | ops',
      );
      expect(copied?.resultIndex, 1);
      expect(copied?.viewIndex, 0);
    });

    test('exportSearchResult sanitizes terminal controls and line breaks', () {
      final text = exportSearchResult(
        const SearchResult(
          title: 'bad\x1b]52;c;secret\x07',
          subtitle: 'two\nlines',
          detail: 'tail\tvalue',
        ),
      );

      expect(text, isNot(contains('\x1b]52')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\n')));
      expect(text, contains(replacementCharacter));
      expect(text, contains('two lines'));
      expect(text, contains('tail value'));
    });
  });

  testWidgets('exposes filtered result semantics with source indexes', (
    tester,
  ) {
    final query = TextEditingController(text: 'deploy');
    tester.pumpWidget(
      SearchPanel(
        label: 'Global search',
        results: results(),
        queryController: query,
        autofocus: true,
        onActivate: (_, _) {},
        copyOptions: const SearchPanelCopyOptions(
          clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
        ),
      ),
    );

    tester.render(size: const CellSize(80, 6));

    final tree = tester.semantics();
    final panel = tree.single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    expect(panel.value, 'deploy');
    expect(panel.actions, contains(SemanticAction.submit));
    expect(panel.actions, contains(SemanticAction.copy));
    expect(panel.state.filterText, 'deploy');
    expect(panel.state.collectionRowCount, 2);
    expect(panel.state['totalResultCount'], 3);
    expect(panel.state['filteredResultCount'], 2);
    expect(panel.state.selectedKey, 'deploy.prod');
    expect(panel.state.clipboardPolicy, 'inProcessOnly');

    final fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.region,
      label: 'Global search',
    );
    expect(
      fallback.states,
      contains(
        'search 3 results, 2 filtered, selected index 0, '
        'selected category Runbook, selected source ops',
      ),
    );

    final row = tree
        .byRole(SemanticRole.listItem)
        .singleWhere((node) => node.state['rowKey'] == 'deploy.prod');
    expect(row.label, 'Deploy production');
    expect(row.selected, isTrue);
    expect(row.actions, contains(SemanticAction.activate));
    expect(row.actions, contains(SemanticAction.copy));
    expect(row.state['rowIndex'], 1);
    expect(row.state['viewIndex'], 0);
    expect(row.state['resultCategory'], 'Runbook');
    expect(row.state['resultSource'], 'ops');

    final rowFallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.listItem,
      label: 'Deploy production',
    );
    expect(
      rowFallback.states,
      contains('row 1, view row 0, row key deploy.prod'),
    );
    expect(rowFallback.states, contains('search category Runbook, source ops'));
  });

  testWidgets('semantic focus and row activation drive SearchPanel', (
    tester,
  ) async {
    final query = TextEditingController(text: 'deploy');
    SearchResult? activated;
    tester.pumpWidget(
      SearchPanel(
        results: results(),
        queryController: query,
        onActivate: (result, _) => activated = result,
      ),
    );

    tester.render(size: const CellSize(80, 6));
    var result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.region,
      label: 'Search',
    );
    expect(result.status, SemanticActionInvocationStatus.completed);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.region, label: 'Search')
          .focused,
      isTrue,
    );
    tester.render(size: const CellSize(80, 6));

    result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.listItem,
      label: 'Deploy production',
    );

    expect(result.status, SemanticActionInvocationStatus.completed);
    expect(activated?.id, 'deploy.prod');
  });

  testWidgets('sanitizes rendered rows and searchable text', (tester) {
    final unsafe = const SearchResult(
      id: 'unsafe',
      title: 'bad\x1b]52;c;secret\x07',
      subtitle: 'line\nbreak',
    );

    expect(buildSearchResultOrder([unsafe], query: 'secret'), isEmpty);

    tester.pumpWidget(SearchPanel(results: [unsafe]));
    final output = tester.renderToString(
      size: const CellSize(60, 4),
      emptyMark: ' ',
    );

    expect(output, contains('bad'));
    expect(output, contains('line break'));
    expect(output, contains(replacementCharacter));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('\x1b]52')));

    final row = tester.semantics().single(role: SemanticRole.listItem);
    expect(row.state.outputSanitized, isTrue);
  });

  testWidgets('shows empty state when no results match', (tester) {
    tester.pumpWidget(SearchPanel(results: results(), autofocus: true));

    tester.type('zzzz');
    tester.pump();

    expect(tester.exists(text('No matching results')), isTrue);
    final panel = tester.semantics().single(role: SemanticRole.region);
    expect(panel.state.collectionRowCount, 0);
    expect(panel.state['selectedIndex'], isNull);
  });
}
