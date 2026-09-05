// Exercises the race-condition-sensitive parts of BillsProvider (stale
// response handling, refetch-after-mutation) using the FetchBillsPage /
// InsertBillRow injection points and the @visibleForTesting *ForHousehold
// methods, so these don't require a real signed-in Supabase session.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/providers/bills_provider.dart';

// Most of these tests don't care about recovered amounts, so this wrapper
// defaults to a no-op fetchRecoveredTotals - otherwise every
// loadBillsForHousehold call below would fall through to BillsProvider's
// real-Supabase default and fail outside a signed-in session. Tests that DO
// care (see the "recovered totals" group) pass their own.
BillsProvider testBillsProvider({
  FetchBillsPage? fetchBillsPage,
  InsertBillRow? insertBillRow,
  UpdateBillRow? updateBillRow,
  DeleteBillRow? deleteBillRow,
  FetchRecoveredTotals? fetchRecoveredTotals,
}) {
  return BillsProvider(
    fetchBillsPage: fetchBillsPage,
    insertBillRow: insertBillRow,
    updateBillRow: updateBillRow,
    deleteBillRow: deleteBillRow,
    fetchRecoveredTotals:
        fetchRecoveredTotals ?? ({required billIds}) async => {},
  );
}

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
  setUpAll(() async {
    // Only the "real Supabase default" group below needs this - it's here
    // rather than in that group's own setUp so it runs once for the whole
    // file, matching test/bills_list_screen_test.dart's pattern.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  group('BillsProvider - recovered totals default (real Supabase client)',
      () {
    test(
        'omitting fetchRecoveredTotals falls through to the real default, '
        'which surfaces a network failure as a provider error rather than '
        'throwing', () async {
      // No fetchRecoveredTotals override, so _withRecoveredTotals falls
      // through to _defaultFetchRecoveredTotals - which has no injection
      // seam of its own and hits Supabase.instance.client directly. Against
      // the fake project url configured in setUpAll, that request fails,
      // proving the fallback wiring itself (the `?? _defaultFetchRecoveredTotals`
      // in BillsProvider's constructor) actually runs and that failure
      // doesn't propagate uncaught.
      final provider = BillsProvider(
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

      await provider.loadBillsForHousehold('household-1');

      expect(provider.error, contains('Failed to load bills'));
    });
  });

  group('BillsProvider - sort', () {
    test('defaults to newest-first by date', () {
      final provider = testBillsProvider();
      expect(provider.sortField, BillSortField.date);
      expect(provider.sortAscending, isFalse);
    });

    test(
        'loadBillsForHousehold passes the active sort through to '
        'fetchBillsPage', () async {
      BillSortField? capturedField;
      bool? capturedAscending;
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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

      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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
      final provider = testBillsProvider(
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

  group('BillsProvider - recovered totals', () {
    test(
        'loadBillsForHousehold with no bills never calls fetchRecoveredTotals',
        () async {
      var fetchRecoveredTotalsCalled = false;
      final provider = testBillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            const [],
        fetchRecoveredTotals: ({required billIds}) async {
          fetchRecoveredTotalsCalled = true;
          return {};
        },
      );

      await provider.loadBillsForHousehold('household-1');

      expect(fetchRecoveredTotalsCalled, isFalse);
      expect(provider.bills, isEmpty);
      expect(provider.error, isNull);
    });

    test(
        'a stale loadBillsForHousehold response is dropped even when it '
        'only becomes stale after fetchBillsPage already resolved - i.e. '
        'while still waiting on fetchRecoveredTotals', () async {
      final recoveredCompleter = Completer<Map<String, double>>();
      var fetchBillsPageCalls = 0;
      final provider = testBillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          fetchBillsPageCalls++;
          return [billRow('bill-$fetchBillsPageCalls', '2026-01-01')];
        },
        // Shared by both calls below - resolving it once resolves both
        // loads' pending _withRecoveredTotals at the same time, so which
        // one is stale is decided purely by the requestId guard.
        fetchRecoveredTotals: ({required billIds}) => recoveredCompleter.future,
      );

      final firstLoad = provider.loadBillsForHousehold('household-1');
      // Let fetchBillsPage resolve and fetchRecoveredTotals get called
      // (and start waiting on the completer) for the first load.
      await Future<void>.delayed(Duration.zero);

      // A second load starts before the first's recovered-totals fetch
      // ever resolves - simulating a fast second filter change.
      final secondLoad = provider.loadBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);

      recoveredCompleter.complete({});
      await firstLoad;
      await secondLoad;

      // Only the second (current) load's bill made it into _bills - the
      // first's result was discarded by the post-fetchRecoveredTotals
      // requestId check, not just the earlier post-fetchBillsPage one.
      expect(provider.bills.map((b) => b.id), ['bill-2']);
      expect(provider.error, isNull);
    });

    test(
        'a stale loadMoreBillsForHousehold response is dropped even when it '
        'only becomes stale while waiting on fetchRecoveredTotals',
        () async {
      final recoveredCompleter = Completer<Map<String, double>>();
      final provider = testBillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          if (offset == 0) {
            // Full page so hasMore is true and loadMore is eligible.
            return List.generate(
              BillsProvider.pageSize,
              (i) => billRow('p1-$i', '2026-01-01'),
            );
          }
          return [billRow('p2-0', '2026-01-02')];
        },
        fetchRecoveredTotals: ({required billIds}) async {
          // The first page's own totals fetch resolves immediately; only
          // the "load more" page's totals fetch waits on the completer.
          if (billIds.contains('p2-0')) return recoveredCompleter.future;
          return {};
        },
      );

      await provider.loadBillsForHousehold('household-1');
      final moreLoad = provider.loadMoreBillsForHousehold('household-1');
      // Let fetchBillsPage resolve and fetchRecoveredTotals start waiting.
      await Future<void>.delayed(Duration.zero);

      // A fresh page-1 load (e.g. the filter changed) resets state while
      // "load more" is still waiting on its recovered-totals fetch.
      final resetLoad = provider.loadBillsForHousehold('household-1');
      await Future<void>.delayed(Duration.zero);

      recoveredCompleter.complete({});
      await moreLoad;
      await resetLoad;

      // The stale "load more" page must not have been appended.
      expect(provider.bills.any((b) => b.id == 'p2-0'), isFalse);
      expect(provider.isLoadingMore, isFalse);
    });

    test('loadBillsForHousehold merges recoveredAmount into each bill',
        () async {
      final provider = testBillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [
              billRow('bill-1', '2026-01-01'),
              billRow('bill-2', '2026-01-02'),
            ],
        fetchRecoveredTotals: ({required billIds}) async {
          expect(billIds, unorderedEquals(['bill-1', 'bill-2']));
          return {'bill-1': 4.0};
        },
      );

      await provider.loadBillsForHousehold('household-1');

      final bill1 = provider.bills.firstWhere((b) => b.id == 'bill-1');
      final bill2 = provider.bills.firstWhere((b) => b.id == 'bill-2');
      expect(bill1.recoveredAmount, 4.0);
      expect(bill1.netAmount, 6.0); // billRow's default amount is 10.0
      // bill-2 has no entry in the fetcher's result - stays at 0, not
      // dropped or errored.
      expect(bill2.recoveredAmount, 0.0);
    });

    test('loadMoreBillsForHousehold merges recoveredAmount into the '
        'appended page too', () async {
      final provider = testBillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async {
          if (offset == 0) {
            return List.generate(
              BillsProvider.pageSize,
              (i) => billRow('p1-$i', '2026-01-01'),
            );
          }
          return [billRow('p2-0', '2026-01-02')];
        },
        fetchRecoveredTotals: ({required billIds}) async {
          if (billIds.contains('p2-0')) return {'p2-0': 2.5};
          return {};
        },
      );

      await provider.loadBillsForHousehold('household-1');
      await provider.loadMoreBillsForHousehold('household-1');

      final appended = provider.bills.firstWhere((b) => b.id == 'p2-0');
      expect(appended.recoveredAmount, 2.5);
    });

    // loadAllBills has no injection seam for its own bill-row query (it
    // calls Supabase.instance.client directly - see BillsProvider._supabase),
    // so it can't be exercised against fake data in a plain unit test; its
    // use of the same _withRecoveredTotals merge helper is covered here via
    // loadBillsForHousehold/loadMoreBillsForHousehold above, and end-to-end
    // against a real database by the integration suite.

    test('updateBillById carries forward the previously known '
        'recoveredAmount instead of resetting it to 0', () async {
      final provider = testBillsProvider(
        updateBillRow: (id, data) async => {
          'id': id,
          'date': data['date'],
          'amount': data['amount'],
          'paid_by': data['paid_by'],
          'category': data['category'],
          'details': data['details'],
        },
      );

      // Seed _allBills with an entry that already carries a known
      // recoveredAmount: since this id isn't in _allBills yet,
      // updateBillById's orElse fallback uses the incoming Bill argument's
      // own recoveredAmount - standing in here for a bill that was
      // originally populated by loadAllBills with its real recovered total
      // already merged in. householdId is null so this skips the refetch
      // and only exercises the _allBills merge itself.
      await provider.updateBillById(
        'bill-1',
        Bill(
          id: 'bill-1',
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Groceries',
          recoveredAmount: 12.0,
        ),
        null,
      );
      expect(provider.allBills.single.recoveredAmount, 12.0);

      // Editing the bill's category shouldn't touch its recovered amounts.
      // The second updatedBill below has no recoveredAmount of its own
      // (matching AddEditBillScreen, which never sets it) and
      // _updateBillRow's response has none either (it's not a `bills`
      // column) - so updateBillById must carry the existing _allBills total
      // forward rather than resetting it to 0.
      await provider.updateBillById(
        'bill-1',
        Bill(
          id: 'bill-1',
          date: DateTime.parse('2026-01-01'),
          amount: 10.0,
          paidBy: 'Alice',
          category: 'Rent',
        ),
        null,
      );

      expect(provider.allBills.single.category, 'Rent');
      expect(provider.allBills.single.recoveredAmount, 12.0);
    });
  });
}
