import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/bills_provider.dart';
import '../providers/config_provider.dart';
import '../utils/spend_chart_data.dart';
import '../widgets/ledger_visuals.dart';
import '../widgets/spend_charts.dart';

// Drill-down from a category's ledger row on SummaryScreen: the category's
// current-period summary (same styling as the ledger row), plus a monthly
// stacked bar chart and a running-total line chart built from every bill
// ever recorded in the category (not a fixed lookback window).
class CategoryDetailScreen extends StatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.category,
    this.icon,
    required this.person1Name,
    required this.person2Name,
    required this.total,
    required this.person1Paid,
    required this.person1Expected,
    required this.person2Paid,
    required this.person2Expected,
  });

  final String category;
  final IconData? icon;
  final String person1Name;
  final String person2Name;

  // Current-period figures, already computed by the summary screen's
  // BalanceResult - passed straight through rather than recomputed here.
  final double total;
  final double person1Paid;
  final double person1Expected;
  final double person2Paid;
  final double person2Expected;

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBills());
  }

  Future<void> _loadBills() async {
    final billsProvider = context.read<BillsProvider>();
    final configProvider = context.read<ConfigProvider>();
    // Skip a redundant refetch if a previous screen (e.g. TotalDetailScreen,
    // when this was reached via its ranked breakdown) already loaded the
    // household's full bill history - add/update/delete keep it in sync
    // incrementally, so the cached list is never stale within a session.
    if (billsProvider.hasLoadedAllBillsForHousehold(configProvider.householdId)) {
      return;
    }
    await billsProvider.loadAllBills(configProvider);
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
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(widget.category, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Consumer<BillsProvider>(
        builder: (context, billsProvider, child) {
          final isInitialLoad =
              billsProvider.isLoadingAll && billsProvider.allBills.isEmpty;

          final categoryBills = billsProvider.allBills
              .where((b) => b.category == widget.category)
              .toList();
          final months = computeMonthlySpend(
              categoryBills, widget.person1Name, widget.person2Name);
          final cumulative = computeCumulativeSpend(
              categoryBills, widget.person1Name, widget.person2Name);

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
                          label: widget.category,
                          icon: widget.icon,
                          total: widget.total,
                          person1Paid: widget.person1Paid,
                          person1Expected: widget.person1Expected,
                          person2Paid: widget.person2Paid,
                          person2Expected: widget.person2Expected,
                          currencyFormat: currencyFormat,
                          person1Name: widget.person1Name,
                          person2Name: widget.person2Name,
                        ),
                      ],
                    ),
                  ),
                ),
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
                        l10n.noBillsInCategory,
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
}
