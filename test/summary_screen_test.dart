// Minimal widget-level check for SummaryScreen after switching it to
// CalculationProvider.calculateAggregatedBalances: confirms the loading and
// result states still render correctly against the new BalanceResult path.
// Not a full visual regression suite - ConfigProvider talks directly to
// Supabase.instance.client with no DI seam (see lib/providers/config_provider.dart),
// so a real signed-in-with-household state can't be faked here; the
// "not signed in" empty state is exercised end-to-end instead, and the
// result-rendering states are exercised by driving CalculationProvider's
// state directly (same DI-of-fetch-functions pattern used everywhere else
// in this repo's tests).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/models/category.dart';
import 'package:splitbalance/models/payment_split.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/calculation_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/payment_splits_provider.dart';
import 'package:splitbalance/screens/category_detail_screen.dart';
import 'package:splitbalance/screens/summary_screen.dart';
import 'package:splitbalance/screens/total_detail_screen.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';
import 'package:splitbalance/services/calculation_service.dart';

Future<void> pumpSummaryScreen(
  WidgetTester tester, {
  required CalculationProvider calculationProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => PaymentSplitsProvider()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => BillsProvider()),
        ChangeNotifierProvider.value(value: calculationProvider),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: SummaryScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    // ConfigProvider talks to Supabase.instance.client as soon as it's
    // constructed, so a client must exist before pumping the widget tree -
    // same setup as test/widget_test.dart.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
      'not signed in: settles on the empty state without throwing (no '
      'BillsProvider/loadAllBills involved anymore)', (tester) async {
    await pumpSummaryScreen(
      tester,
      calculationProvider: CalculationProvider(
        aggregatedCalculationService: AggregatedCalculationService(),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No balance calculated'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while isCalculating', (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(),
    );

    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    // Let the initial (not-signed-in) _calculateBalances() postFrameCallback
    // run to completion and settle on the empty state first, so it can't
    // clobber the isCalculating flip below.
    await tester.pumpAndSettle();

    calculationProvider.setCalculating(true);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
      'renders ledger rows from a BalanceResult produced by '
      'calculateAggregatedBalances', (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            paidBy == 'Alice' ? 120.0 : 80.0,
        fetchPersonBillCount: ({required householdId, required paidBy}) async =>
            paidBy == 'Alice' ? 3 : 1,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
        fetchHouseholdTotals: ({required householdId}) async =>
            const HouseholdTotals(billCount: 5, totalAmount: 999.99),
      ),
    );

    // Populate the provider directly (bypassing the screen's own
    // _calculateBalances, which needs a signed-in ConfigProvider we can't
    // fake here) - same end result the screen would reach once wired up.
    final future = calculationProvider.calculateAggregatedBalances(
      householdId: 'household-1',
      categories: const [],
      person1Name: 'Alice',
      person2Name: 'Bob',
    );
    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    await tester.pump();
    await future;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calculationProvider.balanceResult, isNotNull);
    expect(calculationProvider.balanceResult!.person1Paid, 120.0);
    // Total row reflects the aggregated result's paid totals.
    expect(find.text('\$120.00'), findsOneWidget);
    expect(find.text('\$80.00'), findsOneWidget);
    // Household stats now come from calculationProvider.householdTotals,
    // not a BillsProvider that no longer exists on this screen.
    expect(find.text('5'), findsOneWidget);
    expect(find.text('\$999.99'), findsOneWidget);
    // Expenses Added section reflects the aggregated per-person counts.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
      'ledger rows show a trailing chevron and navigate without throwing '
      'when BillsProvider has no data loaded', (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            paidBy == 'Alice' ? 120.0 : 80.0,
        fetchPersonBillCount: ({required householdId, required paidBy}) async =>
            0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
        fetchHouseholdTotals: ({required householdId}) async =>
            const HouseholdTotals(billCount: 0, totalAmount: 0),
      ),
    );

    final future = calculationProvider.calculateAggregatedBalances(
      householdId: 'household-1',
      categories: const [],
      person1Name: 'Alice',
      person2Name: 'Bob',
    );
    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    await tester.pump();
    await future;
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(find.text('Total').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TotalDetailScreen), findsOneWidget);
    // Not signed in, so BillsProvider.loadAllBills is a no-op and the charts
    // fall back to their empty state instead of throwing.
    expect(find.text('No bills to chart yet'), findsOneWidget);
  });

  testWidgets(
      'tapping the Total row pushes TotalDetailScreen with a ranked category '
      'breakdown', (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(
        fetchSplits: ({required householdId}) async => [],
        fetchPersonPaidTotal: ({required householdId, required paidBy}) async =>
            paidBy == 'Alice' ? 120.0 : 80.0,
        fetchPersonBillCount: ({required householdId, required paidBy}) async =>
            0,
        fetchCategoryPeriodPersonPaid: ({
          required householdId,
          required category,
          required periodStart,
          required periodEnd,
          required paidBy,
        }) async =>
            0.0,
        fetchHouseholdTotals: ({required householdId}) async =>
            const HouseholdTotals(billCount: 0, totalAmount: 0),
      ),
    );

    final future = calculationProvider.calculateAggregatedBalances(
      householdId: 'household-1',
      categories: const [],
      person1Name: 'Alice',
      person2Name: 'Bob',
    );
    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    await tester.pump();
    await future;
    await tester.pumpAndSettle();

    await tester.tap(find.text('Total').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TotalDetailScreen), findsOneWidget);
    expect(find.text('Current Period'), findsOneWidget);

    // Navigate back and confirm SummaryScreen is still intact underneath.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);
  });

  testWidgets(
      'tapping a category ledger row (via ranked breakdown) pushes '
      'CategoryDetailScreen for that category', (tester) async {
    // categoryBalances isn't reachable from SummaryScreen's public API in
    // this DI setup without real per-category fetch data, so this exercises
    // the same InkWell/Navigator.push wiring one level down: from
    // TotalDetailScreen's ranked breakdown into CategoryDetailScreen. Both
    // ledger rows and ranked-breakdown rows share the identical
    // Navigator.push(MaterialPageRoute(...)) pattern.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ConfigProvider()),
          ChangeNotifierProvider(create: (_) => CategoriesProvider()),
          ChangeNotifierProvider(create: (_) => BillsProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: TotalDetailScreen(
            person1Name: 'Alice',
            person2Name: 'Bob',
            person1Paid: 120.0,
            person1Expected: 100.0,
            person2Paid: 80.0,
            person2Expected: 100.0,
            categoryBalances: {
              'Food': CategoryBalance(
                category: 'Food',
                person1Paid: 70.0,
                person2Paid: 30.0,
                person1Expected: 50.0,
                person2Expected: 50.0,
              ),
              'Rent': CategoryBalance(
                category: 'Rent',
                person1Paid: 50.0,
                person2Paid: 50.0,
                person1Expected: 50.0,
                person2Expected: 50.0,
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Ranked by amount descending: Food ($100) before Rent ($100 too, but
    // this just confirms both rows render) - assert both are present.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryDetailScreen), findsOneWidget);
    expect(find.text('No bills in this category yet'), findsOneWidget);
  });

  testWidgets(
      'Net Balance card shows the balanced state when paid matches expected '
      'share (exercises the balanced/green branch of the card color)',
      (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(),
    );

    // Alice and Bob each paid half of a category split 50/50, so person1's
    // expected share (50) equals what they actually paid (50) - netBalance
    // lands exactly on 0.
    final future = calculationProvider.calculateBalances(
      bills: [
        Bill(
          date: DateTime(2026, 1, 1),
          amount: 50,
          paidBy: 'Alice',
          category: 'Groceries',
        ),
        Bill(
          date: DateTime(2026, 1, 1),
          amount: 50,
          paidBy: 'Bob',
          category: 'Groceries',
        ),
      ],
      splits: [
        PaymentSplit(
          category: 'all',
          person1: 'Alice',
          person1Percentage: 50,
          person2: 'Bob',
          person2Percentage: 50,
        ),
      ],
      categories: [Category(name: 'Groceries')],
      person1Name: 'Alice',
      person2Name: 'Bob',
    );
    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    await tester.pump();
    await future;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calculationProvider.balanceResult!.netBalance, closeTo(0.0, 0.01));
    expect(find.text('All Balanced!'), findsOneWidget);
  });

  testWidgets(
      'Net Balance card shows the "owes" state when person1 paid less than '
      'their expected share (exercises the positive/blue branch of the '
      'card color)', (tester) async {
    final calculationProvider = CalculationProvider(
      aggregatedCalculationService: AggregatedCalculationService(),
    );

    // Total spend of 100 split 50/50 means each expects to have paid 50;
    // Alice only paid 30, so she still owes Bob the remaining 20.
    final future = calculationProvider.calculateBalances(
      bills: [
        Bill(
          date: DateTime(2026, 1, 1),
          amount: 30,
          paidBy: 'Alice',
          category: 'Groceries',
        ),
        Bill(
          date: DateTime(2026, 1, 1),
          amount: 70,
          paidBy: 'Bob',
          category: 'Groceries',
        ),
      ],
      splits: [
        PaymentSplit(
          category: 'all',
          person1: 'Alice',
          person1Percentage: 50,
          person2: 'Bob',
          person2Percentage: 50,
        ),
      ],
      categories: [Category(name: 'Groceries')],
      person1Name: 'Alice',
      person2Name: 'Bob',
    );
    await pumpSummaryScreen(tester, calculationProvider: calculationProvider);
    await tester.pump();
    await future;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calculationProvider.balanceResult!.netBalance, greaterThan(0));
    expect(find.text('Alice owes Bob \$20.00'), findsOneWidget);
  });
}
