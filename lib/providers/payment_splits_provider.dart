import 'package:flutter/foundation.dart';
import '../models/payment_split.dart';
import '../models/category.dart' as models;
import '../services/csv_service.dart';
import 'config_provider.dart';

class PaymentSplitsProvider with ChangeNotifier {
  final List<PaymentSplit> _splits = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentSplit> get splits => List.unmodifiable(_splits);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load payment splits from Google Drive
  Future<void> loadPaymentSplits(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = await configProvider.driveService.downloadPaymentSplits();
      if (csvContent.isEmpty) {
        _splits.clear();
        _isLoading = false;
        notifyListeners();
        return;
      }

      _splits.clear();
      _splits.addAll(CsvService.paymentSplitsFromCsv(csvContent));
      // Sort by start date (newest first)
      _splits.sort((a, b) => b.startDate.compareTo(a.startDate));
      _error = null;
    } catch (e) {
      _error = 'Failed to load payment splits: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save payment splits to Google Drive
  Future<void> savePaymentSplits(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      _error = 'Not signed in or folder not set';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = CsvService.paymentSplitsToCsv(_splits);
      await configProvider.driveService.uploadPaymentSplits(csvContent);
      _error = null;
    } catch (e) {
      _error = 'Failed to save payment splits: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a payment split
  Future<void> addPaymentSplit(PaymentSplit split, ConfigProvider configProvider, List<models.Category> categories) async {
    // Validate category exists (unless "all")
    if (split.category != 'all') {
      final categoryExists = categories.any((c) => c.name == split.category);
      if (!categoryExists) {
        _error = 'Category "${split.category}" does not exist';
        notifyListeners();
        return;
      }
    }

    // Check for overlapping date ranges with same category (optional validation)
    // This is a soft validation - we allow overlaps but warn user

    try {
      _splits.add(split);
      // Sort by start date (newest first)
      _splits.sort((a, b) => b.startDate.compareTo(a.startDate));
      await savePaymentSplits(configProvider);
      _error = null;
    } catch (e) {
      _error = 'Failed to add payment split: $e';
      notifyListeners();
    }
  }

  // Update a payment split
  Future<void> updatePaymentSplit(int index, PaymentSplit updatedSplit, ConfigProvider configProvider, List<models.Category> categories) async {
    if (index < 0 || index >= _splits.length) {
      _error = 'Invalid payment split index';
      notifyListeners();
      return;
    }

    // Validate category exists (unless "all")
    if (updatedSplit.category != 'all') {
      final categoryExists = categories.any((c) => c.name == updatedSplit.category);
      if (!categoryExists) {
        _error = 'Category "${updatedSplit.category}" does not exist';
        notifyListeners();
        return;
      }
    }

    try {
      _splits[index] = updatedSplit;
      // Sort by start date (newest first)
      _splits.sort((a, b) => b.startDate.compareTo(a.startDate));
      await savePaymentSplits(configProvider);
      _error = null;
    } catch (e) {
      _error = 'Failed to update payment split: $e';
      notifyListeners();
    }
  }

  // Delete a payment split
  Future<void> deletePaymentSplit(int index, ConfigProvider configProvider) async {
    if (index < 0 || index >= _splits.length) {
      _error = 'Invalid payment split index';
      notifyListeners();
      return;
    }

    _splits.removeAt(index);
    await savePaymentSplits(configProvider);
  }

  // Get payment split by index
  PaymentSplit? getPaymentSplit(int index) {
    if (index < 0 || index >= _splits.length) {
      return null;
    }
    return _splits[index];
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
