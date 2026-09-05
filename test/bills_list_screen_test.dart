// Widget-level coverage for BillsListScreen's empty states, added for GH
// issue #56: "No bills yet" used to be shown even when bills exist but none
// match the active filters, which reads as untrue. hasActiveFilters now
// picks a distinct noBillsMatchFilters string instead.
//
// ConfigProvider talks directly to Supabase.instance.client with no DI seam
// (same limitation documented in test/summary_screen_test.dart), so these
// exercise the not-signed-in path: BillsProvider.loadBills is a no-op there,
// so `bills` stays exactly whatever state is seeded on the provider before
// pumping - which is enough to drive both empty-state branches, since they
// only depend on `bills.isEmpty` and `hasActiveFilters`.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/l10n/app_localizations_fr.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/pending_payments_provider.dart';
import 'package:splitbalance/providers/recovered_amounts_provider.dart';
import 'package:splitbalance/screens/bill_recovered_amounts_screen.dart';
import 'package:splitbalance/screens/bills_list_screen.dart';

Future<void> pumpBillsListScreen(
  WidgetTester tester, {
  required BillsProvider billsProvider,
  ConfigProvider? configProvider,
  CategoriesProvider? categoriesProvider,
  RecoveredAmountsProvider? recoveredAmountsProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider ?? ConfigProvider()),
        ChangeNotifierProvider.value(
            value: categoriesProvider ?? CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
        ChangeNotifierProvider.value(value: billsProvider),
        ChangeNotifierProvider.value(
            value: recoveredAmountsProvider ?? RecoveredAmountsProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: BillsListScreen(),
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
      'shows "No bills yet" and an add-first-bill button when there are no '
      'bills and no filters are active', (tester) async {
    await pumpBillsListScreen(tester, billsProvider: BillsProvider());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No bills yet'), findsOneWidget);
    expect(find.text('Add Your First Bill'), findsOneWidget);
    expect(find.text('No bills match your filters'), findsNothing);
  });

  testWidgets(
      'shows "No bills match your filters" instead of "No bills yet" when a '
      'filter is active but excludes every bill (GH issue #56)',
      (tester) async {
    final billsProvider = BillsProvider();
    // setPaidByFilter records the filter immediately and only attempts a
    // reload if signed in, so this sets hasActiveFilters without needing a
    // real Supabase session.
    await billsProvider.setPaidByFilter('Bob', ConfigProvider());
    expect(billsProvider.hasActiveFilters, isTrue);
    expect(billsProvider.bills, isEmpty);

    await pumpBillsListScreen(tester, billsProvider: billsProvider);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No bills match your filters'), findsOneWidget);
    expect(find.text('No bills yet'), findsNothing);
    expect(find.text('Add Your First Bill'), findsNothing);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  group('BillsListScreen - signed in with bills', () {
    ConfigProvider signedInConfigProvider() => ConfigProvider.forTesting(
          isSignedIn: true,
          config: AppConfig(
            householdId: 'household-1',
            person1Name: 'Alice',
            person2Name: 'Bob',
          ),
        );

    Map<String, dynamic> billRow(
      String id,
      String date, {
      double amount = 100.0,
      String paidBy = 'Alice',
      String category = 'Food',
    }) {
      return {
        'id': id,
        'date': date,
        'amount': amount,
        'paid_by': paidBy,
        'category': category,
        'details': '',
      };
    }

    testWidgets(
        'shows a plain amount for an unrecovered bill and a struck-through '
        'original next to the net amount for one with a recovered amount',
        (tester) async {
      final billsProvider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [
              billRow('plain', '2026-01-01', amount: 50.0),
              billRow('recovered', '2026-01-02', amount: 100.0),
            ],
        fetchRecoveredTotals: ({required billIds}) async =>
            {'recovered': 30.0},
      );

      await pumpBillsListScreen(
        tester,
        billsProvider: billsProvider,
        configProvider: signedInConfigProvider(),
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Amount: \$50.00'), findsOneWidget);
      expect(find.text('\$100.00'), findsOneWidget); // struck-through original
      expect(find.text('\$70.00'), findsOneWidget); // net after recovery
    });

    testWidgets(
        'tapping "Recovered Amounts" on a bill opens '
        'BillRecoveredAmountsScreen', (tester) async {
      final billsProvider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [billRow('bill-1', '2026-01-01', amount: 80.0)],
        fetchRecoveredTotals: ({required billIds}) async => {},
      );

      await pumpBillsListScreen(
        tester,
        billsProvider: billsProvider,
        configProvider: signedInConfigProvider(),
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
        recoveredAmountsProvider: RecoveredAmountsProvider(
          fetchRecoveredAmountsForBill: ({required billId}) async => [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recovered Amounts'));
      // The menu item's onTap fires after a 100ms Future.delayed.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BillRecoveredAmountsScreen), findsOneWidget);
      expect(find.text('Original amount'), findsOneWidget);
      expect(find.text('\$80.00'), findsWidgets);

      // Navigating back lets Navigator.push's returned Future resolve,
      // reaching the post-push `await _loadData()` call - otherwise that
      // line never runs, since push() only completes once its route pops.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BillRecoveredAmountsScreen), findsNothing);
      // Recovered amounts are added/deleted through RecoveredAmountsProvider,
      // which BillsProvider has no way to observe - returning here must
      // force a fresh loadAllBills() (loadAllBills has no injection seam of
      // its own, so hasLoadedAllBillsForHousehold flipping true, which its
      // finally block sets unconditionally, is the only observable signal
      // it ran) rather than leaving BillsProvider.allBills - and therefore
      // the Summary screen's monthly/cumulative spend charts - stuck with
      // whatever recovered totals were cached before this screen opened.
      expect(billsProvider.hasLoadedAllBillsForHousehold('household-1'),
          isTrue);
    });
  });

  test(
      'AppLocalizationsFr provides a French noBillsMatchFilters translation '
      '(no widget test exercises the fr locale, so this covers the getter '
      'directly)', () {
    expect(
      AppLocalizationsFr().noBillsMatchFilters,
      'Aucune facture ne correspond à vos filtres',
    );
  });
}
