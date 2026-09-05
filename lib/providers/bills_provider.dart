import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bill.dart';
import '../services/postgrest_paging.dart';
import 'config_provider.dart';

// Which bill field the list is ordered by.
enum BillSortField { date, amount }

// Fetches one page of bill rows for [householdId], applying the optional
// paid-by/category filters and the sort field/direction server-side.
// Injectable so tests can control exactly when/in what order responses
// resolve, without needing a real Supabase session.
typedef FetchBillsPage = Future<List<Map<String, dynamic>>> Function({
  required String householdId,
  String? paidBy,
  String? category,
  DateTime? startDate,
  DateTime? endDate,
  required BillSortField sortField,
  required bool sortAscending,
  required int offset,
  required int limit,
});

// Inserts a bill row and returns the saved row (including its generated id).
typedef InsertBillRow = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> data,
);

// Updates the row with the given id and returns the saved row.
typedef UpdateBillRow = Future<Map<String, dynamic>> Function(
  String id,
  Map<String, dynamic> data,
);

// Deletes the row with the given id.
typedef DeleteBillRow = Future<void> Function(String id);

// Sums bill_recovered_amounts.amount for each of [billIds], grouped by who
// received it: bill_id -> {receivedBy -> total}. Bills/receivers with
// nothing recovered are simply absent from the result (treated as 0 by the
// caller) rather than present with a 0 entry. The per-receiver breakdown
// (not just a flat per-bill total) is what lets spend-chart attribution
// (see computeMonthlySpend) credit the reduction to whoever actually
// received the money, matching AggregatedCalculationService's balance math
// instead of always netting it against the bill's own paidBy.
typedef FetchRecoveredBreakdown = Future<Map<String, Map<String, double>>>
    Function({required List<String> billIds});

class BillsProvider with ChangeNotifier {
  BillsProvider({
    FetchBillsPage? fetchBillsPage,
    InsertBillRow? insertBillRow,
    UpdateBillRow? updateBillRow,
    DeleteBillRow? deleteBillRow,
    FetchRecoveredBreakdown? fetchRecoveredBreakdown,
  })  : _fetchBillsPage = fetchBillsPage ?? _defaultFetchBillsPage,
        _insertBillRow = insertBillRow ?? _defaultInsertBillRow,
        _updateBillRow = updateBillRow ?? _defaultUpdateBillRow,
        _deleteBillRow = deleteBillRow ?? _defaultDeleteBillRow,
        _fetchRecoveredBreakdown =
            fetchRecoveredBreakdown ?? _defaultFetchRecoveredBreakdown;

  static const int pageSize = 25;

  final FetchBillsPage _fetchBillsPage;
  final InsertBillRow _insertBillRow;
  final UpdateBillRow _updateBillRow;
  final DeleteBillRow _deleteBillRow;
  final FetchRecoveredBreakdown _fetchRecoveredBreakdown;

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

  // Which household loadAllBills() last ran for (successfully or not), so
  // repeat callers (e.g. drilling from TotalDetailScreen into
  // CategoryDetailScreen) can skip an immediate redundant refetch of the
  // household's entire bill history - mutations (add/update/delete) already
  // keep _allBills in sync incrementally, so a cached list is never stale
  // within a session. Same approach as CategoriesProvider.hasLoadedForHousehold.
  String? _allBillsLoadedForHouseholdId;

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
  // Inclusive date-range filter. Either end may be set independently (e.g.
  // "on or after" with no end, or "on or before" with no start); a single
  // exact-date search sets both to the same day.
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  // Active list sort. Defaults to newest-first by date, matching the
  // screen's behavior before sorting was configurable.
  BillSortField _sortField = BillSortField.date;
  bool _sortAscending = false;

  List<Bill> get bills => List.unmodifiable(_bills);
  List<Bill> get allBills => List.unmodifiable(_allBills);
  List<String> get paidByOptions => List.unmodifiable(_paidByOptions);
  List<String> get categoryOptions => List.unmodifiable(_categoryOptions);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingAll => _isLoadingAll;
  bool get hasMore => _hasMore;
  String? get error => _error;

  // Whether loadAllBills has run (successfully or not) for this household,
  // so callers can skip a redundant refetch instead of assuming a fresh
  // fetch is always needed.
  bool hasLoadedAllBillsForHousehold(String? householdId) =>
      householdId != null && _allBillsLoadedForHouseholdId == householdId;

  String? get filterPaidBy => _filterPaidBy;
  String? get filterCategory => _filterCategory;
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  bool get hasActiveFilters =>
      (_filterPaidBy != null && _filterPaidBy!.isNotEmpty) ||
      (_filterCategory != null && _filterCategory!.isNotEmpty) ||
      _filterStartDate != null ||
      _filterEndDate != null;

