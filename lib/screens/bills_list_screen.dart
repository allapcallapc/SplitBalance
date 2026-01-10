import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/bills_provider.dart';
import '../providers/config_provider.dart';
import '../models/bill.dart';
import '../widgets/google_sign_in_status.dart';
import 'add_edit_bill_screen.dart';

class BillsListScreen extends StatefulWidget {
  const BillsListScreen({super.key});

  @override
  State<BillsListScreen> createState() => _BillsListScreenState();
}

class _BillsListScreenState extends State<BillsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final configProvider = context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();
    
    if (configProvider.isSignedIn && configProvider.driveService.folderId != null) {
      await billsProvider.loadBills(configProvider);
    }
  }

  Future<void> _deleteBill(BuildContext context, int index, Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Are you sure you want to delete this bill?\n\n${bill.details.isNotEmpty ? bill.details : "${DateFormat('yyyy-MM-dd').format(bill.date)} - \$${bill.amount.toStringAsFixed(2)}"}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final configProvider = context.read<ConfigProvider>();
      final billsProvider = context.read<BillsProvider>();
      await billsProvider.deleteBill(index, configProvider);
      if (mounted && billsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(billsProvider.error!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          const GoogleSignInStatus(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddEditBillScreen(),
                ),
              );
              if (result == true && mounted) {
                await _loadData();
              }
            },
            tooltip: 'Add Bill',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<BillsProvider>(
        builder: (context, billsProvider, child) {
          if (billsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (billsProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: ${billsProvider.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      billsProvider.clearError();
                      _loadData();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (billsProvider.bills.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No bills yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddEditBillScreen(),
                        ),
                      );
                      if (result == true && mounted) {
                        await _loadData();
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Your First Bill'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: billsProvider.bills.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final bill = billsProvider.bills[index];
              final dateFormat = DateFormat('yyyy-MM-dd');
              final currencyFormat = NumberFormat.currency(symbol: '\$');

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      currencyFormat.format(bill.amount)[1], // First digit
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    bill.details.isNotEmpty ? bill.details : 'Bill',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Date: ${dateFormat.format(bill.date)}'),
                      Text('Amount: ${currencyFormat.format(bill.amount)}'),
                      Text('Paid by: ${bill.paidBy}'),
                      Text('Category: ${bill.category}'),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                        onTap: () {
                          Future.delayed(
                            const Duration(milliseconds: 100),
                            () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AddEditBillScreen(
                                    bill: bill,
                                    index: index,
                                  ),
                                ),
                              );
                              if (result == true && mounted) {
                                await _loadData();
                              }
                            },
                          );
                        },
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        onTap: () {
                          Future.delayed(
                            const Duration(milliseconds: 100),
                            () => _deleteBill(context, index, bill),
                          );
                        },
                      ),
                    ],
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
