import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../models/duplicate_bill_group.dart';
import '../services/duplicate_bills_service.dart';
import 'config_provider.dart';

// Backs the "potential duplicate bills" banner/screen (GH issue #20) and the
// Add/Edit Bill screen's pre-save duplicate check, mirroring
// PendingPaymentsProvider's shape (ChangeNotifier + injectable service).
class DuplicateBillsProvider with ChangeNotifier {
  DuplicateBillsProvider({DuplicateBillsService? service})
      : _service = service ?? DuplicateBillsService();

  final DuplicateBillsService _service;

  List<DuplicateBillGroup> _duplicateGroups = [];
  bool _isLoading = false;
  String? _error;

  List<DuplicateBillGroup> get duplicateGroups =>
      List.unmodifiable(_duplicateGroups);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Total number of bills participating in some duplicate group - the
  // banner's "X potential duplicate bills found" count.
  int get duplicateBillCount =>
      _duplicateGroups.fold(0, (sum, group) => sum + group.bills.length);

  Future<void> loadDuplicates(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }
    await loadDuplicatesForHousehold(configProvider.householdId!);
  }

  // Core of loadDuplicates(), scoped to a household id rather than a
  // ConfigProvider so it can be exercised in tests without a real signed-in
  // Supabase session.
  @visibleForTesting
  Future<void> loadDuplicatesForHousehold(String householdId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _duplicateGroups = await _service.findDuplicateGroups(householdId);
      _error = null;
    } catch (e) {
      _error = 'Failed to load duplicate bills: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Existing bills matching [date]+[amount] in the current household,
  // excluding [excludeId] (the bill being edited, if any) - used by the
  // Add/Edit Bill screen to block Save behind a confirmation step. A failed
  // check fails open (returns no matches) rather than throwing - a network
  // hiccup in this best-effort check should never block saving the bill
  // itself, which is called from a plain (non-error-handling) button
  // onPressed.
  Future<List<Bill>> findMatches({
    required ConfigProvider configProvider,
    required DateTime date,
    required double amount,
    String? excludeId,
  }) async {
    final householdId = configProvider.householdId;
    if (!configProvider.isSignedIn || householdId == null) return const [];
    try {
      return await _service.findMatches(
        householdId: householdId,
        date: date,
        amount: amount,
        excludeId: excludeId,
      );
    } catch (_) {
      return const [];
    }
  }
}
