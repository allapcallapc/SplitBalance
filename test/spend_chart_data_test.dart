import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/utils/spend_chart_data.dart';

void main() {
  const person1 = 'Alice';
  const person2 = 'Bob';

  group('computeMonthlySpend', () {
    test('buckets bills by calendar month, split by payer', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 5),
            amount: 100.0,
            paidBy: person1,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 1, 20),
            amount: 50.0,
            paidBy: person2,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 2, 1),
            amount: 30.0,
            paidBy: person1,
            category: 'Food'),
      ];

      final months = computeMonthlySpend(bills, person1, person2);

      expect(months, hasLength(2));
      expect(months[0].month, DateTime(2024, 1));
      expect(months[0].person1Amount, 100.0);
      expect(months[0].person2Amount, 50.0);
      expect(months[0].total, 150.0);
      expect(months[1].month, DateTime(2024, 2));
      expect(months[1].person1Amount, 30.0);
      expect(months[1].person2Amount, 0.0);
    });

    test('excludes bills paid by someone other than person1/person2', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 5),
            amount: 100.0,
            paidBy: 'Someone Else',
            category: 'Food'),
      ];

      expect(computeMonthlySpend(bills, person1, person2), isEmpty);
    });

    test('returns months sorted chronologically regardless of input order',
        () {
      final bills = [
        Bill(
            date: DateTime(2024, 3, 1),
            amount: 10.0,
            paidBy: person1,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 1, 1),
            amount: 10.0,
            paidBy: person1,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 2, 1),
            amount: 10.0,
            paidBy: person1,
            category: 'Food'),
      ];

      final months = computeMonthlySpend(bills, person1, person2);

      expect(months.map((m) => m.month), [
        DateTime(2024, 1),
        DateTime(2024, 2),
        DateTime(2024, 3),
      ]);
    });

    test('empty bill list produces no months', () {
      expect(computeMonthlySpend([], person1, person2), isEmpty);
    });
  });

  group('computeCumulativeSpend', () {
    test('accumulates a running total in date order', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 10),
            amount: 50.0,
            paidBy: person2,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 1, 1),
            amount: 100.0,
            paidBy: person1,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 1, 20),
            amount: 25.0,
            paidBy: person1,
            category: 'Food'),
      ];

      final points = computeCumulativeSpend(bills, person1, person2);

      expect(points, hasLength(3));
      expect(points[0].date, DateTime(2024, 1, 1));
      expect(points[0].cumulativeAmount, 100.0);
      expect(points[1].date, DateTime(2024, 1, 10));
      expect(points[1].cumulativeAmount, 150.0);
      expect(points[2].date, DateTime(2024, 1, 20));
      expect(points[2].cumulativeAmount, 175.0);
    });

    test('excludes bills paid by someone other than person1/person2', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 1),
            amount: 100.0,
            paidBy: person1,
            category: 'Food'),
        Bill(
            date: DateTime(2024, 1, 2),
            amount: 999.0,
            paidBy: 'Landlord',
            category: 'Rent'),
      ];

      final points = computeCumulativeSpend(bills, person1, person2);

      expect(points, hasLength(1));
      expect(points.last.cumulativeAmount, 100.0);
    });

    test('empty bill list produces no points', () {
      expect(computeCumulativeSpend([], person1, person2), isEmpty);
    });
  });
}
