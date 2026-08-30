import '../models/bill.dart';
import '../models/payment_split.dart';
import '../models/category.dart';

class BalanceResult {
  final String person1Name;
  final String person2Name;
  final double person1Paid;
  final double person2Paid;
  final double person1Expected;
  final double person2Expected;
  final double
      netBalance; // positive = person1 owes person2, negative = person2 owes person1
  final Map<String, CategoryBalance> categoryBalances;

  BalanceResult({
    required this.person1Name,
    required this.person2Name,
    required this.person1Paid,
    required this.person2Paid,
    required this.person1Expected,
    required this.person2Expected,
    required this.netBalance,
    required this.categoryBalances,
  });
}

class CategoryBalance {
  final String category;
  final double person1Paid;
  final double person2Paid;
  final double person1Expected;
  final double person2Expected;

  CategoryBalance({
    required this.category,
    required this.person1Paid,
    required this.person2Paid,
    required this.person1Expected,
    required this.person2Expected,
  });
}

// A time slice bounded by two consecutive distinct split end dates (from
// collectEndDates). [start] is exclusive, [end] is inclusive; either may be
// null for -/+infinity. Within a single period, the split that governs a
// given category is constant - see computeSplitPeriodsForCategory.
class SplitPeriod {
  final DateTime? start;
  final DateTime? end;

  const SplitPeriod({this.start, this.end});
}

// Every distinct endDate across *all* splits (any category) - the global set
// of boundaries PaymentSplit.containsDate resolves ranges against.
List<DateTime> collectEndDates(List<PaymentSplit> splits) {
  return splits.where((s) => s.endDate != null).map((s) => s.endDate!).toList();
}

// Canonical split ordering: newest endDate first, nulls (open-ended
// splits) last. findMatchingSplit's tie-break for same-specificity splits
// (below) is list-order dependent by design - whichever split appears
// first in [splits] wins a tie - so every code path that independently
// fetches a household's splits (PaymentSplitsProvider, and
// AggregatedCalculationService's default fetchSplits) MUST sort with this
// exact comparator, or the two calculators can silently disagree on
// households with more than one same-category split.
int compareSplitsNewestFirst(PaymentSplit a, PaymentSplit b) {
  if (a.endDate == null && b.endDate == null) return 0;
  if (a.endDate == null) return 1; // nulls last
  if (b.endDate == null) return -1; // nulls last
  return b.endDate!.compareTo(a.endDate!);
}

// Finds the split that governs [category] on [date], using the same
// most-specific-wins matching as the per-bill loop this was extracted from:
// a category-specific split beats an 'all' split regardless of list order,
// and among equally-specific matches the first one encountered in [splits]
// wins.
PaymentSplit? findMatchingSplit(
  DateTime date,
  String category,
  List<PaymentSplit> splits,
  List<DateTime> allEndDates,
) {
  PaymentSplit? matchingSplit;
  for (final split in splits) {
    if (split.containsDate(date, allEndDates) &&
        split.appliesToCategory(category)) {
      // Use the most specific split (non-"all" category takes precedence)
      if (matchingSplit == null ||
          (split.category != 'all' && matchingSplit.category == 'all')) {
        matchingSplit = split;
      }
      // If we already have a specific category match, keep it
      if (matchingSplit.category != 'all') {
        break;
      }
    }
  }
  return matchingSplit;
}

// Partitions time into periods bounded by the global split end-date
// boundaries, resolved for [category] specifically. PaymentSplit.containsDate
// used to treat a split's own endDate as inclusive via a buggy "endDate + 1
// day" check that made the single day right after a boundary ambiguously
// match both the closing split and whatever governed the following period
// (list-order dependent, and a real source of incorrect balances - see
// containsDate's fix). Now that that's fixed, every date within a period
// maps to exactly one findMatchingSplit result for [category] and the
// atBoundary/atDayAfter check below always resolves to "no shift" - kept
// rather than deleted so a period's boundary is still derived from
// findMatchingSplit itself (the actual source of truth) instead of a
// separately-maintained assumption about containsDate's semantics.
List<SplitPeriod> computeSplitPeriodsForCategory(
  String category,
  List<PaymentSplit> splits,
) {
  final boundaries = collectEndDates(splits).toSet().toList()..sort();
  if (boundaries.isEmpty) {
    return const [SplitPeriod(start: null, end: null)];
  }

  final effectiveCutoffs = <DateTime>[];
  for (final e in boundaries) {
    final dayAfter = e.add(const Duration(days: 1));
    final atBoundary = findMatchingSplit(e, category, splits, boundaries);
    final atDayAfter = findMatchingSplit(dayAfter, category, splits, boundaries);
    // Same split governs both the boundary day and the day after it: that
    // split absorbs the ambiguous day, so this boundary's effective cutoff
    // moves one day later. Otherwise the boundary stays where it is.
    effectiveCutoffs.add(identical(atBoundary, atDayAfter) ? dayAfter : e);
  }

  final periods = <SplitPeriod>[];
  DateTime? prev;
  for (final cutoff in effectiveCutoffs) {
    periods.add(SplitPeriod(start: prev, end: cutoff));
    prev = cutoff;
  }
  periods.add(SplitPeriod(start: prev, end: null));
  return periods;
}

