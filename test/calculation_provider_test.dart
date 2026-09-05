// State-machine tests for CalculationProvider.calculateAggregatedBalances:
// isCalculating/error/balanceResult/householdTotals transitions, using an
// AggregatedCalculationService built from fake fetchers (no real Supabase,
// no mocking framework - same DI pattern as everywhere else in this repo).
//
// Uses testWidgets/WidgetTester (rather than plain test()) purely to get
// access to tester.pump(): calculateAggregatedBalances awaits
// SchedulerBinding.instance.endOfFrame, which never resolves unless a frame
// is actually pumped - nothing here renders a widget tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/providers/calculation_provider.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';

void main() {
  const person1 = 'Alice';
  const person2 = 'Bob';
  const householdId = 'household-1';
  final categories = [Category(name: 'Food')];

  AggregatedCalculationService serviceWith({
    FetchSplits? fetchSplits,
    FetchPersonPaidTotal? fetchPersonPaidTotal,
    FetchPersonBillCount? fetchPersonBillCount,
    FetchCategoryPeriodPersonPaid? fetchCategoryPeriodPersonPaid,
    FetchHouseholdTotals? fetchHouseholdTotals,
  }) {
    return AggregatedCalculationService(
      fetchSplits: fetchSplits ?? ({required householdId}) async => [],
      fetchPersonPaidTotal: fetchPersonPaidTotal ??
          ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              0.0,
      fetchPersonBillCount: fetchPersonBillCount ??
          ({required householdId, required paidBy}) async => 0,
      fetchCategoryPeriodPersonPaid: fetchCategoryPeriodPersonPaid ??
          ({
            required householdId,
            required category,
            required periodStart,
            required periodEnd,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              0.0,
      fetchHouseholdTotals: fetchHouseholdTotals ??
          ({required householdId}) async =>
              const HouseholdTotals(billCount: 0, totalAmount: 0.0),
    );
  }

  // Runs calculateAggregatedBalances to completion: starts it, pumps a
  // frame so its internal `await SchedulerBinding.instance.endOfFrame`
  // resolves, then awaits the rest.
  Future<void> runToCompletion(
    WidgetTester tester,
    CalculationProvider provider, {
    required String person1Name,
    required String person2Name,
  }) async {
    final future = provider.calculateAggregatedBalances(
      householdId: householdId,
      categories: categories,
      person1Name: person1Name,
      person2Name: person2Name,
    );
    await tester.pump();
    await future;
  }

  group('CalculationProvider.calculateAggregatedBalances', () {
    testWidgets(
        'populates balanceResult, householdTotals, and per-person expense '
        'counts on success', (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonPaidTotal: ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              paidBy == person1 ? 120.0 : 80.0,
          fetchPersonBillCount: ({required householdId, required paidBy}) async =>
              paidBy == person1 ? 4 : 2,
          fetchHouseholdTotals: ({required householdId}) async =>
              const HouseholdTotals(billCount: 3, totalAmount: 200.0),
        ),
      );

      expect(provider.isCalculating, isFalse);

      final future = provider.calculateAggregatedBalances(
        householdId: householdId,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );

      // setCalculating happens synchronously before any await.
      expect(provider.isCalculating, isTrue);
      expect(provider.balanceResult, isNull);
      expect(provider.householdTotals, isNull);
      expect(provider.person1ExpenseCount, 0);
      expect(provider.person2ExpenseCount, 0);

      await tester.pump();
      await future;

      expect(provider.isCalculating, isFalse);
      expect(provider.error, isNull);
      expect(provider.balanceResult, isNotNull);
      expect(provider.balanceResult!.person1Paid, 120.0);
      expect(provider.balanceResult!.person2Paid, 80.0);
      expect(provider.householdTotals, isNotNull);
      expect(provider.householdTotals!.billCount, 3);
      expect(provider.householdTotals!.totalAmount, 200.0);
      expect(provider.person1ExpenseCount, 4);
      expect(provider.person2ExpenseCount, 2);
    });

    testWidgets(
        'a thrown error from fetchPersonBillCount is caught and clears the '
        'expense counts', (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonBillCount: ({required householdId, required paidBy}) async =>
              throw Exception('network error'),
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);

      expect(provider.error, contains('Calculation error'));
      expect(provider.person1ExpenseCount, 0);
      expect(provider.person2ExpenseCount, 0);
    });

    testWidgets(
        'a thrown error from a fetcher is caught and surfaces via error, '
        'not as an unhandled exception', (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonPaidTotal: ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              throw Exception('network error'),
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);

      expect(provider.isCalculating, isFalse);
      expect(provider.error, contains('Calculation error'));
      expect(provider.balanceResult, isNull);
      expect(provider.householdTotals, isNull);
    });

    testWidgets('a split referencing an unknown category surfaces via error',
        (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchSplits: ({required householdId}) async => [
            PaymentSplit(
              category: 'NotARealCategory',
              person1: person1,
              person1Percentage: 50.0,
              person2: person2,
              person2Percentage: 50.0,
            ),
          ],
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);

      expect(provider.error, isNotNull);
      expect(provider.balanceResult, isNull);
    });

    testWidgets('clearError clears a prior error', (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonPaidTotal: ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              throw Exception('network error'),
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);
      expect(provider.error, isNotNull);

      provider.clearError();
      expect(provider.error, isNull);
    });

    testWidgets('reset clears balanceResult, householdTotals, and error',
        (tester) async {
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonPaidTotal: ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async =>
              10.0,
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);
      expect(provider.balanceResult, isNotNull);
      expect(provider.householdTotals, isNotNull);

      provider.reset();

      expect(provider.balanceResult, isNull);
      expect(provider.householdTotals, isNull);
      expect(provider.error, isNull);
      expect(provider.isCalculating, isFalse);
    });

    testWidgets(
        'a second call replaces the state from the first (no stale data '
        'lingers)', (tester) async {
      var callCount = 0;
      final provider = CalculationProvider(
        aggregatedCalculationService: serviceWith(
          fetchPersonPaidTotal: ({
            required householdId,
            required paidBy,
            required trackedPersonNames,
          }) async {
            callCount++;
            return callCount <= 2 ? 10.0 : 999.0;
          },
        ),
      );

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);
      expect(provider.balanceResult!.person1Paid, 10.0);

      await runToCompletion(tester, provider,
          person1Name: person1, person2Name: person2);
      expect(provider.balanceResult!.person1Paid, 999.0);
    });
  });
}
