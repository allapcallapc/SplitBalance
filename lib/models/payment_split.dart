import 'package:intl/intl.dart';

class PaymentSplit {
  final DateTime? endDate; // null means bills after the last end date
  final String category; // "all" for default or specific category name
  final String person1;
  final double person1Percentage;
  final String person2;
  final double person2Percentage;

  PaymentSplit({
    this.endDate,
    required this.category,
    required this.person1,
    required this.person1Percentage,
    required this.person2,
    required this.person2Percentage,
  }) {
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
      endDate != null ? dateFormatter.format(endDate!) : '',
      category,
      person1,
      person1Percentage.toStringAsFixed(2),
      person2,
      person2Percentage.toStringAsFixed(2),
    ];
  }

  // Create from CSV row
  factory PaymentSplit.fromCsvRow(List<String> row) {
    // Support both old format (7 columns with startDate) and new format (6 columns without startDate)
    if (row.length < 6) {
      throw const FormatException('PaymentSplit CSV row must have at least 6 columns');
    }

    final dateFormatter = DateFormat('yyyy-MM-dd');
    DateTime? endDate;
    
    // Try to parse end date - if empty/null, endDate remains null
    final endDateStr = row[0].trim();
    if (endDateStr.isNotEmpty) {
      try {
        endDate = dateFormatter.parse(endDateStr);
      } catch (e) {
        throw FormatException('Invalid end date format: ${row[0]}');
      }
    }

    // Determine column indices based on row length (old format has 7 columns, new has 6)
    int categoryIndex, person1Index, person1PercentIndex, person2Index, person2PercentIndex;
    if (row.length >= 7) {
      // Old format: startDate, endDate, category, person1, person1Percentage, person2, person2Percentage
      categoryIndex = 2;
      person1Index = 3;
      person1PercentIndex = 4;
      person2Index = 5;
      person2PercentIndex = 6;
      // Also parse endDate from column 1 if not already set
      if (endDate == null && row[1].trim().isNotEmpty) {
        try {
          endDate = dateFormatter.parse(row[1].trim());
        } catch (e) {
          // Ignore if invalid
        }
      }
    } else {
      // New format: endDate, category, person1, person1Percentage, person2, person2Percentage
      categoryIndex = 1;
      person1Index = 2;
      person1PercentIndex = 3;
      person2Index = 4;
      person2PercentIndex = 5;
    }

    double person1Percentage;
    double person2Percentage;
    
    try {
      person1Percentage = double.parse(row[person1PercentIndex].trim());
    } catch (e) {
      throw FormatException('Invalid person1Percentage format: ${row[person1PercentIndex]}');
    }

    try {
      person2Percentage = double.parse(row[person2PercentIndex].trim());
    } catch (e) {
      throw FormatException('Invalid person2Percentage format: ${row[person2PercentIndex]}');
    }

    return PaymentSplit(
      endDate: endDate,
      category: row[categoryIndex].trim(),
      person1: row[person1Index].trim(),
      person1Percentage: person1Percentage,
      person2: row[person2Index].trim(),
      person2Percentage: person2Percentage,
    );
  }

  // CSV header
  static List<String> csvHeader() {
    return [
      'endDate',
      'category',
      'person1',
      'person1Percentage',
      'person2',
      'person2Percentage'
    ];
  }

  // Check if a date falls within this split's range
  // If endDate is null, this means it applies to dates after the last defined endDate
  // This method should be called with the list of all endDates sorted to determine the correct range
  bool containsDate(DateTime date, List<DateTime> allEndDates) {
    if (endDate == null) {
      // Empty end date means it applies to dates after the last end date
      if (allEndDates.isEmpty) {
        return true; // If no other end dates, this applies to all dates
      }
      final lastEndDate = allEndDates.reduce((a, b) => a.isAfter(b) ? a : b);
      return date.isAfter(lastEndDate);
    } else {
      // Find the previous end date to determine the range
      final sortedEndDates = [...allEndDates]..sort();
      final thisEndDateIndex = sortedEndDates.indexOf(endDate!);
      if (thisEndDateIndex == -1) {
        // This end date not in list, shouldn't happen
        return false;
      }
      
      DateTime? startOfRange;
      if (thisEndDateIndex > 0) {
        // Range starts after the previous end date
        startOfRange = sortedEndDates[thisEndDateIndex - 1];
      } else {
        // This is the earliest end date, starts from beginning
        startOfRange = null;
      }
      
      final isAfterStart = startOfRange == null || date.isAfter(startOfRange);
      final isOnOrBeforeEnd = date.isBefore(endDate!.add(const Duration(days: 1))) ||
                              date.isAtSameMomentAs(endDate!.add(const Duration(days: 1)));
      
      return isAfterStart && isOnOrBeforeEnd;
    }
  }
  
  // Legacy method for backward compatibility - use containsDate(date, allEndDates) instead
  @Deprecated('Use containsDate(DateTime date, List<DateTime> allEndDates) instead')
  bool containsDateLegacy(DateTime date) {
    if (endDate == null) {
      return false;
    }
    // For legacy compatibility, assume range starts from a very early date
    return date.isBefore(endDate!.add(const Duration(days: 1)));
  }

  // Check if this split applies to a category
  bool appliesToCategory(String billCategory) {
    return category == 'all' || category == billCategory;
  }

  PaymentSplit copyWith({
    DateTime? endDate,
    String? category,
    String? person1,
    double? person1Percentage,
    String? person2,
    double? person2Percentage,
  }) {
    return PaymentSplit(
      endDate: endDate ?? this.endDate,
      category: category ?? this.category,
      person1: person1 ?? this.person1,
      person1Percentage: person1Percentage ?? this.person1Percentage,
      person2: person2 ?? this.person2,
      person2Percentage: person2Percentage ?? this.person2Percentage,
    );
  }
}
