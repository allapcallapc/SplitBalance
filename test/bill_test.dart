import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';

void main() {
  group('Bill - netAmount', () {
    test('defaults recoveredAmount to 0, so netAmount equals amount', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
      );

      expect(bill.recoveredAmount, 0.0);
      expect(bill.netAmount, 100.0);
    });

    test('subtracts recoveredAmount from amount', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredAmount: 30.0,
      );

      expect(bill.netAmount, 70.0);
    });

    test('goes negative rather than clamping at zero when over-recovered',
        () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredAmount: 150.0,
      );

      expect(bill.netAmount, -50.0);
    });
  });

  group('Bill.fromMap', () {
    Map<String, dynamic> row({double? recoveredAmount}) => {
          'id': 'bill-1',
          'date': '2024-01-15',
          'amount': 100.0,
          'paid_by': 'Alice',
          'category': 'Food',
          'details': 'groceries',
          if (recoveredAmount != null) 'recovered_amount': recoveredAmount,
        };

    test('defaults recoveredAmount to 0 when the row has no such key '
        '(the real `bills` table has no recovered_amount column)', () {
      final bill = Bill.fromMap(row());
      expect(bill.recoveredAmount, 0.0);
      expect(bill.netAmount, 100.0);
    });

    test('reads recoveredAmount when the caller injected it into the row '
        '(see BillsProvider._withRecoveredTotals)', () {
      final bill = Bill.fromMap(row(recoveredAmount: 40.0));
      expect(bill.recoveredAmount, 40.0);
      expect(bill.netAmount, 60.0);
    });
  });

  group('Bill.copyWith', () {
    test('preserves recoveredAmount when not overridden', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredAmount: 20.0,
      );

      final copy = bill.copyWith(amount: 120.0);

      expect(copy.amount, 120.0);
      expect(copy.recoveredAmount, 20.0);
    });

    test('overrides recoveredAmount when explicitly passed', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredAmount: 20.0,
      );

      final copy = bill.copyWith(recoveredAmount: 0.0);

      expect(copy.recoveredAmount, 0.0);
      expect(copy.netAmount, 100.0);
    });
  });

  group('Bill.toMap', () {
    test('does not include recoveredAmount - it is not a `bills` column',
        () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredAmount: 30.0,
      );

      expect(bill.toMap().containsKey('recovered_amount'), isFalse);
    });
  });

  group('Bill - recoveredByReceiver', () {
    test('defaults to empty', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
      );

      expect(bill.recoveredByReceiver, isEmpty);
    });

    test('copyWith preserves it when not overridden', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredByReceiver: const {'Alice': 20.0},
      );

      final copy = bill.copyWith(amount: 120.0);

      expect(copy.recoveredByReceiver, {'Alice': 20.0});
    });

    test('copyWith overrides it when explicitly passed', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        recoveredByReceiver: const {'Alice': 20.0},
      );

      final copy =
          bill.copyWith(recoveredByReceiver: const {'Bob': 5.0});

      expect(copy.recoveredByReceiver, {'Bob': 5.0});
    });
  });
}
