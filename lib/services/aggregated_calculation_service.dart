import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/category.dart' as models;
import '../models/payment_split.dart';
import 'calculation_service.dart';
import 'postgrest_paging.dart';

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
// [trackedPersonNames] is always [person1Name, person2Name] (in either
// order) - it's here so the recovered-amount side of this fetch can confirm
// the underlying bill was paid by one of the two people actually being
// balanced, not just that its own received_by/household_id line up (see the
// doc comment on _defaultFetchPersonPaidTotal for why that matters).
typedef FetchPersonPaidTotal = Future<double> Function({
  required String householdId,
  required String paidBy,
  required List<String> trackedPersonNames,
});

// Count of bills in the household paid by [paidBy], across all
// categories/dates - the "Expenses Added" stat on the summary screen's
// Statistics card.
typedef FetchPersonBillCount = Future<int> Function({
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
  required List<String> trackedPersonNames,
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
    FetchPersonBillCount? fetchPersonBillCount,
    FetchCategoryPeriodPersonPaid? fetchCategoryPeriodPersonPaid,
    FetchHouseholdTotals? fetchHouseholdTotals,
  })  : _fetchSplits = fetchSplits ?? _defaultFetchSplits,
        _fetchPersonPaidTotal =
            fetchPersonPaidTotal ?? _defaultFetchPersonPaidTotal,
        _fetchPersonBillCount =
            fetchPersonBillCount ?? _defaultFetchPersonBillCount,
        _fetchCategoryPeriodPersonPaid = fetchCategoryPeriodPersonPaid ??
            _defaultFetchCategoryPeriodPersonPaid,
        _fetchHouseholdTotals =
            fetchHouseholdTotals ?? _defaultFetchHouseholdTotals;

  final FetchSplits _fetchSplits;
  final FetchPersonPaidTotal _fetchPersonPaidTotal;
  final FetchPersonBillCount _fetchPersonBillCount;
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
    // Canonical ordering is enforced in calculateBalances itself (applies
    // regardless of which fetchSplits is in use), not here.
    return rows.map((row) => PaymentSplit.fromMap(row)).toList();
  }

  // None of these need a Postgres RPC/schema migration: PostgREST's
  // max_rows (supabase/config.toml) silently caps an unpaginated .select()
  // at 1000 rows instead of erroring, so a naive single .select() + fold
  // would silently undercount once a household crossed that many matching
  // bills (see https://github.com/allapcallapc/SplitBalance/issues/57).
  // _sumAmounts works around that client-side instead, via the shared
  // pageAndReduce helper (also used by BillsProvider, which hits the same
  // limit summing recovered amounts), rather than relying on a server-side
  // SUM(). .count(CountOption.exact) (used below for bill counts)
  // sidesteps the same limit differently: it's a HEAD request, so PostgREST
  // never materializes a row body for max_rows to truncate - the exact
  // count comes back via the Content-Range header.
  static Future<double> _sumAmounts(
    PostgrestFilterBuilder<PostgrestList> Function() buildQuery,
  ) {
    return pageAndReduce<double>(
      buildQuery: buildQuery,
      initial: 0.0,
      reduce: (total, row) => total + (row['amount'] as num).toDouble(),
    );
  }

  // A recovered amount reduces whoever *received* the money's paid total,
  // not necessarily the bill's original payer - money can come back to
  // either household member regardless of who fronted the bill (see
  // RecoveredAmount.receivedBy). When the receiver differs from the bill's
  // payer, this correctly shifts the debt: the payer's total stays at the
  // bill's full amount (they're still out that cash) while the receiver's
  // total goes negative by the recovered amount (they're now holding money
  // that belongs to the payer), on top of whatever they separately owe from
  // the split itself. bill_recovered_amounts.household_id is denormalized
  // from the linked bill, so no join would be needed for household scoping -
  // but one is still required to check the bill's own paid_by is in
  // [trackedPersonNames]: renaming a household member (person1Name/
  // person2Name in settings) doesn't retroactively update paid_by on bills
  // recorded before the rename, so a stale bill can be paid by a name that
  // matches neither person currently being balanced. Without this check, a
  // recovered amount on such a bill would still reduce a tracked person's
  // total even though the bill it came from was never counted in anyone's
  // paid total in the first place - an unearned reduction with no
  // corresponding paid amount behind it.
  static Future<double> _defaultFetchPersonPaidTotal({
    required String householdId,
    required String paidBy,
    required List<String> trackedPersonNames,
  }) async {
    final results = await Future.wait([
      _sumAmounts(() => Supabase.instance.client
          .from('bills')
          .select('amount')
          .eq('household_id', householdId)
          .eq('paid_by', paidBy)),
      _sumAmounts(() => Supabase.instance.client
          .from('bill_recovered_amounts')
          .select('amount, bills!inner(paid_by)')
          .eq('household_id', householdId)
          .eq('received_by', paidBy)
          .inFilter('bills.paid_by', trackedPersonNames)),
    ]);
    return results[0] - results[1];
  }

  static Future<int> _defaultFetchPersonBillCount({
    required String householdId,
    required String paidBy,
  }) async {
    return Supabase.instance.client
        .from('bills')
        .count(CountOption.exact)
        .eq('household_id', householdId)
        .eq('paid_by', paidBy);
  }

  // Count of bills paid by [paidBy] - see FetchPersonBillCount.
  Future<int> fetchPersonBillCount({
    required String householdId,
    required String paidBy,
  }) {
    return _fetchPersonBillCount(householdId: householdId, paidBy: paidBy);
  }

  static Future<double> _defaultFetchCategoryPeriodPersonPaid({
    required String householdId,
    required String category,
    required DateTime? periodStart,
    required DateTime? periodEnd,
    required String paidBy,
    required List<String> trackedPersonNames,
  }) async {
    final results = await Future.wait([
      _sumAmounts(() {
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
        return query;
      }),
      // Scoped to this (category, period) slot via the linked bill's own
      // category/date (a PostgREST embed, bills!inner(...)), but attributed
      // to whoever *received* the money rather than the bill's payer - see
      // _defaultFetchPersonPaidTotal. Also requires bills.paid_by to be in
      // trackedPersonNames, for the same reason as there: a bill left over
      // from before a household member rename can't be paid_by anyone
      // currently tracked, so a recovered amount against it must not offset
      // either person's total.
      _sumAmounts(() {
        var query = Supabase.instance.client
            .from('bill_recovered_amounts')
            .select('amount, bills!inner(category, date, paid_by)')
            .eq('household_id', householdId)
            .eq('bills.category', category)
            .eq('received_by', paidBy)
            .inFilter('bills.paid_by', trackedPersonNames);
        if (periodStart != null) {
          query = query.gt('bills.date', _dateFormat.format(periodStart));
        }
        if (periodEnd != null) {
          query = query.lte('bills.date', _dateFormat.format(periodEnd));
        }
        return query;
      }),
    ]);
    return results[0] - results[1];
  }

  static Future<HouseholdTotals> _defaultFetchHouseholdTotals({
    required String householdId,
  }) async {
    // Future.wait<num> (not the usual Future<T>.wait) so the differently
    // typed count (int) and sum (double) queries can run in parallel from
    // one call, the same way the two-fetch shape below fires in parallel.
    // bill_recovered_amounts carries its own household_id (denormalized from
    // its linked bill), so this total needs no join - unlike the per-payer
    // fetchers above, which need paid_by off the bill itself.
    final results = await Future.wait<num>([
      Supabase.instance.client
          .from('bills')
          .count(CountOption.exact)
          .eq('household_id', householdId),
      _sumAmounts(() => Supabase.instance.client
          .from('bills')
          .select('amount')
          .eq('household_id', householdId)),
      _sumAmounts(() => Supabase.instance.client
          .from('bill_recovered_amounts')
          .select('amount')
          .eq('household_id', householdId)),
    ]);
    return HouseholdTotals(
      billCount: results[0].toInt(),
      totalAmount: results[1].toDouble() - results[2].toDouble(),
    );
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
  //
  // A second, deliberate divergence: when a recovered amount's receivedBy
  // differs from its bill's paidBy, this service attributes the reduction
  // to whoever actually received the money (see _defaultFetchPersonPaidTotal)
  // - so the receiver's total goes negative by that amount on top of their
  // own split share, correctly shifting the debt to them. CalculationService
  // can't do this: Bill.recoveredAmount is a single pre-aggregated scalar
  // with no per-receiver breakdown, so it always nets the reduction against
  // the bill's own payer regardless of who actually received it.
  Future<BalanceResult> calculateBalances({
    required String householdId,
    required List<models.Category> categories,
    required String person1Name,
    required String person2Name,
  }) async {
    final trackedPersonNames = [person1Name, person2Name];
    final results = await Future.wait([
      _fetchSplits(householdId: householdId),
      _fetchPersonPaidTotal(
        householdId: householdId,
        paidBy: person1Name,
        trackedPersonNames: trackedPersonNames,
      ),
      _fetchPersonPaidTotal(
        householdId: householdId,
        paidBy: person2Name,
        trackedPersonNames: trackedPersonNames,
      ),
    ]);
    // Canonical order enforced here, on whatever fetchSplits returned -
    // not just in the default implementation - so findMatchingSplit's
    // list-order-dependent tie-break can never silently diverge from the
    // order PaymentSplitsProvider always sorts into for the still-live
    // CalculationService path. See compareSplitsNewestFirst's doc comment.
    final splits = (results[0] as List<PaymentSplit>).toList()
      ..sort(compareSplitsNewestFirst);
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
          trackedPersonNames: trackedPersonNames,
        ));
        slots.add(_CategoryPeriodSlot(category: category, period: period));
        futures.add(_fetchCategoryPeriodPersonPaid(
          householdId: householdId,
          category: category,
          periodStart: period.start,
          periodEnd: period.end,
          paidBy: person2Name,
          trackedPersonNames: trackedPersonNames,
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
      // Known, accepted divergence from CalculationService (see this
      // class's doc comment for the other one): a bill fully offset by its
      // own recovered amounts nets to exactly 0 here, indistinguishable from
      // "no bill exists in this slot at all" - so its category can be
      // silently omitted from categoryBalances if nothing else in that
      // category/period contributes a nonzero net amount. CalculationService
      // always includes a bill's category regardless of its net amount, so
      // it would still show that category with $0 values. Rare in practice
      // (a category needs to be *entirely* refunded with no other activity
      // in the same split period) and not worth an extra bill-existence
      // query per slot to close - revisit if it turns out to matter.
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
