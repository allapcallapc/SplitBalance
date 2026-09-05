import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/bill.dart';
import '../models/recovered_amount.dart';
import '../providers/config_provider.dart';
import '../providers/recovered_amounts_provider.dart';

// Lets a household record that part of [bill] came back (an insurance
// payout, a store refund, a friend or outside party paying back their share
// directly, etc), and shows the running list of those recovered amounts
// against the bill's original amount. Balance calculations pick this up on
// their own (see AggregatedCalculationService/Bill.netAmount) - this screen
// only manages the underlying bill_recovered_amounts rows.
class BillRecoveredAmountsScreen extends StatefulWidget {
  final Bill bill;

  const BillRecoveredAmountsScreen({super.key, required this.bill});

  @override
  State<BillRecoveredAmountsScreen> createState() =>
      _BillRecoveredAmountsScreenState();
}

class _BillRecoveredAmountsScreenState
    extends State<BillRecoveredAmountsScreen> {
  // Cached in didChangeDependencies rather than looked up via context.read
  // inside dispose(): by the time dispose runs, this element can already be
  // deactivated (e.g. during widget-tree teardown at the end of a test),
  // and walking up to an ancestor provider at that point throws "Looking up
  // a deactivated widget's ancestor is unsafe" - same pattern
  // BillsListScreen uses for _configProvider.
  RecoveredAmountsProvider? _recoveredAmountsProvider;

  // True until loadForBill for this bill has actually been kicked off.
  // initState defers that call to a post-frame callback (see below), so the
  // very first build happens before RecoveredAmountsProvider.isLoading ever
  // goes true - at that point totalRecovered still reads its pre-load value
  // of 0 (or a stale value left over from whatever bill this shared provider
  // last loaded), which would let the FAB compute a `remaining` larger than
  // the bill's true remaining amount and open the add sheet with a validator
  // that accepts an over-recovering amount. Flips to false in the same
  // synchronous stretch that starts the real load (loadForBill sets
  // isLoading true before its first await), so there's no gap between this
  // and isLoading taking over as the source of truth.
  bool _initialLoadPending = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recoveredAmountsProvider = context.read<RecoveredAmountsProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final billId = widget.bill.id;
      if (billId != null) {
        _recoveredAmountsProvider?.loadForBill(billId);
      }
      if (mounted) {
        setState(() => _initialLoadPending = false);
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
    // Avoids a stale recovered-amounts list briefly flashing if this screen
    // (or one for a different bill) is opened again later.
    final provider = _recoveredAmountsProvider;
    if (provider != null) {
      Future.microtask(provider.reset);
    }
    super.dispose();
  }

  Future<void> _showAddRecoveredAmountSheet(
    BuildContext context,
    double remaining,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();
    final recoveredAmountsProvider = context.read<RecoveredAmountsProvider>();
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    // Defaults to whoever paid the bill - the common case is that they're
    // also the one who gets the money back (a store refund, an insurance
    // payout on their own outlay, etc). Falls back to the signed-in
    // member's own name, then person1Name, only if the bill's payer no
    // longer matches either configured household member (e.g. a rename
    // since the bill was recorded).
    final billPayerIsConfigured =
        widget.bill.paidBy == configProvider.config.person1Name ||
            widget.bill.paidBy == configProvider.config.person2Name;
    String? selectedReceivedBy = billPayerIsConfigured
        ? widget.bill.paidBy
        : (configProvider.myPersonName?.isNotEmpty ?? false)
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
                      l10n.addRecoveredAmount,
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
                          return l10n.recoveredAmountExceedsRemaining;
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

                        final success = await recoveredAmountsProvider
                            .addRecoveredAmount(
                          RecoveredAmount(
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
                            recoveredAmountsProvider.error != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                                content: Text(
                                    recoveredAmountsProvider.error!)),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(l10n.saveRecoveredAmount),
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

  Future<void> _deleteRecoveredAmount(
    BuildContext context,
    RecoveredAmount recoveredAmount,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteRecoveredAmount),
        content: Text(l10n.areYouSureDeleteRecoveredAmount),
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

    if (confirmed == true && recoveredAmount.id != null && context.mounted) {
      final recoveredAmountsProvider =
          context.read<RecoveredAmountsProvider>();
      final success = await recoveredAmountsProvider
          .deleteRecoveredAmount(recoveredAmount.id!);
      if (!success &&
          context.mounted &&
          recoveredAmountsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(recoveredAmountsProvider.error!)),
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
        appBar: AppBar(title: Text(l10n.recoveredAmounts)),
        body: Consumer<RecoveredAmountsProvider>(
          builder: (context, recoveredAmountsProvider, child) {
            final isLoading =
                _initialLoadPending || recoveredAmountsProvider.isLoading;
            final totalRecovered = recoveredAmountsProvider.totalRecovered;
            final remaining = widget.bill.amount - totalRecovered;

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
                          l10n.totalRecovered,
                          '-${currencyFormat.format(totalRecovered)}',
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
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : recoveredAmountsProvider.recoveredAmounts.isEmpty
                          ? Center(
                              child: Text(
                                l10n.noRecoveredAmountsYet,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              itemCount: recoveredAmountsProvider
                                  .recoveredAmounts.length,
                              itemBuilder: (context, index) {
                                final recoveredAmount =
                                    recoveredAmountsProvider
                                        .recoveredAmounts[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(
                                        Icons.currency_exchange),
                                    title: Text(currencyFormat
                                        .format(recoveredAmount.amount)),
                                    subtitle: Text(
                                      [
                                        dateFormat
                                            .format(recoveredAmount.date),
                                        recoveredAmount.receivedBy,
                                        if (recoveredAmount.note.isNotEmpty)
                                          recoveredAmount.note,
                                      ].join(' · '),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _deleteRecoveredAmount(
                                              context, recoveredAmount),
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
        floatingActionButton: Consumer<RecoveredAmountsProvider>(
          builder: (context, recoveredAmountsProvider, child) {
            // Hidden until the real recovered-amounts total has loaded -
            // see _initialLoadPending's doc comment for why this matters.
            if (_initialLoadPending || recoveredAmountsProvider.isLoading) {
              return const SizedBox.shrink();
            }
            final remaining = widget.bill.amount -
                recoveredAmountsProvider.totalRecovered;
            if (remaining <= 0.01) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              onPressed: () =>
                  _showAddRecoveredAmountSheet(context, remaining),
              icon: const Icon(Icons.add),
              label: Text(l10n.addRecoveredAmount),
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
