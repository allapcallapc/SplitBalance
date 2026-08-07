import 'dart:math' as math;
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        _buildPersonLegend(
                            result.person1Name, result.person2Name),
                        ...(result.categoryBalances.values.toList()
                              ..sort(
                                  (a, b) => a.category.compareTo(b.category)))
                            .map((catBalance) {
                          return Column(
                            children: [
                              const Divider(height: 1),
                              _buildLedgerRow(
                                context: context,
                                label: catBalance.category,
                                icon: _lookupCategoryIcon(
                                    catBalance.category, categoriesProvider),
                                total: catBalance.person1Paid +
                                    catBalance.person2Paid,
                                person1Paid: catBalance.person1Paid,
                                person1Expected: catBalance.person1Expected,
                                person2Paid: catBalance.person2Paid,
                                person2Expected: catBalance.person2Expected,
                                currencyFormat: currencyFormat,
                                l10n: l10n,
                                person1Name: result.person1Name,
                                person2Name: result.person2Name,
                              ),
                            ],
                          );
                        }),
                        const Divider(height: 1),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: -16),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[850]
                                    : Colors.grey[50],
                            borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(12)),
                          ),
                          child: _buildLedgerRow(
                            context: context,
                            label: 'Total',
                            total: result.person1Paid + result.person2Paid,
                            person1Paid: result.person1Paid,
                            person1Expected: result.person1Expected,
                            person2Paid: result.person2Paid,
                            person2Expected: result.person2Expected,
                            currencyFormat: currencyFormat,
                            l10n: l10n,
                            person1Name: result.person1Name,
                            person2Name: result.person2Name,
                            isTotalRow: true,
                          ),
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

  static final Color _person1Color = Colors.teal[600]!;
  static final Color _person2Color = Colors.orange[700]!;

  // Category balances only carry the category name, so look up the matching
  // Category to render its icon (falling back to the default icon if it was
  // since renamed/deleted or has no icon set).
  IconData _lookupCategoryIcon(
    String categoryName,
    CategoriesProvider categoriesProvider,
  ) {
    for (final category in categoriesProvider.categories) {
      if (category.name == categoryName) {
        return category.iconData;
      }
    }
    return defaultCategoryIcon;
  }

  Widget _buildPersonLegend(String person1Name, String person2Name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          _buildLegendItem(_person1Color, person1Name),
          const SizedBox(width: 16),
          _buildLegendItem(_person2Color, person2Name),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String name) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  // A single ledger row: category name + total, a bar showing each
  // person's paid amount as a proportion of the total with a tick at
  // where their fair share would land, the raw paid amounts, and a
  // one-line verdict naming whoever overpaid (with 2 people splitting a
  // fixed total, that single fact also tells you what the other person
  // owes, so there's no need to spell out both sides).
  Widget _buildLedgerRow({
    required BuildContext context,
    required String label,
    IconData? icon,
    required double total,
    required double person1Paid,
    required double person1Expected,
    required double person2Paid,
    required double person2Expected,
    required NumberFormat currencyFormat,
    required AppLocalizations l10n,
    required String person1Name,
    required String person2Name,
    bool isTotalRow = false,
  }) {
    final difference = person1Paid - person1Expected;
    final isBalanced = difference.abs() < 0.01;
    final person1Overpaid = difference > 0.01;

    final double person1Fraction = total > 0.01
        ? math.min(1.0, math.max(0.0, person1Paid / total))
        : 0.5;
    final expectedTotal = person1Expected + person2Expected;
    final double tickFraction = expectedTotal > 0.01
        ? math.min(1.0, math.max(0.0, person1Expected / expectedTotal))
        : 0.5;

    final Widget verdict = isBalanced
        ? _buildVerdict(Icons.check, l10n.settled, Colors.grey[600]!)
        : _buildVerdict(
            Icons.arrow_upward,
            '${person1Overpaid ? person1Name : person2Name} '
                '${l10n.overpaid} '
                '${currencyFormat.format(difference.abs())}',
            Colors.green[700]!,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isTotalRow ? FontWeight.bold : FontWeight.w600,
                    fontSize: isTotalRow ? 15 : 14,
                  ),
                ),
              ),
              Text(
                currencyFormat.format(total),
                style: TextStyle(
                  fontWeight: isTotalRow ? FontWeight.bold : FontWeight.w500,
                  fontSize: isTotalRow ? 15 : 13,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildProportionalBar(context, person1Fraction, tickFraction),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildAmountDot(
                  _person1Color, currencyFormat.format(person1Paid)),
              const Spacer(),
              _buildAmountDot(
                  _person2Color, currencyFormat.format(person2Paid)),
            ],
          ),
          const SizedBox(height: 6),
          verdict,
        ],
      ),
    );
  }

  Widget _buildProportionalBar(
    BuildContext context,
    double person1Fraction,
    double tickFraction,
  ) {
    const double barHeight = 14.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final tickColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.35);

    // Flex must be a positive integer, so express the split in thousandths
    // and keep both sides >= 1 even when one person paid nothing.
    final int rawFlex = (person1Fraction * 1000).round();
    final int person1Flex = math.min(999, math.max(1, rawFlex));
    final int person2Flex = 1000 - person1Flex;

    return SizedBox(
      height: barHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barHeight / 2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: trackColor),
            Row(
              children: [
                Expanded(
                    flex: person1Flex,
                    child: Container(color: _person1Color)),
                Expanded(
                    flex: person2Flex,
                    child: Container(color: _person2Color)),
              ],
            ),
            Align(
              alignment: Alignment(tickFraction * 2 - 1, 0),
              child: Container(
                width: 2,
                height: barHeight,
                color: tickColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerdict(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountDot(Color color, String amountText) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          amountText,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
