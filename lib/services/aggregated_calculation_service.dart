import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart' as models;
import '../models/payment_split.dart';
import 'calculation_service.dart';

// Fetches every payment split for the household. Small, unpaginated table -
// this is the same query PaymentSplitsProvider already runs, just owned by
// this service instead of handed in by the caller (see the "why splits is
// fetched internally but categories isn't" note below).
typedef FetchSplits = Future<List<PaymentSplit>> Function({
  required String householdId,
});

// Sum of bill.amount for every bill in the household paid by [paidBy],
// across all categories/dates - the same unconditional total
// CalculationService.calculateBalances accumulates as person1Paid/person2Paid.
typedef FetchPersonPaidTotal = Future<double> Function({
  required String householdId,
  required String paidBy,
});

// Sum of bill.amount for bills in [category] paid by [paidBy], with
// date in (periodStart, periodEnd] (either bound may be null for
// -/+infinity). This is the per-(category, period, person) slice the
// aggregated calculation is built from.
typedef FetchCategoryPeriodPersonPaid = Future<double> Function({
  required String householdId,
  required String category,
  required DateTime? periodStart, // exclusive
  required DateTime? periodEnd, // inclusive
  required String paidBy,
});

class HouseholdTotals {
  const HouseholdTotals({required this.billCount, required this.totalAmount});
  final int billCount;
  final double totalAmount;
}

// Unfiltered bill count/total for the household, for the summary screen's
// "Total Bills"/"Total Amount" stat rows - not part of calculateBalances
// itself since those stats aren't part of BalanceResult either.
typedef FetchHouseholdTotals = Future<HouseholdTotals> Function({
  required String householdId,
});

// Computes the same BalanceResult as CalculationService.calculateBalances,
// but without ever loading the household's full bill list into memory: it
// issues narrow, filtered sum queries grouped by category/split-period/
// person instead. The fetch functions are injectable (defaulting to real
// Supabase calls) so the aggregation/calculation logic itself - the part
// that actually decides what the numbers mean - can be tested without a
// database. calculateBalances is the *only* public entry point that matters
// here: callers never see how many queries it took.
class AggregatedCalculationService {
  AggregatedCalculationService({
    FetchSplits? fetchSplits,
    FetchPersonPaidTotal? fetchPersonPaidTotal,
    FetchCategoryPeriodPersonPaid? fetchCategoryPeriodPersonPaid,
    FetchHouseholdTotals? fetchHouseholdTotals,
  })  : _fetchSplits = fetchSplits ?? _defaultFetchSplits,
        _fetchPersonPaidTotal =
            fetchPersonPaidTotal ?? _defaultFetchPersonPaidTotal,
        _fetchCategoryPeriodPersonPaid = fetchCategoryPeriodPersonPaid ??
            _defaultFetchCategoryPeriodPersonPaid,
        _fetchHouseholdTotals =
            fetchHouseholdTotals ?? _defaultFetchHouseholdTotals;

  final FetchSplits _fetchSplits;
  final FetchPersonPaidTotal _fetchPersonPaidTotal;
  final FetchCategoryPeriodPersonPaid _fetchCategoryPeriodPersonPaid;
  final FetchHouseholdTotals _fetchHouseholdTotals;

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  static Future<List<PaymentSplit>> _defaultFetchSplits({
    required String householdId,
  }) async {
    final rows = await Supabase.instance.client
        .from('payment_splits')
        .select()
        .eq('household_id', householdId);
    return rows.map((row) => PaymentSplit.fromMap(row)).toList();
  }

  static double _sumAmount(List<Map<String, dynamic>> rows) {
    return rows.fold<double>(
        0.0, (sum, row) => sum + (row['amount'] as num).toDouble());
  }

  static Future<double> _defaultFetchPersonPaidTotal({
    required String householdId,
    required String paidBy,
  }) async {
    final rows = await Supabase.instance.client
        .from('bills')
        .select('amount')
        .eq('household_id', householdId)
        .eq('paid_by', paidBy);
    return _sumAmount(rows);
  }

  static Future<double> _defaultFetchCategoryPeriodPersonPaid({
    required String householdId,
    required String category,
    required DateTime? periodStart,
    required DateTime? periodEnd,
    required String paidBy,
  }) async {
    var query = Supabase.instance.client
        .from('bills')
        .select('amount')
        .eq('household_id', householdId)
        .eq('category', category)
        .eq('paid_by', paidBy);
    if (periodStart != null) {
      query = query.gt('date', _dateFormat.format(periodStart));
    }
    if (periodEnd != null) {
      query = query.lte('date', _dateFormat.format(periodEnd));
    }
    final rows = await query;
    return _sumAmount(rows);
  }

  static Future<HouseholdTotals> _defaultFetchHouseholdTotals({
    required String householdId,
  }) async {
    final rows = await Supabase.instance.client
        .from('bills')
        .select('amount')
        .eq('household_id', householdId);
    return HouseholdTotals(billCount: rows.length, totalAmount: _sumAmount(rows));
  }

