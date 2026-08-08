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
          // splitA.endDate (2024-01-31) + 1 day - the ambiguous boundary
          // day exercised in test/aggregated_calculation_parity_test.dart.
          {
            'date': '2024-02-01',
            'amount': 100.0,
            'paid_by': 'Alice',
            'category': 'Food',
          },
        ],
        splitRows: [
          {
            'category': 'all',
            'end_date': '2024-01-31',
            'person1': 'Alice',
            'person1_percentage': 60.0,
            'person2': 'Bob',
            'person2_percentage': 40.0,
          },
          {
            'category': 'all',
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

      // The splits list comes back from the DB in whatever order
      // PostgREST/Postgres happens to return unordered rows in, so this
      // asserts the *pair* is internally consistent (sums to the bill
      // amount) rather than pinning one specific split's percentage -
      // list-order dependence for this exact ambiguous day is already
      // covered deterministically by the in-memory parity suite.
      expect(result.person1Expected + result.person2Expected,
          closeTo(100.0, 0.01));
    });
  });
}
