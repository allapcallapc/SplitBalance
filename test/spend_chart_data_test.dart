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

    test(
        'nets a recovered amount against the payer\'s own bucket when they '
        'received it themselves (the common case)', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 5),
            amount: 100.0,
            paidBy: person1,
            category: 'Food',
            recoveredAmount: 40.0,
            recoveredByReceiver: {person1: 40.0}),
      ];

      final months = computeMonthlySpend(bills, person1, person2);

      expect(months, hasLength(1));
      expect(months.single.person1Amount, 60.0);
      expect(months.single.person2Amount, 0.0);
    });

    test(
        'credits a recovered amount to whoever actually received it, not '
        'the bill\'s payer, matching AggregatedCalculationService\'s '
        'balance math', () {
      // Alice pays $100, but Bob is the one who gets $50 back - Bob's
      // bucket should be pulled down by that $50 (he's holding money that
      // belongs against Alice's outlay), while Alice's stays at her full
      // $100 outlay. Net household total is still 50.
      final bills = [
        Bill(
            date: DateTime(2024, 1, 5),
            amount: 100.0,
            paidBy: person1,
            category: 'Food',
            recoveredAmount: 50.0,
            recoveredByReceiver: {person2: 50.0}),
      ];

      final months = computeMonthlySpend(bills, person1, person2);

      expect(months, hasLength(1));
      expect(months.single.person1Amount, 100.0);
      expect(months.single.person2Amount, -50.0);
      expect(months.single.total, 50.0);
    });

    test('sums recovered amounts split across both receivers on the same '
        'bill', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 5),
            amount: 100.0,
            paidBy: person1,
            category: 'Food',
            recoveredAmount: 50.0,
            recoveredByReceiver: {person1: 30.0, person2: 20.0}),
      ];

      final months = computeMonthlySpend(bills, person1, person2);

      expect(months, hasLength(1));
      expect(months.single.person1Amount, 70.0); // 100 - 30
      expect(months.single.person2Amount, -20.0);
      expect(months.single.total, 50.0);
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

    test('accumulates netAmount, not amount, when a bill has a recovered '
        'amount', () {
      final bills = [
        Bill(
            date: DateTime(2024, 1, 1),
            amount: 100.0,
            paidBy: person1,
            category: 'Food',
            recoveredAmount: 25.0),
        Bill(
            date: DateTime(2024, 1, 2),
            amount: 50.0,
            paidBy: person2,
            category: 'Food'),
      ];

      final points = computeCumulativeSpend(bills, person1, person2);

      expect(points[0].cumulativeAmount, 75.0);
      expect(points[1].cumulativeAmount, 125.0);
    });
  });
}