  // Unfiltered bill count/total for the household - see FetchHouseholdTotals.
  Future<HouseholdTotals> fetchHouseholdTotals({required String householdId}) {
    return _fetchHouseholdTotals(householdId: householdId);
  }

  // Computes balances for the household without ever loading its full bill
  // list. `splits` is fetched internally (small, unpaginated table - see the
  // FetchSplits doc comment for why this differs from `categories`, which
  // stays a parameter since callers already have it loaded for other
  // reasons). Throws ArgumentError under the same condition
  // CalculationService.calculateBalances does: a split referencing a
  // category that no longer exists.
  //
  // Known, accepted divergence from CalculationService: a *bill* referencing
  // a category no longer in `categories` is silently excluded from
  // categoryBalances here (this service can only ever query categories it's
  // told about), whereas the old path throws for that case. Tracked in
  // https://github.com/allapcallapc/SplitBalance/issues/49.
  Future<BalanceResult> calculateBalances({
    required String householdId,
    required List<models.Category> categories,
    required String person1Name,
    required String person2Name,
  }) async {
    final results = await Future.wait([
      _fetchSplits(householdId: householdId),
      _fetchPersonPaidTotal(householdId: householdId, paidBy: person1Name),
      _fetchPersonPaidTotal(householdId: householdId, paidBy: person2Name),
    ]);
    final splits = results[0] as List<PaymentSplit>;
    final person1Paid = results[1] as double;
    final person2Paid = results[2] as double;

    final categoryNames = categories.map((c) => c.name).toSet();
    for (final split in splits) {
      if (split.category != 'all' && !categoryNames.contains(split.category)) {
        throw ArgumentError(
            'Payment split category "${split.category}" does not exist in categories list');
      }
    }

    final allEndDates = collectEndDates(splits);

    // (category, period) slots to fetch, each carrying enough context to
    // process its result once every fetch has resolved.
    final slots = <_CategoryPeriodSlot>[];
    final futures = <Future<double>>[];
    for (final category in categoryNames) {
      final periods = computeSplitPeriodsForCategory(category, splits);
      for (final period in periods) {
        slots.add(_CategoryPeriodSlot(category: category, period: period));
        futures.add(_fetchCategoryPeriodPersonPaid(
          householdId: householdId,
          category: category,
          periodStart: period.start,
          periodEnd: period.end,
          paidBy: person1Name,
        ));
        slots.add(_CategoryPeriodSlot(category: category, period: period));
        futures.add(_fetchCategoryPeriodPersonPaid(
          householdId: householdId,
          category: category,
          periodStart: period.start,
          periodEnd: period.end,
          paidBy: person2Name,
        ));
      }
    }
    final paidAmounts = await Future.wait(futures);

    double person1Expected = 0;
    double person2Expected = 0;
    final categoryBalancesMap = <String, CategoryBalance>{};

    // paidAmounts alternates person1/person2 for each slot, matching the
    // order slots were appended above.
    for (var i = 0; i < slots.length; i += 2) {
      final slot = slots[i];
      final p1 = paidAmounts[i];
      final p2 = paidAmounts[i + 1];
      if (p1 == 0 && p2 == 0) continue;

      final existing = categoryBalancesMap[slot.category] ??
          CategoryBalance(
            category: slot.category,
            person1Paid: 0,
            person2Paid: 0,
            person1Expected: 0,
            person2Expected: 0,
          );

      final match = findMatchingSplit(
        representativeDateFor(slot.period),
        slot.category,
        splits,
        allEndDates,
      );

      // Expected share is based on the *total* amount spent in this
      // category/period, split according to the matching split's
      // percentages - not on who happened to pay it (matches
      // CalculationService: bill.amount * percentage, regardless of paidBy).
      double p1Expected = 0;
      double p2Expected = 0;
      if (match != null) {
        final periodTotal = p1 + p2;
        p1Expected = periodTotal * match.person1Percentage / 100;
        p2Expected = periodTotal * match.person2Percentage / 100;
        person1Expected += p1Expected;
        person2Expected += p2Expected;
      }

      categoryBalancesMap[slot.category] = CategoryBalance(
        category: slot.category,
        person1Paid: existing.person1Paid + p1,
        person2Paid: existing.person2Paid + p2,
        person1Expected: existing.person1Expected + p1Expected,
        person2Expected: existing.person2Expected + p2Expected,
      );
    }

    final netBalance = person1Expected - person1Paid;

    return BalanceResult(
      person1Name: person1Name,
      person2Name: person2Name,
      person1Paid: person1Paid,
      person2Paid: person2Paid,
      person1Expected: person1Expected,
      person2Expected: person2Expected,
      netBalance: netBalance,
      categoryBalances: categoryBalancesMap,
    );
  }
}

class _CategoryPeriodSlot {
  final String category;
  final SplitPeriod period;
  _CategoryPeriodSlot({required this.category, required this.period});
}
