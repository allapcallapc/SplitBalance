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
  final double netBalance; // positive = person1 owes person2, negative = person2 owes person1
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
          'Bill category "${bill.category}" does not exist in categories list'
        );
      }
    }

    // Validate that all split categories exist or are "all"
    for (final split in splits) {
      if (split.category != 'all' && !categoryNames.contains(split.category)) {
        throw ArgumentError(
          'Payment split category "${split.category}" does not exist in categories list'
        );
      }
    }

    double person1Paid = 0;
    double person2Paid = 0;
    double person1Expected = 0;
    double person2Expected = 0;

    final Map<String, CategoryBalance> categoryBalancesMap = {};

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

      // Track who paid
      if (isPaidByPerson1) {
        person1Paid += bill.amount;
      } else {
        person2Paid += bill.amount;
      }

      // Collect all end dates for containsDate logic
      final allEndDates = splits
          .where((s) => s.endDate != null)
          .map((s) => s.endDate!)
          .toList();

      // Find matching payment split
      PaymentSplit? matchingSplit;
      for (final split in splits) {
        if (split.containsDate(bill.date, allEndDates) && split.appliesToCategory(bill.category)) {
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

      if (matchingSplit != null) {
        // Calculate expected amounts
        final person1Share = bill.amount * matchingSplit.person1Percentage / 100;
        final person2Share = bill.amount * matchingSplit.person2Percentage / 100;

        person1Expected += person1Share;
        person2Expected += person2Share;

        // Track by category
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

        final catBalance = categoryBalancesMap[categoryKey]!;
        categoryBalancesMap[categoryKey] = CategoryBalance(
          category: categoryKey,
          person1Paid: catBalance.person1Paid +
              (isPaidByPerson1 ? bill.amount : 0),
          person2Paid: catBalance.person2Paid +
              (isPaidByPerson2 ? bill.amount : 0),
          person1Expected: catBalance.person1Expected + person1Share,
          person2Expected: catBalance.person2Expected + person2Share,
        );
      }
    }

    // Calculate net balance
    // If person1 paid more than expected, person2 owes person1 (negative)
    // If person1 paid less than expected, person1 owes person2 (positive)
    final netBalance = (person1Paid - person1Expected) - (person2Paid - person2Expected);

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
