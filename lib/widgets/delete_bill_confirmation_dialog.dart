import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/bill.dart';

// Shared "Delete Bill?" confirmation dialog used by both BillsListScreen and
// DuplicateBillsScreen, so their delete-confirmation copy/styling can't drift
// out of lockstep the way two independently-maintained AlertDialogs would.
Future<bool?> confirmDeleteBill(BuildContext context, Bill bill) {
  final l10n = AppLocalizations.of(context)!;
  final dateFormat = DateFormat('yyyy-MM-dd');
  return showDialog<bool>(
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
}
