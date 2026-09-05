// Coverage for DuplicateBillsProvider (GH issue #20), mirroring
// bills_provider_test.dart's style: an injected DuplicateBillsService lets
// these run without a real signed-in Supabase session.

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/duplicate_bill_group.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/duplicate_bills_provider.dart';
import 'package:splitbalance/services/duplicate_bills_service.dart';

ConfigProvider signedInConfigProvider({String householdId = 'household-1'}) =>
    ConfigProvider.forTesting(
      isSignedIn: true,
      config: AppConfig(
        householdId: householdId,
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
    );

void main() {
  group('DuplicateBillsProvider.loadDuplicates', () {
    test('is a no-op when not signed in', () async {
      var called = false;
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async {
            called = true;
            return [];
          },
        ),
      );

      await provider
          .loadDuplicates(ConfigProvider.forTesting(isSignedIn: false));

      expect(called, isFalse);
      expect(provider.duplicateGroups, isEmpty);
    });

    test(
        'populates duplicateGroups from the service for the signed-in '
        'household', () async {
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async => [
            {
              'id': 'bill-1',
              'date': '2026-01-01',
              'amount': 10.0,
              'paid_by': 'Alice',
              'category': 'Groceries',
              'details': '',
            },
            {
              'id': 'bill-2',
              'date': '2026-01-01',
              'amount': 10.0,
              'paid_by': 'Bob',
              'category': 'Rent',
              'details': '',
            },
          ],
        ),
      );

      await provider.loadDuplicates(signedInConfigProvider());

      expect(provider.duplicateGroups, hasLength(1));
      expect(provider.duplicateBillCount, 2);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('surfaces a fetch failure as an error instead of throwing',
        () async {
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async =>
              throw Exception('network error'),
        ),
      );

      await provider.loadDuplicates(signedInConfigProvider());

      expect(provider.error, contains('Failed to load duplicate bills'));
      expect(provider.duplicateGroups, isEmpty);
    });

    test('duplicateBillCount sums bills across every group', () async {
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async => [
            {
              'id': 'a1',
              'date': '2026-01-01',
              'amount': 10.0,
              'paid_by': 'Alice',
              'category': 'Groceries',
              'details': '',
            },
            {
              'id': 'a2',
              'date': '2026-01-01',
              'amount': 10.0,
              'paid_by': 'Bob',
              'category': 'Groceries',
              'details': '',
            },
            {
              'id': 'b1',
              'date': '2026-02-01',
              'amount': 20.0,
              'paid_by': 'Alice',
              'category': 'Rent',
              'details': '',
            },
            {
              'id': 'b2',
              'date': '2026-02-01',
              'amount': 20.0,
              'paid_by': 'Bob',
              'category': 'Rent',
              'details': '',
            },
            {
              'id': 'b3',
              'date': '2026-02-01',
              'amount': 20.0,
              'paid_by': 'Alice',
              'category': 'Rent',
              'details': '',
            },
          ],
        ),
      );

      await provider.loadDuplicates(signedInConfigProvider());

      expect(provider.duplicateGroups, hasLength(2));
      expect(provider.duplicateBillCount, 5);
    });
  });

  group('DuplicateBillsProvider.findMatches', () {
    test('returns an empty list when not signed in', () async {
      var called = false;
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchMatchingBillRows: ({
            required householdId,
            required date,
            required amount,
            excludeId,
          }) async {
            called = true;
            return [];
          },
        ),
      );

      final matches = await provider.findMatches(
        configProvider: ConfigProvider.forTesting(isSignedIn: false),
        date: DateTime(2026, 1, 1),
        amount: 10.0,
      );

      expect(called, isFalse);
      expect(matches, isEmpty);
    });

    test('delegates to the service for the signed-in household, forwarding '
        'excludeId', () async {
      String? seenExcludeId;
      final provider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchMatchingBillRows: ({
            required householdId,
            required date,
            required amount,
            excludeId,
          }) async {
            seenExcludeId = excludeId;
            return [
              {
                'id': 'bill-1',
                'date': '2026-01-01',
                'amount': 10.0,
                'paid_by': 'Alice',
                'category': 'Groceries',
                'details': '',
              },
            ];
          },
        ),
      );

      final matches = await provider.findMatches(
        configProvider: signedInConfigProvider(),
        date: DateTime(2026, 1, 1),
        amount: 10.0,
        excludeId: 'bill-being-edited',
      );

      expect(matches, hasLength(1));
      expect(matches.single, isA<Bill>());
      expect(seenExcludeId, 'bill-being-edited');
    });
  });

  test('DuplicateBillGroup exposes its date, amount and bills', () {
    final bills = [
      Bill(
        id: 'bill-1',
        date: DateTime(2026, 1, 1),
        amount: 10.0,
        paidBy: 'Alice',
        category: 'Groceries',
      ),
      Bill(
        id: 'bill-2',
        date: DateTime(2026, 1, 1),
        amount: 10.0,
        paidBy: 'Bob',
        category: 'Rent',
      ),
    ];
    final group = DuplicateBillGroup(
        date: DateTime(2026, 1, 1), amount: 10.0, bills: bills);

    expect(group.date, DateTime(2026, 1, 1));
    expect(group.amount, 10.0);
    expect(group.bills, bills);
  });
}
