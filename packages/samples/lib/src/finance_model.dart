/// Account types represented by the sample ledger.
enum FinanceAccountKind { checking, savings, credit, investment }

extension FinanceAccountKindLabel on FinanceAccountKind {
  String get label => switch (this) {
    FinanceAccountKind.checking => 'Chequing',
    FinanceAccountKind.savings => 'Savings',
    FinanceAccountKind.credit => 'Credit card',
    FinanceAccountKind.investment => 'Investment',
  };
}

/// Transaction categories represented by the sample ledger.
enum FinanceCategory {
  income,
  housing,
  groceries,
  dining,
  transport,
  shopping,
  subscriptions,
  utilities,
  travel,
  health,
  entertainment,
  transfer,
}

extension FinanceCategoryLabel on FinanceCategory {
  String get label => switch (this) {
    FinanceCategory.income => 'Income',
    FinanceCategory.housing => 'Housing',
    FinanceCategory.groceries => 'Groceries',
    FinanceCategory.dining => 'Dining',
    FinanceCategory.transport => 'Transport',
    FinanceCategory.shopping => 'Shopping',
    FinanceCategory.subscriptions => 'Subscriptions',
    FinanceCategory.utilities => 'Utilities',
    FinanceCategory.travel => 'Travel',
    FinanceCategory.health => 'Health',
    FinanceCategory.entertainment => 'Entertainment',
    FinanceCategory.transfer => 'Transfer',
  };

  String get shortLabel => switch (this) {
    FinanceCategory.income => 'Inc',
    FinanceCategory.housing => 'Rent',
    FinanceCategory.groceries => 'Food',
    FinanceCategory.dining => 'Dine',
    FinanceCategory.transport => 'Ride',
    FinanceCategory.shopping => 'Shop',
    FinanceCategory.subscriptions => 'Subs',
    FinanceCategory.utilities => 'Util',
    FinanceCategory.travel => 'Trip',
    FinanceCategory.health => 'Med',
    FinanceCategory.entertainment => 'Fun',
    FinanceCategory.transfer => 'Xfer',
  };
}

/// A deterministic account in the sample ledger.
final class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.institution,
    required this.kind,
    required this.balanceCents,
    required this.lastFour,
  });

  final String id;
  final String name;
  final String institution;
  final FinanceAccountKind kind;

  /// Signed balance: liabilities use a negative value.
  final int balanceCents;
  final String lastFour;
}

/// A deterministic transaction in the sample ledger.
final class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.date,
    required this.merchant,
    required this.note,
    required this.accountId,
    required this.category,
    required this.amountCents,
  });

  final String id;
  final DateTime date;
  final String merchant;
  final String note;
  final String accountId;
  final FinanceCategory category;

  /// Signed amount: inflows are positive, outflows are negative.
  final int amountCents;
}

/// Cash-flow totals for a calendar month.
final class FinanceCashFlow {
  const FinanceCashFlow({
    required this.inflowCents,
    required this.outflowCents,
  });

  final int inflowCents;

  /// Positive magnitude of money spent.
  final int outflowCents;

  int get netCents => inflowCents - outflowCents;
}

/// Sort modes shared by the toolbar and sortable table headers.
enum FinanceTransactionSort {
  newest,
  oldest,
  amountHigh,
  amountLow,
  merchantAscending,
  merchantDescending,
  categoryAscending,
  categoryDescending,
  accountAscending,
  accountDescending,
}

extension FinanceTransactionSortLabel on FinanceTransactionSort {
  String get label => switch (this) {
    FinanceTransactionSort.newest => 'Newest first',
    FinanceTransactionSort.oldest => 'Oldest first',
    FinanceTransactionSort.amountHigh => 'Amount high',
    FinanceTransactionSort.amountLow => 'Amount low',
    FinanceTransactionSort.merchantAscending => 'Merchant A–Z',
    FinanceTransactionSort.merchantDescending => 'Merchant Z–A',
    FinanceTransactionSort.categoryAscending => 'Category A–Z',
    FinanceTransactionSort.categoryDescending => 'Category Z–A',
    FinanceTransactionSort.accountAscending => 'Account A–Z',
    FinanceTransactionSort.accountDescending => 'Account Z–A',
  };
}

