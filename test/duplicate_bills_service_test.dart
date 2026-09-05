// Pure-logic coverage for DuplicateBillsService (GH issue #20): grouping
// bills into "potential duplicates" (same date + amount) and finding
// conflicting bills for the Add/Edit Bill screen's pre-save check. Both
// fetch functions are injected, so none of this touches a real Supabase
// session.

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/services/duplicate_bills_service.dart';

Map<String, dynamic> billRow(
  String id,
  String date, {
  double amount = 10.0,
  String paidBy = 'Alice',
  String category = 'Groceries',
}) {
  return {
    'id': id,
    'date': date,
    'amount': amount,
    'paid_by': paidBy,
    'category': category,
    'details': '',
  };
}

void main() {
  group('DuplicateBillsService.findDuplicateGroups', () {
    test('returns no groups when every bill has a distinct date+amount',
        () async {
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01', amount: 10.0),
          billRow('bill-2', '2026-01-02', amount: 20.0),
        ],
      );

      final groups = await service.findDuplicateGroups('household-1');

      expect(groups, isEmpty);
    });

    test('groups two bills sharing the same date and amount', () async {
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01', amount: 10.0, paidBy: 'Alice'),
          billRow('bill-2', '2026-01-01', amount: 10.0, paidBy: 'Bob'),
          billRow('bill-3', '2026-01-05', amount: 30.0),
        ],
      );

      final groups = await service.findDuplicateGroups('household-1');

      expect(groups, hasLength(1));
      expect(groups.single.date, DateTime.parse('2026-01-01'));
      expect(groups.single.amount, 10.0);
      expect(groups.single.bills.map((b) => b.id), ['bill-1', 'bill-2']);
    });

    test('ignores category, payer and details when matching', () async {
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-02-01',
              amount: 50.0, paidBy: 'Alice', category: 'Rent'),
          billRow('bill-2', '2026-02-01',
              amount: 50.0, paidBy: 'Bob', category: 'Utilities'),
        ],
      );

      final groups = await service.findDuplicateGroups('household-1');

      expect(groups, hasLength(1));
      expect(groups.single.bills, hasLength(2));
    });

    test('groups three or more bills sharing the same date and amount',
        () async {
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-03-01', amount: 15.0),
          billRow('bill-2', '2026-03-01', amount: 15.0),
          billRow('bill-3', '2026-03-01', amount: 15.0),
        ],
      );

      final groups = await service.findDuplicateGroups('household-1');

      expect(groups, hasLength(1));
      expect(groups.single.bills, hasLength(3));
    });

    test('sorts multiple duplicate groups newest date first', () async {
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01', amount: 10.0),
          billRow('bill-2', '2026-01-01', amount: 10.0),
          billRow('bill-3', '2026-03-01', amount: 20.0),
          billRow('bill-4', '2026-03-01', amount: 20.0),
        ],
      );

      final groups = await service.findDuplicateGroups('household-1');

      expect(groups, hasLength(2));
      expect(groups[0].date, DateTime.parse('2026-03-01'));
      expect(groups[1].date, DateTime.parse('2026-01-01'));
    });

    test('passes the given householdId through to the fetch function',
        () async {
      String? seenHouseholdId;
      final service = DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async {
          seenHouseholdId = householdId;
          return [];
        },
      );

      await service.findDuplicateGroups('household-42');

      expect(seenHouseholdId, 'household-42');
    });
  });

  group('DuplicateBillsService.findMatches', () {
    test('returns bills the fetch function reports as matching', () async {
      final service = DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [billRow('bill-1', '2026-01-01', amount: 10.0)],
      );

      final matches = await service.findMatches(
        householdId: 'household-1',
        date: DateTime(2026, 1, 1),
        amount: 10.0,
      );

      expect(matches, hasLength(1));
      expect(matches.single.id, 'bill-1');
    });

    test('returns no matches when the fetch function finds none', () async {
      final service = DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [],
      );

      final matches = await service.findMatches(
        householdId: 'household-1',
        date: DateTime(2026, 1, 1),
        amount: 10.0,
      );

      expect(matches, isEmpty);
    });

    test('forwards date, amount, householdId and excludeId to the fetch '
        'function', () async {
      String? seenHouseholdId;
      DateTime? seenDate;
      double? seenAmount;
      String? seenExcludeId;

      final service = DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async {
          seenHouseholdId = householdId;
          seenDate = date;
          seenAmount = amount;
          seenExcludeId = excludeId;
          return [];
        },
      );

      await service.findMatches(
        householdId: 'household-1',
        date: DateTime(2026, 5, 10),
        amount: 42.5,
        excludeId: 'bill-being-edited',
      );

      expect(seenHouseholdId, 'household-1');
      expect(seenDate, DateTime(2026, 5, 10));
      expect(seenAmount, 42.5);
      expect(seenExcludeId, 'bill-being-edited');
    });
  });
}
