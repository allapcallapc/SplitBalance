import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/bill.dart';
import '../models/duplicate_bill_group.dart';
import '../providers/bills_provider.dart';
import '../providers/config_provider.dart';
import '../providers/duplicate_bills_provider.dart';
import '../widgets/app_bar_action_icon_button.dart';
import 'add_edit_bill_screen.dart';

// Parallel to PendingPaymentsScreen: lists every group of "potential
// duplicate" bills (same date + amount, see DuplicateBillsService) so the
// user can decide whether to edit or delete either one - no auto-merge, no
// silent fix (GH issue #20).
class DuplicateBillsScreen extends StatefulWidget {
  const DuplicateBillsScreen({super.key});

  @override
  State<DuplicateBillsScreen> createState() => _DuplicateBillsScreenState();
}

class _DuplicateBillsScreenState extends State<DuplicateBillsScreen> {
  Future<void> _load() async {
    final configProvider = context.read<ConfigProvider>();
    await context.read<DuplicateBillsProvider>().loadDuplicates(configProvider);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _editBill(Bill bill) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditBillScreen(bill: bill),
      ),
    );
    if (result == true && mounted) {
      await _load();
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBill),
        content: Text(
            '${l10n.areYouSureDeleteBill}\n\n${bill.details.isNotEmpty ? bill.details : "${dateFormat.format(bill.date)} - \$${bill.amount.toStringAsFixed(2)}"}'),
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
      final billsProvider = context.read<BillsProvider>();
      await billsProvider.deleteBillById(bill.id!);
      if (mounted && billsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(billsProvider.error!)),
        );
      }
      if (mounted) {
        await _load();
      }
    }
  }

  Widget _buildBillCard(Bill bill, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.only(right: 8),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l10n.paidBy}: ${bill.paidBy}'),
            const SizedBox(height: 4),
            Text('${l10n.category}: ${bill.category}'),
            if (bill.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                bill.details,
                style: const TextStyle(color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: l10n.edit,
                  onPressed: () => _editBill(bill),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  tooltip: l10n.delete,
                  onPressed: () => _deleteBill(bill),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(DuplicateBillGroup group, AppLocalizations l10n) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final currencyFormat = NumberFormat.currency(symbol: '\$');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_outlined, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  '${dateFormat.format(group.date)} · '
                  '${currencyFormat.format(group.amount)}',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final bill in group.bills) _buildBillCard(bill, l10n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.duplicateBills),
        actions: [
          AppBarActionIconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: Consumer<DuplicateBillsProvider>(
        builder: (context, duplicateBillsProvider, child) {
          if (duplicateBillsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = duplicateBillsProvider.duplicateGroups;
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noDuplicateBills,
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.noDuplicateBillsMessage,
                      style: const TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: groups.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) => _buildGroup(groups[index], l10n),
          );
        },
      ),
    );
  }
}
