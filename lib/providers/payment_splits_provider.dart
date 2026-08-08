import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/payment_split.dart';
import '../models/category.dart' as models;
import '../services/calculation_service.dart' show compareSplitsNewestFirst;
import 'config_provider.dart';

class PaymentSplitsProvider with ChangeNotifier {
  final List<PaymentSplit> _splits = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentSplit> get splits => List.unmodifiable(_splits);
  bool get isLoading => _isLoading;
  String? get error => _error;

  SupabaseClient get _supabase => Supabase.instance.client;

  void _sortSplits() {
    _splits.sort(compareSplitsNewestFirst);
  }

  // Load payment splits for the current household from Supabase
  Future<void> loadPaymentSplits(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('payment_splits')
          .select()
          .eq('household_id', configProvider.householdId!);

      _splits
        ..clear()
        ..addAll(rows.map((row) => PaymentSplit.fromMap(row)));
      _sortSplits();
      _error = null;
    } catch (e) {
      _error = 'Failed to load payment splits: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a payment split
  Future<void> addPaymentSplit(PaymentSplit split,
      ConfigProvider configProvider, List<models.Category> categories) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      _error = 'Not signed in or no household selected';
      notifyListeners();
      return;
    }

    // Validate category exists (unless "all")
    if (split.category != 'all') {
      final categoryExists = categories.any((c) => c.name == split.category);
      if (!categoryExists) {
        _error = 'Category "${split.category}" does not exist';
        notifyListeners();
        return;
      }
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (split.category == 'all') {
        // "all"-category splits are UI-only bulk-edit helpers and are never
        // persisted (the database rejects them via a check constraint,
        // matching the old CsvService behavior of dropping them on save).
        _splits.add(split);
      } else {
        final row = await _supabase
            .from('payment_splits')
            .insert({
              ...split.toMap(),
              'household_id': configProvider.householdId,
            })
            .select()
            .single();
        _splits.add(PaymentSplit.fromMap(row));
      }
      _sortSplits();
      _error = null;
    } catch (e) {
      _error = 'Failed to add payment split: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a payment split
  Future<void> updatePaymentSplit(int index, PaymentSplit updatedSplit,
      ConfigProvider configProvider, List<models.Category> categories) async {
    if (index < 0 || index >= _splits.length) {
      _error = 'Invalid payment split index';
      notifyListeners();
      return;
    }

    // Validate category exists (unless "all")
    if (updatedSplit.category != 'all') {
      final categoryExists =
          categories.any((c) => c.name == updatedSplit.category);
      if (!categoryExists) {
        _error = 'Category "${updatedSplit.category}" does not exist';
        notifyListeners();
        return;
      }
    }

    final existingId = _splits[index].id;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (updatedSplit.category == 'all') {
        // Never persisted - see addPaymentSplit.
        if (existingId != null) {
          await _supabase.from('payment_splits').delete().eq('id', existingId);
        }
        _splits[index] = updatedSplit;
      } else if (existingId == null) {
        // The split being edited was itself an unpersisted "all" split -
        // this edit gives it a real category, so it needs a fresh insert.
        final row = await _supabase
            .from('payment_splits')
            .insert({
              ...updatedSplit.toMap(),
              'household_id': configProvider.householdId,
            })
            .select()
            .single();
        _splits[index] = PaymentSplit.fromMap(row);
      } else {
        final row = await _supabase
            .from('payment_splits')
            .update(updatedSplit.toMap())
            .eq('id', existingId)
            .select()
            .single();
        _splits[index] = PaymentSplit.fromMap(row);
      }
      _sortSplits();
      _error = null;
    } catch (e) {
      _error = 'Failed to update payment split: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a payment split
  Future<void> deletePaymentSplit(
      int index, ConfigProvider configProvider) async {
    if (index < 0 || index >= _splits.length) {
      _error = 'Invalid payment split index';
      notifyListeners();
      return;
    }

    final id = _splits[index].id;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (id != null) {
        await _supabase.from('payment_splits').delete().eq('id', id);
      }
      _splits.removeAt(index);
      _error = null;
    } catch (e) {
      _error = 'Failed to delete payment split: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get payment split by index
  PaymentSplit? getPaymentSplit(int index) {
    if (index < 0 || index >= _splits.length) {
      return null;
    }
    return _splits[index];
  }

  // Remove all payment splits that reference a specific category
  // This is called when a category is deleted
  Future<void> removeSplitsByCategory(
      String categoryName, ConfigProvider configProvider) async {
    if (configProvider.householdId == null) return;

    final categoryLower = categoryName.toLowerCase().trim();
    final removedIds = <String>{};
    _splits.removeWhere((split) {
      final matches = split.category.toLowerCase().trim() == categoryLower;
      if (matches && split.id != null) {
        removedIds.add(split.id!);
      }
      return matches;
    });

    if (removedIds.isEmpty) return;

    try {
      await _supabase
          .from('payment_splits')
          .delete()
          .eq('household_id', configProvider.householdId!)
          .inFilter('id', removedIds.toList());
      _error = null;
    } catch (e) {
      _error = 'Failed to remove payment splits for deleted category: $e';
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
