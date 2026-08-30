import 'package:intl/intl.dart';

// A record of money that came back against part of a bill - an insurance
// payout, a store refund, a friend paying back their share directly, etc.
// See Bill.netAmount for how these reduce a bill's effective cost.
class Reimbursement {
  final String? id;
  final String billId;
  final DateTime date;
  final double amount;
  final String receivedBy;
  final String note;

  Reimbursement({
    this.id,
    required this.billId,
    required this.date,
    required this.amount,
    required this.receivedBy,
    this.note = '',
  });

  // Convert to a Supabase row payload (no id/household_id: assigned by the
  // caller/database).
  Map<String, dynamic> toMap() {
    final dateFormatter = DateFormat('yyyy-MM-dd');
    return {
      'bill_id': billId,
      'date': dateFormatter.format(date),
      'amount': amount,
      'received_by': receivedBy,
      'note': note,
    };
  }

  factory Reimbursement.fromMap(Map<String, dynamic> map) {
    return Reimbursement(
      id: map['id'] as String,
      billId: map['bill_id'] as String,
      date: DateTime.parse(map['date'] as String),
      amount: (map['amount'] as num).toDouble(),
      receivedBy: map['received_by'] as String,
      note: map['note'] as String? ?? '',
    );
  }
}
