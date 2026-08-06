// Exercises the race-condition-sensitive parts of BillsProvider (stale
// response handling, refetch-after-mutation) using the FetchBillsPage /
// InsertBillRow injection points and the @visibleForTesting *ForHousehold
// methods, so these don't require a real signed-in Supabase session.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/providers/bills_provider.dart';

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
  group('BillsProvider - sort', () {
    test('defaults to newest-first by date', () {
      final provider = BillsProvider();
      expect(provider.sortField, BillSortField.date);
      expect(provider.sortAscending, isFalse);
    });

    test(
        'loadBillsForHousehold passes the active sort through to '
        'fetchBillsPage', () async {
      BillSortField? capturedField;
      bool? capturedAscending;
      final provider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          capturedField = sortField;
          capturedAscending = sortAscending;
          return [billRow('b1', '2026-01-01')];
        },
      );

      await provider.loadBillsForHousehold('household-1');
      expect(capturedField, BillSortField.date);
      expect(capturedAscending, isFalse);
    });
  });

  group('BillsProvider - request id guard', () {
    test('a stale loadBillsForHousehold response is dropped', () async {
      final completers = <Completer<List<Map<String, dynamic>>>>[];
      final provider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) {
          final completer = Completer<List<Map<String, dynamic>>>();
          completers.add(completer);
          return completer.future;
        },
      );

      // Simulate a user tapping filter A, then tapping filter B before A's
      // response comes back: two loadBillsForHousehold() calls in flight.
      final firstLoad = provider.loadBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);
      final secondLoad = provider.loadBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);

      expect(completers.length, 2);

      // Resolve out of order: the newer (second) request wins the race and
      // comes back first, then the stale first request resolves after.
      completers[1].complete([billRow('b2', '2026-01-02', paidBy: 'Bob')]);
      await secondLoad;

      completers[0].complete([billRow('b1', '2026-01-01')]);
      await firstLoad;

      // The stale response must not have clobbered the newer state.
      expect(provider.bills.length, 1);
      expect(provider.bills.single.id, 'b2');
      expect(provider.error, isNull);
    });

    test(
        'loadMoreBillsForHousehold ignores a response invalidated by a '
        'concurrent loadBillsForHousehold reset', () async {
      final pageCompleter = Completer<List<Map<String, dynamic>>>();
      var moreRequested = false;
      final provider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) {
          if (offset == 0) {
            // First page load resolves immediately with a full page so
            // hasMore is true and loadMoreBillsForHousehold is eligible.
            return Future.value(List.generate(
              BillsProvider.pageSize,
              (i) => billRow(
                  'p1-$i', '2026-01-${(i + 1).toString().padLeft(2, '0')}'),
            ));
          }
          moreRequested = true;
          return pageCompleter.future;
        },
      );

      await provider.loadBillsForHousehold('household-1');
      expect(provider.hasMore, isTrue);

      final moreLoad = provider.loadMoreBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);
      expect(moreRequested, isTrue);

      // A fresh page-1 load (e.g. the filter changed) resets state while
      // the "load more" call above is still in flight.
      final resetLoad = provider.loadBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);

      // Now the stale "load more" response arrives.
      pageCompleter.complete([billRow('stale', '2025-01-01')]);
      await moreLoad;
      await resetLoad;

      // The stale page must not have been appended, and "loading more"
      // must not be stuck on.
      expect(provider.bills.any((b) => b.id == 'stale'), isFalse);
      expect(provider.isLoadingMore, isFalse);
    });
  });

  group('BillsProvider - refetch after mutation', () {
    test(
        'addBillForHousehold refreshes _bills from the server instead of '
        'guessing the new row\'s position locally', () async {
      var fetchCallCount = 0;
      final provider = BillsProvider(
        insertBillRow: (data) async => {
          'id': 'new-id',
          'date': data['date'],
          'amount': data['amount'],
          'paid_by': data['paid_by'],
          'category': data['category'],
          'details': data['details'],
        },
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          fetchCallCount++;
          // Authoritative server order: the backdated new bill sorts
          // *after* an existing, newer-dated bill that a naive "just
          // append and sort by date" local splice would never have seen.
          return [
            billRow('existing-newer', '2026-01-05'),
            billRow('new-id', '2026-01-01'),
          ];
        },
      );

      final newBill = Bill(
        date: DateTime.parse('2026-01-01'),
        amount: 10.0,
        paidBy: 'Alice',
        category: 'Groceries',
      );

      await provider.addBillForHousehold(newBill, 'household-1');

      // Exactly one reload happened (the refetch triggered by the add).
      expect(fetchCallCount, 1);
      // _bills reflects the server's authoritative page, not a local guess.
      expect(
        provider.bills.map((b) => b.id).toList(),
        ['existing-newer', 'new-id'],
      );
      expect(provider.allBills.any((b) => b.id == 'new-id'), isTrue);
      expect(provider.error, isNull);
    });

    test(
        'addBillForHousehold surfaces an insert failure without touching '
        'the bill lists', () async {
      final provider = BillsProvider(
        insertBillRow: (data) async => throw Exception('network error'),
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          fail('fetchBillsPage should not be called when the insert fails');
        },
      );

      final newBill = Bill(
        date: DateTime.parse('2026-01-01'),
        amount: 10.0,
        paidBy: 'Alice',
        category: 'Groceries',
      );

      await provider.addBillForHousehold(newBill, 'household-1');

      expect(provider.error, contains('Failed to add bill'));
      expect(provider.bills, isEmpty);
      expect(provider.allBills, isEmpty);
    });
  });

  group('BillsProvider - updateBillById / deleteBillById', () {
    Map<String, dynamic> echoUpdate(String id, Map<String, dynamic> data) => {
          'id': id,
          'date': data['date'],
          'amount': data['amount'],
          'paid_by': data['paid_by'],
          'category': data['category'],
          'details': data['details'],
        };

    test(
        'updateBillById refreshes _bills via a refetch and updates '
        '_allBills in place', () async {
      var fetchCallCount = 0;
      var page = [billRow('bill-1', '2026-01-01', category: 'Groceries')];

      final provider = BillsProvider(
        insertBillRow: (data) async => echoUpdate('bill-1', data),
        updateBillRow: (id, data) async => echoUpdate(id, data),
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          fetchCallCount++;
          return page;
        },
      );

      // Seed one bill (the add itself triggers a refetch too).
      await provider.addBillForHousehold(
        Bill(
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Groceries',
        ),
        'household-1',
      );
      expect(fetchCallCount, 1);

      // Edit it: the server's authoritative page reflects the new category.
      page = [billRow('bill-1', '2026-01-01', category: 'Rent')];
      await provider.updateBillById(
        'bill-1',
        Bill(
          id: 'bill-1',
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Rent',
        ),
        'household-1',
      );

      expect(fetchCallCount, 2);
      expect(provider.bills.single.category, 'Rent');
      expect(provider.allBills.single.category, 'Rent');
      expect(provider.error, isNull);
    });

    test(
        'updateBillById with no household id skips the refetch but still '
        'updates _allBills', () async {
      var fetchCallCount = 0;
      final provider = BillsProvider(
        updateBillRow: (id, data) async => echoUpdate(id, data),
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          fetchCallCount++;
          return const [];
        },
      );

      await provider.updateBillById(
        'bill-1',
        Bill(
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Rent',
        ),
        null,
      );

      expect(fetchCallCount, 0);
      expect(provider.allBills.single.category, 'Rent');
    });

    test(
        'updateBillById surfaces a failure without touching the bill '
        'lists', () async {
      final provider = BillsProvider(
        updateBillRow: (id, data) async => throw Exception('network error'),
      );

      await provider.updateBillById(
        'bill-1',
        Bill(
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Rent',
        ),
        'household-1',
      );

      expect(provider.error, contains('Failed to update bill'));
      expect(provider.allBills, isEmpty);
    });

    test('deleteBillById removes the bill from both bills and allBills',
        () async {
      var deletedId = '';
      final provider = BillsProvider(
        insertBillRow: (data) async => echoUpdate('bill-1', data),
        deleteBillRow: (id) async => deletedId = id,
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [billRow('bill-1', '2026-01-01')],
      );

      await provider.addBillForHousehold(
        Bill(
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Groceries',
        ),
        'household-1',
      );
      expect(provider.bills, isNotEmpty);

      await provider.deleteBillById('bill-1');

      expect(deletedId, 'bill-1');
      expect(provider.bills, isEmpty);
      expect(provider.allBills, isEmpty);
      expect(provider.error, isNull);
    });

    test(
        'deleteBillById surfaces a failure and leaves the bill lists '
        'untouched', () async {
      final provider = BillsProvider(
        insertBillRow: (data) async => echoUpdate('bill-1', data),
        deleteBillRow: (id) async => throw Exception('network error'),
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [billRow('bill-1', '2026-01-01')],
      );

      await provider.addBillForHousehold(
        Bill(
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Groceries',
        ),
        'household-1',
      );

      await provider.deleteBillById('bill-1');

      expect(provider.error, contains('Failed to delete bill'));
      expect(provider.bills, isNotEmpty);
      expect(provider.allBills, isNotEmpty);
    });
  });
}
