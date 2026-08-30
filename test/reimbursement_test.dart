import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/reimbursement.dart';

void main() {
  group('Reimbursement.toMap', () {
    test('formats the date as yyyy-MM-dd and omits id/household_id '
        '(assigned by the caller/database)', () {
      final reimbursement = Reimbursement(
        billId: 'bill-1',
        date: DateTime(2024, 3, 5),
        amount: 30.0,
        receivedBy: 'Alice',
        note: 'insurance payout',
      );

      final map = reimbursement.toMap();

      expect(map['bill_id'], 'bill-1');
      expect(map['date'], '2024-03-05');
      expect(map['amount'], 30.0);
      expect(map['received_by'], 'Alice');
      expect(map['note'], 'insurance payout');
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('household_id'), isFalse);
    });

    test('note defaults to an empty string', () {
      final reimbursement = Reimbursement(
        billId: 'bill-1',
        date: DateTime(2024, 3, 5),
        amount: 30.0,
        receivedBy: 'Alice',
      );

      expect(reimbursement.toMap()['note'], '');
    });
  });

  group('Reimbursement.fromMap', () {
    test('round-trips a full row', () {
      final row = {
        'id': 'reimb-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30.0,
        'received_by': 'Alice',
        'note': 'insurance payout',
      };

      final reimbursement = Reimbursement.fromMap(row);

      expect(reimbursement.id, 'reimb-1');
      expect(reimbursement.billId, 'bill-1');
      expect(reimbursement.date, DateTime(2024, 3, 5));
      expect(reimbursement.amount, 30.0);
      expect(reimbursement.receivedBy, 'Alice');
      expect(reimbursement.note, 'insurance payout');
    });

    test('defaults note to an empty string when the row omits it', () {
      final row = {
        'id': 'reimb-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30.0,
        'received_by': 'Alice',
      };

      expect(Reimbursement.fromMap(row).note, '');
    });

    test('reads an integer amount (num) the same as a double', () {
      final row = {
        'id': 'reimb-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30,
        'received_by': 'Alice',
      };

      expect(Reimbursement.fromMap(row).amount, 30.0);
    });
  });
}