/// Integer-cents model behind the finance showcase.
///
/// The fixture intentionally uses recognizable merchants and institutions so
/// the demo reads like a real personal-finance workflow, while every value is
/// local and deterministic.
final class FinanceLedger {
  FinanceLedger({
    required List<FinanceAccount> accounts,
    required List<FinanceTransaction> transactions,
  }) : accounts = List<FinanceAccount>.unmodifiable(accounts),
       transactions = List<FinanceTransaction>.unmodifiable(transactions);

  factory FinanceLedger.sample() {
    const accounts = <FinanceAccount>[
      FinanceAccount(
        id: 'rbc-chequing',
        name: 'Everyday Chequing',
        institution: 'RBC',
        kind: FinanceAccountKind.checking,
        balanceCents: 482143,
        lastFour: '1842',
      ),
      FinanceAccount(
        id: 'eq-savings',
        name: 'High Interest Savings',
        institution: 'EQ Bank',
        kind: FinanceAccountKind.savings,
        balanceCents: 1852000,
        lastFour: '9017',
      ),
      FinanceAccount(
        id: 'amex-cobalt',
        name: 'Cobalt Card',
        institution: 'American Express',
        kind: FinanceAccountKind.credit,
        balanceCents: -124673,
        lastFour: '3004',
      ),
      FinanceAccount(
        id: 'wealthsimple-tfsa',
        name: 'Managed TFSA',
        institution: 'Wealthsimple',
        kind: FinanceAccountKind.investment,
        balanceCents: 4284512,
        lastFour: '7710',
      ),
    ];

    final transactions = <FinanceTransaction>[];
    const groceryByMonth = <int>[
      38642,
      40118,
      39470,
      41860,
      40725,
      43210,
      42165,
    ];
    const hydroByMonth = <int>[18430, 17625, 16890, 15110, 14380, 13765, 14592];
    for (var month = 1; month <= 7; month++) {
      final mm = month.toString().padLeft(2, '0');
      transactions.addAll(<FinanceTransaction>[
        FinanceTransaction(
          id: '2026-$mm-payroll',
          date: DateTime(2026, month, 26),
          merchant: 'Shopify Payroll',
          note: 'Regular payroll deposit',
          accountId: 'rbc-chequing',
          category: FinanceCategory.income,
          amountCents: 675000,
        ),
        FinanceTransaction(
          id: '2026-$mm-rent',
          date: DateTime(2026, month, 1),
          merchant: 'Greenwin Property Management',
          note: 'Monthly rent',
          accountId: 'rbc-chequing',
          category: FinanceCategory.housing,
          amountCents: -225000,
        ),
        FinanceTransaction(
          id: '2026-$mm-hydro',
          date: DateTime(2026, month, 8),
          merchant: 'Hydro One',
          note: 'Electricity bill',
          accountId: 'rbc-chequing',
          category: FinanceCategory.utilities,
          amountCents: -hydroByMonth[month - 1],
        ),
        FinanceTransaction(
          id: '2026-$mm-bell',
          date: DateTime(2026, month, 10),
          merchant: 'Bell Canada',
          note: 'Mobile and internet',
          accountId: 'amex-cobalt',
          category: FinanceCategory.utilities,
          amountCents: -9040,
        ),
        FinanceTransaction(
          id: '2026-$mm-netflix',
          date: DateTime(2026, month, 12),
          merchant: 'Netflix',
          note: 'Standard plan',
          accountId: 'amex-cobalt',
          category: FinanceCategory.subscriptions,
          amountCents: -2259,
        ),
        FinanceTransaction(
          id: '2026-$mm-spotify',
          date: DateTime(2026, month, 14),
          merchant: 'Spotify',
          note: 'Individual plan',
          accountId: 'amex-cobalt',
          category: FinanceCategory.subscriptions,
          amountCents: -1243,
        ),
        FinanceTransaction(
          id: '2026-$mm-presto',
          date: DateTime(2026, month, 3),
          merchant: 'PRESTO / TTC',
          note: 'Monthly transit load',
          accountId: 'amex-cobalt',
          category: FinanceCategory.transport,
          amountCents: -15600,
        ),
        FinanceTransaction(
          id: '2026-$mm-loblaws',
          date: DateTime(2026, month, 19),
          merchant: 'Loblaws',
          note: 'Groceries',
          accountId: 'amex-cobalt',
          category: FinanceCategory.groceries,
          amountCents: -groceryByMonth[month - 1],
        ),
        FinanceTransaction(
          id: '2026-$mm-invest',
          date: DateTime(2026, month, 27),
          merchant: 'Wealthsimple',
          note: 'Automatic TFSA contribution',
          accountId: 'rbc-chequing',
          category: FinanceCategory.transfer,
          amountCents: -50000,
        ),
      ]);
    }

    transactions.addAll(<FinanceTransaction>[
      FinanceTransaction(
        id: 'tx-jul-amazon',
        date: DateTime(2026, 7, 29),
        merchant: 'Amazon.ca',
        note: 'Desk lamp and USB-C cable',
        accountId: 'amex-cobalt',
        category: FinanceCategory.shopping,
        amountCents: -7624,
      ),
      FinanceTransaction(
        id: 'tx-jul-whole-foods',
        date: DateTime(2026, 7, 28),
        merchant: 'Whole Foods Market',
        note: 'Weekly groceries',
        accountId: 'amex-cobalt',
        category: FinanceCategory.groceries,
        amountCents: -12847,
      ),
      FinanceTransaction(
        id: 'tx-jul-air-canada',
        date: DateTime(2026, 7, 24),
        merchant: 'Air Canada',
        note: 'Toronto to Montréal',
        accountId: 'amex-cobalt',
        category: FinanceCategory.travel,
        amountCents: -34892,
      ),
      FinanceTransaction(
        id: 'tx-jul-starbucks',
        date: DateTime(2026, 7, 23),
        merchant: 'Starbucks',
        note: 'Coffee with Sam',
        accountId: 'amex-cobalt',
        category: FinanceCategory.dining,
        amountCents: -743,
      ),
      FinanceTransaction(
        id: 'tx-jul-uber',
        date: DateTime(2026, 7, 21),
        merchant: 'Uber',
        note: 'Ride home',
        accountId: 'amex-cobalt',
        category: FinanceCategory.transport,
        amountCents: -2438,
      ),
      FinanceTransaction(
        id: 'tx-jul-shoppers',
        date: DateTime(2026, 7, 18),
        merchant: 'Shoppers Drug Mart',
        note: 'Pharmacy and essentials',
        accountId: 'amex-cobalt',
        category: FinanceCategory.health,
        amountCents: -5834,
      ),
      FinanceTransaction(
        id: 'tx-jul-cineplex',
        date: DateTime(2026, 7, 16),
        merchant: 'Cineplex',
        note: 'Two movie tickets',
        accountId: 'amex-cobalt',
        category: FinanceCategory.entertainment,
        amountCents: -3198,
      ),
      FinanceTransaction(
        id: 'tx-jun-indigo',
        date: DateTime(2026, 6, 29),
        merchant: 'Indigo',
        note: 'Books',
        accountId: 'amex-cobalt',
        category: FinanceCategory.shopping,
        amountCents: -6842,
      ),
      FinanceTransaction(
        id: 'tx-jun-freshbooks-refund',
        date: DateTime(2026, 6, 22),
        merchant: 'FreshBooks',
        note: 'Expense reimbursement',
        accountId: 'rbc-chequing',
        category: FinanceCategory.income,
        amountCents: 14850,
      ),
      FinanceTransaction(
        id: 'tx-may-via-rail',
        date: DateTime(2026, 5, 21),
        merchant: 'VIA Rail',
        note: 'Weekend trip',
        accountId: 'amex-cobalt',
        category: FinanceCategory.travel,
        amountCents: -12155,
      ),
    ]);

    return FinanceLedger(accounts: accounts, transactions: transactions);
  }