  BillSortField get sortField => _sortField;
  bool get sortAscending => _sortAscending;

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

  // Update the date-range filter and reload the first page with it applied
  // server-side. Both bounds are inclusive; pass null for either to leave
  // that side open-ended, or the same date for both to search a single day.
  Future<void> setDateRangeFilter(DateTime? startDate, DateTime? endDate,
      ConfigProvider configProvider) async {
    if (startDate == _filterStartDate && endDate == _filterEndDate) return;
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    await loadBills(configProvider);
  }

  // Reset all filters back to "All" and reload the first (unfiltered) page.
  Future<void> clearFilters(ConfigProvider configProvider) async {
    if (_filterPaidBy == null &&
        _filterCategory == null &&
        _filterStartDate == null &&
        _filterEndDate == null) {
      return;
    }
    _filterPaidBy = null;
    _filterCategory = null;
    _filterStartDate = null;
    _filterEndDate = null;
    await loadBills(configProvider);
  }

  // Update the sort field/direction and reload the first page ordered by it
  // server-side.
  Future<void> setSort(BillSortField field, bool ascending,
      ConfigProvider configProvider) async {
    if (field == _sortField && ascending == _sortAscending) return;
    _sortField = field;
    _sortAscending = ascending;
    await loadBills(configProvider);
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> _defaultFetchBillsPage({
    required String householdId,
    String? paidBy,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    required BillSortField sortField,
    required bool sortAscending,
    required int offset,
    required int limit,
  }) async {
    var query = Supabase.instance.client
        .from('bills')
        .select()
        .eq('household_id', householdId);

    if (paidBy != null) {
      query = query.eq('paid_by', paidBy);
    }
    if (category != null) {
      query = query.eq('category', category);
    }
    final dateFormat = DateFormat('yyyy-MM-dd');
    if (startDate != null) {
      query = query.gte('date', dateFormat.format(startDate));
    }
    if (endDate != null) {
      query = query.lte('date', dateFormat.format(endDate));
    }

    final column = sortField == BillSortField.date ? 'date' : 'amount';
    return await query
        .order(column, ascending: sortAscending)
        .order('id', ascending: sortAscending)
        .range(offset, offset + limit - 1);
  }

  static Future<Map<String, dynamic>> _defaultInsertBillRow(
    Map<String, dynamic> data,
  ) async {
    return await Supabase.instance.client
        .from('bills')
        .insert(data)
        .select()
        .single();
  }

  static Future<Map<String, dynamic>> _defaultUpdateBillRow(
    String id,
    Map<String, dynamic> data,
  ) async {
    return await Supabase.instance.client
        .from('bills')
        .update(data)
        .eq('id', id)
        .select()
        .single();
  }

  static Future<void> _defaultDeleteBillRow(String id) async {
    await Supabase.instance.client.from('bills').delete().eq('id', id);
  }

  static Future<Map<String, Map<String, double>>>
      _defaultFetchRecoveredBreakdown({
    required List<String> billIds,
  }) async {
    if (billIds.isEmpty) return {};

    // Paginated via the shared pageAndReduce helper (also used by
    // AggregatedCalculationService._sumAmounts), in case a household's
    // full bill set (loadAllBills) pushes this past PostgREST's max_rows
    // cap.
    return pageAndReduce<Map<String, Map<String, double>>>(
      buildQuery: () => Supabase.instance.client
          .from('bill_recovered_amounts')
          .select('bill_id, received_by, amount')
          .inFilter('bill_id', billIds),
      initial: <String, Map<String, double>>{},
      reduce: (byBill, row) {
        final billId = row['bill_id'] as String;
        final receivedBy = row['received_by'] as String;
        final amount = (row['amount'] as num).toDouble();
        final byReceiver = byBill.putIfAbsent(billId, () => <String, double>{});
        byReceiver[receivedBy] = (byReceiver[receivedBy] ?? 0) + amount;
        return byBill;
      },
    );
  }

  static double _sumRecovered(Map<String, double>? byReceiver) =>
      byReceiver == null ? 0 : byReceiver.values.fold(0.0, (a, b) => a + b);

  // Fetches recovered totals for [bills] and returns them with
  // recoveredAmount/recoveredByReceiver populated, for display (list
  // badges, category/summary charts) - not consulted by balance
  // calculations, which subtract recovered amounts at the query level (see
  // AggregatedCalculationService).
  Future<List<Bill>> _withRecoveredTotals(List<Bill> bills) async {
    final ids = [for (final b in bills) if (b.id != null) b.id!];
    if (ids.isEmpty) return bills;
    final breakdown = await _fetchRecoveredBreakdown(billIds: ids);
    if (breakdown.isEmpty) return bills;
    return [
      for (final bill in bills)
        bill.copyWith(
          recoveredAmount: _sumRecovered(breakdown[bill.id]),
          recoveredByReceiver: breakdown[bill.id] ?? const {},
        ),
    ];
  }

  // Load the first page of bills for the current household, applying the
  // active paid-by/category filters server-side. Resets any pagination
  // already accumulated via loadMoreBills().
  Future<void> loadBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }
    await loadBillsForHousehold(configProvider.householdId!);
  }

  // Core of loadBills(), scoped to a household id rather than a
  // ConfigProvider so it can be exercised in tests without a real signed-in
  // Supabase session.
  @visibleForTesting
  Future<void> loadBillsForHousehold(String householdId) async {
    // Starting a fresh page-1 load invalidates any loadMoreBills() already
    // in flight for the previous filter/page window.
    final requestId = ++_requestId;

    _isLoading = true;
    _isLoadingMore = false;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetchBillsPage(
        householdId: householdId,
        paidBy: _filterPaidBy,
        category: _filterCategory,
        startDate: _filterStartDate,
        endDate: _filterEndDate,
        sortField: _sortField,
        sortAscending: _sortAscending,
        offset: 0,
        limit: pageSize,
      );

      // A newer loadBills() call (e.g. a fast second filter change) has
      // since superseded this one; drop the stale response.
      if (requestId != _requestId) return;

      final pageBills =
          await _withRecoveredTotals(rows.map(Bill.fromMap).toList());
      if (requestId != _requestId) return;

      _bills
        ..clear()
        ..addAll(pageBills);
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
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }
    await loadMoreBillsForHousehold(configProvider.householdId!);
  }

  @visibleForTesting
  Future<void> loadMoreBillsForHousehold(String householdId) async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    final requestId = _requestId;
    _isLoadingMore = true;
    notifyListeners();

    try {
      final rows = await _fetchBillsPage(
        householdId: householdId,
        paidBy: _filterPaidBy,
        category: _filterCategory,
        startDate: _filterStartDate,
        endDate: _filterEndDate,
        sortField: _sortField,
        sortAscending: _sortAscending,
        offset: _bills.length,
        limit: pageSize,
      );

      // A loadBills() reset happened while this was in flight (e.g. the
      // filter changed) — its results belong to a window that no longer
      // exists, so drop them instead of appending onto the new page 1.
      if (requestId != _requestId) return;

      final pageBills =
          await _withRecoveredTotals(rows.map(Bill.fromMap).toList());
      if (requestId != _requestId) return;

      _bills.addAll(pageBills);
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

      final loadedBills =
          await _withRecoveredTotals(rows.map(Bill.fromMap).toList());

      _allBills
        ..clear()
        ..addAll(loadedBills);
      _error = null;
    } catch (e) {
      _error = 'Failed to load bills: $e';
    } finally {
      _isLoadingAll = false;
      _allBillsLoadedForHouseholdId = configProvider.householdId;
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
    await addBillForHousehold(bill, configProvider.householdId!);
  }

  @visibleForTesting
  Future<void> addBillForHousehold(Bill bill, String householdId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    Bill saved;
    try {
      final row = await _insertBillRow({
        ...bill.toMap(),
        'household_id': householdId,
      });
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
    await loadBillsForHousehold(householdId);
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

    await updateBillById(id, updatedBill, configProvider.householdId);
  }

  // Core of updateBill(), scoped to a bill id and (optional) household id
  // rather than an index into `_bills`/a ConfigProvider, so it can be
  // exercised in tests without a real signed-in Supabase session.
  @visibleForTesting
  Future<void> updateBillById(
      String id, Bill updatedBill, String? householdId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    Bill saved;
    try {
      final row = await _updateBillRow(id, updatedBill.toMap());
      // Editing a bill's own fields never touches its recovered amounts,
      // but the row from _updateBillRow has none of its own (not a `bills`
      // column) - fetch the authoritative total rather than trusting
      // whatever _allBills happens to have cached locally, which can be
      // stale relative to a recovered amount added/deleted elsewhere
      // (another device, or a screen that skipped a refetch via
      // hasLoadedAllBillsForHousehold).
      final breakdown = await _fetchRecoveredBreakdown(billIds: [id]);
      saved = Bill.fromMap(row).copyWith(
        recoveredAmount: _sumRecovered(breakdown[id]),
        recoveredByReceiver: breakdown[id] ?? const {},
      );
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
    if (householdId != null) {
      await loadBillsForHousehold(householdId);
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

    await deleteBillById(id);
  }

  @visibleForTesting
  Future<void> deleteBillById(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _deleteBillRow(id);
      // Remove by id, not a caller-supplied index: a loadBills() reset could
      // have run while the delete was in flight, making an index describe a
      // different row (or none) by the time we get here.
      _bills.removeWhere((b) => b.id == id);
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
