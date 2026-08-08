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
import 'package:splitbalance/providers/calculation_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/payment_splits_provider.dart';
import 'package:splitbalance/screens/summary_screen.dart';
import 'package:splitbalance/services/aggregated_calculation_service.dart';

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
}
