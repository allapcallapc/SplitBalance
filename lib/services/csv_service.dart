import 'package:csv/csv.dart';
import '../models/bill.dart';
import '../models/payment_split.dart';
import '../models/category.dart';

class CsvService {
  // Serialize bills to CSV string
  static String billsToCsv(List<Bill> bills) {
    final rows = <List<String>>[];
    rows.add(Bill.csvHeader());
    rows.addAll(bills.map((bill) => bill.toCsvRow()));
    
    return const ListToCsvConverter().convert(rows);
  }

  // Parse bills from CSV string
  static List<Bill> billsFromCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return [];
    }
    
    // Auto-detect delimiter: check if first line contains semicolons
    final firstLine = csvContent.split('\n').first.trim();
    final fieldDelimiter = firstLine.contains(';') ? ';' : ',';
    
    final converter = CsvToListConverter(fieldDelimiter: fieldDelimiter);
    final rows = converter.convert(csvContent);
    
    if (rows.isEmpty) {
      return [];
    }
    
    // Skip header row if present
    final startIndex = _isHeader(rows[0].cast<String>(), Bill.csvHeader()) ? 1 : 0;
    
    final bills = <Bill>[];
    for (var i = startIndex; i < rows.length; i++) {
      try {
        final bill = Bill.fromCsvRow(rows[i].map((e) => e.toString()).toList());
        bills.add(bill);
      } catch (e) {
        // Skip invalid rows, could log error in production
        continue;
      }
    }
    
    return bills;
  }

  // Serialize payment splits to CSV string
  // Note: "all" category splits are not saved - they're UI-only for bulk changes
  static String paymentSplitsToCsv(List<PaymentSplit> splits) {
    final rows = <List<String>>[];
    rows.add(PaymentSplit.csvHeader());
    // Filter out "all" category splits - they're not persisted
    final splitsToSave = splits.where((split) => split.category != 'all').toList();
    rows.addAll(splitsToSave.map((split) => split.toCsvRow()));
    
    return const ListToCsvConverter().convert(rows);
  }

  // Parse payment splits from CSV string
  static List<PaymentSplit> paymentSplitsFromCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return [];
    }
    
    // Auto-detect delimiter: check if first line contains semicolons
    final firstLine = csvContent.split('\n').first.trim();
    final fieldDelimiter = firstLine.contains(';') ? ';' : ',';
    
    final converter = CsvToListConverter(fieldDelimiter: fieldDelimiter);
    final rows = converter.convert(csvContent);
    
    if (rows.isEmpty) {
      return [];
    }
    
    // Skip header row if present
    final startIndex = _isHeader(rows[0].cast<String>(), PaymentSplit.csvHeader()) ? 1 : 0;
    
    final splits = <PaymentSplit>[];
    for (var i = startIndex; i < rows.length; i++) {
      try {
        final split = PaymentSplit.fromCsvRow(rows[i].map((e) => e.toString()).toList());
        splits.add(split);
      } catch (e) {
        // Skip invalid rows, could log error in production
        continue;
      }
    }
    
    return splits;
  }

  // Serialize categories to CSV string
  static String categoriesToCsv(List<Category> categories) {
    final rows = <List<String>>[];
    rows.add(Category.csvHeader());
    rows.addAll(categories.map((category) => category.toCsvRow()));
    
    return const ListToCsvConverter().convert(rows);
  }

  // Parse categories from CSV string
  static List<Category> categoriesFromCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return [];
    }
    
    // Auto-detect delimiter: check if first line contains semicolons
    final firstLine = csvContent.split('\n').first.trim();
    final fieldDelimiter = firstLine.contains(';') ? ';' : ',';
    
    final converter = CsvToListConverter(fieldDelimiter: fieldDelimiter);
    final rows = converter.convert(csvContent);
    
    if (rows.isEmpty) {
      return [];
    }
    
    // Skip header row if present
    final startIndex = _isHeader(rows[0].cast<String>(), Category.csvHeader()) ? 1 : 0;
    
    final categories = <Category>[];
    for (var i = startIndex; i < rows.length; i++) {
      try {
        final category = Category.fromCsvRow(rows[i].map((e) => e.toString()).toList());
        categories.add(category);
      } catch (e) {
        // Skip invalid rows, could log error in production
        continue;
      }
    }
    
    return categories;
  }

  // Serialize person names to CSV string
  static String personNamesToCsv(String person1Name, String person2Name) {
    final rows = <List<String>>[];
    rows.add(['person1Name', 'person2Name']); // Header
    rows.add([person1Name, person2Name]); // Data row
    
    return const ListToCsvConverter().convert(rows);
  }

  // Parse person names from CSV string
  static Map<String, String> personNamesFromCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return {'person1Name': '', 'person2Name': ''};
    }
    
    // Auto-detect delimiter: check if first line contains semicolons
    final firstLine = csvContent.split('\n').first.trim();
    final fieldDelimiter = firstLine.contains(';') ? ';' : ',';
    
    final converter = CsvToListConverter(fieldDelimiter: fieldDelimiter);
    final rows = converter.convert(csvContent);
    
    if (rows.isEmpty) {
      return {'person1Name': '', 'person2Name': ''};
    }
    
    // Skip header row if present
    final startIndex = rows.isNotEmpty && 
                       rows[0].length >= 2 && 
                       rows[0][0].toString().toLowerCase() == 'person1name' ? 1 : 0;
    
    if (rows.length <= startIndex) {
      return {'person1Name': '', 'person2Name': ''};
    }
    
    try {
      final row = rows[startIndex];
      final person1Name = row.length > 0 ? row[0].toString().trim() : '';
      final person2Name = row.length > 1 ? row[1].toString().trim() : '';
      
      return {
        'person1Name': person1Name,
        'person2Name': person2Name,
      };
    } catch (e) {
      print('Error parsing person names CSV: $e');
      return {'person1Name': '', 'person2Name': ''};
    }
  }

  // Helper to check if a row is a header
  static bool _isHeader(List<String> row, List<String> header) {
    if (row.length != header.length) return false;
    for (var i = 0; i < row.length; i++) {
      if (row[i].toLowerCase() != header[i].toLowerCase()) {
        return false;
      }
    }
    return true;
  }
}
