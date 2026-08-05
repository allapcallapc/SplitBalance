import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bill.dart';
import 'config_provider.dart';

class BillsProvider with ChangeNotifier {
  static const int pageSize = 25;

  // Paginated, server-filtered bills backing the bills list screen.
  final List<Bill> _bills = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  // Full, unpaginated/unfiltered household bill set. Kept separate from
  // _bills because balance calculations (summary screen) and category
  // "in use" checks (payment splits screen) need every bill, not just the
  // page currently shown in the list.
  final List<Bill> _allBills = [];
  bool _isLoadingAll = false;

  String? _error;

  // Active list filters. Null/empty means "no filter" (i.e. "All").
  String? _filterPaidBy;
  String? _filterCategory;

  List<Bill> get bills => List.unmodifiable(_bills);
  List<Bill> get allBills => List.unmodifiable(_allBills);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingAll => _isLoadingAll;
  bool get hasMore => _hasMore;
  String? get error => _error;

  String? get filterPaidBy => _filterPaidBy;
  String? get filterCategory => _filterCategory;
  bool get hasActiveFilters =>
      (_filterPaidBy != null && _filterPaidBy!.isNotEmpty) ||
      (_filterCategory != null && _filterCategory!.isNotEmpty);

  // Update the "paid by" filter and reload the first page with it applied
  // server-side. Pass null (or empty) to clear it.
  Future<void> setPaidByFilter(
      String? paidBy, ConfigProvider configProvider) async {
    final normalized = (paidBy == null || paidBy.isEmpty) ? null : paidBy;
    if (normalized == _filterPaidBy) return;
    _filterPaidBy = normalized;
    await loadBills(configProvider);
  }

  // Update the category filter and reload the first page with it applied
  // server-side. Pass null (or empty) to clear it.
  Future<void> setCategoryFilter(
      String? category, ConfigProvider configProvider) async {
    final normalized = (category == null || category.isEmpty) ? null : category;
    if (normalized == _filterCategory) return;
    _filterCategory = normalized;
    await loadBills(configProvider);
  }

  // Reset both filters back to "All" and reload the first (unfiltered) page.
  Future<void> clearFilters(ConfigProvider configProvider) async {
    if (_filterPaidBy == null && _filterCategory == null) return;
    _filterPaidBy = null;
    _filterCategory = null;
    await loadBills(configProvider);
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _billsQuery(
      ConfigProvider configProvider) {
    var query = _supabase
        .from('bills')
        .select()
        .eq('household_id', configProvider.householdId!);

    if (_filterPaidBy != null) {
      query = query.eq('paid_by', _filterPaidBy!);
    }
    if (_filterCategory != null) {
      query = query.eq('category', _filterCategory!);
    }

    return query;
  }

  // Load the first page of bills for the current household, applying the
  // active paid-by/category filters server-side. Resets any pagination
  // already accumulated via loadMoreBills().
  Future<void> loadBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _billsQuery(configProvider)
          .order('date', ascending: false)
          .order('id', ascending: false)
          .range(0, pageSize - 1);

      _bills
        ..clear()
        ..addAll(rows.map((row) => Bill.fromMap(row)));
      _hasMore = rows.length == pageSize;
      _error = null;
    } catch (e) {
      _error = 'Failed to load bills: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load the next page of bills (same filters as the current page) and
  // append it to the already-loaded list, for infinite scroll.
  Future<void> loadMoreBills(ConfigProvider configProvider) async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      final rows = await _billsQuery(configProvider)
          .order('date', ascending: false)
          .order('id', ascending: false)
          .range(_bills.length, _bills.length + pageSize - 1);

      _bills.addAll(rows.map((row) => Bill.fromMap(row)));
      _hasMore = rows.length == pageSize;
      _error = null;
    } catch (e) {
      _error = 'Failed to load more bills: $e';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // Load every bill for the household, ignoring the list filters/pagination.
  // Used where the full data set is required, e.g. balance calculations and
  // category "in use" checks.
  Future<void> loadAllBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    _isLoadingAll = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('bills')
          .select()
          .eq('household_id', configProvider.householdId!)
          .order('date', ascending: false);

      _allBills
        ..clear()
        ..addAll(rows.map((row) => Bill.fromMap(row)));
      _error = null;
    } catch (e) {
      _error = 'Failed to load bills: $e';
    } finally {
      _isLoadingAll = false;
      notifyListeners();
    }
  }

  bool _matchesActiveFilters(Bill bill) {
    if (_filterPaidBy != null && bill.paidBy != _filterPaidBy) return false;
    if (_filterCategory != null && bill.category != _filterCategory) {
      return false;
    }
    return true;
  }

  // Add a bill
  Future<void> addBill(Bill bill, ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      _error = 'Not signed in or no household selected';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _supabase
          .from('bills')
          .insert({
            ...bill.toMap(),
            'household_id': configProvider.householdId,
          })
          .select()
          .single();

      final saved = Bill.fromMap(row);

      // Only surface the new bill in the paginated list if it matches the
      // active filters; otherwise it belongs on a page/filter we're not
      // currently viewing.
      if (_matchesActiveFilters(saved)) {
        _bills.add(saved);
        _bills.sort((a, b) => b.date.compareTo(a.date));
      }

      _allBills.add(saved);
      _allBills.sort((a, b) => b.date.compareTo(a.date));
      _error = null;
    } catch (e) {
      _error = 'Failed to add bill: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update a bill
  Future<void> updateBill(
      int index, Bill updatedBill, ConfigProvider configProvider) async {
    if (index < 0 || index >= _bills.length) {
      _error = 'Invalid bill index';
      notifyListeners();
      return;
    }

    final id = _bills[index].id;
    if (id == null) {
      _error = 'Bill has not finished saving yet';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final row = await _supabase
          .from('bills')
          .update(updatedBill.toMap())
          .eq('id', id)
          .select()
          .single();

      final saved = Bill.fromMap(row);

      // The edit may have moved the bill out of the active filters (e.g.
      // changed its category away from the one being filtered on).
      if (_matchesActiveFilters(saved)) {
        _bills[index] = saved;
        _bills.sort((a, b) => b.date.compareTo(a.date));
      } else {
        _bills.removeAt(index);
      }

      final allIndex = _allBills.indexWhere((b) => b.id == id);
      if (allIndex != -1) {
        _allBills[allIndex] = saved;
        _allBills.sort((a, b) => b.date.compareTo(a.date));
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to update bill: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete a bill
  Future<void> deleteBill(int index, ConfigProvider configProvider) async {
    if (index < 0 || index >= _bills.length) {
      _error = 'Invalid bill index';
      notifyListeners();
      return;
    }

    final id = _bills[index].id;
    if (id == null) {
      _error = 'Bill has not finished saving yet';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _supabase.from('bills').delete().eq('id', id);
      _bills.removeAt(index);
      _allBills.removeWhere((b) => b.id == id);
      _error = null;
    } catch (e) {
      _error = 'Failed to delete bill: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get bill by index
  Bill? getBill(int index) {
    if (index < 0 || index >= _bills.length) {
      return null;
    }
    return _bills[index];
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
