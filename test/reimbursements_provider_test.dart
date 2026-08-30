// Exercises ReimbursementsProvider's load/add/delete flows using its
// injectable fetch/insert/delete points, so these don't require a real
// signed-in Supabase session - same pattern as test/bills_provider_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:splitbalance/models/reimbursement.dart';
import 'package:splitbalance/providers/reimbursements_provider.dart';

Map<String, dynamic> reimbursementRow(
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

  group('ReimbursementsProvider - real Supabase defaults', () {
    // None of these override fetchReimbursementsForBill/insertReimbursementRow/
    // deleteReimbursementRow, so each falls through to its real default,
    // which has no injection seam and hits Supabase.instance.client
    // directly. Against the fake project url configured above, every call
    // fails - proving the defaults actually run and that the failure
    // surfaces as a provider error rather than an uncaught exception.
    test('loadForBill', () async {
      final provider = ReimbursementsProvider();
      await provider.loadForBill('bill-1');
      expect(provider.error, contains('Failed to load reimbursements'));
    });

    test('addReimbursement', () async {
      final provider = ReimbursementsProvider();
      final success = await provider.addReimbursement(
        Reimbursement(
          billId: 'bill-1',
          date: DateTime(2024, 1, 1),
          amount: 10.0,
          receivedBy: 'Alice',
        ),
        'household-1',
      );
      expect(success, isFalse);
      expect(provider.error, contains('Failed to add reimbursement'));
    });

    test('deleteReimbursement', () async {
      final provider = ReimbursementsProvider();
      final success = await provider.deleteReimbursement('reimb-1');
      expect(success, isFalse);
      expect(provider.error, contains('Failed to delete reimbursement'));
    });
  });

  group('ReimbursementsProvider - loadForBill', () {
    test('populates reimbursements from the fetcher, newest first as '
        'returned', () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async {
          expect(billId, 'bill-1');
          return [
            reimbursementRow('r2', 'bill-1', '2024-02-01', amount: 20.0),
            reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0),
          ];
        },
      );

      await provider.loadForBill('bill-1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.reimbursements.map((r) => r.id), ['r2', 'r1']);
      expect(provider.totalReimbursed, 30.0);
    });

    test('surfaces a fetch failure without leaving isLoading stuck on',
        () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            throw Exception('network error'),
      );

      await provider.loadForBill('bill-1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, contains('Failed to load reimbursements'));
      expect(provider.reimbursements, isEmpty);
    });

    test('an empty result clears totalReimbursed to 0', () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
      );

      await provider.loadForBill('bill-1');

      expect(provider.reimbursements, isEmpty);
      expect(provider.totalReimbursed, 0.0);
    });
  });

  group('ReimbursementsProvider - addReimbursement', () {
    test('inserts with the household id attached and prepends the saved '
        'row to the list', () async {
      Map<String, dynamic>? capturedInsert;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        insertReimbursementRow: (data) async {
          capturedInsert = data;
          return reimbursementRow('r2', 'bill-1', '2024-02-01', amount: 20.0);
        },
      );
      await provider.loadForBill('bill-1');

      final success = await provider.addReimbursement(
        Reimbursement(
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
      // Prepended, not appended.
      expect(provider.reimbursements.map((r) => r.id), ['r2', 'r1']);
      expect(provider.totalReimbursed, 30.0);
    });

    test('returns false and sets error without touching the list when the '
        'insert fails', () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        insertReimbursementRow: (data) async =>
            throw Exception('network error'),
      );
      await provider.loadForBill('bill-1');

      final success = await provider.addReimbursement(
        Reimbursement(
          billId: 'bill-1',
          date: DateTime(2024, 2, 1),
          amount: 20.0,
          receivedBy: 'Bob',
        ),
        'household-1',
      );

      expect(success, isFalse);
      expect(provider.error, contains('Failed to add reimbursement'));
      expect(provider.reimbursements, hasLength(1));
      expect(provider.reimbursements.single.id, 'r1');
    });
  });

  group('ReimbursementsProvider - deleteReimbursement', () {
    test('removes the deleted row by id', () async {
      String? deletedId;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [
          reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0),
          reimbursementRow('r2', 'bill-1', '2024-02-01', amount: 20.0),
        ],
        deleteReimbursementRow: (id) async => deletedId = id,
      );
      await provider.loadForBill('bill-1');

      final success = await provider.deleteReimbursement('r1');

      expect(success, isTrue);
      expect(deletedId, 'r1');
      expect(provider.reimbursements.map((r) => r.id), ['r2']);
      expect(provider.totalReimbursed, 20.0);
    });

    test('returns false and leaves the list untouched when the delete fails',
        () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
        deleteReimbursementRow: (id) async =>
            throw Exception('network error'),
      );
      await provider.loadForBill('bill-1');

      final success = await provider.deleteReimbursement('r1');

      expect(success, isFalse);
      expect(provider.error, contains('Failed to delete reimbursement'));
      expect(provider.reimbursements, hasLength(1));
    });
  });

  group('ReimbursementsProvider - reset', () {
    test('clears reimbursements and error so a stale bill\'s data never '
        'flashes for the next one', () async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 10.0)],
      );
      await provider.loadForBill('bill-1');
      expect(provider.reimbursements, isNotEmpty);

      provider.reset();

      expect(provider.reimbursements, isEmpty);
      expect(provider.error, isNull);
      expect(provider.totalReimbursed, 0.0);
    });
  });
}
