import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';

void main() {
  group('Bill - netAmount', () {
    test('defaults reimbursedAmount to 0, so netAmount equals amount', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
      );

      expect(bill.reimbursedAmount, 0.0);
      expect(bill.netAmount, 100.0);
    });

    test('subtracts reimbursedAmount from amount', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        reimbursedAmount: 30.0,
      );

      expect(bill.netAmount, 70.0);
    });

    test('goes negative rather than clamping at zero when over-reimbursed',
        () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        reimbursedAmount: 150.0,
      );

      expect(bill.netAmount, -50.0);
    });
  });

  group('Bill.fromMap', () {
    Map<String, dynamic> row({double? reimbursedAmount}) => {
          'id': 'bill-1',
          'date': '2024-01-15',
          'amount': 100.0,
          'paid_by': 'Alice',
          'category': 'Food',
          'details': 'groceries',
          if (reimbursedAmount != null) 'reimbursed_amount': reimbursedAmount,
        };

    test('defaults reimbursedAmount to 0 when the row has no such key '
        '(the real `bills` table has no reimbursed_amount column)', () {
      final bill = Bill.fromMap(row());
      expect(bill.reimbursedAmount, 0.0);
      expect(bill.netAmount, 100.0);
    });

    test('reads reimbursedAmount when the caller injected it into the row '
        '(see BillsProvider._withReimbursedTotals)', () {
      final bill = Bill.fromMap(row(reimbursedAmount: 40.0));
      expect(bill.reimbursedAmount, 40.0);
      expect(bill.netAmount, 60.0);
    });
  });

  group('Bill.copyWith', () {
    test('preserves reimbursedAmount when not overridden', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        reimbursedAmount: 20.0,
      );

      final copy = bill.copyWith(amount: 120.0);

      expect(copy.amount, 120.0);
      expect(copy.reimbursedAmount, 20.0);
    });

    test('overrides reimbursedAmount when explicitly passed', () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        reimbursedAmount: 20.0,
      );

      final copy = bill.copyWith(reimbursedAmount: 0.0);

      expect(copy.reimbursedAmount, 0.0);
      expect(copy.netAmount, 100.0);
    });
  });

  group('Bill.toMap', () {
    test('does not include reimbursedAmount - it is not a `bills` column',
        () {
      final bill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 100.0,
        paidBy: 'Alice',
        category: 'Food',
        reimbursedAmount: 30.0,
      );

      expect(bill.toMap().containsKey('reimbursed_amount'), isFalse);
    });
  });
}
