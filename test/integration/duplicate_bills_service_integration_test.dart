// Integration suite for DuplicateBillsService's *real* Supabase-calling
// default implementations (GH issue #20) - the one thing the rest of this
// test framework deliberately doesn't exercise (everywhere else uses
// injected fakes). In particular, this is the only place that actually
// invokes the row-accumulation closure inside _defaultFetchHouseholdBillRows
// with real rows - a unit test against a fake project URL can only ever
// observe that fetch failing before any row comes back. Runs against a
// local Supabase stack only (`supabase start`, via
// tool/run_integration_tests.ps1) - never the hosted project. Tagged
// 'integration' and excluded from the default `flutter test` run (see
// dart_test.yaml and .github/workflows/test.yml) since it needs Docker.
//
// Uses the service-role key to seed data, bypassing RLS - this suite tests
// query correctness, not RLS enforcement, which is a separate concern.

@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/services/duplicate_bills_service.dart';

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
    // setup as test/widget_test.dart and
    // test/integration/aggregated_calculation_service_integration_test.dart.
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

  Future<String> seedHousehold(List<Map<String, dynamic>> billRows) async {
    final household =
        await admin.from('households').insert({}).select().single();
    final householdId = household['id'] as String;
    createdHouseholdIds.add(householdId);

    if (billRows.isNotEmpty) {
      await admin.from('bills').insert(
          billRows.map((r) => {...r, 'household_id': householdId}).toList());
    }

    return householdId;
  }

  group('DuplicateBillsService - real Supabase queries', () {
    test('findDuplicateGroups groups bills that share a date and amount',
        () async {
      final householdId = await seedHousehold([
        {
          'date': '2024-01-15',
          'amount': 50.0,
          'paid_by': 'Alice',
          'category': 'Rent',
        },
        {
          'date': '2024-01-15',
          'amount': 50.0,
          'paid_by': 'Bob',
          'category': 'Utilities',
        },
        {
          'date': '2024-02-01',
          'amount': 20.0,
          'paid_by': 'Alice',
          'category': 'Food',
        },
      ]);

      final service = DuplicateBillsService();
      final groups = await service.findDuplicateGroups(householdId);

      expect(groups, hasLength(1));
      expect(groups.single.bills, hasLength(2));
      expect(groups.single.date, DateTime.parse('2024-01-15'));
      expect(groups.single.amount, 50.0);
    });

    test('findDuplicateGroups returns no groups when nothing shares a date '
        'and amount', () async {
      final householdId = await seedHousehold([
        {
          'date': '2024-01-15',
          'amount': 50.0,
          'paid_by': 'Alice',
          'category': 'Rent',
        },
        {
          'date': '2024-02-01',
          'amount': 20.0,
          'paid_by': 'Alice',
          'category': 'Food',
        },
      ]);

      final service = DuplicateBillsService();
      final groups = await service.findDuplicateGroups(householdId);

      expect(groups, isEmpty);
    });

    test(
        'findMatches returns bills matching date+amount, excluding excludeId',
        () async {
      final householdId = await seedHousehold([
        {
          'date': '2024-03-10',
          'amount': 75.0,
          'paid_by': 'Alice',
          'category': 'Rent',
        },
        {
          'date': '2024-03-10',
          'amount': 75.0,
          'paid_by': 'Bob',
          'category': 'Utilities',
        },
        {
          'date': '2024-03-11',
          'amount': 75.0,
          'paid_by': 'Alice',
          'category': 'Food',
        },
      ]);

      final service = DuplicateBillsService();
      final matches = await service.findMatches(
        householdId: householdId,
        date: DateTime.parse('2024-03-10'),
        amount: 75.0,
      );

      expect(matches, hasLength(2));

      final excluded = await service.findMatches(
        householdId: householdId,
        date: DateTime.parse('2024-03-10'),
        amount: 75.0,
        excludeId: matches.first.id,
      );

      expect(excluded, hasLength(1));
      expect(excluded.single.id, isNot(matches.first.id));
    });
  });
}
