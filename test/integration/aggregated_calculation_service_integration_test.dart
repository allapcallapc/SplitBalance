// Integration suite for AggregatedCalculationService's *real*
// Supabase-calling default implementations - the one thing the rest of
// this test framework deliberately doesn't exercise (everywhere else uses
// injected fakes). Runs against a local Supabase stack only
// (`supabase start`, via tool/run_integration_tests.ps1) - never the hosted
// project. Tagged 'integration' and excluded from the default `flutter
// test` run (see dart_test.yaml and .github/workflows/test.yml) since it
// needs Docker.
//
// Uses the service-role key to seed data, bypassing RLS - this suite tests
// query correctness (do the sums/filters return the right numbers), not RLS
// enforcement, which is a separate concern.

@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';

void main() {
  late SupabaseClient admin;
  final createdHouseholdIds = <String>[];

  setUpAll(() async {
    final url = Platform.environment['SUPABASE_TEST_URL'];
    final serviceRoleKey = Platform.environment['SUPABASE_TEST_SERVICE_ROLE_KEY'];

    if (url == null || serviceRoleKey == null) {
      throw StateError(
        'SUPABASE_TEST_URL and SUPABASE_TEST_SERVICE_ROLE_KEY must be set to '
        'run this suite - see tool/run_integration_tests.ps1, which starts a '
        'local Supabase stack and sets both automatically. Run that script '
        'instead of `flutter test` directly for this file.',
      );
    }

    // Supabase.initialize() persists its session via SharedPreferences,
    // which needs a mocked platform channel under `flutter test` - same
    // setup as test/widget_test.dart and test/summary_screen_test.dart.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: url, anonKey: serviceRoleKey);
    admin = Supabase.instance.client;
  });

  tearDown(() async {
    for (final id in createdHouseholdIds) {
      // Cascades to bills/payment_splits/categories/household_members via
      // the FKs' `on delete cascade` in the initial schema migration.
      await admin.from('households').delete().eq('id', id);
    }
    createdHouseholdIds.clear();
  });

  Future<String> seedHousehold({
    required List<Map<String, dynamic>> categoryRows,
    required List<Map<String, dynamic>> billRows,
    required List<Map<String, dynamic>> splitRows,
  }) async {
    final household =
        await admin.from('households').insert({}).select().single();
    final householdId = household['id'] as String;
    createdHouseholdIds.add(householdId);

    if (categoryRows.isNotEmpty) {
      await admin.from('categories').insert(
          categoryRows.map((r) => {...r, 'household_id': householdId}).toList());
    }
    if (billRows.isNotEmpty) {
      await admin.from('bills').insert(
          billRows.map((r) => {...r, 'household_id': householdId}).toList());
    }
    if (splitRows.isNotEmpty) {
      await admin.from('payment_splits').insert(
          splitRows.map((r) => {...r, 'household_id': householdId}).toList());
    }

    return householdId;
  }

  group('AggregatedCalculationService - real Supabase queries', () {
    test('simple 50/50 split across two people, one category', () async {
      final householdId = await seedHousehold(
        categoryRows: [
          {'name': 'Food'},
        ],
        billRows: [
          {
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          },
          {
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Bob',
            'category': 'Food',
          },
        ],
        splitRows: [
          {
            'category': 'Food',
            'person1': 'Alice',
            'person1_percentage': 50.0,
            'person2': 'Bob',
            'person2_percentage': 50.0,
          },
        ],
      );

      final service = AggregatedCalculationService();
      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );

      expect(result.person1Paid, closeTo(100.0, 0.01));
      expect(result.person2Paid, closeTo(100.0, 0.01));
      expect(result.person1Expected, closeTo(100.0, 0.01));
      expect(result.person2Expected, closeTo(100.0, 0.01));
      expect(result.netBalance, closeTo(0.0, 0.01));

      final foodBalance = result.categoryBalances['Food'];
      expect(foodBalance, isNotNull);
      expect(foodBalance!.person1Paid, closeTo(100.0, 0.01));
      expect(foodBalance.person2Paid, closeTo(100.0, 0.01));

      final totals = await service.fetchHouseholdTotals(householdId: householdId);
      expect(totals.billCount, 2);
      expect(totals.totalAmount, closeTo(200.0, 0.01));
    });

    test('category-specific split overrides the default, across two '
        'categories, one paid entirely by person1', () async {
      final householdId = await seedHousehold(
        categoryRows: [
          {'name': 'Rent'},
          {'name': 'Food'},
        ],
        billRows: [
          {
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Rent',
          },
          {
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          },
        ],
        splitRows: [
          {
            'category': 'Rent',
            'person1': 'Alice',
            'person1_percentage': 70.0,
            'person2': 'Bob',
            'person2_percentage': 30.0,
          },
        ],
      );

      final service = AggregatedCalculationService();
      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Rent'), Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );

      expect(result.person1Paid, closeTo(200.0, 0.01));
      expect(result.person2Paid, closeTo(0.0, 0.01));
      // Rent: 70% of 100 = 70. Food has no matching split (no 'all'
      // fallback seeded), so it contributes nothing to expected.
      expect(result.person1Expected, closeTo(70.0, 0.01));
      expect(result.person2Expected, closeTo(30.0, 0.01));

      final rentBalance = result.categoryBalances['Rent'];
      expect(rentBalance!.person1Expected, closeTo(70.0, 0.01));

      // Food had a paid bill but no matching split: still shows up with
      // its paid amount, zero expected - matches CalculationService's
      // documented paid/expected asymmetry.
      final foodBalance = result.categoryBalances['Food'];
      expect(foodBalance, isNotNull);
      expect(foodBalance!.person1Paid, closeTo(100.0, 0.01));
      expect(foodBalance.person1Expected, closeTo(0.0, 0.01));
    });

    test('a bill dated exactly split.endDate + 1 day resolves through the '
        'real query the same way the parity suite proved in memory',
        () async {
      final householdId = await seedHousehold(
        categoryRows: [
          {'name': 'Food'},
        ],
        billRows: [
          // The day after the first split's end_date (2024-01-31) - used
          // to be an ambiguous boundary day under a now-fixed
          // PaymentSplit.containsDate bug; see
          // test/aggregated_calculation_parity_test.dart's "split-list
          // ordering independence" group for the real-world case that
          // caught it.
          {
            'date': '2024-02-01',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          },
        ],
        // 'all'-category splits are UI-only (see PaymentSplit.toMap) and
        // the database rejects them via payment_splits_category_check - use
        // the real category directly, equivalent for a single-category
        // scenario like this one.
        splitRows: [
          {
            'category': 'Food',
            'end_date': '2024-01-31',
            'person1': 'Alice',
            'person1_percentage': 60.0,
            'person2': 'Bob',
            'person2_percentage': 40.0,
          },
          {
            'category': 'Food',
            'end_date': '2024-02-28',
            'person1': 'Alice',
            'person1_percentage': 50.0,
            'person2': 'Bob',
            'person2_percentage': 50.0,
          },
        ],
      );

      final service = AggregatedCalculationService();
      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );

      // The day after the first split's end_date belongs to the *second*
      // split (50/50), unambiguously - not the closing 60/40 split. Also
      // implicitly exercises calculateBalances' own canonicalization of
      // whatever order the real DB happens to return splits in (see
      // compareSplitsNewestFirst).
      expect(result.person1Expected, closeTo(50.0, 0.01));
      expect(result.person2Expected, closeTo(50.0, 0.01));
    });

    test(
      'a payer with more bills than PostgREST max_rows is not silently '
      'truncated - the exact bug '
      'https://github.com/allapcallapc/SplitBalance/issues/57 describes',
      () async {
        // supabase/config.toml sets max_rows = 1000. A naive single
        // `.select('amount')` + fold-in-Dart would silently cap at
        // max_rows instead of erroring, so a payer with more bills than
        // that would get a quietly undercounted total (#57). The default
        // fetch functions avoid this without a server-side RPC: sums page
        // through .range() in chunks of _pageSize, and counts use
        // .count(CountOption.exact) (a HEAD request PostgREST answers via
        // Content-Range, without ever materializing/truncating a row body).
        const billCount = 1200;
        final householdId = await seedHousehold(
          categoryRows: [
            {'name': 'Food'},
          ],
          billRows: const [],
          splitRows: const [],
        );

        const batchSize = 500;
        for (var start = 0; start < billCount; start += batchSize) {
          final end =
              (start + batchSize < billCount) ? start + batchSize : billCount;
          await admin.from('bills').insert(List.generate(
                end - start,
                (_) => {
                  'household_id': householdId,
                  'date': '2024-01-01',
                  'amount': 1.0,
                  'paid_by': 'Alice',
                  'category': 'Food',
                },
              ));
        }

        final service = AggregatedCalculationService();

        final totals =
            await service.fetchHouseholdTotals(householdId: householdId);
        expect(totals.billCount, billCount);
        expect(totals.totalAmount, closeTo(billCount.toDouble(), 0.01));

        // fetchPersonBillCount at the same scale - the "Expenses Added" stat
        // had the identical unpaginated-.select() bug until it switched to
        // .count(CountOption.exact), a HEAD-request count max_rows can't
        // truncate.
        final aliceBillCount = await service.fetchPersonBillCount(
          householdId: householdId,
          paidBy: 'Alice',
        );
        expect(aliceBillCount, billCount);

        final result = await service.calculateBalances(
          householdId: householdId,
          categories: [Category(name: 'Food')],
          person1Name: 'Alice',
          person2Name: 'Bob',
        );
        expect(result.person1Paid, closeTo(billCount.toDouble(), 0.01));

        // Also exercises the category/period paid-total path at the same
        // scale (all 1200 bills fall into Food's single open-ended period,
        // since no splits were seeded) - not just the household/person
        // totals above. 1200 > _pageSize (1000), so this exercises the
        // multi-page branch of _sumAmounts, not just its single-page path.
        final foodBalance = result.categoryBalances['Food'];
        expect(foodBalance, isNotNull);
        expect(foodBalance!.person1Paid, closeTo(billCount.toDouble(), 0.01));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('AggregatedCalculationService - reimbursements (real Supabase '
      'queries)', () {
    // seedHousehold's billRows path doesn't hand back generated ids, and
    // bill_reimbursements needs a real bill_id to link against - so these
    // tests seed bills directly instead, capturing the inserted row.
    test('a reimbursement reduces the payer\'s total and the household '
        'total, without changing the 50/50 split ratio', () async {
      final household =
          await admin.from('households').insert({}).select().single();
      final householdId = household['id'] as String;
      createdHouseholdIds.add(householdId);

      await admin.from('categories').insert({
        'household_id': householdId,
        'name': 'Food',
      });
      final bill = await admin
          .from('bills')
          .insert({
            'household_id': householdId,
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          })
          .select()
          .single();
      await admin.from('payment_splits').insert({
        'household_id': householdId,
        'category': 'Food',
        'person1': 'Alice',
        'person1_percentage': 50.0,
        'person2': 'Bob',
        'person2_percentage': 50.0,
      });
      await admin.from('bill_reimbursements').insert({
        'household_id': householdId,
        'bill_id': bill['id'],
        'date': '2024-01-20',
        'amount': 30.0,
        'received_by': 'Alice',
      });

      final service = AggregatedCalculationService();
      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );

      // Net cost is 70 (100 - 30), split ratio unchanged at 50/50.
      expect(result.person1Paid, closeTo(70.0, 0.01));
      expect(result.person2Paid, closeTo(0.0, 0.01));
      expect(result.person1Expected, closeTo(35.0, 0.01));
      expect(result.person2Expected, closeTo(35.0, 0.01));

      final foodBalance = result.categoryBalances['Food'];
      expect(foodBalance, isNotNull);
      expect(foodBalance!.person1Paid, closeTo(70.0, 0.01));

      final totals = await service.fetchHouseholdTotals(householdId: householdId);
      expect(totals.billCount, 1); // reimbursements aren't bills
      expect(totals.totalAmount, closeTo(70.0, 0.01));
    });

    test('a reimbursement on one payer\'s bill does not leak into the '
        'other payer\'s total (proves the bills!inner(paid_by) embed '
        'filters correctly)', () async {
      final household =
          await admin.from('households').insert({}).select().single();
      final householdId = household['id'] as String;
      createdHouseholdIds.add(householdId);

      await admin.from('categories').insert({
        'household_id': householdId,
        'name': 'Food',
      });
      final aliceBill = await admin
          .from('bills')
          .insert({
            'household_id': householdId,
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          })
          .select()
          .single();
      await admin.from('bills').insert({
        'household_id': householdId,
        'date': '2024-01-15',
        'amount': 100.0,
        'paid_by': 'Bob',
        'category': 'Food',
      });
      // Only Alice's bill is reimbursed.
      await admin.from('bill_reimbursements').insert({
        'household_id': householdId,
        'bill_id': aliceBill['id'],
        'date': '2024-01-20',
        'amount': 40.0,
        'received_by': 'Alice',
      });

      final service = AggregatedCalculationService();
      final result = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );

      expect(result.person1Paid, closeTo(60.0, 0.01)); // 100 - 40
      expect(result.person2Paid, closeTo(100.0, 0.01)); // untouched
    });

    test('deleting a reimbursement restores the bill\'s full amount to the '
        'calculation', () async {
      final household =
          await admin.from('households').insert({}).select().single();
      final householdId = household['id'] as String;
      createdHouseholdIds.add(householdId);

      await admin.from('categories').insert({
        'household_id': householdId,
        'name': 'Food',
      });
      final bill = await admin
          .from('bills')
          .insert({
            'household_id': householdId,
            'date': '2024-01-15',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          })
          .select()
          .single();
      final reimbursement = await admin
          .from('bill_reimbursements')
          .insert({
            'household_id': householdId,
            'bill_id': bill['id'],
            'date': '2024-01-20',
            'amount': 25.0,
            'received_by': 'Alice',
          })
          .select()
          .single();

      final service = AggregatedCalculationService();
      final reimbursedResult = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );
      expect(reimbursedResult.person1Paid, closeTo(75.0, 0.01));

      await admin
          .from('bill_reimbursements')
          .delete()
          .eq('id', reimbursement['id']);

      final restoredResult = await service.calculateBalances(
        householdId: householdId,
        categories: [Category(name: 'Food')],
        person1Name: 'Alice',
        person2Name: 'Bob',
      );
      expect(restoredResult.person1Paid, closeTo(100.0, 0.01));
    });
  });
}
