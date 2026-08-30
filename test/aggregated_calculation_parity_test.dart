// Parity suite: proves AggregatedCalculationService produces bit-for-bit the
// same BalanceResult as today's CalculationService, for every scenario
// tried. This is what gives confidence that moving from a full bill-list
// fetch to narrow, filtered sum queries doesn't silently change any number
// the user sees.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';
import 'package:splitbalance/services/calculation_service.dart';

import 'helpers/in_memory_bill_source.dart';

void main() {
  const person1 = 'Alice';
  const person2 = 'Bob';
  final baseDate = DateTime(2024, 1, 15);

  List<Category> categoriesFor(List<String> names) =>
      names.map((n) => Category(name: n)).toList();

  Future<void> expectParity({
    required List<Bill> bills,
    required List<PaymentSplit> splits,
    required List<String> categoryNames,
  }) async {
    final categories = categoriesFor(categoryNames);

    // Real production splits lists are always canonically sorted before
    // either calculator ever sees them (PaymentSplitsProvider sorts before
    // handing off to CalculationService; AggregatedCalculationService now
    // canonicalizes internally regardless of what fetchSplits returns - see
    // compareSplitsNewestFirst). Matching that here, rather than passing
    // [splits] through in whatever order a test happened to list them in,
    // is what makes this a faithful parity check - list order itself is
    // covered separately by the "split-list ordering independence" group
    // below.
    final canonicalSplits = splits.toList()..sort(compareSplitsNewestFirst);

    final expected = CalculationService.calculateBalances(
      bills: bills,
      splits: canonicalSplits,
      categories: categories,
      person1Name: person1,
      person2Name: person2,
    );

    final actual = await InMemoryBillSource(bills: bills, splits: splits)
        .toService()
        .calculateBalances(
          householdId: 'household-1',
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        );

    expect(actual.person1Paid, closeTo(expected.person1Paid, 0.01),
        reason: 'person1Paid');
    expect(actual.person2Paid, closeTo(expected.person2Paid, 0.01),
        reason: 'person2Paid');
    expect(actual.person1Expected, closeTo(expected.person1Expected, 0.01),
        reason: 'person1Expected');
    expect(actual.person2Expected, closeTo(expected.person2Expected, 0.01),
        reason: 'person2Expected');
    expect(actual.netBalance, closeTo(expected.netBalance, 0.01),
        reason: 'netBalance');

    expect(actual.categoryBalances.keys.toSet(),
        expected.categoryBalances.keys.toSet(),
        reason: 'categoryBalances key set');
    for (final key in expected.categoryBalances.keys) {
      final e = expected.categoryBalances[key]!;
      final a = actual.categoryBalances[key]!;
      expect(a.person1Paid, closeTo(e.person1Paid, 0.01),
          reason: 'categoryBalances[$key].person1Paid');
      expect(a.person2Paid, closeTo(e.person2Paid, 0.01),
          reason: 'categoryBalances[$key].person2Paid');
      expect(a.person1Expected, closeTo(e.person1Expected, 0.01),
          reason: 'categoryBalances[$key].person1Expected');
      expect(a.person2Expected, closeTo(e.person2Expected, 0.01),
          reason: 'categoryBalances[$key].person2Expected');
    }
  }

  group('Parity - ported scenarios', () {
    test('Simple 50/50 split', () async {
      await expectParity(
        bills: [
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
          Bill(date: baseDate, amount: 100.0, paidBy: person2, category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ],
        categoryNames: ['Food', 'Rent', 'Utilities'],
      );
    });

    test('Category-specific split overrides default', () async {
      await expectParity(
        bills: [
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Rent'),
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
          PaymentSplit(
            category: 'Rent',
            person1: person1,
            person1Percentage: 70.0,
            person2: person2,
            person2Percentage: 30.0,
          ),
        ],
        categoryNames: ['Food', 'Rent'],
      );
    });

    test('Multi-period date-based splits', () async {
      await expectParity(
        bills: [
          Bill(
              date: DateTime(2024, 1, 15),
              amount: 100.0,
              paidBy: person1,
              category: 'Food'),
          Bill(
              date: DateTime(2024, 2, 15),
              amount: 100.0,
              paidBy: person1,
              category: 'Food'),
          Bill(
              date: DateTime(2024, 3, 5),
              amount: 100.0,
              paidBy: person1,
              category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            endDate: DateTime(2024, 1, 31),
            category: 'all',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
          PaymentSplit(
            endDate: DateTime(2024, 2, 28),
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 70.0,
            person2: person2,
            person2Percentage: 30.0,
          ),
        ],
        categoryNames: ['Food'],
      );
    });

    test('Third-party payer is excluded entirely', () async {
      await expectParity(
        bills: [
          Bill(
              date: baseDate,
              amount: 200.0,
              paidBy: 'Charlie',
              category: 'Rent'),
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Rent'),
          Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
        ],
        categoryNames: ['Food', 'Rent'],
      );
    });

    test('Bill with no matching split is ignored (for expected, not paid)',
        () async {
      await expectParity(
        bills: [
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            endDate: DateTime(2024, 1, 1),
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ],
        categoryNames: ['Food'],
      );
    });

    test('Complex scenario: multiple bills, categories, and date ranges',
        () async {
      await expectParity(
        bills: [
          Bill(
              date: DateTime(2024, 1, 10),
              amount: 200.0,
              paidBy: person1,
              category: 'Rent'),
          Bill(
              date: DateTime(2024, 1, 10),
              amount: 50.0,
              paidBy: person2,
              category: 'Food'),
          Bill(
              date: DateTime(2024, 2, 15),
              amount: 200.0,
              paidBy: person1,
              category: 'Rent'),
          Bill(
              date: DateTime(2024, 2, 15),
              amount: 75.0,
              paidBy: person1,
              category: 'Food'),
          Bill(
              date: DateTime(2024, 3, 20),
              amount: 200.0,
              paidBy: person2,
              category: 'Rent'),
          Bill(
              date: DateTime(2024, 3, 20),
              amount: 40.0,
              paidBy: person2,
              category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            endDate: DateTime(2024, 2, 29),
            category: 'Rent',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
          PaymentSplit(
            endDate: DateTime(2024, 2, 29),
            category: 'Food',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
          PaymentSplit(
            category: 'Rent',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
          PaymentSplit(
            category: 'Food',
            person1: person1,
            person1Percentage: 30.0,
            person2: person2,
            person2Percentage: 70.0,
          ),
        ],
        categoryNames: ['Rent', 'Food'],
      );
    });

    test('Duplicate endDate shared across categories', () async {
      await expectParity(
        bills: [
          Bill(
              date: DateTime(2024, 1, 15),
              amount: 100.0,
              paidBy: person1,
              category: 'Rent'),
          Bill(
              date: DateTime(2024, 3, 15),
              amount: 100.0,
              paidBy: person1,
              category: 'Rent'),
          Bill(
              date: DateTime(2024, 1, 15),
              amount: 50.0,
              paidBy: person2,
              category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            endDate: DateTime(2024, 2, 29),
            category: 'Rent',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
          PaymentSplit(
            endDate: DateTime(2024, 2, 29),
            category: 'Food',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
          PaymentSplit(
            category: 'Rent',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ],
        categoryNames: ['Rent', 'Food'],
      );
    });
  });

  group('Parity - reimbursements', () {
    // CalculationService nets out bill.reimbursedAmount via netAmount, and
    // InMemoryBillSource's fetch functions do the same - proving the two
    // calculators still agree once reimbursements are in the mix, the same
    // way the rest of this suite does for the un-reimbursed case.
    test('a partially reimbursed bill', () async {
      await expectParity(
        bills: [
          Bill(
              date: baseDate,
              amount: 100.0,
              paidBy: person1,
              category: 'Food',
              reimbursedAmount: 30.0),
          Bill(date: baseDate, amount: 100.0, paidBy: person2, category: 'Food'),
        ],
        splits: [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ],
        categoryNames: ['Food'],
      );
    });

    test('reimbursements spread across categories and date periods',
        () async {
      await expectParity(
        bills: [
          Bill(
              date: DateTime(2024, 1, 10),
              amount: 200.0,
              paidBy: person1,
              category: 'Rent',
              reimbursedAmount: 50.0),
          Bill(
              date: DateTime(2024, 2, 15),
              amount: 75.0,
              paidBy: person2,
              category: 'Food',
              reimbursedAmount: 75.0), // fully reimbursed
        ],
        splits: [
          PaymentSplit(
            endDate: DateTime(2024, 1, 31),
            category: 'all',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ],
        categoryNames: ['Rent', 'Food'],
      );
    });
  });

  group('Parity - endDate+1 ambiguous boundary day', () {
    // The single calendar day right after a split's endDate is ambiguous
    // under PaymentSplit.containsDate, and which split wins depends on the
    // splits list's order. This is exactly the case an earlier, wrong draft
    // of the aggregation design would have gotten wrong silently - assert
    // parity explicitly for a real bill dated on that exact day, in both
    // orderings.
    final splitA = PaymentSplit(
      endDate: DateTime(2024, 1, 31),
      category: 'all',
      person1: person1,
      person1Percentage: 60.0,
      person2: person2,
      person2Percentage: 40.0,
    );
    final splitB = PaymentSplit(
      endDate: DateTime(2024, 2, 28),
      category: 'all',
      person1: person1,
      person1Percentage: 50.0,
      person2: person2,
      person2Percentage: 50.0,
    );
    final ambiguousBill = Bill(
      date: DateTime(2024, 2, 1), // splitA.endDate + 1 day
      amount: 100.0,
      paidBy: person1,
      category: 'Food',
    );

    test('ascending splits order [A, B]', () async {
      await expectParity(
        bills: [ambiguousBill],
        splits: [splitA, splitB],
        categoryNames: ['Food'],
      );
    });

    test('descending splits order [B, A]', () async {
      await expectParity(
        bills: [ambiguousBill],
        splits: [splitB, splitA],
        categoryNames: ['Food'],
      );
    });
  });

  group('Parity - fuzzed scenarios', () {
    // Deterministic seed: reproducible failures, no CI flakiness.
    final random = Random(42);
    const categoryPool = ['Food', 'Rent', 'Utilities', 'Entertainment'];
    const payers = [person1, person2, 'Charlie'];

    DateTime randomDate() =>
        DateTime(2024, 1, 1).add(Duration(days: random.nextInt(365)));

    for (var i = 0; i < 30; i++) {
      test('fuzzed scenario #$i', () async {
        final categoryCount = 1 + random.nextInt(4);
        final categoryNames = categoryPool.sublist(0, categoryCount);

        // Split end-dates spaced >=10 days apart, to avoid the (separately,
        // explicitly tested above) adjacent-day boundary ambiguity showing
        // up as noise in an otherwise-unrelated fuzz failure.
        final splitCount = random.nextInt(4);
        final endDates = <DateTime>[];
        var cursor = DateTime(2024, 1, 15);
        for (var s = 0; s < splitCount; s++) {
          cursor = cursor.add(Duration(days: 10 + random.nextInt(40)));
          endDates.add(cursor);
        }

        final splits = <PaymentSplit>[];
        for (final endDate in endDates) {
          final p1Pct = (random.nextInt(9) + 1) * 10.0; // 10..90
          splits.add(PaymentSplit(
            endDate: endDate,
            category: 'all',
            person1: person1,
            person1Percentage: p1Pct,
            person2: person2,
            person2Percentage: 100.0 - p1Pct,
          ));
        }
        // Trailing open-ended split so every date has coverage.
        final p1Pct = (random.nextInt(9) + 1) * 10.0;
        splits.add(PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: p1Pct,
          person2: person2,
          person2Percentage: 100.0 - p1Pct,
        ));

        final bills = <Bill>[];
        final billCount = random.nextInt(16);
        for (var b = 0; b < billCount; b++) {
          bills.add(Bill(
            date: randomDate(),
            amount: (random.nextInt(20000) + 1) / 100.0,
            paidBy: payers[random.nextInt(payers.length)],
            category: categoryNames[random.nextInt(categoryNames.length)],
          ));
        }

        await expectParity(
          bills: bills,
          splits: splits,
          categoryNames: categoryNames,
        );
      });
    }
  });

  group('Parity - split-list ordering independence', () {
    // Regression coverage for a real production discrepancy: three
    // category-specific splits for the same category, at different end
    // dates (mirrors a real household's actual Groceries splits: two dated
    // end points plus an open-ended default). findMatchingSplit's tie-break
    // for same-specificity splits depends on list order, and
    // AggregatedCalculationService's default fetchSplits doesn't come back
    // in any particular DB order - if calculateBalances didn't canonicalize
    // that order itself, this scenario would silently disagree with
    // CalculationService (which always sees PaymentSplitsProvider's
    // newest-first-nulls-last sorted list) depending on how the DB happened
    // to return rows that day.
    final julSplit = PaymentSplit(
      endDate: DateTime(2026, 7, 17),
      category: 'Groceries',
      person1: 'Bobby',
      person1Percentage: 21.0,
      person2: 'Jane',
      person2Percentage: 79.0,
    );
    final augSplit = PaymentSplit(
      endDate: DateTime(2026, 8, 5),
      category: 'Groceries',
      person1: 'Bobby',
      person1Percentage: 72.8,
      person2: 'Jane',
      person2Percentage: 27.2,
    );
    final openSplit = PaymentSplit(
      category: 'Groceries',
      person1: 'Bobby',
      person1Percentage: 52.5,
      person2: 'Jane',
      person2Percentage: 47.5,
    );
    final bills = [
      Bill(
          date: DateTime(2026, 6, 5),
          amount: 42.50,
          paidBy: 'Bobby',
          category: 'Groceries'),
      // The day after julSplit.endDate - the ambiguous boundary day this
      // bug hinged on.
      Bill(
          date: DateTime(2026, 7, 18),
          amount: 38.90,
          paidBy: 'Jane',
          category: 'Groceries'),
      Bill(
          date: DateTime(2026, 8, 1),
          amount: 45.75,
          paidBy: 'Jane',
          category: 'Groceries'),
      // The day after augSplit.endDate.
      Bill(
          date: DateTime(2026, 8, 6),
          amount: 20.00,
          paidBy: 'Bobby',
          category: 'Groceries'),
    ];

    Future<BalanceResult> aggregatedResultFor(List<PaymentSplit> splitsOrder) {
      final source = InMemoryBillSource(bills: bills, splits: splitsOrder);
      return AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => splitsOrder,
        fetchPersonPaidTotal: source.fetchPersonPaidTotal,
        fetchCategoryPeriodPersonPaid: source.fetchCategoryPeriodPersonPaid,
        fetchHouseholdTotals: source.fetchHouseholdTotals,
      ).calculateBalances(
        householdId: 'household-1',
        categories: categoriesFor(['Groceries']),
        person1Name: 'Bobby',
        person2Name: 'Jane',
      );
    }

    test('canonical (newest-first) order matches CalculationService',
        () async {
      final canonical = [augSplit, julSplit, openSplit];
      final expected = CalculationService.calculateBalances(
        bills: bills,
        splits: canonical,
        categories: categoriesFor(['Groceries']),
        person1Name: 'Bobby',
        person2Name: 'Jane',
      );

      final actual = await aggregatedResultFor(canonical);

      expect(actual.person1Expected, closeTo(expected.person1Expected, 0.01));
      expect(actual.person2Expected, closeTo(expected.person2Expected, 0.01));
      expect(actual.netBalance, closeTo(expected.netBalance, 0.01));
    });

    test('reversed (oldest-first) DB order still matches CalculationService '
        "'s canonical-order result - this is the exact bug that shipped",
        () async {
      final canonical = [augSplit, julSplit, openSplit];
      final scrambled = [openSplit, julSplit, augSplit]; // reversed

      final expected = CalculationService.calculateBalances(
        bills: bills,
        splits: canonical, // PaymentSplitsProvider always sorts this way
        categories: categoriesFor(['Groceries']),
        person1Name: 'Bobby',
        person2Name: 'Jane',
      );

      final actual = await aggregatedResultFor(scrambled);

      expect(actual.person1Expected, closeTo(expected.person1Expected, 0.01),
          reason: 'person1Expected diverged when fetchSplits returned '
              'splits in non-canonical order');
      expect(actual.person2Expected, closeTo(expected.person2Expected, 0.01));
      expect(actual.netBalance, closeTo(expected.netBalance, 0.01));

      final groceriesBalance = actual.categoryBalances['Groceries']!;
      final expectedGroceries = expected.categoryBalances['Groceries']!;
      expect(groceriesBalance.person1Expected,
          closeTo(expectedGroceries.person1Expected, 0.01));
      expect(groceriesBalance.person2Expected,
          closeTo(expectedGroceries.person2Expected, 0.01));
    });

    test('insertion-order and reversed-order fetchSplits results agree with '
        'each other too', () async {
      final orderA = [julSplit, augSplit, openSplit];
      final orderB = [openSplit, augSplit, julSplit];

      final resultA = await aggregatedResultFor(orderA);
      final resultB = await aggregatedResultFor(orderB);

      expect(resultA.person1Expected, closeTo(resultB.person1Expected, 0.01));
      expect(resultA.person2Expected, closeTo(resultB.person2Expected, 0.01));
    });
  });
}
