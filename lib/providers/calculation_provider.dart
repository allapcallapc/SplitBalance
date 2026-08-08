import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/bill.dart';
import '../models/payment_split.dart';
import '../models/category.dart' as models;
import '../services/calculation_service.dart';
import '../services/aggregated_calculation_service.dart';
import '../l10n/app_localizations.dart';

class CalculationProvider with ChangeNotifier {
  CalculationProvider({
    AggregatedCalculationService? aggregatedCalculationService,
  }) : _aggregatedCalculationService =
            aggregatedCalculationService ?? AggregatedCalculationService();

  final AggregatedCalculationService _aggregatedCalculationService;

  BalanceResult? _balanceResult;
  HouseholdTotals? _householdTotals;
  bool _isCalculating = false;
  String? _error;

  BalanceResult? get balanceResult => _balanceResult;
  HouseholdTotals? get householdTotals => _householdTotals;
  bool get isCalculating => _isCalculating;
  String? get error => _error;

  // Set calculating state (used to show loading indicator before data loading)
  void setCalculating(bool value) {
    _isCalculating = value;
    if (value) {
      _balanceResult = null; // Clear old result when starting
      _householdTotals = null;
    }
    notifyListeners();
  }

  // Calculate balances
  Future<void> calculateBalances({
    required List<Bill> bills,
    required List<PaymentSplit> splits,
    required List<models.Category> categories,
    required String person1Name,
    required String person2Name,
  }) async {
    _isCalculating = true;
    _error = null;
    _balanceResult = null; // Clear old result to prevent showing stale data
    notifyListeners();

    // Wait for the next frame to ensure UI has rendered the loading indicator
    await SchedulerBinding.instance.endOfFrame;

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

  // Calculate balances via AggregatedCalculationService (narrow, filtered
  // queries instead of a full bill list) and fetch the household stat
  // totals alongside it, in parallel. Same setCalculating/try-catch-
  // finally-notifyListeners state machine as calculateBalances above - only
  // what's being called internally differs.
  Future<void> calculateAggregatedBalances({
    required String householdId,
    required List<models.Category> categories,
    required String person1Name,
    required String person2Name,
  }) async {
    _isCalculating = true;
    _error = null;
    _balanceResult = null; // Clear old result to prevent showing stale data
    _householdTotals = null;
    notifyListeners();

    // Wait for the next frame to ensure UI has rendered the loading indicator
    await SchedulerBinding.instance.endOfFrame;

    try {
      final results = await Future.wait([
        _aggregatedCalculationService.calculateBalances(
          householdId: householdId,
          categories: categories,
          person1Name: person1Name,
          person2Name: person2Name,
        ),
        _aggregatedCalculationService.fetchHouseholdTotals(
          householdId: householdId,
        ),
      ]);
      _balanceResult = results[0] as BalanceResult;
      _householdTotals = results[1] as HouseholdTotals;
      _error = null;
    } catch (e) {
      _error = 'Calculation error: $e';
      _balanceResult = null;
      _householdTotals = null;
    } finally {
      _isCalculating = false;
      notifyListeners();
    }
  }

  // Get formatted balance message
  String getBalanceMessage(AppLocalizations l10n) {
    if (_balanceResult == null) {
      return l10n.noBalanceCalculated;
    }

    final result = _balanceResult!;
    final currencyFormat = '\$${result.netBalance.abs().toStringAsFixed(2)}';

    if (result.netBalance.abs() < 0.01) {
      return l10n.allBalancedNoOneOwes;
    }

    if (result.netBalance > 0) {
      return l10n.personOwesPerson(
          result.person1Name, result.person2Name, currencyFormat);
    } else {
      return l10n.personOwesPerson(
          result.person2Name, result.person1Name, currencyFormat);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _balanceResult = null;
    _householdTotals = null;
    _error = null;
    _isCalculating = false;
    notifyListeners();
  }
}
