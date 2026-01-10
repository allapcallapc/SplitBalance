import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/calculation_provider.dart';
import '../providers/bills_provider.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../widgets/google_sign_in_status.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateBalances();
    });
  }

  Future<void> _calculateBalances() async {
    final configProvider = context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final calculationProvider = context.read<CalculationProvider>();

    // Ensure data is loaded
    if (configProvider.isSignedIn && configProvider.driveService.folderId != null) {
      await categoriesProvider.loadCategories(configProvider);
      await billsProvider.loadBills(configProvider);
      await splitsProvider.loadPaymentSplits(configProvider);
    }

    // Calculate balances
    calculationProvider.calculateBalances(
      bills: billsProvider.bills,
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
    final currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Summary'),
        actions: [
          const GoogleSignInStatus(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _calculateBalances,
            tooltip: 'Recalculate',
          ),
        ],
      ),
      body: Consumer4<CalculationProvider, BillsProvider, PaymentSplitsProvider, CategoriesProvider>(
        builder: (context, calculationProvider, billsProvider, splitsProvider, categoriesProvider, child) {
          if (calculationProvider.isCalculating) {
            return const Center(child: CircularProgressIndicator());
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
                    'Error: ${calculationProvider.error}',
                    style: TextStyle(color: Colors.red[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      calculationProvider.clearError();
                      _calculateBalances();
                    },
                    child: const Text('Retry'),
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
                  const Text(
                    'No balance calculated',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _calculateBalances,
                    child: const Text('Calculate Balances'),
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
                      ? Colors.green[50]
                      : (result.netBalance > 0 ? Colors.blue[50] : Colors.orange[50]),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          result.netBalance.abs() < 0.01
                              ? 'All Balanced!'
                              : 'Net Balance',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: result.netBalance.abs() < 0.01
                                ? Colors.green[900]
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          calculationProvider.getBalanceMessage(),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: result.netBalance.abs() < 0.01
                                ? Colors.green[900]
                                : Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Person 1 Summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.person1Name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          'Paid',
                          currencyFormat.format(result.person1Paid),
                          Colors.blue,
                        ),
                        _buildSummaryRow(
                          'Expected',
                          currencyFormat.format(result.person1Expected),
                          Colors.grey,
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          'Difference',
                          currencyFormat.format(result.person1Paid - result.person1Expected),
                          result.person1Paid > result.person1Expected
                              ? Colors.green
                              : Colors.red,
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Person 2 Summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.person2Name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          'Paid',
                          currencyFormat.format(result.person2Paid),
                          Colors.blue,
                        ),
                        _buildSummaryRow(
                          'Expected',
                          currencyFormat.format(result.person2Expected),
                          Colors.grey,
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          'Difference',
                          currencyFormat.format(result.person2Paid - result.person2Expected),
                          result.person2Paid > result.person2Expected
                              ? Colors.green
                              : Colors.red,
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Category Breakdown (if available)
                if (result.categoryBalances.isNotEmpty) ...[
                  const Text(
                    'Category Breakdown',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...result.categoryBalances.values.map((catBalance) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text(
                          catBalance.category,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildSummaryRow(
                                  '${result.person1Name} Paid',
                                  currencyFormat.format(catBalance.person1Paid),
                                  Colors.blue,
                                ),
                                _buildSummaryRow(
                                  '${result.person1Name} Expected',
                                  currencyFormat.format(catBalance.person1Expected),
                                  Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                _buildSummaryRow(
                                  '${result.person2Name} Paid',
                                  currencyFormat.format(catBalance.person2Paid),
                                  Colors.blue,
                                ),
                                _buildSummaryRow(
                                  '${result.person2Name} Expected',
                                  currencyFormat.format(catBalance.person2Expected),
                                  Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // Statistics
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Statistics',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        _buildSummaryRow(
                          'Total Bills',
                          '${billsProvider.bills.length}',
                          Colors.grey,
                        ),
                        _buildSummaryRow(
                          'Total Amount',
                          currencyFormat.format(
                            billsProvider.bills.fold(
                              0.0,
                              (sum, bill) => sum + bill.amount,
                            ),
                          ),
                          Colors.blue,
                        ),
                        _buildSummaryRow(
                          'Payment Splits',
                          '${splitsProvider.splits.length}',
                          Colors.grey,
                        ),
                        _buildSummaryRow(
                          'Categories',
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
}
