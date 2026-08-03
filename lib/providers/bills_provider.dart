import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bill.dart';
import 'config_provider.dart';

class BillsProvider with ChangeNotifier {
  final List<Bill> _bills = [];
  bool _isLoading = false;
  String? _error;

  List<Bill> get bills => List.unmodifiable(_bills);
  bool get isLoading => _isLoading;
  String? get error => _error;

  SupabaseClient get _supabase => Supabase.instance.client;

  // Load bills for the current household from Supabase
  Future<void> loadBills(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.householdId == null) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final rows = await _supabase
          .from('bills')
          .select()
          .eq('household_id', configProvider.householdId!)
          .order('date', ascending: false);

      _bills
        ..clear()
        ..addAll(rows.map((row) => Bill.fromMap(row)));
      _error = null;
    } catch (e) {
      _error = 'Failed to load bills: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

      _bills.add(Bill.fromMap(row));
      _bills.sort((a, b) => b.date.compareTo(a.date));
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

      _bills[index] = Bill.fromMap(row);
      _bills.sort((a, b) => b.date.compareTo(a.date));
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
      if (category != null &&
          category.isNotEmpty &&
          bill.category != category) {
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
