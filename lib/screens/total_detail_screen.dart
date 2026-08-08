import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bills_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../services/calculation_service.dart';
import '../utils/category_icons.dart';
import '../utils/spend_chart_data.dart';
import '../widgets/ledger_visuals.dart';
import '../widgets/spend_charts.dart';
import 'category_detail_screen.dart';

// Drill-down from the Total ledger row on SummaryScreen: the household's
// current-period summary (same styling as the ledger row), a ranked
// breakdown of categories by amount (rather than the ledger's alphabetical
// order), and the same monthly/cumulative charts as CategoryDetailScreen
// but rolled up across every category.
class TotalDetailScreen extends StatefulWidget {
  const TotalDetailScreen({
    super.key,
    required this.person1Name,
    required this.person2Name,
    required this.person1Paid,
    required this.person1Expected,
    required this.person2Paid,
    required this.person2Expected,
    required this.categoryBalances,
  });

  final String person1Name;
  final String person2Name;
  final double person1Paid;
  final double person1Expected;
  final double person2Paid;
  final double person2Expected;
  final Map<String, CategoryBalance> categoryBalances;

  @override
  State<TotalDetailScreen> createState() => _TotalDetailScreenState();
}

class _TotalDetailScreenState extends State<TotalDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final billsProvider = context.read<BillsProvider>();
    final configProvider = context.read<ConfigProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    await Future.wait([
      billsProvider.loadAllBills(configProvider),
      categoriesProvider.loadCategories(configProvider),
    ]);
  }

  // Category balances only carry the category name, so look up the matching
  // Category to render its icon (falling back to the default icon if it was
  // since renamed/deleted or has no icon set) - same approach as
  // SummaryScreen's own lookup.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat =
        NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final total = widget.person1Paid + widget.person2Paid;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.total)),
      body: Consumer2<BillsProvider, CategoriesProvider>(
        builder: (context, billsProvider, categoriesProvider, child) {
          final isInitialLoad =
              billsProvider.isLoadingAll && billsProvider.allBills.isEmpty;
          final months = computeMonthlySpend(
              billsProvider.allBills, widget.person1Name, widget.person2Name);
          final cumulative = computeCumulativeSpend(
              billsProvider.allBills, widget.person1Name, widget.person2Name);

          final rankedCategories = widget.categoryBalances.values.toList()
            ..sort((a, b) => (b.person1Paid + b.person2Paid)
                .compareTo(a.person1Paid + a.person2Paid));

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.currentPeriod,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        LedgerSummaryCard(
                          label: l10n.total,
                          total: total,
                          person1Paid: widget.person1Paid,
                          person1Expected: widget.person1Expected,
                          person2Paid: widget.person2Paid,
                          person2Expected: widget.person2Expected,
                          currencyFormat: currencyFormat,
                          person1Name: widget.person1Name,
                          person2Name: widget.person2Name,
                          isTotalRow: true,
                        ),
                      ],
                    ),
                  ),
                ),
                if (rankedCategories.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    l10n.categoriesByAmount,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < rankedCategories.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _buildRankedRow(
                            context,
                            rankedCategories[i],
                            categoriesProvider,
                            currencyFormat,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (isInitialLoad)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (months.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        l10n.noBillsToChart,
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  )
                else ...[
                  Text(
                    l10n.monthlySpend,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      child: MonthlySpendBarChart(
                          months: months, currencyFormat: currencyFormat),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.cumulativeSpend,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      child: CumulativeSpendLineChart(
                          points: cumulative, currencyFormat: currencyFormat),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRankedRow(
    BuildContext context,
    CategoryBalance categoryBalance,
    CategoriesProvider categoriesProvider,
    NumberFormat currencyFormat,
  ) {
    final amount = categoryBalance.person1Paid + categoryBalance.person2Paid;
    final icon =
        _lookupCategoryIcon(categoryBalance.category, categoriesProvider);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategoryDetailScreen(
              category: categoryBalance.category,
              icon: icon,
              person1Name: widget.person1Name,
              person2Name: widget.person2Name,
              total: amount,
              person1Paid: categoryBalance.person1Paid,
              person1Expected: categoryBalance.person1Expected,
              person2Paid: categoryBalance.person2Paid,
              person2Expected: categoryBalance.person2Expected,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                categoryBalance.category,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              currencyFormat.format(amount),
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
