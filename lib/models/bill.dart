import 'package:intl/intl.dart';

class Bill {
  final String? id;
  final DateTime date;
  final double amount;
  final String paidBy;
  final String category;
  final String details;
  // Sum of this bill's recovered amounts (see RecoveredAmount) - not a
  // `bills` table column, so it's always 0 unless the caller explicitly
  // populated it (e.g. BillsProvider merges in a live sum after loading
  // bill rows). A single scalar with no per-receiver breakdown, so anything
  // computed from it (netAmount, CalculationService's balance math) always
  // nets the reduction against this bill's own paidBy - it can't know that
  // the money was received by the other person instead. Only
  // AggregatedCalculationService, which queries
  // bill_recovered_amounts.received_by directly, gets that case right (see
  // its calculateBalances doc comment).
  final double recoveredAmount;
  // Per-receiver breakdown of this bill's recovered amounts (receivedBy ->
  // total) - unlike [recoveredAmount], which always nets against [paidBy]
  // regardless of who actually received the money. Needed for spend-chart
  // attribution (see computeMonthlySpend), which - like
  // AggregatedCalculationService, and unlike [netAmount]/[recoveredAmount]
  // - has to credit the reduction to the actual receiver. Not a `bills`
  // column; populated the same way [recoveredAmount] is (see
  // BillsProvider._withRecoveredTotals).
  final Map<String, double> recoveredByReceiver;

  Bill({
    this.id,
    required this.date,
    required this.amount,
    required this.paidBy,
    required this.category,
    this.details = '',
    this.recoveredAmount = 0,
    this.recoveredByReceiver = const {},
  });

  // What this bill "really" cost after subtracting anything recovered
  // against it - what balance/spend calculations should use instead of
  // [amount].
  double get netAmount => amount - recoveredAmount;

  // Convert to a Supabase row payload (no id: assigned by the database)
  Map<String, dynamic> toMap() {
    final dateFormatter = DateFormat('yyyy-MM-dd');
    return {
      'date': dateFormatter.format(date),
      'amount': amount,
      'paid_by': paidBy,
      'category': category,
      'details': details,
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      amount: (map['amount'] as num).toDouble(),
      paidBy: map['paid_by'] as String,
      category: map['category'] as String,
      details: map['details'] as String? ?? '',
      // Not a real `bills` column - only present when the caller injected it
      // into the row map (see BillsProvider's recovered-totals merge).
      recoveredAmount: (map['recovered_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  // Convert to CSV row
  List<String> toCsvRow() {
    final dateFormatter = DateFormat('yyyy-MM-dd');
    return [
      dateFormatter.format(date),
      amount.toStringAsFixed(2),
      paidBy,
      category,
      details,
    ];
  }

  // Create from CSV row
  factory Bill.fromCsvRow(List<String> row) {
    if (row.length < 4) {
      throw const FormatException('Bill CSV row must have at least 4 columns');
    }

    final dateFormatter = DateFormat('yyyy-MM-dd');
    DateTime date;
    try {
      date = dateFormatter.parse(row[0].trim());
    } catch (e) {
      throw FormatException('Invalid date format: ${row[0]}');
    }

    double amount;
    try {
      amount = double.parse(row[1].trim());
    } catch (e) {
      throw FormatException('Invalid amount format: ${row[1]}');
    }

    return Bill(
      date: date,
      amount: amount,
      paidBy: row[2].trim(),
      category: row[3].trim(),
      details: row.length > 4 ? row[4].trim() : '',
    );
  }

  // CSV header
  static List<String> csvHeader() {
    return ['date', 'amount', 'paidBy', 'category', 'details'];
  }

  Bill copyWith({
    String? id,
    DateTime? date,
    double? amount,
    String? paidBy,
    String? category,
    String? details,
    double? recoveredAmount,
    Map<String, double>? recoveredByReceiver,
  }) {
    return Bill(
      id: id ?? this.id,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      paidBy: paidBy ?? this.paidBy,
      category: category ?? this.category,
      details: details ?? this.details,
      recoveredAmount: recoveredAmount ?? this.recoveredAmount,
      recoveredByReceiver: recoveredByReceiver ?? this.recoveredByReceiver,
    );
  }
}
