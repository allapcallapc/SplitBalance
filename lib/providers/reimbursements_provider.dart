import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reimbursement.dart';

// Fetches every reimbursement linked to [billId]. Small, per-bill result set
// (no pagination needed) - injectable so tests can control it without a real
// Supabase session, same pattern as BillsProvider.
typedef FetchReimbursementsForBill = Future<List<Map<String, dynamic>>>
    Function({required String billId});

typedef InsertReimbursementRow = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> data,
);

typedef DeleteReimbursementRow = Future<void> Function(String id);

// Owns the reimbursements for a single bill at a time - backs the
// "Reimbursements" screen opened from a bill's menu. Balance/spend
// calculations don't go through this provider; they query
// bill_reimbursements directly (see AggregatedCalculationService).
class ReimbursementsProvider with ChangeNotifier {
  ReimbursementsProvider({
    FetchReimbursementsForBill? fetchReimbursementsForBill,
    InsertReimbursementRow? insertReimbursementRow,
    DeleteReimbursementRow? deleteReimbursementRow,
  })  : _fetchReimbursementsForBill =
            fetchReimbursementsForBill ?? _defaultFetchReimbursementsForBill,
        _insertReimbursementRow =
            insertReimbursementRow ?? _defaultInsertReimbursementRow,
        _deleteReimbursementRow =
            deleteReimbursementRow ?? _defaultDeleteReimbursementRow;

  final FetchReimbursementsForBill _fetchReimbursementsForBill;
  final InsertReimbursementRow _insertReimbursementRow;
  final DeleteReimbursementRow _deleteReimbursementRow;

  List<Reimbursement> _reimbursements = [];
  bool _isLoading = false;
  String? _error;

  List<Reimbursement> get reimbursements => List.unmodifiable(_reimbursements);
  bool get isLoading => _isLoading;
  String? get error => _error;
  double get totalReimbursed =>
      _reimbursements.fold(0.0, (sum, r) => sum + r.amount);

  static Future<List<Map<String, dynamic>>>
      _defaultFetchReimbursementsForBill({required String billId}) async {
    return await Supabase.instance.client
        .from('bill_reimbursements')
        .select()
        .eq('bill_id', billId)
        .order('date', ascending: false);
  }

  static Future<Map<String, dynamic>> _defaultInsertReimbursementRow(
    Map<String, dynamic> data,
  ) async {
    return await Supabase.instance.client
        .from('bill_reimbursements')
        .insert(data)
        .select()
        .single();
  }

  static Future<void> _defaultDeleteReimbursementRow(String id) async {
    await Supabase.instance.client
        .from('bill_reimbursements')
        .delete()
        .eq('id', id);
  }

  Future<void> loadForBill(String billId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _fetchReimbursementsForBill(billId: billId);
      _reimbursements =
          rows.map((row) => Reimbursement.fromMap(row)).toList();
      _error = null;
    } catch (e) {
      _error = 'Failed to load reimbursements: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Returns whether the add succeeded, so the caller can decide whether to
  // pop/show a message without also inspecting [error].
  Future<bool> addReimbursement(
      Reimbursement reimbursement, String householdId) async {
    _error = null;
    try {
      final row = await _insertReimbursementRow({
        ...reimbursement.toMap(),
        'household_id': householdId,
      });
      final saved = Reimbursement.fromMap(row);
      _reimbursements = [saved, ..._reimbursements];
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add reimbursement: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteReimbursement(String id) async {
    _error = null;
    try {
      await _deleteReimbursementRow(id);
      _reimbursements = _reimbursements.where((r) => r.id != id).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete reimbursement: $e';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Drops the currently loaded bill's reimbursements - called when leaving
  // the reimbursements screen so a future loadForBill for a different bill
  // never briefly shows stale data.
  void reset() {
    _reimbursements = [];
    _error = null;
    notifyListeners();
  }
}
