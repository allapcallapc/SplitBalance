import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/pending_payment.dart';
import '../providers/pending_payments_provider.dart';
import '../widgets/app_bar_action_icon_button.dart';
import 'add_edit_bill_screen.dart';

class PendingPaymentsScreen extends StatefulWidget {
  // When set, shows only this single pending payment instead of the full
  // list — used by the "See more" action on a pending-bill notification so
  // it opens straight to that detection's detail rather than the whole list.
  final String? focusedId;

  const PendingPaymentsScreen({super.key, this.focusedId});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PendingPaymentsProvider>().loadPending();
    });
  }

  Future<void> _addAsBill(PendingPayment payment) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditBillScreen(
          prefillAmount: payment.parsedAmount,
          prefillDetails: payment.rawText,
        ),
      ),
    );

    if (result == true && mounted) {
      await context.read<PendingPaymentsProvider>().dismiss(payment.id);
      if (widget.focusedId != null && mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _dismiss(PendingPayment payment) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dismissPendingPaymentTitle),
        content: Text(l10n.dismissPendingPaymentMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.dismiss),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<PendingPaymentsProvider>().dismiss(payment.id);
      if (widget.focusedId != null && mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pendingPayments),
        actions: [
          AppBarActionIconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<PendingPaymentsProvider>().loadPending(),
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: Consumer<PendingPaymentsProvider>(
        builder: (context, pendingPaymentsProvider, child) {
          if (pendingPaymentsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final pending = widget.focusedId != null
              ? pendingPaymentsProvider.pendingPayments
                  .where((p) => p.id == widget.focusedId)
                  .toList()
              : pendingPaymentsProvider.pendingPayments;

          if (pending.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noPendingPayments,
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.noPendingPaymentsMessage,
                      style: const TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
          final currencyFormat = NumberFormat.currency(symbol: '\$');

          return ListView.builder(
            itemCount: pending.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final payment = pending[index];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.payments_outlined),
                          const SizedBox(width: 8),
                          Text(
                            payment.parsedAmount != null
                                ? currencyFormat.format(payment.parsedAmount)
                                : '—',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${l10n.detectedAt}: ${dateFormat.format(payment.detectedAt)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.rawNotificationText}: ${payment.rawText}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _dismiss(payment),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                            child: Text(l10n.dismiss),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => _addAsBill(payment),
                            child: Text(l10n.addAsBill),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
