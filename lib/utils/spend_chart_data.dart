import '../models/bill.dart';

// One calendar month's paid amounts, split by person.
class MonthlySpend {
  final DateTime month; // First of the month.
  final double person1Amount;
  final double person2Amount;

  const MonthlySpend({
    required this.month,
    required this.person1Amount,
    required this.person2Amount,
  });

  double get total => person1Amount + person2Amount;
}

// Buckets [bills] by calendar month and splits each month's total between
// person1Name/person2Name. Bills paid by anyone else are excluded, matching
// CalculationService's treatment of paid/expected totals. Only months that
// actually contain a bill appear, in chronological order.
//
// Each bill's full (gross) amount is credited to whoever paid it, then each
// recovered amount is debited from whoever actually *received* it (via
// bill.recoveredByReceiver) - not necessarily the payer - matching
// AggregatedCalculationService's balance math instead of always netting the
// reduction against the bill's own paidBy. When a bill's receiver is the
// same as its payer (the common case), this reduces to exactly
// bill.netAmount attributed to the payer, same as before.
List<MonthlySpend> computeMonthlySpend(
  List<Bill> bills,
  String person1Name,
  String person2Name,
) {
  final Map<DateTime, MonthlySpend> byMonth = {};
  for (final bill in bills) {
    final isPerson1 = bill.paidBy == person1Name;
    final isPerson2 = bill.paidBy == person2Name;
    if (!isPerson1 && !isPerson2) continue;

    final monthKey = DateTime(bill.date.year, bill.date.month);
    final existing = byMonth[monthKey];
    final person1Recovered = bill.recoveredByReceiver[person1Name] ?? 0;
    final person2Recovered = bill.recoveredByReceiver[person2Name] ?? 0;
    byMonth[monthKey] = MonthlySpend(
      month: monthKey,
      person1Amount: (existing?.person1Amount ?? 0) +
          (isPerson1 ? bill.amount : 0) -
          person1Recovered,
      person2Amount: (existing?.person2Amount ?? 0) +
          (isPerson2 ? bill.amount : 0) -
          person2Recovered,
    );
  }

  final months = byMonth.values.toList()
    ..sort((a, b) => a.month.compareTo(b.month));
  return months;
}

// A single point on the running-total line: the cumulative amount paid by
// person1Name/person2Name across every bill up to and including [date].
class CumulativeSpendPoint {
  final DateTime date;
  final double cumulativeAmount;

  const CumulativeSpendPoint({
    required this.date,
    required this.cumulativeAmount,
  });
}

// Sorts [bills] by date (oldest first) and accumulates a running total, one
// point per bill. Bills paid by anyone else are excluded, matching
// CalculationService's treatment of paid/expected totals - so the last
// point's cumulativeAmount equals the ledger's "total" figure. A single
// household-wide total, not split by person - so unlike computeMonthlySpend,
// it doesn't matter who actually received a bill's recovered amount:
// bill.netAmount (gross minus everything recovered, regardless of receiver)
// is exactly the household's net cost either way.
List<CumulativeSpendPoint> computeCumulativeSpend(
  List<Bill> bills,
  String person1Name,
  String person2Name,
) {
  final relevant = bills
      .where((b) => b.paidBy == person1Name || b.paidBy == person2Name)
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  double running = 0;
  return relevant.map((bill) {
    running += bill.netAmount;
    return CumulativeSpendPoint(date: bill.date, cumulativeAmount: running);
  }).toList();
}
