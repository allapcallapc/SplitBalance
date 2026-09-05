import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recovered_amount.dart';

// Fetches every recovered amount linked to [billId]. Small, per-bill result
// set (no pagination needed) - injectable so tests can control it without a
// real Supabase session, same pattern as BillsProvider.
typedef FetchRecoveredAmountsForBill = Future<List<Map<String, dynamic>>>
    Function({required String billId});

typedef InsertRecoveredAmountRow = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> data,
);

typedef DeleteRecoveredAmountRow = Future<void> Function(String id);

// Owns the recovered amounts for a single bill at a time - backs the
// "Recovered Amounts" screen opened from a bill's menu. Balance/spend
// calculations don't go through this provider; they query
// bill_recovered_amounts directly (see AggregatedCalculationService).
class RecoveredAmountsProvider with ChangeNotifier {
  RecoveredAmountsProvider({
    FetchRecoveredAmountsForBill? fetchRecoveredAmountsForBill,
    InsertRecoveredAmountRow? insertRecoveredAmountRow,
    DeleteRecoveredAmountRow? deleteRecoveredAmountRow,
  })  : _fetchRecoveredAmountsForBill = fetchRecoveredAmountsForBill ??
            _defaultFetchRecoveredAmountsForBill,
        _insertRecoveredAmountRow =
            insertRecoveredAmountRow ?? _defaultInsertRecoveredAmountRow,
        _deleteRecoveredAmountRow =
            deleteRecoveredAmountRow ?? _defaultDeleteRecoveredAmountRow;

  final FetchRecoveredAmountsForBill _fetchRecoveredAmountsForBill;
  final InsertRecoveredAmountRow _insertRecoveredAmountRow;
  final DeleteRecoveredAmountRow _deleteRecoveredAmountRow;

  List<RecoveredAmount> _recoveredAmounts = [];
  bool _isLoading = false;
  String? _error;

  List<RecoveredAmount> get recoveredAmounts =>
      List.unmodifiable(_recoveredAmounts);
  bool get isLoading => _isLoading;
  String? get error => _error;
  double get totalRecovered =>
      _recoveredAmounts.fold(0.0, (sum, r) => sum + r.amount);

  static Future<List<Map<String, dynamic>>>
      _defaultFetchRecoveredAmountsForBill({required String billId}) async {
    return await Supabase.instance.client
        .from('bill_recovered_amounts')
        .select()
        .eq('bill_id', billId)
        .order('date', ascending: false);
  }

  static Future<Map<String, dynamic>> _defaultInsertRecoveredAmountRow(
    Map<String, dynamic> data,
  ) async {
    return await Supabase.instance.client
        .from('bill_recovered_amounts')
        .insert(data)
        .select()
        .single();
  }

  static Future<void> _defaultDeleteRecoveredAmountRow(String id) async {
    await Supabase.instance.client
        .from('bill_recovered_amounts')
        .delete()
        .eq('id', id);
  }

  Future<void> loadForBill(String billId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetchRecoveredAmountsForBill(billId: billId);
      _recoveredAmounts =
          rows.map((row) => RecoveredAmount.fromMap(row)).toList();
      _error = null;
    } catch (e) {
      _error = 'Failed to load recovered amounts: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Returns whether the add succeeded, so the caller can decide whether to
  // pop/show a message without also inspecting [error].
  Future<bool> addRecoveredAmount(
      RecoveredAmount recoveredAmount, String householdId) async {
    _error = null;
    try {
      final row = await _insertRecoveredAmountRow({
        ...recoveredAmount.toMap(),
        'household_id': householdId,
      });
      final saved = RecoveredAmount.fromMap(row);
      // loadForBill fetches ordered by date descending (newest first) - keep
      // that invariant here too, rather than always prepending, so a
      // backdated entry (recording something added after the fact) doesn't
      // display above a genuinely newer one until the next reload.
      _recoveredAmounts = [saved, ..._recoveredAmounts]
        ..sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add recovered amount: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteRecoveredAmount(String id) async {
    _error = null;
    try {
      await _deleteRecoveredAmountRow(id);
      _recoveredAmounts =
          _recoveredAmounts.where((r) => r.id != id).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete recovered amount: $e';
      notifyListeners();
      return false;
    }
  }

  // Drops the currently loaded bill's recovered amounts - called when
  // leaving the recovered amounts screen so a future loadForBill for a
  // different bill never briefly shows stale data.
  void reset() {
    _recoveredAmounts = [];
    _error = null;
    notifyListeners();
  }
}
