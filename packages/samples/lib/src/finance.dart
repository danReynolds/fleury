import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'finance_model.dart';
import 'scaffold.dart';

export 'finance_model.dart';

/// A polished, browser-safe personal-finance dashboard built from Fleury's
/// public widgets. All figures are deterministic sample data: no network,
/// filesystem, clock, or host account access is used.
class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _FinanceBody());
}

class _FinanceBody extends StatefulWidget {
  const _FinanceBody();

  @override
  State<_FinanceBody> createState() => _FinanceBodyState();
}

class _FinanceBodyState extends State<_FinanceBody> {
  late final FinanceLedger _ledger = FinanceLedger.sample();
  late final List<FinanceTransaction> _stressRows = _ledger
      .stressTransactions();
  final DataTableController _tableController = DataTableController();
  final TextEditingController _searchController = TextEditingController();

  late List<FinanceTransaction> _rows;
  String? _selectedTransactionId;
  String? _accountFilter;
  FinanceCategory? _categoryFilter;
  FinanceTransactionSort _sort = FinanceTransactionSort.newest;
  String _query = '';
  bool _stressMode = false;
  bool _syncingTableSelection = false;

  @override
  void initState() {
    super.initState();
    _rows = _ledger.queryTransactions();
    _selectedTransactionId = _rows.firstOrNull?.id;
    _tableController.addListener(_onTableSelectionChanged);
  }

