import 'package:fleury/fleury.dart';
import 'package:fleury_samples/src/finance.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('finance ledger', () {
    late FinanceLedger ledger;

    setUp(() => ledger = FinanceLedger.sample());

    test('uses exact integer-cents math for balances and July cash flow', () {
      expect(ledger.netWorthCents, 6493982);
      expect(ledger.liquidCents, 2334143);
      expect(ledger.debtCents, 124673);
      expect(ledger.investmentCents, 4284512);

      final july = ledger.cashFlowForMonth(2026, 7);
      expect(july.inflowCents, 675000);
      expect(july.outflowCents, 377475);
      expect(july.netCents, 297525);
      expect(
        ledger.categorySpendForMonth(2026, 7)[FinanceCategory.groceries],
        55012,
      );
    });

    test('filters and sorts while resolving selection by stable row ID', () {
      const selectedId = 'tx-jul-whole-foods';
      final amountSorted = ledger.queryTransactions(
        sort: FinanceTransactionSort.amountHigh,
      );
      expect(
        ledger.resolveSelectionId(amountSorted, selectedId),
        selectedId,
        reason: 'sorting must not turn selection into a positional identity',
      );

      final netflix = ledger.queryTransactions(
        query: 'netflix',
        sort: FinanceTransactionSort.newest,
      );
      expect(netflix, hasLength(7));
      expect(netflix.every((row) => row.merchant == 'Netflix'), isTrue);
      expect(
        ledger.resolveSelectionId(netflix, selectedId),
        '2026-07-netflix',
        reason: 'an excluded selection falls back deterministically',
      );

      final groceries = ledger.queryTransactions(
        category: FinanceCategory.groceries,
        accountId: 'amex-cobalt',
        sort: FinanceTransactionSort.merchantAscending,
      );
      expect(
        groceries.every(
          (row) =>
              row.category == FinanceCategory.groceries &&
              row.accountId == 'amex-cobalt',
        ),
        isTrue,
      );
      expect(
        groceries.map((row) => row.merchant),
        orderedEquals(
          <String>[for (final row in groceries) row.merchant]..sort(),
        ),
      );

      final categoryDescending = ledger.queryTransactions(
        sort: FinanceTransactionSort.categoryDescending,
      );
      expect(
        categoryDescending.map((row) => row.category.label),
        orderedEquals(
          <String>[for (final row in categoryDescending) row.category.label]
            ..sort((a, b) => b.compareTo(a)),
        ),
      );

      final accountDescending = ledger.queryTransactions(
        sort: FinanceTransactionSort.accountDescending,
      );
      expect(
        accountDescending.map(
          (row) => ledger.accountById(row.accountId).institution,
        ),
        orderedEquals(
          <String>[
            for (final row in accountDescending)
              ledger.accountById(row.accountId).institution,
          ]..sort((a, b) => b.compareTo(a)),
        ),
      );
    });

    test('stress fixture is large, unique, and reproducible', () {
      final first = ledger.stressTransactions();
      final second = ledger.stressTransactions();

      expect(first, hasLength(2500));
      expect(first.map((row) => row.id).toSet(), hasLength(2500));
      expect(first.first.id, 'stress-00000');
      expect(first.last.id, 'stress-02499');
      expect(first.first.merchant, second.first.merchant);
      expect(first[173].date, second[173].date);
      expect(first[173].amountCents, second[173].amountCents);

      final filtered = ledger.queryTransactions(
        source: first,
        query: 'Costco',
        sort: FinanceTransactionSort.amountLow,
      );
      expect(filtered, isNotEmpty);
      expect(
        filtered.every((row) => row.merchant == 'Costco Wholesale'),
        isTrue,
      );
      for (var index = 1; index < filtered.length; index++) {
        expect(
          filtered[index - 1].amountCents <= filtered[index].amountCents,
          isTrue,
        );
      }
    });

    test('currency and date formatting are locale-independent', () {
      expect(formatFinanceCents(482143), r'$4,821.43');
      expect(formatFinanceCents(-124673), r'-$1,246.73');
      expect(formatFinanceCents(-50000), r'-$500.00');
      expect(formatFinanceCents(-12847), r'-$128.47');
      expect(formatFinanceCents(675000, showPlus: true), r'+$6,750.00');
      expect(formatFinanceDate(DateTime(2026, 7, 9)), '2026-07-09');
    });
  });

  group('finance showcase', () {
    const wide = CellSize(132, 48);
    const narrow = CellSize(72, 56);

    testWidgets('renders the full overview and virtualized ledger when wide', (
      tester,
    ) {
      tester.pumpWidget(const FinanceApp());
      final output = tester.renderToString(size: wide);

      expect(output, contains('Fleury Finance'));
      expect(output, contains('deterministic sample data · local only'));
      expect(output, contains('Net worth'));
      expect(output, contains(r'$64,939.82'));
      expect(output, contains('Monthly cash flow'));
      expect(output, contains('July spending'));
      expect(output, contains('Accounts'));
      expect(output, contains('Transactions'));
      expect(output, contains('Amazon.ca'));
      expect(output, contains('MERCHANT'));

      final table = tester.semantics().single(
        role: SemanticRole.table,
        label: 'Finance transactions',
      );
      expect(table.state['collectionRowCount'], 73);
      final firstRow = tester.semantics().single(
        role: SemanticRole.tableRow,
        label: 'tx-jul-amazon',
      );
      expect(firstRow.id.value, contains('/table/row/tx-jul-amazon'));
      expect(firstRow.id.value, isNot(contains('/row/~')));
    });

    testWidgets('adapts the overview, charts, table, and detail when narrow', (
      tester,
    ) {
      tester.pumpWidget(const FinanceApp());
      final output = tester.renderToString(size: narrow);

      expect(output, contains('Fleury Finance · sample data'));
      expect(output, contains('Net worth'));
      expect(output, contains('Accounts'));
      expect(output, contains('Monthly cash flow'));
      expect(output, contains('July spending'));
      expect(output, contains('Find transactions'));
      expect(output, contains('Transactions'));
      expect(output, contains('Selected transaction'));
      expect(output, contains('MERCHANT'));
      expect(output, isNot(contains('CATEGORY')));
    });

    testWidgets('keeps the ledger useful in a standard 80x24 terminal', (
      tester,
    ) {
      tester.pumpWidget(const FinanceApp());
      final output = tester.renderToString(size: const CellSize(80, 24));

      expect(output, contains('Fleury Finance · sample data'));
      expect(output, contains('Snapshot · Jul 2026'));
      expect(output, contains('Find transactions'));
      expect(output, contains('Newest first'));
      expect(output, contains('Transactions'));
      expect(output, contains('Amazon.ca'));
      expect(output, contains('sort + filter'));
      expect(output, isNot(contains('Monthly cash flow')));
    });

    testWidgets('search input filters rows and keeps the detail synchronized', (
      tester,
    ) {
      tester.pumpWidget(const FinanceApp());
      tester.render(size: wide);

      tester.type('Netflix');
      final output = tester.renderToString(size: wide);

      expect(output, contains('7 rows'));
      expect(output, contains('Netflix'));
      expect(output, contains('Standard plan'));
      expect(output, isNot(contains('Amazon.ca')));
      expect(tester.semantics().byRole(SemanticRole.tableRow), isNotEmpty);
      expect(
        tester
            .semantics()
            .byRole(SemanticRole.tableRow)
            .where((node) => node.state['header'] != true)
            .every((node) => node.label?.contains('netflix') ?? false),
        isTrue,
      );
    });

    testWidgets('semantic selection and keyboard navigation update detail', (
      tester,
    ) async {
      tester.pumpWidget(const FinanceApp());
      tester.render(size: wide);

      final wholeFoods = tester.semantics().single(
        role: SemanticRole.tableRow,
        label: 'tx-jul-whole-foods',
        action: SemanticAction.select,
      );
      final result = await tester.invokeSemanticAction(
        SemanticAction.select,
        node: wholeFoods,
      );
      expect(result.completed, isTrue);
      var output = tester.renderToString(size: wide);
      expect(output, contains('Weekly groceries'));

      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      output = tester.renderToString(size: wide);
      expect(output, contains('Automatic TFSA contribution'));
    });

    testWidgets('shrinking filters reconcile table and detail by stable ID', (
      tester,
    ) async {
      tester.pumpWidget(const FinanceApp());
      tester.render(size: wide);

      final shoppers = tester.semantics().single(
        role: SemanticRole.tableRow,
        label: 'tx-jul-shoppers',
        action: SemanticAction.select,
      );
      expect(
        (await tester.invokeSemanticAction(
          SemanticAction.select,
          node: shoppers,
        )).completed,
        isTrue,
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(tester.renderToString(size: wide), contains('ID 2026-07-spotify'));

      expect(
        (await tester.invokeSemanticAction(
          SemanticAction.focus,
          role: SemanticRole.textField,
          label: 'Search transactions',
        )).completed,
        isTrue,
      );
      tester.type('Netflix');
      tester.render(size: wide);
      tester.pump();
      final output = tester.renderToString(size: wide);

      expect(output, contains('7 rows'));
      expect(output, contains('ID 2026-07-netflix'));
      expect(output, isNot(contains('ID 2026-01-netflix')));
    });

    testWidgets('stress mode mounts 2,500 deterministic rows on demand', (
      tester,
    ) async {
      tester.pumpWidget(const FinanceApp());
      tester.render(size: wide);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Stress +2,500',
      );
      expect(result.completed, isTrue);
      final output = tester.renderToString(size: wide);

      expect(output, contains('2573 rows'));
      expect(output, contains('deterministic stress mode'));
      expect(output, contains('Stress on · 2,500'));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.table, label: 'Finance transactions')
            .state['collectionRowCount'],
        2573,
      );
    });
  });
}
