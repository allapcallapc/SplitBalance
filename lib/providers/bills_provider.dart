import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../services/csv_service.dart';
import 'config_provider.dart';

class BillsProvider with ChangeNotifier {
  final List<Bill> _bills = [];
  bool _isLoading = false;
  String? _error;

  List<Bill> get bills => List.unmodifiable(_bills);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load bills from Google Drive
  Future<void> loadBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = await configProvider.driveService.downloadBills();
      if (csvContent.isEmpty) {
        _bills.clear();
        _isLoading = false;
        notifyListeners();
        return;
      }

      _bills.clear();
      _bills.addAll(CsvService.billsFromCsv(csvContent));
      // Sort by date (newest first)
      _bills.sort((a, b) => b.date.compareTo(a.date));
      _error = null;
    } catch (e) {
      _error = 'Failed to load bills: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save bills to Google Drive
  Future<void> saveBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      _error = 'Not signed in or folder not set';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = CsvService.billsToCsv(_bills);
      await configProvider.driveService.uploadBills(csvContent);
      _error = null;
    } catch (e) {
      _error = 'Failed to save bills: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a bill
  Future<void> addBill(Bill bill, ConfigProvider configProvider) async {
    _bills.add(bill);
    // Sort by date (newest first)
    _bills.sort((a, b) => b.date.compareTo(a.date));
    await saveBills(configProvider);
  }

  // Update a bill
  Future<void> updateBill(int index, Bill updatedBill, ConfigProvider configProvider) async {
    if (index < 0 || index >= _bills.length) {
      _error = 'Invalid bill index';
      notifyListeners();
      return;
    }

    _bills[index] = updatedBill;
    // Sort by date (newest first)
    _bills.sort((a, b) => b.date.compareTo(a.date));
    await saveBills(configProvider);
  }

  // Delete a bill
  Future<void> deleteBill(int index, ConfigProvider configProvider) async {
    if (index < 0 || index >= _bills.length) {
      _error = 'Invalid bill index';
      notifyListeners();
      return;
    }

    _bills.removeAt(index);
    await saveBills(configProvider);
  }

  // Get bill by index
  Bill? getBill(int index) {
    if (index < 0 || index >= _bills.length) {
      return null;
    }
    return _bills[index];
  }

  // Filter bills
  List<Bill> filterBills({
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? paidBy,
  }) {
    return _bills.where((bill) {
      if (startDate != null && bill.date.isBefore(startDate)) {
        return false;
      }
      if (endDate != null && bill.date.isAfter(endDate)) {
        return false;
      }
      if (category != null && category.isNotEmpty && bill.category != category) {
        return false;
      }
      if (paidBy != null && paidBy.isNotEmpty && bill.paidBy != paidBy) {
        return false;
      }
      return true;
    }).toList();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