  final List<FinanceAccount> accounts;
  final List<FinanceTransaction> transactions;

  int get netWorthCents =>
      accounts.fold<int>(0, (sum, account) => sum + account.balanceCents);

  int get liquidCents => accounts
      .where(
        (account) =>
            account.kind == FinanceAccountKind.checking ||
            account.kind == FinanceAccountKind.savings,
      )
      .fold<int>(0, (sum, account) => sum + account.balanceCents);

  int get debtCents => accounts
      .where((account) => account.balanceCents < 0)
      .fold<int>(0, (sum, account) => sum + account.balanceCents.abs());

  int get investmentCents => accounts
      .where((account) => account.kind == FinanceAccountKind.investment)
      .fold<int>(0, (sum, account) => sum + account.balanceCents);

  FinanceAccount accountById(String id) =>
      accounts.firstWhere((account) => account.id == id);

  FinanceCashFlow cashFlowForMonth(int year, int month) {
    var inflow = 0;
    var outflow = 0;
    for (final transaction in transactions) {
      if (transaction.date.year != year ||
          transaction.date.month != month ||
          transaction.category == FinanceCategory.transfer) {
        continue;
      }
      if (transaction.amountCents >= 0) {
        inflow += transaction.amountCents;
      } else {
        outflow += transaction.amountCents.abs();
      }
    }
    return FinanceCashFlow(inflowCents: inflow, outflowCents: outflow);
  }

