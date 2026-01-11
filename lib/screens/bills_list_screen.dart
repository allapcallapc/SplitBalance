import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/bills_provider.dart';
import '../providers/config_provider.dart';
import '../models/bill.dart';
import 'add_edit_bill_screen.dart';

class BillsListScreen extends StatefulWidget {
  const BillsListScreen({super.key});

  @override
  State<BillsListScreen> createState() => _BillsListScreenState();
}

class _BillsListScreenState extends State<BillsListScreen> {
  ConfigProvider? _configProvider;
  String? _lastLoadedFolderId; // Track which folder we loaded data for
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configProvider = context.read<ConfigProvider>();
    
    // Set up listener only once
    if (_configProvider != configProvider) {
      _configProvider?.removeListener(_onConfigChanged);
      _configProvider = configProvider;
      _configProvider?.addListener(_onConfigChanged);
    }
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (!mounted || _configProvider == null) return;
    
    final currentFolderId = _configProvider!.driveService.folderId;
    
    // Reload data if folder changes
    if (_configProvider!.isSignedIn && 
        currentFolderId != null && 
        currentFolderId != _lastLoadedFolderId) {
      // Folder changed or just selected - reload data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadData() async {
    final configProvider = _configProvider ?? context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();
    
    if (configProvider.isSignedIn && configProvider.driveService.folderId != null) {
      _lastLoadedFolderId = configProvider.driveService.folderId;
      await billsProvider.loadBills(configProvider);
    }
  }

  String _getCategoryInitials(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) {
      return '??';
    }
    final words = trimmed.split(' ');
    if (words.length >= 2) {
      // If multiple words, use first letter of first two words
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    } else if (trimmed.length >= 2) {
      // If single word with 2+ characters, use first two letters
      return trimmed.substring(0, 2).toUpperCase();
    } else {
      // If only one character, repeat it
      return '${trimmed[0]}${trimmed[0]}'.toUpperCase();
    }
  }

  Future<void> _deleteBill(BuildContext context, int index, Bill bill) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBill),
        content: Text('${l10n.areYouSureDeleteBill}\n\n${bill.details.isNotEmpty ? bill.details : "${DateFormat('yyyy-MM-dd').format(bill.date)} - \$${bill.amount.toStringAsFixed(2)}"}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
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
            Text(l10n.bills),
          ],
        ),
        actions: [
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
            tooltip: l10n.addBillTooltip,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: l10n.refreshTooltip,
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
                    l10n.error(billsProvider.error!),
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      billsProvider.clearError();
                      _loadData();
                    },
                    child: Text(l10n.retry),
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
                  Text(
                    l10n.noBillsYet,
                    style: const TextStyle(
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
                    label: Text(l10n.addYourFirstBill),
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
                      _getCategoryInitials(bill.category),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('${l10n.date}: ${dateFormat.format(bill.date)}'),
                      Text('${l10n.amount}: ${currencyFormat.format(bill.amount)}'),
                      Text('${l10n.paidBy}: ${bill.paidBy}'),
                      Text('${l10n.category}: ${bill.category}'),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: Row(
                          children: [
                            const Icon(Icons.edit, size: 20),
                            const SizedBox(width: 8),
                            Text(l10n.edit),
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
                        child: Row(
                          children: [
                            const Icon(Icons.delete, size: 20, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(l10n.delete, style: const TextStyle(color: Colors.red)),
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
