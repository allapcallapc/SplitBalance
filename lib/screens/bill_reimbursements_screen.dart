import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/bill.dart';
import '../models/reimbursement.dart';
import '../providers/config_provider.dart';
import '../providers/reimbursements_provider.dart';

// Lets a household record that part of [bill] came back (an insurance
// payout, a store refund, a friend paying back their share directly, etc),
// and shows the running list of those reimbursements against the bill's
// original amount. Balance calculations pick this up on their own (see
// AggregatedCalculationService/Bill.netAmount) - this screen only manages
// the underlying bill_reimbursements rows.
class BillReimbursementsScreen extends StatefulWidget {
  final Bill bill;

  const BillReimbursementsScreen({super.key, required this.bill});

  @override
  State<BillReimbursementsScreen> createState() =>
      _BillReimbursementsScreenState();
}

class _BillReimbursementsScreenState extends State<BillReimbursementsScreen> {
  // Cached in didChangeDependencies rather than looked up via context.read
  // inside dispose(): by the time dispose runs, this element can already be
  // deactivated (e.g. during widget-tree teardown at the end of a test),
  // and walking up to an ancestor provider at that point throws "Looking up
  // a deactivated widget's ancestor is unsafe" - same pattern
  // BillsListScreen uses for _configProvider.
  ReimbursementsProvider? _reimbursementsProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reimbursementsProvider = context.read<ReimbursementsProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final billId = widget.bill.id;
      if (billId != null) {
        _reimbursementsProvider?.loadForBill(billId);
      }
    });
  }

  @override
  void dispose() {
    // Deferred to a microtask rather than called synchronously: reset()
    // calls notifyListeners(), and this provider is registered above both
    // this screen and BillsListScreen, so its InheritedProviderScope tries
    // to rebuild immediately - during a pop transition that lands mid-frame
    // (the tree still locked), throwing "setState()/markNeedsBuild() called
    // when widget tree was locked". A microtask runs after the current
    // frame finishes, once the tree is unlocked again. Safe to call on the
    // provider after this widget is gone - reset() only touches the
    // ChangeNotifier itself, not this element/context.
    //
    // Avoids a stale reimbursement list briefly flashing if this screen (or
    // one for a different bill) is opened again later.
    final provider = _reimbursementsProvider;
    if (provider != null) {
      Future.microtask(provider.reset);
    }
    super.dispose();
  }

  Future<void> _showAddReimbursementSheet(
    BuildContext context,
    double remaining,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();
    final reimbursementsProvider = context.read<ReimbursementsProvider>();
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedReceivedBy = (configProvider.myPersonName?.isNotEmpty ??
            false)
        ? configProvider.myPersonName
        : (configProvider.config.person1Name.isNotEmpty
            ? configProvider.config.person1Name
            : null);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.addReimbursement,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: l10n.amount,
                        prefixText: '\$ ',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        final amount = double.tryParse((value ?? '').trim());
                        if (amount == null || amount <= 0) {
                          return l10n.enterValidAmount;
                        }
                        if (amount > remaining + 0.01) {
                          return l10n.reimbursementExceedsRemaining;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.date),
                      subtitle:
                          Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReceivedBy,
                      decoration: InputDecoration(
                        labelText: l10n.receivedBy,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        if (configProvider.config.person1Name.isNotEmpty)
                          DropdownMenuItem(
                            value: configProvider.config.person1Name,
                            child: Text(configProvider.config.person1Name),
                          ),
                        if (configProvider.config.person2Name.isNotEmpty)
                          DropdownMenuItem(
                            value: configProvider.config.person2Name,
                            child: Text(configProvider.config.person2Name),
                          ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => selectedReceivedBy = value),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.selectWhoReceived
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: noteController,
                      decoration: InputDecoration(
                        labelText: l10n.detailsOptional,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final billId = widget.bill.id;
                        final householdId = configProvider.householdId;
                        if (billId == null || householdId == null) return;

                        final success =
                            await reimbursementsProvider.addReimbursement(
                          Reimbursement(
                            billId: billId,
                            date: selectedDate,
                            amount: double.parse(amountController.text.trim()),
                            receivedBy: selectedReceivedBy!,
                            note: noteController.text.trim(),
                          ),
                          householdId,
                        );

                        if (success) {
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } else if (sheetContext.mounted &&
                            reimbursementsProvider.error != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                                content:
                                    Text(reimbursementsProvider.error!)),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(l10n.saveReimbursement),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteReimbursement(
    BuildContext context,
    Reimbursement reimbursement,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteReimbursement),
        content: Text(l10n.areYouSureDeleteReimbursement),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && reimbursement.id != null && context.mounted) {
      final reimbursementsProvider = context.read<ReimbursementsProvider>();
      final success =
          await reimbursementsProvider.deleteReimbursement(reimbursement.id!);
      if (!success && context.mounted && reimbursementsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reimbursementsProvider.error!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(symbol: '\$');
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Scaffold(
        appBar: AppBar(title: Text(l10n.reimbursements)),
        body: Consumer<ReimbursementsProvider>(
          builder: (context, reimbursementsProvider, child) {
            final totalReimbursed = reimbursementsProvider.totalReimbursed;
            final remaining = widget.bill.amount - totalReimbursed;

            return Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summaryRow(
                          l10n.originalAmount,
                          currencyFormat.format(widget.bill.amount),
                        ),
                        const SizedBox(height: 8),
                        _summaryRow(
                          l10n.totalReimbursed,
                          '-${currencyFormat.format(totalReimbursed)}',
                        ),
                        const Divider(height: 24),
                        _summaryRow(
                          l10n.remainingAmount,
                          currencyFormat.format(remaining),
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: reimbursementsProvider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : reimbursementsProvider.reimbursements.isEmpty
                          ? Center(
                              child: Text(
                                l10n.noReimbursementsYet,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              itemCount:
                                  reimbursementsProvider.reimbursements.length,
                              itemBuilder: (context, index) {
                                final reimbursement = reimbursementsProvider
                                    .reimbursements[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.currency_exchange),
                                    title: Text(currencyFormat
                                        .format(reimbursement.amount)),
                                    subtitle: Text(
                                      [
                                        dateFormat
                                            .format(reimbursement.date),
                                        reimbursement.receivedBy,
                                        if (reimbursement.note.isNotEmpty)
                                          reimbursement.note,
                                      ].join(' · '),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _deleteReimbursement(
                                          context, reimbursement),
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: Consumer<ReimbursementsProvider>(
          builder: (context, reimbursementsProvider, child) {
            final remaining =
                widget.bill.amount - reimbursementsProvider.totalReimbursed;
            if (remaining <= 0.01) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () => _showAddReimbursementSheet(context, remaining),
              icon: const Icon(Icons.add),
              label: Text(l10n.addReimbursement),
            );
          },
        ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