  Map<FinanceCategory, int> categorySpendForMonth(int year, int month) {
    final totals = <FinanceCategory, int>{};
    for (final transaction in transactions) {
      if (transaction.date.year != year ||
          transaction.date.month != month ||
          transaction.amountCents >= 0 ||
          transaction.category == FinanceCategory.transfer) {
        continue;
      }
      totals.update(
        transaction.category,
        (value) => value + transaction.amountCents.abs(),
        ifAbsent: () => transaction.amountCents.abs(),
      );
    }
    return totals;
  }

  /// Applies all table transformations while preserving deterministic ordering.
  List<FinanceTransaction> queryTransactions({
    List<FinanceTransaction>? source,
    String query = '',
    String? accountId,
    FinanceCategory? category,
    FinanceTransactionSort sort = FinanceTransactionSort.newest,
  }) {
    final needle = query.trim().toLowerCase();
    final rows = (source ?? transactions).where((transaction) {
      if (accountId != null && transaction.accountId != accountId) {
        return false;
      }
      if (category != null && transaction.category != category) return false;
      if (needle.isEmpty) return true;
      final account = accountById(transaction.accountId);
      final haystack =
          '${transaction.merchant} ${transaction.note} '
                  '${transaction.category.label} ${account.institution} '
                  '${account.name}'
              .toLowerCase();
      return haystack.contains(needle);
    }).toList();

    int compareDate(FinanceTransaction a, FinanceTransaction b) =>
        a.date.compareTo(b.date);
    int compareAmount(FinanceTransaction a, FinanceTransaction b) =>
        a.amountCents.compareTo(b.amountCents);
    int compareMerchant(FinanceTransaction a, FinanceTransaction b) =>
        a.merchant.toLowerCase().compareTo(b.merchant.toLowerCase());
    int compareCategory(FinanceTransaction a, FinanceTransaction b) =>
        a.category.label.compareTo(b.category.label);
    int compareAccount(FinanceTransaction a, FinanceTransaction b) =>
        accountById(
          a.accountId,
        ).institution.compareTo(accountById(b.accountId).institution);

    rows.sort((a, b) {
      final primary = switch (sort) {
        FinanceTransactionSort.newest => compareDate(b, a),
        FinanceTransactionSort.oldest => compareDate(a, b),
        FinanceTransactionSort.amountHigh => compareAmount(b, a),
        FinanceTransactionSort.amountLow => compareAmount(a, b),
        FinanceTransactionSort.merchantAscending => compareMerchant(a, b),
        FinanceTransactionSort.merchantDescending => compareMerchant(b, a),
        FinanceTransactionSort.categoryAscending => compareCategory(a, b),
        FinanceTransactionSort.categoryDescending => compareCategory(b, a),
        FinanceTransactionSort.accountAscending => compareAccount(a, b),
        FinanceTransactionSort.accountDescending => compareAccount(b, a),
      };
      return primary != 0 ? primary : a.id.compareTo(b.id);
    });
    return rows;
  }

