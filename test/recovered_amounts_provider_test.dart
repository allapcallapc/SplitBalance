// Exercises RecoveredAmountsProvider's load/add/delete flows using its
// injectable fetch/insert/delete points, so these don't require a real
// signed-in Supabase session - same pattern as test/bills_provider_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:splitbalance/models/recovered_amount.dart';
import 'package:splitbalance/providers/recovered_amounts_provider.dart';

Map<String, dynamic> recoveredAmountRow(
  String id,
  String billId,
  String date, {
  double amount = 10.0,
  String receivedBy = 'Alice',
  String note = '',
}) {
  return {
    'id': id,
    'bill_id': billId,
    'date': date,
    'amount': amount,
    'received_by': receivedBy,
    'note': note,
  };
}

void main() {
  setUpAll(() async {
    // Only the "real Supabase defaults" group below needs this - matches
    // test/bills_list_screen_test.dart's pattern.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  group('RecoveredAmountsProvider - real Supabase defaults', () {
    // None of these override fetchRecoveredAmountsForBill/
    // insertRecoveredAmountRow/deleteRecoveredAmountRow, so each falls
    // through to its real default, which has no injection seam and hits
    // Supabase.instance.client directly. Against the fake project url
    // configured above, every call fails - proving the defaults actually
    // run and that the failure surfaces as a provider error rather than an
    // uncaught exception.
    test('loadForBill', () async {
      final provider = RecoveredAmountsProvider();
      await provider.loadForBill('bill-1');
      expect(provider.error, contains('Failed to load recovered amounts'));
    });

    test('addRecoveredAmount', () async {
      final provider = RecoveredAmountsProvider();
      final success = await provider.addRecoveredAmount(
        RecoveredAmount(
          billId: 'bill-1',
          date: DateTime(2024, 1, 1),
          amount: 10.0,
          receivedBy: 'Alice',
        ),
        'household-1',
      );
      expect(success, isFalse);
      expect(provider.error, contains('Failed to add recovered amount'));
    });

    test('deleteRecoveredAmount', () async {
      final provider = RecoveredAmountsProvider();
      final success = await provider.deleteRecoveredAmount('recovered-1');
      expect(success, isFalse);
      expect(provider.error, contains('Failed to delete recovered amount'));
    });
  });

  group('RecoveredAmountsProvider - loadForBill', () {
    test('populates recoveredAmounts from the fetcher, newest first as '
        'returned', () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async {
          expect(billId, 'bill-1');
          return [
            recoveredAmountRow('r2', 'bill-1', '2024-02-01', amount: 20.0),
            recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0),
          ];
        },
      );

      await provider.loadForBill('bill-1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.recoveredAmounts.map((r) => r.id), ['r2', 'r1']);
      expect(provider.totalRecovered, 30.0);
    });

    test('surfaces a fetch failure without leaving isLoading stuck on',
        () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            throw Exception('network error'),
      );

      await provider.loadForBill('bill-1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, contains('Failed to load recovered amounts'));
      expect(provider.recoveredAmounts, isEmpty);
    });

    test('an empty result clears totalRecovered to 0', () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
      );

      await provider.loadForBill('bill-1');

      expect(provider.recoveredAmounts, isEmpty);
      expect(provider.totalRecovered, 0.0);
    });
  });

  group('RecoveredAmountsProvider - addRecoveredAmount', () {
    test('inserts with the household id attached and places the saved row '
        'first when its date is the newest', () async {
      Map<String, dynamic>? capturedInsert;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        insertRecoveredAmountRow: (data) async {
          capturedInsert = data;
          return recoveredAmountRow('r2', 'bill-1', '2024-02-01',
              amount: 20.0);
        },
      );
      await provider.loadForBill('bill-1');

      final success = await provider.addRecoveredAmount(
        RecoveredAmount(
          billId: 'bill-1',
          date: DateTime(2024, 2, 1),
          amount: 20.0,
          receivedBy: 'Bob',
          note: 'refund',
        ),
        'household-1',
      );

      expect(success, isTrue);
      expect(provider.error, isNull);
      expect(capturedInsert!['household_id'], 'household-1');
      expect(capturedInsert!['bill_id'], 'bill-1');
      expect(capturedInsert!['amount'], 20.0);
      // Newest date first, matching loadForBill's ordering.
      expect(provider.recoveredAmounts.map((r) => r.id), ['r2', 'r1']);
      expect(provider.totalRecovered, 30.0);
    });

    test(
        'inserts the saved row into its sorted position, not always first, '
        'when it backdates an entry recorded after the fact', () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-02-01', amount: 10.0)],
        insertRecoveredAmountRow: (data) async =>
            recoveredAmountRow('r2', 'bill-1', '2024-01-15', amount: 20.0),
      );
      await provider.loadForBill('bill-1');

      final success = await provider.addRecoveredAmount(
        RecoveredAmount(
          billId: 'bill-1',
          date: DateTime(2024, 1, 15),
          amount: 20.0,
          receivedBy: 'Bob',
        ),
        'household-1',
      );

      expect(success, isTrue);
      // r1 (2024-02-01) is still newer than the backdated r2 (2024-01-15),
      // so it must stay first rather than being pushed down by a plain
      // prepend.
      expect(provider.recoveredAmounts.map((r) => r.id), ['r1', 'r2']);
    });

    test('returns false and sets error without touching the list when the '
        'insert fails', () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        insertRecoveredAmountRow: (data) async =>
            throw Exception('network error'),
      );
      await provider.loadForBill('bill-1');

      final success = await provider.addRecoveredAmount(
        RecoveredAmount(
          billId: 'bill-1',
          date: DateTime(2024, 2, 1),
          amount: 20.0,
          receivedBy: 'Bob',
        ),
        'household-1',
      );

      expect(success, isFalse);
      expect(provider.error, contains('Failed to add recovered amount'));
      expect(provider.recoveredAmounts, hasLength(1));
      expect(provider.recoveredAmounts.single.id, 'r1');
    });
  });

  group('RecoveredAmountsProvider - deleteRecoveredAmount', () {
    test('removes the deleted row by id', () async {
      String? deletedId;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [
          recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0),
          recoveredAmountRow('r2', 'bill-1', '2024-02-01', amount: 20.0),
        ],
        deleteRecoveredAmountRow: (id) async => deletedId = id,
      );
      await provider.loadForBill('bill-1');

      final success = await provider.deleteRecoveredAmount('r1');

      expect(success, isTrue);
      expect(deletedId, 'r1');
      expect(provider.recoveredAmounts.map((r) => r.id), ['r2']);
      expect(provider.totalRecovered, 20.0);
    });

    test('returns false and leaves the list untouched when the delete fails',
        () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        deleteRecoveredAmountRow: (id) async =>
            throw Exception('network error'),
      );
      await provider.loadForBill('bill-1');

      final success = await provider.deleteRecoveredAmount('r1');

      expect(success, isFalse);
      expect(provider.error, contains('Failed to delete recovered amount'));
      expect(provider.recoveredAmounts, hasLength(1));
    });
  });

  group('RecoveredAmountsProvider - reset', () {
    test('clears recoveredAmounts and error so a stale bill\'s data never '
        'flashes for the next one', () async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
      );
      await provider.loadForBill('bill-1');
      expect(provider.recoveredAmounts, isNotEmpty);

      provider.reset();

      expect(provider.recoveredAmounts, isEmpty);
      expect(provider.error, isNull);
      expect(provider.totalRecovered, 0.0);
    });
  });
}
