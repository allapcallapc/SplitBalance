import 'package:intl/intl.dart';

class Bill {
  final DateTime date;
  final double amount;
  final String paidBy;
  final String category;
  final String details;

  Bill({
    required this.date,
    required this.amount,
    required this.paidBy,
    required this.category,
    this.details = '',
  });

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
    DateTime? date,
    double? amount,
    String? paidBy,
    String? category,
    String? details,
  }) {
    return Bill(
      date: date ?? this.date,
      amount: amount ?? this.amount,
      paidBy: paidBy ?? this.paidBy,
      category: category ?? this.category,
      details: details ?? this.details,
    );
  }
}