  @override
  void dispose() {
    _tableController
      ..removeListener(_onTableSelectionChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  FinanceTransaction? get _selectedTransaction {
    final selectedId = _selectedTransactionId;
    if (selectedId == null) return null;
    for (final transaction in _rows) {
      if (transaction.id == selectedId) return transaction;
    }
    return null;
  }

  void _onTableSelectionChanged() {
    if (_syncingTableSelection || _rows.isEmpty) return;
    final index = _tableController.selectedIndex;
    if (index < 0 || index >= _rows.length) return;
    final nextId = _rows[index].id;
    if (nextId == _selectedTransactionId || !mounted) return;
    setState(() => _selectedTransactionId = nextId);
  }

  void _refreshRows({
    String? query,
    String? accountId,
    bool updateAccount = false,
    FinanceCategory? category,
    bool updateCategory = false,
    FinanceTransactionSort? sort,
    bool? stressMode,
  }) {
    final nextQuery = query ?? _query;
    final nextAccount = updateAccount ? accountId : _accountFilter;
    final nextCategory = updateCategory ? category : _categoryFilter;
    final nextSort = sort ?? _sort;
    final nextStress = stressMode ?? _stressMode;
    final source = nextStress
        ? <FinanceTransaction>[..._ledger.transactions, ..._stressRows]
        : _ledger.transactions;
    final nextRows = _ledger.queryTransactions(
      source: source,
      query: nextQuery,
      accountId: nextAccount,
      category: nextCategory,
      sort: nextSort,
    );
    final nextSelected = _ledger.resolveSelectionId(
      nextRows,
      _selectedTransactionId,
    );
    final nextSelectedIndex = nextSelected == null
        ? 0
        : nextRows.indexWhere((transaction) => transaction.id == nextSelected);

    // DataTableController is positional. Prime it while the old row count is
    // still installed, then hold the listener guard through the rebuild and
    // reconcile the stable row ID after DataTable installs its new row count.
    // Without the across-frame guard, a shrinking filter can synchronously
    // clamp index 10 to index 6 and overwrite the intended selected ID.
    _syncingTableSelection = true;
    final oldRowCount = _tableController.rowCount;
    if (oldRowCount > 0) {
      _tableController.selectedIndex = nextSelectedIndex.clamp(
        0,
        oldRowCount - 1,
      );
    }
    setState(() {
      _query = nextQuery;
      _accountFilter = nextAccount;
      _categoryFilter = nextCategory;
      _sort = nextSort;
      _stressMode = nextStress;
      _rows = nextRows;
      _selectedTransactionId = nextSelected;
    });
    _scheduleTableSelectionSync(nextSelected);
  }

  void _scheduleTableSelectionSync(String? selectedId) {
    void sync() {
      if (!mounted) return;
      try {
        if (selectedId == null) return;
        final index = _rows.indexWhere(
          (transaction) => transaction.id == selectedId,
        );
        if (index < 0 || _tableController.selectedIndex == index) return;
        _tableController.selectedIndex = index;
      } finally {
        _syncingTableSelection = false;
      }
    }

    final binding = TuiBinding.maybeOf(context);
    if (binding == null) {
      sync();
    } else {
      binding.addPostFrameCallback((_) => sync());
    }
  }

  void _selectRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    setState(() => _selectedTransactionId = _rows[rowIndex].id);
  }

  void _sortFromColumn(String columnId) {
    final next = switch (columnId) {
      'date' =>
        _sort == FinanceTransactionSort.newest
            ? FinanceTransactionSort.oldest
            : FinanceTransactionSort.newest,
      'merchant' =>
        _sort == FinanceTransactionSort.merchantAscending
            ? FinanceTransactionSort.merchantDescending
            : FinanceTransactionSort.merchantAscending,
      'amount' =>
        _sort == FinanceTransactionSort.amountHigh
            ? FinanceTransactionSort.amountLow
            : FinanceTransactionSort.amountHigh,
      'category' =>
        _sort == FinanceTransactionSort.categoryAscending
            ? FinanceTransactionSort.categoryDescending
            : FinanceTransactionSort.categoryAscending,
      'account' =>
        _sort == FinanceTransactionSort.accountAscending
            ? FinanceTransactionSort.accountDescending
            : FinanceTransactionSort.accountAscending,
      _ => _sort,
    };
    _refreshRows(sort: next);
  }

  String get _sortColumnId => switch (_sort) {
    FinanceTransactionSort.newest || FinanceTransactionSort.oldest => 'date',
    FinanceTransactionSort.amountHigh ||
    FinanceTransactionSort.amountLow => 'amount',
    FinanceTransactionSort.merchantAscending ||
    FinanceTransactionSort.merchantDescending => 'merchant',
    FinanceTransactionSort.categoryAscending ||
    FinanceTransactionSort.categoryDescending => 'category',
    FinanceTransactionSort.accountAscending ||
    FinanceTransactionSort.accountDescending => 'account',
  };

  DataTableSortDirection get _sortDirection => switch (_sort) {
    FinanceTransactionSort.oldest ||
    FinanceTransactionSort.amountLow ||
    FinanceTransactionSort.merchantAscending ||
    FinanceTransactionSort.categoryAscending ||
    FinanceTransactionSort.accountAscending => DataTableSortDirection.ascending,
    _ => DataTableSortDirection.descending,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxCols ?? 120;
        final height = constraints.maxRows ?? 48;
        final wide = width >= 104;
        final richLayoutMinimumRows = wide ? 36 : 52;
        if (height < richLayoutMinimumRows) {
          return _shortLayout(context);
        }
        return wide ? _wideLayout(context) : _narrowLayout(context);
      },
    );
  }

  /// A ledger-first layout for the classic 80×24 terminal and other short
  /// viewports. Charts remain available as soon as vertical space permits;
  /// here the useful workflow—summary, filters, sort, and rows—wins.
  Widget _shortLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(context, compact: true),
        const SizedBox(height: 1),
        SizedBox(height: 5, child: _snapshotPanel(context)),
        const SizedBox(height: 1),
        SizedBox(height: 6, child: _filters(context, compact: true)),
        const SizedBox(height: 1),
        Expanded(child: _transactionTable(context, wide: false)),
        const SizedBox(height: 1),
        _footer(context, short: true),
      ],
    );
  }

  Widget _wideLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(context),
        const SizedBox(height: 1),
        SizedBox(height: 6, child: _overviewCards(context, compact: false)),
        const SizedBox(height: 1),
        SizedBox(height: 14, child: _insights(context, compact: false)),
        const SizedBox(height: 1),
        SizedBox(height: 5, child: _filters(context, compact: false)),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(flex: 7, child: _transactionTable(context, wide: true)),
              const SizedBox(width: 1),
              Expanded(flex: 3, child: _transactionDetail(context)),
            ],
          ),
        ),
        const SizedBox(height: 1),
        _footer(context),
      ],
    );
  }

  Widget _narrowLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(context, compact: true),
        const SizedBox(height: 1),
        SizedBox(height: 8, child: _overviewCards(context, compact: true)),
        const SizedBox(height: 1),
        SizedBox(height: 13, child: _insights(context, compact: true)),
        const SizedBox(height: 1),
        SizedBox(height: 8, child: _filters(context, compact: true)),
        const SizedBox(height: 1),
        Expanded(child: _transactionTable(context, wide: false)),
        const SizedBox(height: 1),
        SizedBox(height: 8, child: _transactionDetail(context, compact: true)),
        const SizedBox(height: 1),
        _footer(context, compact: true),
      ],
    );
  }

  Widget _header(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text('▌ ', style: CellStyle(foreground: theme.colorScheme.primary)),
        Text(
          'Fleury Finance',
          style: CellStyle(bold: true, foreground: theme.colorScheme.primary),
          softWrap: false,
        ),
        Text(
          compact
              ? ' · sample data'
              : '   deterministic sample data · local only',
          style: theme.mutedStyle,
          softWrap: false,
        ),
        const Expanded(child: SizedBox.shrink()),
        if (!compact)
          Text(
            'Overview · Jul 2026',
            style: CellStyle(foreground: theme.colorScheme.info),
            softWrap: false,
          ),
      ],
    );
  }

  Widget _overviewCards(BuildContext context, {required bool compact}) {
    final cashFlow = _ledger.cashFlowForMonth(2026, 7);
    final cards = <Widget>[
      _metricPanel(
        context,
        title: 'Net worth',
        value: formatFinanceCents(_ledger.netWorthCents),
        detail: 'Across ${_ledger.accounts.length} accounts',
        color: Theme.of(context).colorScheme.primary,
      ),
      _metricPanel(
        context,
        title: 'Available cash',
        value: formatFinanceCents(_ledger.liquidCents),
        detail: 'Chequing + savings',
        color: Theme.of(context).colorScheme.info,
      ),
      _metricPanel(
        context,
        title: 'July cash flow',
        value: formatFinanceCents(cashFlow.netCents, showPlus: true),
        detail:
            '${formatFinanceCents(cashFlow.inflowCents)} in · '
            '${formatFinanceCents(cashFlow.outflowCents)} out',
        color: Theme.of(context).colorScheme.success,
      ),
      _metricPanel(
        context,
        title: 'Investments / debt',
        value:
            '${formatFinanceWholeDollars(_ledger.investmentCents)} / '
            '${formatFinanceWholeDollars(-_ledger.debtCents)}',
        detail: 'TFSA · Cobalt balance',
        color: Theme.of(context).colorScheme.warning,
      ),
    ];

    if (!compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var index = 0; index < cards.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: 1),
            Expanded(child: cards[index]),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: cards[0]),
        const SizedBox(width: 1),
        Expanded(child: _accountsPanel(context, compact: true)),
      ],
    );
  }

  Widget _snapshotPanel(BuildContext context) {
    final theme = Theme.of(context);
    final flow = _ledger.cashFlowForMonth(2026, 7);

    Widget metric(String label, String value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.mutedStyle, softWrap: false),
          Text(
            value,
            style: CellStyle(bold: true, foreground: color),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Panel(
      title: 'Snapshot · Jul 2026',
      trailing: Text('local sample data', style: theme.mutedStyle),
      child: Row(
        children: <Widget>[
          metric(
            'Net worth',
            formatFinanceCents(_ledger.netWorthCents),
            theme.colorScheme.primary,
          ),
          metric(
            'Cash',
            formatFinanceCents(_ledger.liquidCents),
            theme.colorScheme.info,
          ),
          metric(
            'July flow',
            formatFinanceCents(flow.netCents, showPlus: true),
            theme.colorScheme.success,
          ),
          metric(
            'Debt',
            formatFinanceCents(-_ledger.debtCents),
            theme.colorScheme.warning,
          ),
        ],
      ),
    );
  }

  Widget _metricPanel(
    BuildContext context, {
    required String title,
    required String value,
    required String detail,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            value,
            style: CellStyle(bold: true, foreground: color),
            softWrap: false,
          ),
          Text(
            detail,
            style: theme.mutedStyle,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _insights(BuildContext context, {required bool compact}) {
    if (compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(flex: 3, child: _cashFlowPanel(context)),
          const SizedBox(width: 1),
          Expanded(flex: 2, child: _categoryPanel(context)),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(flex: 5, child: _cashFlowPanel(context)),
        const SizedBox(width: 1),
        Expanded(flex: 3, child: _categoryPanel(context)),
        const SizedBox(width: 1),
        Expanded(flex: 3, child: _accountsPanel(context, compact: false)),
      ],
    );
  }

  Widget _cashFlowPanel(BuildContext context) {
    final theme = Theme.of(context);
    final inflow = <(num, num)>[];
    final spending = <(num, num)>[];
    for (var month = 1; month <= 7; month++) {
      final flow = _ledger.cashFlowForMonth(2026, month);
      inflow.add((month, flow.inflowCents / 100));
      spending.add((month, flow.outflowCents / 100));
    }
    return Panel(
      title: 'Monthly cash flow',
      trailing: Text('Jan–Jul', style: theme.mutedStyle),
      child: LineChart(
        series: <LineSeries>[
          LineSeries(inflow, label: 'in', color: theme.colorScheme.success),
          LineSeries(spending, label: 'out', color: theme.colorScheme.warning),
        ],
        xRange: const (1, 7),
        showAxes: true,
        showGrid: true,
        showLegend: true,
        padding: 0.04,
        xTickFormat: formatFinanceMonthTick,
        yTickFormat: TickFormat.currency(r'$'),
        interactive: true,
        semanticLabel: 'Monthly cash flow from January through July 2026',
      ),
    );
  }

  Widget _categoryPanel(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _ledger.categorySpendForMonth(2026, 7).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5);
    return Panel(
      title: 'July spending',
      trailing: Text('top 5', style: theme.mutedStyle),
      child: BarChart(
        bars: <Bar>[
          for (final entry in top) Bar(entry.key.shortLabel, entry.value / 100),
        ],
        barWidth: 3,
        gap: 1,
        palette: Palettes.categorical,
        showLabels: true,
        showValues: false,
        showYAxis: true,
        semanticLabel: 'July spending by category',
      ),
    );
  }

  Widget _accountsPanel(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    return Panel(
      title: 'Accounts',
      trailing: compact
          ? null
          : Text(
              formatFinanceCents(_ledger.netWorthCents),
              style: theme.mutedStyle,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final account in _ledger.accounts)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    compact ? account.institution : account.name,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatFinanceCents(account.balanceCents),
                  style: CellStyle(
                    foreground: account.balanceCents < 0
                        ? theme.colorScheme.warning
                        : theme.colorScheme.foreground,
                  ),
                  softWrap: false,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final search = Row(
      children: <Widget>[
        Text('Search ', style: theme.mutedStyle),
        Expanded(
          child: TextInput(
            controller: _searchController,
            autofocus: true,
            placeholder: 'merchant, note, category…',
            semanticLabel: 'Search transactions',
            enableBlink: false,
            onChanged: (value) => _refreshRows(query: value),
          ),
        ),
      ],
    );
    final account = Select<String?>(
      options: <SelectOption<String?>>[
        const SelectOption<String?>(value: null, label: 'All accounts'),
        for (final item in _ledger.accounts)
          SelectOption<String?>(
            value: item.id,
            label: '${item.institution} •${item.lastFour}',
          ),
      ],
      value: _accountFilter,
      onChanged: (value) => _refreshRows(accountId: value, updateAccount: true),
      semanticLabel: 'Account filter',
    );
    final category = Select<FinanceCategory?>(
      options: <SelectOption<FinanceCategory?>>[
        const SelectOption<FinanceCategory?>(
          value: null,
          label: 'All categories',
        ),
        for (final item in FinanceCategory.values)
          SelectOption<FinanceCategory?>(value: item, label: item.label),
      ],
      value: _categoryFilter,
      onChanged: (value) => _refreshRows(category: value, updateCategory: true),
      semanticLabel: 'Category filter',
    );
    final sort = Select<FinanceTransactionSort>(
      options: <SelectOption<FinanceTransactionSort>>[
        for (final item in FinanceTransactionSort.values)
          SelectOption<FinanceTransactionSort>(value: item, label: item.label),
      ],
      value: _sort,
      onChanged: (value) => _refreshRows(sort: value),
      semanticLabel: 'Transaction sort',
    );
    final stress = Button(
      label: _stressMode ? 'Stress on · 2,500' : 'Stress +2,500',
      variant: _stressMode ? ButtonVariant.warning : ButtonVariant.normal,
      onPressed: () => _refreshRows(stressMode: !_stressMode),
    );

    return Panel(
      title: 'Find transactions',
      trailing: Text(
        '${_rows.length} ${_rows.length == 1 ? 'row' : 'rows'}',
        style: theme.mutedStyle,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                search,
                Row(
                  children: <Widget>[
                    Expanded(child: account),
                    const SizedBox(width: 1),
                    Expanded(child: category),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Expanded(child: sort),
                    const SizedBox(width: 1),
                    stress,
                  ],
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(flex: 3, child: search),
                const SizedBox(width: 1),
                Expanded(flex: 2, child: account),
                const SizedBox(width: 1),
                Expanded(flex: 2, child: category),
                const SizedBox(width: 1),
                Expanded(flex: 2, child: sort),
                const SizedBox(width: 1),
                stress,
              ],
            ),
    );
  }

  String _tableAccountLabel(FinanceAccount account) =>
      switch (account.institution) {
        'American Express' => 'Amex',
        'Wealthsimple' => 'WS',
        final institution => institution,
      };

  Widget _transactionTable(BuildContext context, {required bool wide}) {
    final theme = Theme.of(context);
    final columns = wide
        ? const <DataTableColumn>[
            DataTableColumn(
              id: 'date',
              title: 'DATE',
              width: FixedColumnWidth(10),
              sortable: true,
            ),
            DataTableColumn(id: 'merchant', title: 'MERCHANT', sortable: true),
            DataTableColumn(
              id: 'category',
              title: 'CATEGORY',
              width: FixedColumnWidth(13),
              sortable: true,
            ),
            DataTableColumn(
              id: 'account',
              title: 'ACCOUNT',
              width: FixedColumnWidth(9),
              sortable: true,
            ),
            DataTableColumn(
              id: 'amount',
              title: 'AMOUNT',
              width: FixedColumnWidth(11),
              sortable: true,
            ),
          ]
        : const <DataTableColumn>[
            DataTableColumn(
              id: 'date',
              title: 'DATE',
              width: FixedColumnWidth(10),
              sortable: true,
            ),
            DataTableColumn(id: 'merchant', title: 'MERCHANT', sortable: true),
            DataTableColumn(
              id: 'amount',
              title: 'AMOUNT',
              width: FixedColumnWidth(11),
              sortable: true,
            ),
          ];
    return Panel(
      title: 'Transactions',
      trailing: Text(
        _stressMode ? 'deterministic stress mode' : _sort.label,
        style: theme.mutedStyle,
      ),
      child: _rows.isEmpty
          ? Center(
              child: Text('No matching transactions', style: theme.mutedStyle),
            )
          : DataTable(
              rowCount: _rows.length,
              columns: columns,
              controller: _tableController,
              rowKeyBuilder: (row) => _rows[row].id,
              cellBuilder: (row, columnId) {
                final transaction = _rows[row];
                final account = _ledger.accountById(transaction.accountId);
                return switch (columnId) {
                  'date' => formatFinanceDate(transaction.date),
                  'merchant' => transaction.merchant,
                  'category' => transaction.category.label,
                  'account' => _tableAccountLabel(account),
                  'amount' => formatFinanceCents(
                    transaction.amountCents,
                    showPlus: true,
                  ),
                  _ => '',
                };
              },
              autofocus: false,
              typeahead: false,
              selectionMode: DataTableSelectionMode.row,
              selectedStyle: theme.selectionStyle,
              sortColumnId: _sortColumnId,
              sortDirection: _sortDirection,
              onSort: _sortFromColumn,
              filterText: _query,
              onSelect: _selectRow,
              semanticLabel: 'Finance transactions',
            ),
    );
  }

  Widget _transactionDetail(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    final transaction = _selectedTransaction;
    if (transaction == null) {
      return Panel(
        title: 'Transaction detail',
        child: Center(
          child: Text('Adjust filters to see details', style: theme.mutedStyle),
        ),
      );
    }
    final account = _ledger.accountById(transaction.accountId);
    return Panel(
      title: compact ? 'Selected transaction' : 'Transaction detail',
      trailing: Text(
        formatFinanceCents(transaction.amountCents, showPlus: true),
        style: CellStyle(
          bold: true,
          foreground: transaction.amountCents >= 0
              ? theme.colorScheme.success
              : theme.colorScheme.warning,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            transaction.merchant,
            style: const CellStyle(bold: true),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${formatFinanceDate(transaction.date)} · '
            '${transaction.category.label}',
            style: theme.mutedStyle,
            softWrap: false,
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: 1),
            Text(transaction.note, maxLines: 2),
            const SizedBox(height: 1),
          ],
          Text(
            '${account.institution} •${account.lastFour}',
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          if (!compact)
            Text(
              '${account.kind.label} · '
              '${formatFinanceCents(account.balanceCents)}',
              style: theme.mutedStyle,
              softWrap: false,
            ),
          Text(
            'ID ${transaction.id}',
            style: theme.mutedStyle,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _footer(
    BuildContext context, {
    bool compact = false,
    bool short = false,
  }) {
    final theme = Theme.of(context);
    return Text(
      short
          ? ' Tab focus · ↑/↓ browse · sort + filter · deterministic sample data'
          : compact
          ? ' Tab focus · ↑/↓ rows · Enter select · all data is sample data'
          : ' Tab move focus   ↑/↓ select row   Enter inspect   '
                'charts use ←/→   deterministic sample data',
      style: theme.mutedStyle,
      softWrap: false,
    );
  }
}
