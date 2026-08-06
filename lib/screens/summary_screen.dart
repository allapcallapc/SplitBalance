import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/calculation_provider.dart';
import '../providers/bills_provider.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../utils/category_icons.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, this.navigationNotifier});

  final ValueNotifier<int>? navigationNotifier;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  int? _lastNavigationIndex;

  @override
  void initState() {
    super.initState();
    widget.navigationNotifier?.addListener(_onNavigationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateBalances();
    });
  }

  @override
  void dispose() {
    widget.navigationNotifier?.removeListener(_onNavigationChanged);
    super.dispose();
  }

  void _onNavigationChanged() {
    final currentIndex = widget.navigationNotifier?.value ?? -1;
    // Refresh when navigating to summary screen (index 2)
    if (currentIndex == 2 && _lastNavigationIndex != 2 && mounted) {
      _lastNavigationIndex = currentIndex;
      _calculateBalances();
    } else {
      _lastNavigationIndex = currentIndex;
    }
  }

  Future<void> _calculateBalances() async {
    final configProvider = context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final calculationProvider = context.read<CalculationProvider>();

    // Set calculating state immediately to show loading indicator
    calculationProvider.setCalculating(true);

    // Ensure data is loaded
    if (configProvider.isSignedIn && configProvider.householdId != null) {
      await categoriesProvider.loadCategories(configProvider);
      await billsProvider.loadAllBills(configProvider);
      await splitsProvider.loadPaymentSplits(configProvider);
    }

    // Calculate balances
    await calculationProvider.calculateBalances(
      bills: billsProvider.allBills,
      splits: splitsProvider.splits,
      categories: categoriesProvider.categories,
      person1Name: configProvider.config.person1Name.isNotEmpty
          ? configProvider.config.person1Name
          : 'Person 1',
      person2Name: configProvider.config.person2Name.isNotEmpty
          ? configProvider.config.person2Name
          : 'Person 2',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              width: 32,
            ),
            const SizedBox(width: 12),
            Text(l10n.summary),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _calculateBalances,
            tooltip: l10n.recalculate,
          ),
        ],
      ),
      body: Consumer4<CalculationProvider, BillsProvider, PaymentSplitsProvider,
          CategoriesProvider>(
        builder: (context, calculationProvider, billsProvider, splitsProvider,
            categoriesProvider, child) {
          if (calculationProvider.isCalculating) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (calculationProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.error(calculationProvider.error!),
                    style: TextStyle(color: Colors.red[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      calculationProvider.clearError();
                      _calculateBalances();
                    },
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          final result = calculationProvider.balanceResult;
          if (result == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.calculate,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noBalanceCalculated,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _calculateBalances,
                    child: Text(l10n.calculateBalances),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Net Balance Card
                Card(
                  color: result.netBalance.abs() < 0.01
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.green[50])
                      : (result.netBalance > 0
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.withValues(alpha: 0.3)
                              : Colors.blue[50])
                          : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange.withValues(alpha: 0.3)
                              : Colors.orange[50])),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          result.netBalance.abs() < 0.01
                              ? l10n.allBalanced
                              : l10n.netBalance,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: result.netBalance.abs() < 0.01
                                ? (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.green[300]
                                    : Colors.green[900])
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          calculationProvider.getBalanceMessage(l10n),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: result.netBalance.abs() < 0.01
                                ? (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.green[300]
                                    : Colors.green[900])
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Expense Summary
                Text(
                  l10n.summary,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: IntrinsicColumnWidth(),
                        2: IntrinsicColumnWidth(),
                        3: IntrinsicColumnWidth(),
                      },
                      children: [
                        // Header row
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor,
                                width: 1,
                              ),
                            ),
                          ),
                          children: [
                            _buildTableHeaderCell(l10n.category),
                            _buildTableHeaderCell('Total',
                                isRightAligned: true),
                            _buildTableHeaderCell(result.person1Name,
                                isRightAligned: true),
                            _buildTableHeaderCell(result.person2Name,
                                isRightAligned: true),
                          ],
                        ),
                        // Category rows
                        ...(result.categoryBalances.values.toList()
                              ..sort(
                                  (a, b) => a.category.compareTo(b.category)))
                            .map((catBalance) {
                          final total =
                              catBalance.person1Paid + catBalance.person2Paid;
                          return TableRow(
                            children: [
                              _buildCategoryCell(
                                catBalance.category,
                                categoriesProvider,
                              ),
                              _buildTableCell(currencyFormat.format(total),
                                  isRightAligned: true),
                              _buildPaidExpectedCell(
                                catBalance.person1Paid,
                                catBalance.person1Expected,
                                currencyFormat,
                                l10n,
                              ),
                              _buildPaidExpectedCell(
                                catBalance.person2Paid,
                                catBalance.person2Expected,
                                currencyFormat,
                                l10n,
                              ),
                            ],
                          );
                        }),
                        // Total row
                        TableRow(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                          ),
                          children: [
                            _buildTableCell('Total', isBold: true),
                            _buildTableCell(
                              currencyFormat.format(
                                  result.person1Paid + result.person2Paid),
                              isRightAligned: true,
                              isBold: true,
                            ),
                            _buildPaidExpectedCell(
                              result.person1Paid,
                              result.person1Expected,
                              currencyFormat,
                              l10n,
                              isTotalRow: true,
                            ),
                            _buildPaidExpectedCell(
                              result.person2Paid,
                              result.person2Expected,
                              currencyFormat,
                              l10n,
                              isTotalRow: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Statistics
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.statistics,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          l10n.totalBills,
                          '${billsProvider.allBills.length}',
                          Colors.grey,
                        ),
                        _buildSummaryRow(
                          l10n.totalAmount,
                          currencyFormat.format(
                            billsProvider.allBills.fold(
                              0.0,
                              (sum, bill) => sum + bill.amount,
                            ),
                          ),
                          Colors.blue,
                        ),
                        _buildSummaryRow(
                          l10n.paymentSplits,
                          '${splitsProvider.splits.length}',
                          Colors.grey,
                        ),
                        _buildSummaryRow(
                          l10n.categories,
                          '${categoriesProvider.categories.length}',
                          Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    Color? color, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, {bool isRightAligned = false}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        text,
        textAlign: isRightAligned ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  // Category balances only carry the category name, so look up the matching
  // Category to render its icon (falling back to the default icon if it was
  // since renamed/deleted or has no icon set).
  Widget _buildCategoryCell(
    String categoryName,
    CategoriesProvider categoriesProvider,
  ) {
    IconData iconData = defaultCategoryIcon;
    for (final category in categoriesProvider.categories) {
      if (category.name == categoryName) {
        iconData = category.iconData;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 18),
          const SizedBox(width: 8),
          Text(
            categoryName,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(
    String text, {
    bool isRightAligned = false,
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        text,
        textAlign: isRightAligned ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          fontSize: isBold ? 16 : 14,
          color: color,
        ),
      ),
    );
  }

  // Combines what a person paid with their expected share into a single
  // cell: the paid amount, a muted caption with the expected share, and a
  // pill that states the direction in words (not just color) so the
  // meaning doesn't depend on distinguishing red from green.
  Widget _buildPaidExpectedCell(
    double paid,
    double expected,
    NumberFormat currencyFormat,
    AppLocalizations l10n, {
    bool isTotalRow = false,
  }) {
    final difference = paid - expected;
    final isBalanced = difference.abs() < 0.01;
    final isOverpaid = difference > 0.01;

    final Color pillColor;
    final Color pillBackground;
    final IconData pillIcon;
    final String pillLabel;

    if (isBalanced) {
      pillColor = Colors.grey[700]!;
      pillBackground = Colors.grey.withValues(alpha: 0.15);
      pillIcon = Icons.check;
      pillLabel = l10n.settled;
    } else if (isOverpaid) {
      pillColor = Colors.green[700]!;
      pillBackground = Colors.green.withValues(alpha: 0.15);
      pillIcon = Icons.arrow_upward;
      pillLabel = '+${currencyFormat.format(difference)} ${l10n.overpaid}';
    } else {
      pillColor = Colors.red[700]!;
      pillBackground = Colors.red.withValues(alpha: 0.15);
      pillIcon = Icons.arrow_downward;
      pillLabel =
          '${currencyFormat.format(difference.abs())} ${l10n.owes}';
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currencyFormat.format(paid),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isTotalRow ? 16 : 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.ofAmountExpected(currencyFormat.format(expected)),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pillBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(pillIcon, size: 12, color: pillColor),
                const SizedBox(width: 4),
                Text(
                  pillLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: pillColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
