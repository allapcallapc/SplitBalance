import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/calculation_provider.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../widgets/app_bar_action_icon_button.dart';
import '../widgets/ledger_visuals.dart';
import 'category_detail_screen.dart';
import 'total_detail_screen.dart';

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
          AppBarActionIconButton(
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
                        child: _buildPersonLegend(
                            result.person1Name, result.person2Name),
                      ),
                      // Rows themselves carry their own horizontal padding
                      // (see _buildLedgerRow) instead of being inset by a
                      // padding wrapper here, so each row's InkWell spans the
                      // full card width and its hover/press highlight reaches
                      // both edges rather than stopping short of them.
                      ...(result.categoryBalances.values.toList()
                            ..sort(
                                (a, b) => a.category.compareTo(b.category)))
                          .map((catBalance) {
                        return Column(
                          children: [
                            const Divider(height: 1),
                            _buildLedgerRow(
                              label: catBalance.category,
                              icon: categoriesProvider
                                  .iconForCategory(catBalance.category),
                              total: catBalance.person1Paid +
                                  catBalance.person2Paid,
                              person1Paid: catBalance.person1Paid,
                              person1Expected: catBalance.person1Expected,
                              person2Paid: catBalance.person2Paid,
                              person2Expected: catBalance.person2Expected,
                              currencyFormat: currencyFormat,
                              person1Name: result.person1Name,
                              person2Name: result.person2Name,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CategoryDetailScreen(
                                    category: catBalance.category,
                                    icon: categoriesProvider.iconForCategory(
                                        catBalance.category),
                                    person1Name: result.person1Name,
                                    person2Name: result.person2Name,
                                    total: catBalance.person1Paid +
                                        catBalance.person2Paid,
                                    person1Paid: catBalance.person1Paid,
                                    person1Expected:
                                        catBalance.person1Expected,
                                    person2Paid: catBalance.person2Paid,
                                    person2Expected:
                                        catBalance.person2Expected,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      const Divider(height: 1),
                      SizedBox(
                        width: double.infinity,
                        // A Material (rather than a plain Container) so the
                        // InkWell inside _buildLedgerRow paints its splash/
                        // hover on top of this row's background instead of
                        // underneath it - a plain Container's decoration
                        // would paint after (i.e. over) the ink features
                        // layer from the Card's Material further up, masking
                        // the effect the other (undecorated) ledger rows show.
                        child: Material(
                          color: Theme.of(context).brightness ==
                                  Brightness.dark
                              ? Colors.grey[850]
                              : Colors.grey[50],
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12)),
                          clipBehavior: Clip.antiAlias,
                          child: _buildLedgerRow(
                            label: 'Total',
                            total: result.person1Paid + result.person2Paid,
                            person1Paid: result.person1Paid,
                            person1Expected: result.person1Expected,
                            person2Paid: result.person2Paid,
                            person2Expected: result.person2Expected,
                            currencyFormat: currencyFormat,
                            person1Name: result.person1Name,
                            person2Name: result.person2Name,
                            isTotalRow: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TotalDetailScreen(
                                  person1Name: result.person1Name,
                                  person2Name: result.person2Name,
                                  person1Paid: result.person1Paid,
                                  person1Expected: result.person1Expected,
                                  person2Paid: result.person2Paid,
                                  person2Expected: result.person2Expected,
                                  categoryBalances: result.categoryBalances,
                                ),
                              ),
                            ),
                          ),
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
                          calculationProvider.person1ExpenseCount,
                          result.person2Name,
                          calculationProvider.person2ExpenseCount,
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

  Widget _buildExpensesAddedSection(
    BuildContext context,
    AppLocalizations l10n,
    String person1Name,
    int person1Count,
    String person2Name,
    int person2Count,
  ) {
    // Reuse the same fixed per-person colors as the rest of this card (the
    // "Who Paid What" legend/bars below) rather than a second palette, so a
    // person's color means the same thing everywhere on the Statistics card.
    final colorA = PersonColors.person1;
    final colorB = PersonColors.person2;
    final totalCount = person1Count + person2Count;
    // person2's share is the remainder rather than independently rounded,
    // so the two percentages always sum to 100.
    final person1Percent =
        totalCount > 0 ? ((person1Count / totalCount) * 100).round() : 0;
    final person2Percent = 100 - person1Percent;

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
                    person1Percent.toString(),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  l10n.paymentSplitPersonDisplay(
                    person2Name,
                    person2Percent.toString(),
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
                l10n.expenses(count),
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

  Widget _buildPersonLegend(String person1Name, String person2Name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          _buildLegendItem(PersonColors.person1, person1Name),
          const SizedBox(width: 16),
          _buildLegendItem(PersonColors.person2, person2Name),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String name) {
    return DotLabel(
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

  // A single tappable ledger row: the shared current-period summary
  // (LedgerSummaryCard - category/total name, proportional bar, paid
  // amounts, verdict), plus a trailing chevron indicating it can be tapped
  // to drill into the category/Total detail screen. Matches the plain
  // trailing-chevron affordance already used by TotalDetailScreen's ranked
  // category rows, rather than a separate text hint.
  //
  // Carries its own horizontal inset (rather than relying on a padding
  // wrapper around the InkWell) so the InkWell itself spans the full card
  // width - its hover/press highlight then reaches both edges instead of
  // stopping short of them the way it would if only the visible content
  // were inset.
  Widget _buildLedgerRow({
    required String label,
    IconData? icon,
    required double total,
    required double person1Paid,
    required double person1Expected,
    required double person2Paid,
    required double person2Expected,
    required NumberFormat currencyFormat,
    required String person1Name,
    required String person2Name,
    required VoidCallback onTap,
    bool isTotalRow = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              child: LedgerSummaryCard(
                label: label,
                icon: icon,
                total: total,
                person1Paid: person1Paid,
                person1Expected: person1Expected,
                person2Paid: person2Paid,
                person2Expected: person2Expected,
                currencyFormat: currencyFormat,
                person1Name: person1Name,
                person2Name: person2Name,
                isTotalRow: isTotalRow,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 22, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
