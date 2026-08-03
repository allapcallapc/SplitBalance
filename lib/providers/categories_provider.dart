import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart' as models;
import '../models/bill.dart';
import '../models/payment_split.dart';
import 'config_provider.dart';

class CategoriesProvider with ChangeNotifier {
  final List<models.Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  List<models.Category> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;
  String? get error => _error;

  SupabaseClient get _supabase => Supabase.instance.client;

  // Load categories for the current household from Supabase
  Future<void> loadCategories(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    // Prevent multiple simultaneous calls
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('categories')
          .select()
          .eq('household_id', configProvider.householdId!)
          .order('name', ascending: true);

      _categories
        ..clear()
        ..addAll(rows.map((row) => models.Category.fromMap(row)));
      _error = null;
    } catch (e) {
      _error = 'Failed to load categories: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a category
  Future<void> addCategory(
      models.Category category, ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      _error = 'Not signed in or no household selected';
      notifyListeners();
      return;
    }

    // Check if category already exists (case-insensitive), matching the
    // household_id + lower(name) unique index in the database.
    if (_categories
        .any((c) => c.name.toLowerCase() == category.name.toLowerCase())) {
      _error = 'Category "${category.name}" already exists';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _supabase
          .from('categories')
          .insert({
            ...category.toMap(),
            'household_id': configProvider.householdId,
          })
          .select()
          .single();

      _categories.add(models.Category.fromMap(row));
      _categories.sort((a, b) => a.name.compareTo(b.name));
      _error = null;
    } catch (e) {
      _error = 'Failed to add category: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a category
  Future<void> updateCategory(int index, models.Category newCategory,
      ConfigProvider configProvider) async {
    if (index < 0 || index >= _categories.length) {
      _error = 'Invalid category index';
      notifyListeners();
      return;
    }

    final oldCategory = _categories[index];
    if (oldCategory.id == null) {
      _error = 'Category has not finished saving yet';
      notifyListeners();
      return;
    }

    // Check if new name conflicts with another category
    if (oldCategory.name.toLowerCase() != newCategory.name.toLowerCase() &&
        _categories.any(
            (c) => c.name.toLowerCase() == newCategory.name.toLowerCase())) {
      _error = 'Category "${newCategory.name}" already exists';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _supabase
          .from('categories')
          .update(newCategory.toMap())
          .eq('id', oldCategory.id!)
          .select()
          .single();

      _categories[index] = models.Category.fromMap(row);
      _categories.sort((a, b) => a.name.compareTo(b.name));
      _error = null;
    } catch (e) {
      _error = 'Failed to update category: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a category
  // Payment splits referencing this category should be removed separately (see PaymentSplitsProvider.removeSplitsByCategory)
  Future<void> deleteCategory(int index, ConfigProvider configProvider,
      {required bool isCategoryUsed}) async {
    if (index < 0 || index >= _categories.length) {
      _error = 'Invalid category index';
      notifyListeners();
      return;
    }

    if (isCategoryUsed) {
      _error = 'Cannot delete category that is in use by bills';
      notifyListeners();
      return;
    }

    final id = _categories[index].id;
    if (id == null) {
      _error = 'Category has not finished saving yet';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _supabase.from('categories').delete().eq('id', id);
      _categories.removeAt(index);
      _error = null;
    } catch (e) {
      _error = 'Failed to delete category: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Check if a category is in use (used by bills)
  // Note: Payment splits don't prevent category deletion - they will be removed automatically
  bool isCategoryInUse(
      String categoryName, List<Bill> bills, List<PaymentSplit> splits) {
    final categoryLower = categoryName.toLowerCase().trim();

    // Only check bills - splits don't prevent deletion (they'll be removed automatically)
    for (final bill in bills) {
      final billCategory = bill.category.toLowerCase().trim();
      if (billCategory == categoryLower) {
        return true;
      }
    }

    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
