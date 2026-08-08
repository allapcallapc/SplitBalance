// A fake data source for AggregatedCalculationService's injectable fetch
// functions, backed by a plain in-memory List<Bill>/List<PaymentSplit>
// instead of a real Supabase call. Lets tests build a scenario once and run
// both CalculationService (which takes bills/splits directly) and
// AggregatedCalculationService (fed via this fixture) over the same
// underlying data, without needing a real or mocked database.

import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';

class InMemoryBillSource {
  InMemoryBillSource({required this.bills, required this.splits});

  final List<Bill> bills;
  final List<PaymentSplit> splits;

  Future<List<PaymentSplit>> fetchSplits({required String householdId}) async {
    return splits;
  }

  Future<double> fetchPersonPaidTotal({
    required String householdId,
    required String paidBy,
  }) async {
    return bills
        .where((b) => b.paidBy == paidBy)
        .fold<double>(0.0, (sum, b) => sum + b.amount);
  }

  Future<double> fetchCategoryPeriodPersonPaid({
    required String householdId,
    required String category,
    required DateTime? periodStart,
    required DateTime? periodEnd,
    required String paidBy,
  }) async {
    return bills
        .where((b) =>
            b.category == category &&
            b.paidBy == paidBy &&
            (periodStart == null || b.date.isAfter(periodStart)) &&
            (periodEnd == null || !b.date.isAfter(periodEnd)))
        .fold<double>(0.0, (sum, b) => sum + b.amount);
  }

  Future<HouseholdTotals> fetchHouseholdTotals({
    required String householdId,
  }) async {
    return HouseholdTotals(
      billCount: bills.length,
      totalAmount: bills.fold<double>(0.0, (sum, b) => sum + b.amount),
    );
  }

  // Constructs an AggregatedCalculationService wired to this fixture's data.
  AggregatedCalculationService toService() {
    return AggregatedCalculationService(
      fetchSplits: fetchSplits,
      fetchPersonPaidTotal: fetchPersonPaidTotal,
      fetchCategoryPeriodPersonPaid: fetchCategoryPeriodPersonPaid,
      fetchHouseholdTotals: fetchHouseholdTotals,
    );
  }
}
