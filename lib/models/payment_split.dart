import 'package:intl/intl.dart';

class PaymentSplit {
  final DateTime startDate;
  final DateTime endDate;
  final String category; // "all" for default or specific category name
  final String person1;
  final double person1Percentage;
  final String person2;
  final double person2Percentage;

  PaymentSplit({
    required this.startDate,
    required this.endDate,
    required this.category,
    required this.person1,
    required this.person1Percentage,
    required this.person2,
    required this.person2Percentage,
  }) {
    // Validate dates
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date must be after start date');
    }
    // Validate percentages
    final total = person1Percentage + person2Percentage;
    if ((total - 100.0).abs() > 0.01) {
      throw ArgumentError('Percentages must sum to 100 (currently $total)');
    }
    if (person1Percentage < 0 || person1Percentage > 100) {
      throw ArgumentError('Person1 percentage must be between 0 and 100');
    }
    if (person2Percentage < 0 || person2Percentage > 100) {
      throw ArgumentError('Person2 percentage must be between 0 and 100');
    }
  }

  // Convert to CSV row
  List<String> toCsvRow() {
    final dateFormatter = DateFormat('yyyy-MM-dd');
    return [
      dateFormatter.format(startDate),
      dateFormatter.format(endDate),
      category,
      person1,
      person1Percentage.toStringAsFixed(2),
      person2,
      person2Percentage.toStringAsFixed(2),
    ];
  }

  // Create from CSV row
  factory PaymentSplit.fromCsvRow(List<String> row) {
    if (row.length < 7) {
      throw const FormatException('PaymentSplit CSV row must have 7 columns');
    }

    final dateFormatter = DateFormat('yyyy-MM-dd');
    DateTime startDate;
    DateTime endDate;
    
    try {
      startDate = dateFormatter.parse(row[0].trim());
    } catch (e) {
      throw FormatException('Invalid start date format: ${row[0]}');
    }

    try {
      endDate = dateFormatter.parse(row[1].trim());
    } catch (e) {
      throw FormatException('Invalid end date format: ${row[1]}');
    }

    double person1Percentage;
    double person2Percentage;
    
    try {
      person1Percentage = double.parse(row[4].trim());
    } catch (e) {
      throw FormatException('Invalid person1Percentage format: ${row[4]}');
    }

    try {
      person2Percentage = double.parse(row[6].trim());
    } catch (e) {
      throw FormatException('Invalid person2Percentage format: ${row[6]}');
    }

    return PaymentSplit(
      startDate: startDate,
      endDate: endDate,
      category: row[2].trim(),
      person1: row[3].trim(),
      person1Percentage: person1Percentage,
      person2: row[5].trim(),
      person2Percentage: person2Percentage,
    );
  }

  // CSV header
  static List<String> csvHeader() {
    return [
      'startDate',
      'endDate',
      'category',
      'person1',
      'person1Percentage',
      'person2',
      'person2Percentage'
    ];
  }

  // Check if a date falls within this split's range
  bool containsDate(DateTime date) {
    return date.isAfter(startDate.subtract(const Duration(days: 1))) &&
        date.isBefore(endDate.add(const Duration(days: 1)));
  }

  // Check if this split applies to a category
  bool appliesToCategory(String billCategory) {
    return category == 'all' || category == billCategory;
  }

  PaymentSplit copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? person1,
    double? person1Percentage,
    String? person2,
    double? person2Percentage,
  }) {
    return PaymentSplit(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      category: category ?? this.category,
      person1: person1 ?? this.person1,
      person1Percentage: person1Percentage ?? this.person1Percentage,
      person2: person2 ?? this.person2,
      person2Percentage: person2Percentage ?? this.person2Percentage,
    );
  }
}
