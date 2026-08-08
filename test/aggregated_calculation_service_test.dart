// Orchestration-focused unit tests for AggregatedCalculationService: how it
// calls its injected fetch functions and assembles their results into a
// BalanceResult. Uses hand-written fake closures (no mocking framework, no
// real Supabase - see test/bills_provider_test.dart for the same pattern
// this repo already uses).

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';

void main() {
  const person1 = 'Alice';
  const person2 = 'Bob';
  const householdId = 'household-1';

  List<Category> categories([List<String>? names]) =>
      (names ?? ['Food', 'Rent']).map((n) => Category(name: n)).toList();

  group('AggregatedCalculationService - orchestration', () {
    test('fetches splits and both persons\' global paid totals exactly once',
        () async {
      var splitsCalls = 0;
      final paidCalls = <String>[];

      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async {
          splitsCalls++;
          return [];
        },
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async {
          paidCalls.add(paidBy);
          return paidBy == person1 ? 150.0 : 50.0;
        },
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
      );

      final result = await service.calculateBalances(
        householdId: householdId,
        categories: categories(),
        person1Name: person1,
        person2Name: person2,
      );

      expect(splitsCalls, 1);
      expect(paidCalls, unorderedEquals([person1, person2]));
      expect(result.person1Paid, 150.0);
      expect(result.person2Paid, 50.0);
    });

    test('empty categories list: no category/period fetches at all',
        () async {
      var categoryPeriodCalls = 0;

      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            0.0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async {
          categoryPeriodCalls++;
          return 0.0;
        },
      );

      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [],
        person1Name: person1,
        person2Name: person2,
      );

      expect(categoryPeriodCalls, 0);
      expect(result.categoryBalances, isEmpty);
    });

    test(
        'one category, no splits: single open period fetched once per person',
        () async {
      final requestedPeriods = <String>[];

      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            0.0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async {
          requestedPeriods.add('$category|$periodStart|$periodEnd|$paidBy');
          return 0.0;
        },
      );

      await service.calculateBalances(
        householdId: householdId,
        categories: categories(['Food']),
        person1Name: person1,
        person2Name: person2,
      );

      // A single fully-open period (start: null, end: null), fetched once
      // per person - no wasted calls.
      expect(requestedPeriods, unorderedEquals([
        'Food|null|null|$person1',
        'Food|null|null|$person2',
      ]));
    });

    test(
        'no-matching-split case: paid amounts land in categoryBalances with '
        'zero expected, and reach the top-level paid totals but not the '
        'top-level expected totals', () async {
      final splits = [
        PaymentSplit(
          endDate: DateTime(2024, 1, 1), // ends before the bill period
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];

      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => splits,
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            paidBy == person1 ? 100.0 : 0.0,
        // The lone split only covers dates up to 2024-01-01, so every
        // period after that has no matching split - simulate a bill
        // entirely in that unmatched trailing period.
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async {
          if (periodEnd == null && paidBy == person1) return 100.0;
          return 0.0;
        },
      );

      final result = await service.calculateBalances(
        householdId: householdId,
        categories: categories(['Food']),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.person1Paid, 100.0); // top-level paid: unconditional
      expect(result.person1Expected, 0.0); // top-level expected: match-gated
      expect(result.person2Expected, 0.0);

      final foodBalance = result.categoryBalances['Food'];
      expect(foodBalance, isNotNull);
      expect(foodBalance!.person1Paid, 100.0);
      expect(foodBalance.person1Expected, 0.0);
      expect(foodBalance.person2Expected, 0.0);
    });

    test('a category+period with zero paid amount is skipped: no entry '
        'created', () async {
      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            0.0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
      );

      final result = await service.calculateBalances(
        householdId: householdId,
        categories: categories(['Food', 'Rent']),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.categoryBalances, isEmpty);
    });

    test('a fetcher throwing surfaces as an error on calculateBalances',
        () async {
      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            throw Exception('network error'),
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
      );

      expect(
        () => service.calculateBalances(
          householdId: householdId,
          categories: categories(),
          person1Name: person1,
          person2Name: person2,
        ),
        throwsException,
      );
    });

    test('a split referencing an unknown category throws ArgumentError, '
        'matching CalculationService', () async {
      final splits = [
        PaymentSplit(
          category: 'NotARealCategory',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];

      final service = AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => splits,
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            0.0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
      );

      expect(
        () => service.calculateBalances(
          householdId: householdId,
          categories: categories(),
          person1Name: person1,
          person2Name: person2,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fetchHouseholdTotals passes through to the injected fetcher',
        () async {
      final service = AggregatedCalculationService(
        fetchHouseholdTotals: ({required householdId}) async =>
            const HouseholdTotals(billCount: 7, totalAmount: 543.21),
      );

      final totals = await service.fetchHouseholdTotals(
        householdId: householdId,
      );

      expect(totals.billCount, 7);
      expect(totals.totalAmount, 543.21);
    });

    test('fetchPersonBillCount passes through to the injected fetcher',
        () async {
      final service = AggregatedCalculationService(
        fetchPersonBillCount: ({required householdId, required paidBy}) async =>
            paidBy == person1 ? 4 : 2,
      );

      final person1Count = await service.fetchPersonBillCount(
        householdId: householdId,
        paidBy: person1,
      );
      final person2Count = await service.fetchPersonBillCount(
        householdId: householdId,
        paidBy: person2,
      );

      expect(person1Count, 4);
      expect(person2Count, 2);
    });
  });
}
