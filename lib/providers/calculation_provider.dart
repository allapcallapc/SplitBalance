import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../models/payment_split.dart';
import '../models/category.dart' as models;
import '../services/calculation_service.dart';

class CalculationProvider with ChangeNotifier {
  BalanceResult? _balanceResult;
  bool _isCalculating = false;
  String? _error;

  BalanceResult? get balanceResult => _balanceResult;
  bool get isCalculating => _isCalculating;
  String? get error => _error;

  // Calculate balances
  void calculateBalances({
    required List<Bill> bills,
    required List<PaymentSplit> splits,
    required List<models.Category> categories,
    required String person1Name,
    required String person2Name,
  }) {
    _isCalculating = true;
    _error = null;
    notifyListeners();

    try {
      _balanceResult = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1Name,
        person2Name: person2Name,
      );
      _error = null;
    } catch (e) {
      _error = 'Calculation error: $e';
      _balanceResult = null;
    } finally {
      _isCalculating = false;
      notifyListeners();
    }
  }

  // Get formatted balance message
  String getBalanceMessage() {
    if (_balanceResult == null) {
      return 'No balance calculated';
    }

    final result = _balanceResult!;
    
    if (result.netBalance.abs() < 0.01) {
      return 'All balanced! No one owes anyone.';
    }

    if (result.netBalance > 0) {
      return '${result.person1Name} owes ${result.person2Name} \$${result.netBalance.toStringAsFixed(2)}';
    } else {
      return '${result.person2Name} owes ${result.person1Name} \$${(-result.netBalance).toStringAsFixed(2)}';
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _balanceResult = null;
    _error = null;
    _isCalculating = false;
    notifyListeners();
  }
}