  /// Keeps a selected row by stable ID, falling back to the first visible row.
  String? resolveSelectionId(
    Iterable<FinanceTransaction> visibleRows,
    String? selectedId,
  ) {
    final rows = visibleRows is List<FinanceTransaction>
        ? visibleRows
        : visibleRows.toList();
    if (selectedId != null &&
        rows.any((transaction) => transaction.id == selectedId)) {
      return selectedId;
    }
    return rows.isEmpty ? null : rows.first.id;
  }

  /// Creates a large deterministic fixture for virtualization/filter/sort QA.
  ///
  /// These rows are opt-in in the UI and deliberately predate the overview
  /// data, so enabling stress mode does not make the newest rows jump.
  List<FinanceTransaction> stressTransactions({int count = 2500}) {
    const merchants = <String>[
      'Costco Wholesale',
      'IKEA',
      'Tim Hortons',
      'Canadian Tire',
      'Metro',
      'Uber Eats',
      'Apple',
      'GoodLife Fitness',
      'Petro-Canada',
      'The Home Depot',
      'DoorDash',
      'Rexall',
    ];
    const categories = <FinanceCategory>[
      FinanceCategory.groceries,
      FinanceCategory.shopping,
      FinanceCategory.dining,
      FinanceCategory.utilities,
      FinanceCategory.transport,
      FinanceCategory.subscriptions,
      FinanceCategory.health,
      FinanceCategory.entertainment,
    ];
    final rows = <FinanceTransaction>[];
    for (var index = 0; index < count; index++) {
      final isRefund = index % 47 == 0;
      final amount = 550 + ((index * 7919) % 180000);
      rows.add(
        FinanceTransaction(
          id: 'stress-${index.toString().padLeft(5, '0')}',
          date: DateTime(2023, 1, 1).add(Duration(days: (index * 37) % 1095)),
          merchant: merchants[index % merchants.length],
          note: isRefund
              ? 'Deterministic stress fixture refund'
              : 'Deterministic stress fixture purchase',
          accountId: index % 5 == 0 ? 'rbc-chequing' : 'amex-cobalt',
          category: categories[index % categories.length],
          amountCents: isRefund ? amount : -amount,
        ),
      );
    }
    return rows;
  }
}

String formatFinanceMonthTick(num value) {
  const labels = <String>['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
  final month = value.round();
  return month >= 1 && month < labels.length ? labels[month] : '';
}

String formatFinanceWholeDollars(int cents) {
  final negative = cents < 0;
  final rounded = (cents.abs() + 50) ~/ 100;
  final digits = rounded.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${negative ? '-' : ''}\$$grouped';
}

/// Formats cents without locale or floating-point dependencies.
String formatFinanceCents(int cents, {bool showPlus = false}) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final whole = (absolute ~/ 100).toString();
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
    grouped.write(whole[index]);
  }
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final sign = negative ? '-' : (showPlus && cents > 0 ? '+' : '');
  return '$sign\$$grouped.$fraction';
}

/// ISO-style date formatting that sorts and scans cleanly in a terminal.
String formatFinanceDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
