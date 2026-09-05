import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/recovered_amount.dart';

void main() {
  group('RecoveredAmount.toMap', () {
    test('formats the date as yyyy-MM-dd and omits id/household_id '
        '(assigned by the caller/database)', () {
      final recoveredAmount = RecoveredAmount(
        billId: 'bill-1',
        date: DateTime(2024, 3, 5),
        amount: 30.0,
        receivedBy: 'Alice',
        note: 'insurance payout',
      );

      final map = recoveredAmount.toMap();

      expect(map['bill_id'], 'bill-1');
      expect(map['date'], '2024-03-05');
      expect(map['amount'], 30.0);
      expect(map['received_by'], 'Alice');
      expect(map['note'], 'insurance payout');
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('household_id'), isFalse);
    });

    test('note defaults to an empty string', () {
      final recoveredAmount = RecoveredAmount(
        billId: 'bill-1',
        date: DateTime(2024, 3, 5),
        amount: 30.0,
        receivedBy: 'Alice',
      );

      expect(recoveredAmount.toMap()['note'], '');
    });
  });

  group('RecoveredAmount.fromMap', () {
    test('round-trips a full row', () {
      final row = {
        'id': 'recovered-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30.0,
        'received_by': 'Alice',
        'note': 'insurance payout',
      };

      final recoveredAmount = RecoveredAmount.fromMap(row);

      expect(recoveredAmount.id, 'recovered-1');
      expect(recoveredAmount.billId, 'bill-1');
      expect(recoveredAmount.date, DateTime(2024, 3, 5));
      expect(recoveredAmount.amount, 30.0);
      expect(recoveredAmount.receivedBy, 'Alice');
      expect(recoveredAmount.note, 'insurance payout');
    });

    test('defaults note to an empty string when the row omits it', () {
      final row = {
        'id': 'recovered-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30.0,
        'received_by': 'Alice',
      };

      expect(RecoveredAmount.fromMap(row).note, '');
    });

    test('reads an integer amount (num) the same as a double', () {
      final row = {
        'id': 'recovered-1',
        'bill_id': 'bill-1',
        'date': '2024-03-05',
        'amount': 30,
        'received_by': 'Alice',
      };

      expect(RecoveredAmount.fromMap(row).amount, 30.0);
    });
  });
}
