import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/calculation_provider.dart';
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
    final splitsProvider = context.read<PaymentSplitsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final calculationProvider = context.read<CalculationProvider>();

    // Set calculating state immediately to show loading indicator
    calculationProvider.setCalculating(true);

    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      calculationProvider.reset();
      return;
    }

    // Categories (for ledger row icons) and splits (for the "Payment
    // Splits" stat row) still need loading in full here - both are small,
    // unpaginated tables. Bills are not: calculateAggregatedBalances below
    // fetches only the narrow, filtered sums it actually needs instead of
    // the household's entire bill history.
    await categoriesProvider.loadCategories(configProvider);
    await splitsProvider.loadPaymentSplits(configProvider);

    await calculationProvider.calculateAggregatedBalances(
      householdId: configProvider.householdId!,
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
      body: Consumer3<CalculationProvider, PaymentSplitsProvider,
          CategoriesProvider>(
        builder: (context, calculationProvider, splitsProvider,
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

          final person1ExpenseCount = billsProvider.allBills
              .where((bill) => bill.paidBy == result.person1Name)
              .length;
          final person2ExpenseCount = billsProvider.allBills
              .where((bill) => bill.paidBy == result.person2Name)
              .length;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPersonLegend(
                                result.person1Name, result.person2Name),
                            ...(result.categoryBalances.values.toList()
                                  ..sort((a, b) =>
                                      a.category.compareTo(b.category)))
                                .map((catBalance) {
                              return Column(
                                children: [
                                  const Divider(height: 1),
                                  _buildLedgerRow(
                                    context: context,
                                    label: catBalance.category,
                                    icon: _lookupCategoryIcon(
                                        catBalance.category,
                                        categoriesProvider),
                                    total: catBalance.person1Paid +
                                        catBalance.person2Paid,
                                    person1Paid: catBalance.person1Paid,
                                    person1Expected:
                                        catBalance.person1Expected,
                                    person2Paid: catBalance.person2Paid,
                                    person2Expected:
                                        catBalance.person2Expected,
                                    currencyFormat: currencyFormat,
                                    l10n: l10n,
                                    person1Name: result.person1Name,
                                    person2Name: result.person2Name,
                                  ),
                                ],
                              );
                            }),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
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
                        _buildExpensesAddedSection(
                          context,
                          l10n,
                          result.person1Name,
                          person1ExpenseCount,
                          result.person2Name,
                          person2ExpenseCount,
                        ),
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            l10n.totals,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        _buildSummaryRow(
                          l10n.totalBills,
                          '${calculationProvider.householdTotals?.billCount ?? 0}',
                          Colors.grey,
                        ),
                        _buildSummaryRow(
                          l10n.totalAmount,
                          currencyFormat.format(
                            calculationProvider.householdTotals?.totalAmount ??
                                0.0,
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

  // Fixed per-person accent colors, independent of the app's seed color, so
  // the split stays legible and consistent across all four theme modes
  // (light, dark, pink, teal) instead of shifting with the seed.
  static const _personAColorLight = Color(0xFF2A78D6);
  static const _personAColorDark = Color(0xFF3987E5);
  static const _personBColorLight = Color(0xFFEB6834);
  static const _personBColorDark = Color(0xFFD95926);

  Widget _buildExpensesAddedSection(
    BuildContext context,
    AppLocalizations l10n,
    String person1Name,
    int person1Count,
    String person2Name,
    int person2Count,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorA = isDark ? _personAColorDark : _personAColorLight;
    final colorB = isDark ? _personBColorDark : _personBColorLight;
    final totalCount = person1Count + person2Count;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.expensesAdded,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildPersonCountTile(
                    context, l10n, person1Name, person1Count, colorA),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildPersonCountTile(
                    context, l10n, person2Name, person2Count, colorB),
              ),
            ],
          ),
          if (totalCount > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: person1Count == 0
                    ? Container(color: colorB)
                    : person2Count == 0
                        ? Container(color: colorA)
                        : Row(
                            children: [
                              Expanded(
                                flex: person1Count,
                                child: Container(color: colorA),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                flex: person2Count,
                                child: Container(color: colorB),
                              ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.paymentSplitPersonDisplay(
                    person1Name,
                    ((person1Count / totalCount) * 100).round().toString(),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  l10n.paymentSplitPersonDisplay(
                    person2Name,
                    ((person2Count / totalCount) * 100).round().toString(),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonCountTile(
    BuildContext context,
    AppLocalizations l10n,
    String name,
    int count,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isDark ? 0.20 : 0.12),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.5 : 0.35),
              width: 2,
            ),
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                l10n.expenses,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
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
    return _buildDotLabel(
      color,
      name,
      dotSize: 8,
      gap: 6,
      textStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey[700],
      ),
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
    // A category can have paid amounts with no matching payment split (see
    // CalculationService), in which case expected stays 0 for both people -
    // there's no fair-share basis to compare against, so no verdict should
    // be declared.
    final expectedTotal = person1Expected + person2Expected;
    final hasExpectedShare = expectedTotal > 0.01;

    const epsilon = 0.01;
    final difference = person1Paid - person1Expected;
    final isBalanced = difference.abs() < epsilon;
    final person1Overpaid = difference >= epsilon;

    final double person1Fraction = total > 0.01
        ? math.min(1.0, math.max(0.0, person1Paid / total))
        : 0.5;
    // Shares the same denominator (total paid) as person1Fraction above, so
    // the fill boundary and the tick are on the same scale and the gap
    // between them reads as a real dollar imbalance. Centered when there's
    // no expected share at all, matching the "No split set" verdict below -
    // otherwise person1Expected being 0 would pin the tick to the far-left
    // edge as if a $0 fair share were a known fact.
    final double tickFraction = hasExpectedShare && total > 0.01
        ? math.min(1.0, math.max(0.0, person1Expected / total))
        : 0.5;

    final Widget verdict;
    if (!hasExpectedShare) {
      verdict = _buildVerdict(
          Icons.remove, l10n.noSplitSet, Colors.grey[500]!);
    } else if (isBalanced) {
      verdict = _buildVerdict(Icons.check, l10n.settled, Colors.grey[600]!);
    } else {
      verdict = _buildVerdict(
        Icons.arrow_upward,
        '${person1Overpaid ? person1Name : person2Name} '
            '${l10n.overpaid} '
            '${currencyFormat.format(difference.abs())}',
        person1Overpaid ? _person1Color : _person2Color,
      );
    }

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
    return _buildDotLabel(
      color,
      amountText,
      dotSize: 6,
      gap: 5,
      textStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
    );
  }

  // Shared by the person legend and the per-row paid amounts: a colored
  // dot followed by a label, at whatever size/spacing/style the caller
  // needs.
  Widget _buildDotLabel(
    Color color,
    String text, {
    required double dotSize,
    required double gap,
    required TextStyle textStyle,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: gap),
        Text(text, style: textStyle),
      ],
    );
  }
}