// A concrete date that findMatchingSplit can use to classify every date
// within [period] - see computeSplitPeriodsForCategory for why a period's
// own end boundary (rather than some arbitrary interior date) is always
// safe to use for this.
DateTime representativeDateFor(SplitPeriod period) {
  if (period.end != null) return period.end!;
  if (period.start != null) {
    return period.start!.add(const Duration(days: 1));
  }
  return DateTime.utc(1970);
}

class CalculationService {
  /// Calculate balances for both people based on bills and payment splits
  static BalanceResult calculateBalances({
    required List<Bill> bills,
    required List<PaymentSplit> splits,
    required List<Category> categories,
    required String person1Name,
    required String person2Name,
  }) {
    // Validate that all bill categories exist
    final categoryNames = categories.map((c) => c.name).toSet();
    for (final bill in bills) {
      if (!categoryNames.contains(bill.category)) {
        throw ArgumentError(
            'Bill category "${bill.category}" does not exist in categories list');
      }
    }

    // Validate that all split categories exist or are "all"
    for (final split in splits) {
      if (split.category != 'all' && !categoryNames.contains(split.category)) {
        throw ArgumentError(
            'Payment split category "${split.category}" does not exist in categories list');
      }
    }

    double person1Paid = 0;
    double person2Paid = 0;
    double person1Expected = 0;
    double person2Expected = 0;

    final Map<String, CategoryBalance> categoryBalancesMap = {};

    // Collect all end dates once for containsDate logic - doesn't depend on
    // the bill being processed, so it doesn't need to be recomputed per bill.
    final allEndDates = collectEndDates(splits);

    // Process each bill
    for (final bill in bills) {
      // Only process bills paid by person1 or person2
      // Bills paid by others are ignored (don't count in paid or expected amounts)
      final isPaidByPerson1 = bill.paidBy == person1Name;
      final isPaidByPerson2 = bill.paidBy == person2Name;

      if (!isPaidByPerson1 && !isPaidByPerson2) {
        // Bill paid by someone else - skip it entirely
        continue;
      }

      // Track who paid, net of anything reimbursed against this bill.
      if (isPaidByPerson1) {
        person1Paid += bill.netAmount;
      } else {
        person2Paid += bill.netAmount;
      }

      // Find matching payment split
      final matchingSplit =
          findMatchingSplit(bill.date, bill.category, splits, allEndDates);

      // Track by category. Paid amounts always count here, mirroring the
      // grand totals above, even when there's no matching split - otherwise
      // the category breakdown silently drops bills and doesn't sum to the
      // grand total. Expected amounts only accumulate when a split applies,
      // since without one there's no basis to expect a particular share.
      final categoryKey = bill.category;
      if (!categoryBalancesMap.containsKey(categoryKey)) {
        categoryBalancesMap[categoryKey] = CategoryBalance(
          category: categoryKey,
          person1Paid: 0,
          person2Paid: 0,
          person1Expected: 0,
          person2Expected: 0,
        );
      }

      var person1Share = 0.0;
      var person2Share = 0.0;
      if (matchingSplit != null) {
        person1Share = bill.netAmount * matchingSplit.person1Percentage / 100;
        person2Share = bill.netAmount * matchingSplit.person2Percentage / 100;

        person1Expected += person1Share;
        person2Expected += person2Share;
      }

      final catBalance = categoryBalancesMap[categoryKey]!;
      categoryBalancesMap[categoryKey] = CategoryBalance(
        category: categoryKey,
        person1Paid:
            catBalance.person1Paid + (isPaidByPerson1 ? bill.netAmount : 0),
        person2Paid:
            catBalance.person2Paid + (isPaidByPerson2 ? bill.netAmount : 0),
        person1Expected: catBalance.person1Expected + person1Share,
        person2Expected: catBalance.person2Expected + person2Share,
      );
    }

    // Calculate net balance
    // If person1 paid more than expected, person2 owes person1 (negative)
    // If person1 paid less than expected, person1 owes person2 (positive)
    // netBalance = person1Expected - person1Paid
    // Positive means person1 owes person2 (person1 underpaid)
    // Negative means person2 owes person1 (person1 overpaid)
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
