import 'package:flutter_test/flutter_test.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/services/calculation_service.dart';
import 'package:splitbalance/providers/categories_provider.dart';

void main() {
  group('CalculationService - Balance Calculations', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';
    
    final DateTime baseDate = DateTime(2024, 1, 15);
    
    List<Category> getCategories([List<String>? names]) {
      return (names ?? ['Food', 'Rent', 'Utilities', 'Entertainment'])
          .map((name) => Category(name: name))
          .toList();
    }

    test('Simple 50/50 split - both people pay equally', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 100.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 100.0);
      expect(result.person2Paid, 100.0);
      expect(result.person1Expected, 100.0); // 50% of 200
      expect(result.person2Expected, 100.0); // 50% of 200
      expect(result.netBalance, closeTo(0.0, 0.01)); // Balanced
    });

    test('Simple 50/50 split - one person pays more', () {
      final bills = [
        Bill(date: baseDate, amount: 150.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 150.0);
      expect(result.person2Paid, 50.0);
      expect(result.person1Expected, 100.0); // 50% of 200
      expect(result.person2Expected, 100.0); // 50% of 200
      // Person1 paid 150, expected 100 (overpaid by 50)
      // Person2 paid 50, expected 100 (underpaid by 50)
      // netBalance = person1Expected - person1Paid = 100 - 150 = -50
      // Negative means person2 owes person1 (person1 overpaid)
      expect(result.netBalance, closeTo(-50.0, 0.01));
    });

    test('60/40 split - person1 pays more, person2 owes', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 100.0);
      expect(result.person2Paid, 0.0);
      expect(result.person1Expected, 60.0); // 60% of 100
      expect(result.person2Expected, 40.0); // 40% of 100
      // Person1 paid 100, expected 60 (overpaid by 40)
      // netBalance = person1Expected - person1Paid = 60 - 100 = -40
      // Negative means person2 owes person1 (person1 overpaid)
      expect(result.netBalance, closeTo(-40.0, 0.01));
    });

    test('Multiple bills with same split', () {
      final bills = [
        Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate.add(const Duration(days: 1)), amount: 75.0, paidBy: person2, category: 'Food'),
        Bill(date: baseDate.add(const Duration(days: 2)), amount: 25.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 75.0); // 50 + 25
      expect(result.person2Paid, 75.0); // 75
      expect(result.person1Expected, 75.0); // 50% of 150
      expect(result.person2Expected, 75.0); // 50% of 150
      expect(result.netBalance, closeTo(0.0, 0.01)); // Balanced
    });

    test('Category-specific split overrides default', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 70.0,
          person2: person2,
          person2Percentage: 30.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 200.0);
      expect(result.person2Paid, 0.0);
      // Rent: 70% of 100 = 70, Food: 50% of 100 = 50
      expect(result.person1Expected, closeTo(120.0, 0.01)); // 70 + 50
      // Rent: 30% of 100 = 30, Food: 50% of 100 = 50
      expect(result.person2Expected, closeTo(80.0, 0.01)); // 30 + 50
      
      // Check category balances
      expect(result.categoryBalances.containsKey('Rent'), true);
      expect(result.categoryBalances.containsKey('Food'), true);
      
      final rentBalance = result.categoryBalances['Rent']!;
      expect(rentBalance.person1Paid, 100.0);
      expect(rentBalance.person1Expected, closeTo(70.0, 0.01));
      expect(rentBalance.person2Expected, closeTo(30.0, 0.01));
      
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 100.0);
      expect(foodBalance.person1Expected, closeTo(50.0, 0.01));
      expect(foodBalance.person2Expected, closeTo(50.0, 0.01));
    });

    test('Date-based splits - different percentages over time', () {
      // Using dates that are clearly within each period.
      final date1 = DateTime(2024, 1, 15); // January - matches Jan 31 split
      final date2 = DateTime(2024, 2, 15); // February - matches Feb 28 split
      final date3 = DateTime(2024, 3, 5); // March - matches null endDate split (after Feb 28)

      final bills = [
        Bill(date: date1, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: date2, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: date3, amount: 100.0, paidBy: person1, category: 'Food'),
      ];

      final splits = [
        PaymentSplit(
          endDate: DateTime(2024, 1, 31), // First period (up to and including Jan 31)
          category: 'all',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          endDate: DateTime(2024, 2, 28), // Second period (Feb 1 up to and including Feb 28)
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          // No endDate means applies to dates after last endDate (after Mar 1)
          category: 'all',
          person1: person1,
          person1Percentage: 70.0,
          person2: person2,
          person2Percentage: 30.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 300.0);
      expect(result.person2Paid, 0.0);
      // Jan 15: 60% of 100 = 60, Feb 15: 50% of 100 = 50, Mar 5: 70% of 100 = 70
      expect(result.person1Expected, closeTo(180.0, 0.01)); // 60 + 50 + 70
      // Jan 15: 40% of 100 = 40, Feb 15: 50% of 100 = 50, Mar 5: 30% of 100 = 30
      expect(result.person2Expected, closeTo(120.0, 0.01)); // 40 + 50 + 30
    });

    test('Multiple categories with different splits', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
        Bill(date: baseDate, amount: 30.0, paidBy: person1, category: 'Utilities'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'all', // Default for Utilities
          person1: person1,
          person1Percentage: 70.0,
          person2: person2,
          person2Percentage: 30.0,
        ),
      ];
      
      final categories = getCategories(['Rent', 'Food', 'Utilities']);
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 130.0); // 100 + 30
      expect(result.person2Paid, 50.0);
      
      // Rent: 60% of 100 = 60, Food: 50% of 50 = 25, Utilities: 70% of 30 = 21
      expect(result.person1Expected, closeTo(106.0, 0.01)); // 60 + 25 + 21
      // Rent: 40% of 100 = 40, Food: 50% of 50 = 25, Utilities: 30% of 30 = 9
      expect(result.person2Expected, closeTo(74.0, 0.01)); // 40 + 25 + 9
      
      // Verify all categories are tracked
      expect(result.categoryBalances.length, 3);
      expect(result.categoryBalances.containsKey('Rent'), true);
      expect(result.categoryBalances.containsKey('Food'), true);
      expect(result.categoryBalances.containsKey('Utilities'), true);
    });

    test('Empty bills list returns zero balances', () {
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: [],
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.person1Paid, 0.0);
      expect(result.person2Paid, 0.0);
      expect(result.person1Expected, 0.0);
      expect(result.person2Expected, 0.0);
      expect(result.netBalance, closeTo(0.0, 0.01));
      expect(result.categoryBalances.isEmpty, true);
    });

    test('Bill with no matching split is ignored', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          endDate: DateTime(2024, 1, 1), // Before bill date
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      // Bill date is Jan 15, but split ends Jan 1, so no matching split
      // The split with null endDate should apply (dates after Jan 1), but we only have one split
      // Actually, if there's only one split with endDate Jan 1, then dates after Jan 1 should match the null endDate split
      // But we don't have a null endDate split, so the bill won't match
      // Wait, let me check the logic again. If all splits have endDates, what happens?
      // Looking at containsDate: if endDate is null, it applies to dates after last endDate
      // If endDate is not null, it checks if date falls in the range
      // So if we have a split ending Jan 1, and a bill on Jan 15, it won't match
      // unless there's a split with null endDate
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Bill is paid but not matched to any split
      expect(result.person1Paid, 100.0); // Still tracked as paid
      expect(result.person2Paid, 0.0);
      expect(result.person1Expected, 0.0); // No matching split, so no expected amount
      expect(result.person2Expected, 0.0);

      // The category breakdown must still reflect the paid amount, so it
      // sums to the grand total above, even though there's no expected
      // amount to attribute without a matching split.
      final foodBalance = result.categoryBalances['Food'];
      expect(foodBalance, isNotNull);
      expect(foodBalance!.person1Paid, 100.0);
      expect(foodBalance.person2Paid, 0.0);
      expect(foodBalance.person1Expected, 0.0);
      expect(foodBalance.person2Expected, 0.0);
    });

    test('Throws error for invalid bill category', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'InvalidCategory'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      expect(
        () => CalculationService.calculateBalances(
          bills: bills,
          splits: splits,
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('does not exist in categories list'),
        )),
      );
    });

    test('Throws error for invalid split category', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'InvalidCategory',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      expect(
        () => CalculationService.calculateBalances(
          bills: bills,
          splits: splits,
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('does not exist in categories list'),
        )),
      );
    });

    test('Complex scenario: multiple bills, categories, and date ranges', () {
      final date1 = DateTime(2024, 1, 10);
      final date2 = DateTime(2024, 2, 15);
      final date3 = DateTime(2024, 3, 20);
      
      final bills = [
        // January bills
        Bill(date: date1, amount: 200.0, paidBy: person1, category: 'Rent'),
        Bill(date: date1, amount: 50.0, paidBy: person2, category: 'Food'),
        // February bills
        Bill(date: date2, amount: 200.0, paidBy: person1, category: 'Rent'),
        Bill(date: date2, amount: 75.0, paidBy: person1, category: 'Food'),
        // March bills
        Bill(date: date3, amount: 200.0, paidBy: person2, category: 'Rent'),
        Bill(date: date3, amount: 40.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        // January-February: 60/40 for Rent, 50/50 for Food
        PaymentSplit(
          endDate: DateTime(2024, 2, 29),
          category: 'Rent',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          endDate: DateTime(2024, 2, 29),
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        // March onwards: 50/50 for Rent, 70/30 for Food
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 30.0,
          person2: person2,
          person2Percentage: 70.0,
        ),
      ];
      
      final categories = getCategories(['Rent', 'Food']);
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Payments
      // Person1: Jan Rent 200 + Feb Rent 200 + Feb Food 75 = 475
      expect(result.person1Paid, closeTo(475.0, 0.01));
      // Person2: Jan Food 50 + Mar Rent 200 + Mar Food 40 = 290
      expect(result.person2Paid, closeTo(290.0, 0.01));
      
      // Expected amounts
      // Jan Rent: 60% of 200 = 120, Feb Rent: 60% of 200 = 120, Mar Rent: 50% of 200 = 100
      // Total Rent expected for Person1: 340
      // Jan Food: 50% of 50 = 25, Feb Food: 50% of 75 = 37.5, Mar Food: 30% of 40 = 12
      // Total Food expected for Person1: 74.5
      expect(result.person1Expected, closeTo(414.5, 0.01)); // 340 + 74.5
      
      // Jan Rent: 40% of 200 = 80, Feb Rent: 40% of 200 = 80, Mar Rent: 50% of 200 = 100
      // Total Rent expected for Person2: 260
      // Jan Food: 50% of 50 = 25, Feb Food: 50% of 75 = 37.5, Mar Food: 70% of 40 = 28
      // Total Food expected for Person2: 90.5
      expect(result.person2Expected, closeTo(350.5, 0.01)); // 260 + 90.5
      
      // Net balance
      // Person1 paid 475, expected 414.5 (overpaid by 60.5)
      // netBalance = person1Expected - person1Paid = 414.5 - 475 = -60.5
      // Negative means person2 owes person1 (person1 overpaid)
      expect(result.netBalance, closeTo(-60.5, 0.01));
    });

    test('Balanced scenario - exact payments match expected', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 100.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.netBalance, closeTo(0.0, 0.01));
      expect(result.person1Paid - result.person1Expected, closeTo(0.0, 0.01));
      expect(result.person2Paid - result.person2Expected, closeTo(0.0, 0.01));
    });

    // Tests to demonstrate the net balance calculation bug
    group('Net Balance Calculation Bug Tests', () {
      test('Bug: Person1 overpays by 50, person2 underpays by 50 - person2 should owe person1 50', () {
        // Scenario: Person1 paid 150, expected 100 (overpaid by 50)
        // Person2 paid 50, expected 100 (underpaid by 50)
        // Net: Person2 owes Person1 50, so netBalance should be -50 (negative = person2 owes person1)
        final bills = [
          Bill(date: baseDate, amount: 150.0, paidBy: person1, category: 'Food'),
          Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
        ];
        
        final splits = [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ];
        
        final categories = getCategories();
        
        final result = CalculationService.calculateBalances(
          bills: bills,
          splits: splits,
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        );
        
        expect(result.person1Paid, 150.0);
        expect(result.person2Paid, 50.0);
        expect(result.person1Expected, 100.0); // 50% of 200
        expect(result.person2Expected, 100.0); // 50% of 200
        
        // Person1 overpaid by 50, Person2 underpaid by 50
        // According to comment: "negative = person2 owes person1"
        // So netBalance should be -50
        expect(result.netBalance, closeTo(-50.0, 0.01),
          reason: 'Person1 overpaid by 50, Person2 underpaid by 50, so Person2 owes Person1 50. NetBalance should be -50 (negative = person2 owes person1)');
      });

      test('Bug: Person1 underpays by 50, person2 overpays by 50 - person1 should owe person2 50', () {
        // Scenario: Person1 paid 50, expected 100 (underpaid by 50)
        // Person2 paid 150, expected 100 (overpaid by 50)
        // Net: Person1 owes Person2 50, so netBalance should be +50 (positive = person1 owes person2)
        final bills = [
          Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Food'),
          Bill(date: baseDate, amount: 150.0, paidBy: person2, category: 'Food'),
        ];
        
        final splits = [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 50.0,
            person2: person2,
            person2Percentage: 50.0,
          ),
        ];
        
        final categories = getCategories();
        
        final result = CalculationService.calculateBalances(
          bills: bills,
          splits: splits,
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        );
        
        expect(result.person1Paid, 50.0);
        expect(result.person2Paid, 150.0);
        expect(result.person1Expected, 100.0); // 50% of 200
        expect(result.person2Expected, 100.0); // 50% of 200
        
        // Person1 underpaid by 50, Person2 overpaid by 50
        // According to comment: "positive = person1 owes person2"
        // So netBalance should be +50
        expect(result.netBalance, closeTo(50.0, 0.01),
          reason: 'Person1 underpaid by 50, Person2 overpaid by 50, so Person1 owes Person2 50. NetBalance should be +50 (positive = person1 owes person2)');
      });

      test('Bug: Person1 pays exactly their share, person2 underpays - person2 should owe person1', () {
        // Scenario: 60/40 split, Person1 pays 60, expected 60 (balanced)
        // Person2 pays 0, expected 40 (underpaid by 40)
        // Net: Person2 owes Person1 40, so netBalance should be -40
        final bills = [
          Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        ];
        
        final splits = [
          PaymentSplit(
            category: 'all',
            person1: person1,
            person1Percentage: 60.0,
            person2: person2,
            person2Percentage: 40.0,
          ),
        ];
        
        final categories = getCategories();
        
        final result = CalculationService.calculateBalances(
          bills: bills,
          splits: splits,
          categories: categories,
          person1Name: person1,
          person2Name: person2,
        );
        
        expect(result.person1Paid, 100.0);
        expect(result.person2Paid, 0.0);
        expect(result.person1Expected, 60.0); // 60% of 100
        expect(result.person2Expected, 40.0); // 40% of 100
        
        // Person1 overpaid by 40 (100 - 60), Person2 underpaid by 40 (0 - 40)
        // According to comment: "negative = person2 owes person1"
        // So netBalance should be -40
        expect(result.netBalance, closeTo(-40.0, 0.01),
          reason: 'Person1 overpaid by 40, Person2 underpaid by 40, so Person2 owes Person1 40. NetBalance should be -40 (negative = person2 owes person1)');
      });
    });

    test('Person name matching is case-sensitive', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: 'alice', category: 'Food'), // lowercase
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1, // 'Alice'
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // 'alice' != 'Alice', so the bill is paid by a third person and should be ignored entirely
      expect(result.person1Paid, 0.0);
      expect(result.person2Paid, 0.0);
      // Expected amounts should also be 0 because the bill is ignored (paid by third person)
      expect(result.person1Expected, 0.0);
      expect(result.person2Expected, 0.0);
    });

    test('Multiple splits for same category - most specific wins', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'Food', // More specific
          person1: person1,
          person1Percentage: 80.0,
          person2: person2,
          person2Percentage: 20.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Food-specific split should be used (80/20), not the 'all' split (50/50)
      expect(result.person1Expected, 80.0);
      expect(result.person2Expected, 20.0);
    });
  });

  group('CalculationService - Category Paid Amounts', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';
    
    final DateTime baseDate = DateTime(2024, 1, 15);
    
    List<Category> getCategories([List<String>? names]) {
      return (names ?? ['Food', 'Rent', 'Utilities', 'Entertainment'])
          .map((name) => Category(name: name))
          .toList();
    }

    test('Category paid amounts - single person pays all bills in category', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 75.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.categoryBalances.containsKey('Food'), true);
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 225.0); // 100 + 50 + 75
      expect(foodBalance.person2Paid, 0.0);
    });

    test('Category paid amounts - both people pay bills in same category', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
        Bill(date: baseDate, amount: 75.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 25.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.categoryBalances.containsKey('Food'), true);
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 175.0); // 100 + 75
      expect(foodBalance.person2Paid, 75.0);  // 50 + 25
    });

    test('Category paid amounts - multiple categories tracked separately', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
        Bill(date: baseDate, amount: 200.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate, amount: 30.0, paidBy: person2, category: 'Utilities'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      expect(result.categoryBalances.length, 3);
      
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 100.0);
      expect(foodBalance.person2Paid, 50.0);
      
      final rentBalance = result.categoryBalances['Rent']!;
      expect(rentBalance.person1Paid, 200.0);
      expect(rentBalance.person2Paid, 0.0);
      
      final utilitiesBalance = result.categoryBalances['Utilities']!;
      expect(utilitiesBalance.person1Paid, 0.0);
      expect(utilitiesBalance.person2Paid, 30.0);
    });

    test('Category paid amounts - person pays bills across multiple categories', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 200.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Utilities'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Total person1 paid across all categories
      expect(result.person1Paid, 350.0); // 100 + 200 + 50
      
      // Category-specific paid amounts
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 100.0);
      
      final rentBalance = result.categoryBalances['Rent']!;
      expect(rentBalance.person1Paid, 200.0);
      
      final utilitiesBalance = result.categoryBalances['Utilities']!;
      expect(utilitiesBalance.person1Paid, 50.0);
      
      // Person2 paid nothing in any category
      expect(foodBalance.person2Paid, 0.0);
      expect(rentBalance.person2Paid, 0.0);
      expect(utilitiesBalance.person2Paid, 0.0);
    });

    test('Category paid amounts - complex scenario with multiple bills per category', () {
      final bills = [
        // Food category
        Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate.add(const Duration(days: 1)), amount: 30.0, paidBy: person2, category: 'Food'),
        Bill(date: baseDate.add(const Duration(days: 2)), amount: 20.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate.add(const Duration(days: 3)), amount: 40.0, paidBy: person2, category: 'Food'),
        // Rent category
        Bill(date: baseDate, amount: 500.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate.add(const Duration(days: 10)), amount: 500.0, paidBy: person1, category: 'Rent'),
        // Utilities category
        Bill(date: baseDate, amount: 60.0, paidBy: person2, category: 'Utilities'),
        Bill(date: baseDate.add(const Duration(days: 5)), amount: 40.0, paidBy: person2, category: 'Utilities'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Verify category paid amounts are correctly aggregated
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 70.0);  // 50 + 20
      expect(foodBalance.person2Paid, 70.0);  // 30 + 40
      
      final rentBalance = result.categoryBalances['Rent']!;
      expect(rentBalance.person1Paid, 1000.0); // 500 + 500
      expect(rentBalance.person2Paid, 0.0);
      
      final utilitiesBalance = result.categoryBalances['Utilities']!;
      expect(utilitiesBalance.person1Paid, 0.0);
      expect(utilitiesBalance.person2Paid, 100.0); // 60 + 40
      
      // Verify totals match
      expect(result.person1Paid, 1070.0); // 70 (Food) + 1000 (Rent)
      expect(result.person2Paid, 170.0);  // 70 (Food) + 100 (Utilities)
    });

    test('Category paid amounts - zero amounts when no bills in category', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories(['Food', 'Rent', 'Utilities']);
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Only Food category should have a balance
      expect(result.categoryBalances.length, 1);
      expect(result.categoryBalances.containsKey('Food'), true);
      expect(result.categoryBalances.containsKey('Rent'), false);
      expect(result.categoryBalances.containsKey('Utilities'), false);
      
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 100.0);
      expect(foodBalance.person2Paid, 0.0);
    });

    test('Category paid amounts - category-specific split does not affect paid amounts', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 100.0, paidBy: person2, category: 'Rent'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 70.0,
          person2: person2,
          person2Percentage: 30.0,
        ),
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 30.0,
          person2: person2,
          person2Percentage: 70.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      // Paid amounts should reflect who actually paid, regardless of split percentages
      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 100.0); // Person1 paid the bill
      expect(foodBalance.person2Paid, 0.0);
      
      final rentBalance = result.categoryBalances['Rent']!;
      expect(rentBalance.person1Paid, 0.0);
      expect(rentBalance.person2Paid, 100.0); // Person2 paid the bill
      
      // Expected amounts should reflect the split percentages
      expect(foodBalance.person1Expected, 70.0); // 70% of 100
      expect(foodBalance.person2Expected, 30.0); // 30% of 100
      expect(rentBalance.person1Expected, 30.0); // 30% of 100
      expect(rentBalance.person2Expected, 70.0); // 70% of 100
    });
  });

  group('CategoriesProvider - isCategoryInUse', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';
    final DateTime baseDate = DateTime(2024, 1, 15);

    test('Category not in use when no bills or splits', () {
      final provider = CategoriesProvider();
      
      final result = provider.isCategoryInUse('Food', [], []);
      
      expect(result, false);
    });

    test('Category in use when bill uses it', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final result = provider.isCategoryInUse('Food', bills, []);
      
      expect(result, true);
    });

    test('Category not in use when bill uses different category', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      
      final result = provider.isCategoryInUse('Rent', bills, []);
      
      expect(result, false);
    });

    test('Category NOT in use when split uses it - splits dont prevent deletion', () {
      final provider = CategoriesProvider();
      final splits = [
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      // Categories referenced in splits don't prevent deletion - they'll be removed automatically
      final result = provider.isCategoryInUse('Food', [], splits);
      
      expect(result, false);
    });

    test('Category not in use when only referenced in splits - splits dont prevent deletion', () {
      final provider = CategoriesProvider();
      final splits = [
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      // Categories referenced in splits don't prevent deletion - they'll be removed automatically
      final result = provider.isCategoryInUse('Food', [], splits);
      
      expect(result, false);
    });

    test('Category not in use when split has "all" category', () {
      final provider = CategoriesProvider();
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final result = provider.isCategoryInUse('Food', [], splits);
      
      expect(result, false);
    });

    test('Category not in use when split uses different category', () {
      final provider = CategoriesProvider();
      final splits = [
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final result = provider.isCategoryInUse('Food', [], splits);
      
      expect(result, false);
    });

    test('Category matching is case-insensitive', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'FOOD'),
      ];
      
      final result = provider.isCategoryInUse('food', bills, []);
      
      expect(result, true);
    });

    test('Category with multiple bills - only matching one counts', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 200.0, paidBy: person1, category: 'Rent'),
      ];
      
      expect(provider.isCategoryInUse('Food', bills, []), true);
      expect(provider.isCategoryInUse('Rent', bills, []), true);
      expect(provider.isCategoryInUse('Utilities', bills, []), false);
    });

    test('Category with multiple splits - splits dont prevent deletion', () {
      final provider = CategoriesProvider();
      final splits = [
        PaymentSplit(
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      // Splits don't prevent deletion - all should return false
      expect(provider.isCategoryInUse('Food', [], splits), false);
      expect(provider.isCategoryInUse('Rent', [], splits), false);
      expect(provider.isCategoryInUse('Utilities', [], splits), false);
      expect(provider.isCategoryInUse('Entertainment', [], splits), false);
    });

    test('Category checked in bills only - splits dont prevent deletion', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];
      final splits = [
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      // Only bills prevent deletion - Food is in use (bill), Rent is not (only in split)
      expect(provider.isCategoryInUse('Food', bills, splits), true);
      expect(provider.isCategoryInUse('Rent', bills, splits), false);
      expect(provider.isCategoryInUse('Utilities', bills, splits), false);
    });

    test('Multiple categories - only bills prevent deletion', () {
      final provider = CategoriesProvider();
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 200.0, paidBy: person1, category: 'Food'),
      ];
      final splits = [
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      // Food is in use (via bills) - prevents deletion
      expect(provider.isCategoryInUse('Food', bills, splits), true);
      // Rent is NOT in use (only referenced in split, which doesn't prevent deletion)
      expect(provider.isCategoryInUse('Rent', bills, splits), false);
      // Utilities is NOT in use
      expect(provider.isCategoryInUse('Utilities', bills, splits), false);
      // Entertainment is NOT in use
      expect(provider.isCategoryInUse('Entertainment', bills, splits), false);
    });
  });

  group('CalculationService - Expected Amount Validation', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';
    final DateTime baseDate = DateTime(2024, 1, 15);
    
    List<Category> getCategories([List<String>? names]) {
      return (names ?? ['Food', 'Rent', 'Utilities', 'Entertainment'])
          .map((name) => Category(name: name))
          .toList();
    }

    test('Expected amounts cannot exceed total paid by both people', () {
      // Scenario: Third person pays a bill, but it should be ignored (not counted in paid or expected)
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: 'Charlie', category: 'Food'), // Third person pays - should be ignored
        Bill(date: baseDate, amount: 50.0, paidBy: person1, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      final totalPaid = result.person1Paid + result.person2Paid;
      final totalExpected = result.person1Expected + result.person2Expected;
      
      // Expected amounts should not exceed total paid
      // Third person's bill is ignored, so only person1's bill counts
      expect(totalExpected, lessThanOrEqualTo(totalPaid), 
        reason: 'Expected amounts ($totalExpected) should not exceed total paid ($totalPaid)');
      expect(totalExpected, closeTo(50.0, 0.01)); // 50% of 50 (only person1's bill)
      expect(totalPaid, closeTo(50.0, 0.01)); // Only person1 paid
    });

    test('Expected amounts match total paid when all bills are paid by person1 or person2', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      final totalPaid = result.person1Paid + result.person2Paid;
      final totalExpected = result.person1Expected + result.person2Expected;
      
      // When all bills are paid by person1 or person2, expected should equal total paid
      expect(totalExpected, closeTo(totalPaid, 0.01));
    });

    test('Expected amounts are capped at total paid when third person pays', () {
      // More complex scenario: mix of bills paid by different people
      // Third person's bill should be ignored entirely
      final bills = [
        Bill(date: baseDate, amount: 200.0, paidBy: 'ThirdPerson', category: 'Rent'), // Should be ignored
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Rent'),
        Bill(date: baseDate, amount: 50.0, paidBy: person2, category: 'Food'),
      ];
      
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
      ];
      
      final categories = getCategories();
      
      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: categories,
        person1Name: person1,
        person2Name: person2,
      );
      
      final totalPaid = result.person1Paid + result.person2Paid; // Only 100 + 50 = 150
      final totalExpected = result.person1Expected + result.person2Expected; // 60% + 40% of 150 = 150
      
      // Expected should equal total paid (150) because third person's bill is ignored
      expect(totalExpected, lessThanOrEqualTo(totalPaid),
        reason: 'Expected amounts should not exceed total paid');
      expect(totalExpected, closeTo(150.0, 0.01)); // 60% of 100 + 40% of 100 + 60% of 50 + 40% of 50 = 60 + 40 + 30 + 20 = 150
      expect(totalPaid, closeTo(150.0, 0.01)); // 100 + 50
    });
  });

  group('CalculationService - Reimbursements', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';
    final DateTime baseDate = DateTime(2024, 1, 15);

    List<Category> getCategories([List<String>? names]) {
      return (names ?? ['Food', 'Rent'])
          .map((name) => Category(name: name))
          .toList();
    }

    final splits = [
      PaymentSplit(
        category: 'all',
        person1: person1,
        person1Percentage: 50.0,
        person2: person2,
        person2Percentage: 50.0,
      ),
    ];

    test('a reimbursed bill reduces both paid and expected amounts, '
        'preserving the split ratio', () {
      final bills = [
        Bill(
          date: baseDate,
          amount: 100.0,
          paidBy: person1,
          category: 'Food',
          reimbursedAmount: 30.0,
        ),
      ];

      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: getCategories(),
        person1Name: person1,
        person2Name: person2,
      );

      // Net cost is 70, not the original 100.
      expect(result.person1Paid, 70.0);
      expect(result.person2Paid, 0.0);
      // Still split 50/50, just over the smaller net amount.
      expect(result.person1Expected, 35.0);
      expect(result.person2Expected, 35.0);

      final foodBalance = result.categoryBalances['Food']!;
      expect(foodBalance.person1Paid, 70.0);
      expect(foodBalance.person1Expected, 35.0);
      expect(foodBalance.person2Expected, 35.0);
    });

    test('a bill with no reimbursements behaves exactly as before '
        '(reimbursedAmount defaults to 0)', () {
      final bills = [
        Bill(date: baseDate, amount: 100.0, paidBy: person1, category: 'Food'),
      ];

      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: getCategories(),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.person1Paid, 100.0);
      expect(result.person1Expected, 50.0);
      expect(result.person2Expected, 50.0);
    });

    test('a fully reimbursed bill contributes nothing to paid or expected',
        () {
      final bills = [
        Bill(
          date: baseDate,
          amount: 100.0,
          paidBy: person1,
          category: 'Food',
          reimbursedAmount: 100.0,
        ),
      ];

      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: getCategories(),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.person1Paid, 0.0);
      expect(result.person1Expected, 0.0);
      expect(result.person2Expected, 0.0);
    });

    test('reimbursements exceeding the bill amount are allowed to go '
        'negative rather than clamp at zero', () {
      // Deliberately over-reimbursed (e.g. a race condition, or a manual DB
      // edit outside the app's own add-reimbursement validation, which
      // itself blocks this in the normal flow). netAmount is defined as a
      // plain subtraction with no floor, so this bill acts as a small
      // credit rather than being treated as free.
      final bills = [
        Bill(
          date: baseDate,
          amount: 100.0,
          paidBy: person1,
          category: 'Food',
          reimbursedAmount: 120.0,
        ),
      ];

      expect(bills.single.netAmount, -20.0);

      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: getCategories(),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.person1Paid, -20.0);
      expect(result.person1Expected, -10.0);
      expect(result.person2Expected, -10.0);
    });

    test('reimbursements on multiple bills across categories net out '
        'independently', () {
      final bills = [
        Bill(
          date: baseDate,
          amount: 200.0,
          paidBy: person1,
          category: 'Rent',
          reimbursedAmount: 50.0,
        ),
        Bill(
          date: baseDate,
          amount: 60.0,
          paidBy: person2,
          category: 'Food',
          reimbursedAmount: 10.0,
        ),
      ];

      final result = CalculationService.calculateBalances(
        bills: bills,
        splits: splits,
        categories: getCategories(),
        person1Name: person1,
        person2Name: person2,
      );

      expect(result.person1Paid, 150.0); // 200 - 50
      expect(result.person2Paid, 50.0); // 60 - 10
      expect(result.categoryBalances['Rent']!.person1Paid, 150.0);
      expect(result.categoryBalances['Food']!.person2Paid, 50.0);
    });
  });

  group('computeSplitPeriodsForCategory / findMatchingSplit / collectEndDates', () {
    const String person1 = 'Alice';
    const String person2 = 'Bob';

    test('No splits at all: single fully-open period', () {
      final periods = computeSplitPeriodsForCategory('Food', []);
      expect(periods.length, 1);
      expect(periods.single.start, isNull);
      expect(periods.single.end, isNull);
    });

    test('Only open-ended splits (no endDate on any of them): single fully-open period', () {
      final splits = [
        PaymentSplit(
          category: 'all',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      final periods = computeSplitPeriodsForCategory('Food', splits);
      expect(periods.length, 1);
      expect(periods.single.start, isNull);
      expect(periods.single.end, isNull);
    });

    test('collectEndDates dedupes the same endDate shared across categories', () {
      // Mirrors the "Complex scenario" test: Rent and Food splits both end
      // on 2024-02-29. Without dedupe this would produce a spurious
      // zero-width period around that shared boundary.
      final splits = [
        PaymentSplit(
          endDate: DateTime(2024, 2, 29),
          category: 'Rent',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          endDate: DateTime(2024, 2, 29),
          category: 'Food',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];

      final endDates = collectEndDates(splits);
      expect(endDates.toSet().length, 1);

      // Two periods for Rent (before/after the boundary), not three, and no
      // zero-width period sitting between duplicate boundary entries.
      final periods = computeSplitPeriodsForCategory('Rent', splits);
      expect(periods.length, 2);
    });

    test('Normal (non-ambiguous) boundary: category-specific splits on either '
        'side of a shared boundary produce two clean periods', () {
      final splits = [
        PaymentSplit(
          endDate: DateTime(2024, 1, 31),
          category: 'Rent',
          person1: person1,
          person1Percentage: 60.0,
          person2: person2,
          person2Percentage: 40.0,
        ),
        PaymentSplit(
          category: 'Rent',
          person1: person1,
          person1Percentage: 50.0,
          person2: person2,
          person2Percentage: 50.0,
        ),
      ];
      final allEndDates = collectEndDates(splits);
      final periods = computeSplitPeriodsForCategory('Rent', splits);

      expect(periods.length, 2);
      expect(periods[0].start, isNull);
      expect(periods[1].end, isNull);

      final firstMatch = findMatchingSplit(
        representativeDateFor(periods[0]),
        'Rent',
        splits,
        allEndDates,
      );
      final secondMatch = findMatchingSplit(
        representativeDateFor(periods[1]),
        'Rent',
        splits,
        allEndDates,
      );
      expect(firstMatch?.person1Percentage, 60.0);
      expect(secondMatch?.person1Percentage, 50.0);
    });

    test('Open-tail representative date is one day past the period start', () {
      const period = SplitPeriod(start: null, end: null);
      expect(representativeDateFor(period), DateTime.utc(1970));

      final bounded = SplitPeriod(start: DateTime(2024, 5, 1), end: null);
      expect(
        representativeDateFor(bounded),
        DateTime(2024, 5, 1).add(const Duration(days: 1)),
      );

      final closed = SplitPeriod(start: null, end: DateTime(2024, 5, 1));
      expect(representativeDateFor(closed), DateTime(2024, 5, 1));
    });

    // The single calendar day right after a split's endDate used to be
    // ambiguous under PaymentSplit.containsDate (both the closing split and
    // whatever followed it matched that day, with whichever came first in
    // splits list order silently winning - see payment_split.dart's
    // containsDate for the fix and why it mattered: it was capable of
    // attributing a real bill's expected share to the wrong split,
    // list-order permitting). Now that containsDate no longer has that
    // off-by-one, the day after a boundary belongs unambiguously to the
    // *next* split, regardless of list order - these tests guard against
    // that regressing.
    group('endDate+1 boundary day belongs to the next split', () {
      final splitA = PaymentSplit(
        endDate: DateTime(2024, 1, 31),
        category: 'all',
        person1: person1,
        person1Percentage: 60.0,
        person2: person2,
        person2Percentage: 40.0,
      );
      final splitB = PaymentSplit(
        endDate: DateTime(2024, 2, 28),
        category: 'all',
        person1: person1,
        person1Percentage: 50.0,
        person2: person2,
        person2Percentage: 50.0,
      );
      final dayAfterBoundary = DateTime(2024, 2, 1); // splitA.endDate + 1 day

      test('ascending list order [A, B]', () {
        final splits = [splitA, splitB];
        final allEndDates = collectEndDates(splits);
        final groundTruth =
            findMatchingSplit(dayAfterBoundary, 'Food', splits, allEndDates);

        expect(groundTruth?.person1Percentage, splitB.person1Percentage);

        final periods = computeSplitPeriodsForCategory('Food', splits);
        final containing = periods.firstWhere(
          (p) =>
              (p.start == null || dayAfterBoundary.isAfter(p.start!)) &&
              (p.end == null || !dayAfterBoundary.isAfter(p.end!)),
        );
        final periodMatch = findMatchingSplit(
          representativeDateFor(containing),
          'Food',
          splits,
          allEndDates,
        );

        expect(periodMatch?.person1Percentage, groundTruth?.person1Percentage);
      });

      test('descending list order [B, A]', () {
        final splits = [splitB, splitA];
        final allEndDates = collectEndDates(splits);
        final groundTruth =
            findMatchingSplit(dayAfterBoundary, 'Food', splits, allEndDates);

        expect(groundTruth?.person1Percentage, splitB.person1Percentage);

        final periods = computeSplitPeriodsForCategory('Food', splits);
        final containing = periods.firstWhere(
          (p) =>
              (p.start == null || dayAfterBoundary.isAfter(p.start!)) &&
              (p.end == null || !dayAfterBoundary.isAfter(p.end!)),
        );
        final periodMatch = findMatchingSplit(
          representativeDateFor(containing),
          'Food',
          splits,
          allEndDates,
        );

        expect(periodMatch?.person1Percentage, groundTruth?.person1Percentage);
      });

      test('the two orderings agree on the winner (no ambiguity left)', () {
        final ascendingMatch = findMatchingSplit(
          dayAfterBoundary,
          'Food',
          [splitA, splitB],
          collectEndDates([splitA, splitB]),
        );
        final descendingMatch = findMatchingSplit(
          dayAfterBoundary,
          'Food',
          [splitB, splitA],
          collectEndDates([splitB, splitA]),
        );
        expect(
          ascendingMatch?.person1Percentage,
          descendingMatch?.person1Percentage,
        );
      });

      test('the closing split itself no longer matches the day after its '
          'own endDate', () {
        final splits = [splitA, splitB];
        final allEndDates = collectEndDates(splits);
        expect(splitA.containsDate(dayAfterBoundary, allEndDates), false);
      });
    });
  });
}