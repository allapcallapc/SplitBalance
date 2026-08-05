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

  // Every distinct paid-by/category value ever used on a household bill,
  // for the filter dropdown options. Populated by loadFilterOptions(),
  // which projects just these two columns so it stays cheap even though it
  // scans every bill row (unlike _allBills, which pulls full rows).
  List<String> _paidByOptions = [];
  List<String> _categoryOptions = [];

  // Bumped by every loadBills() call. Lets loadBills()/loadMoreBills() tell
  // whether they're still the most recent request before applying their
  // response, so a slow response from a filter the user has since changed
  // away from can't clobber newer state (or vice versa).
  int _requestId = 0;

  String? _error;

  // Active list filters. Null/empty means "no filter" (i.e. "All").
  String? _filterPaidBy;
  String? _filterCategory;

  List<Bill> get bills => List.unmodifiable(_bills);
  List<Bill> get allBills => List.unmodifiable(_allBills);
  List<String> get paidByOptions => List.unmodifiable(_paidByOptions);
  List<String> get categoryOptions => List.unmodifiable(_categoryOptions);
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

    // Starting a fresh page-1 load invalidates any loadMoreBills() already
    // in flight for the previous filter/page window.
    final requestId = ++_requestId;

    _isLoading = true;
    _isLoadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final rows = await _billsQuery(configProvider)
          .order('date', ascending: false)
          .order('id', ascending: false)
          .range(0, pageSize - 1);

      // A newer loadBills() call (e.g. a fast second filter change) has
      // since superseded this one; drop the stale response.
      if (requestId != _requestId) return;

      _bills
        ..clear()
        ..addAll(rows.map((row) => Bill.fromMap(row)));
      _hasMore = rows.length == pageSize;
      _error = null;
    } catch (e) {
      if (requestId == _requestId) {
        _error = 'Failed to load bills: $e';
      }
    } finally {
      if (requestId == _requestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Load the next page of bills (same filters as the current page) and
  // append it to the already-loaded list, for infinite scroll.
  Future<void> loadMoreBills(ConfigProvider configProvider) async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    final requestId = _requestId;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final rows = await _billsQuery(configProvider)
          .order('date', ascending: false)
          .order('id', ascending: false)
          .range(_bills.length, _bills.length + pageSize - 1);

      // A loadBills() reset happened while this was in flight (e.g. the
      // filter changed) — its results belong to a window that no longer
      // exists, so drop them instead of appending onto the new page 1.
      if (requestId != _requestId) return;

      _bills.addAll(rows.map((row) => Bill.fromMap(row)));
      _hasMore = rows.length == pageSize;
      _error = null;
    } catch (e) {
      if (requestId == _requestId) {
        _error = 'Failed to load more bills: $e';
      }
    } finally {
      if (requestId == _requestId) {
        _isLoadingMore = false;
        notifyListeners();
      }
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

  // Load every distinct paid-by/category value used across the household's
  // bills, for the filter dropdown options. Renamed/deleted payers and
  // categories stay filterable this way even though they're no longer in
  // ConfigProvider/CategoriesProvider. Only the two narrow columns are
  // fetched (not full bill rows), and dedup happens client-side since
  // PostgREST has no SELECT DISTINCT.
  Future<void> loadFilterOptions(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    try {
      final rows = await _supabase
          .from('bills')
          .select('paid_by, category')
          .eq('household_id', configProvider.householdId!);

      final paidBySet = <String>{};
      final categorySet = <String>{};
      for (final row in rows) {
        final paidBy = row['paid_by'] as String?;
        final category = row['category'] as String?;
        if (paidBy != null && paidBy.isNotEmpty) paidBySet.add(paidBy);
        if (category != null && category.isNotEmpty) categorySet.add(category);
      }

      _paidByOptions = paidBySet.toList()..sort();
      _categoryOptions = categorySet.toList()..sort();
      notifyListeners();
    } catch (_) {
      // Best-effort: leave whatever options were already loaded in place
      // rather than surfacing this as a blocking error.
    }
  }

  // Sort order that matches the server's `.order('date', ..).order('id', ..)`
  // so locally-maintained lists (_allBills) don't drift from what a fresh
  // fetch would return when two bills share a date.
  int _byDateThenId(Bill a, Bill b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return (b.id ?? '').compareTo(a.id ?? '');
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

    Bill saved;
    try {
      final row = await _supabase
          .from('bills')
          .insert({
            ...bill.toMap(),
            'household_id': configProvider.householdId,
          })
          .select()
          .single();
      saved = Bill.fromMap(row);
    } catch (e) {
      _error = 'Failed to add bill: $e';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _allBills.add(saved);
    _allBills.sort(_byDateThenId);

    // Re-fetch page 1 from the server rather than optimistically splicing
    // the new row into `_bills`: the new bill's position relative to the
    // already-loaded window can't be determined locally, and guessing wrong
    // desyncs the .range() offset that loadMoreBills() relies on.
    await loadBills(configProvider);
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

    Bill saved;
    try {
      final row = await _supabase
          .from('bills')
          .update(updatedBill.toMap())
          .eq('id', id)
          .select()
          .single();
      saved = Bill.fromMap(row);
    } catch (e) {
      _error = 'Failed to update bill: $e';
      _isLoading = false;
      notifyListeners();
      return;
    }

    final allIndex = _allBills.indexWhere((b) => b.id == id);
    if (allIndex != -1) {
      _allBills[allIndex] = saved;
    } else {
      _allBills.add(saved);
    }
    _allBills.sort(_byDateThenId);

    // Same rationale as addBill: the edit may have changed the bill's sort
    // position or taken it out of the active filter, which a local splice
    // into `_bills` can't safely reason about relative to the already-loaded
    // window/offset. Re-fetch page 1 instead.
    await loadBills(configProvider);
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
