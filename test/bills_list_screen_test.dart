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
import 'package:splitbalance/providers/duplicate_bills_provider.dart';
import 'package:splitbalance/providers/pending_payments_provider.dart';
import 'package:splitbalance/providers/recovered_amounts_provider.dart';
import 'package:splitbalance/screens/bill_recovered_amounts_screen.dart';
import 'package:splitbalance/screens/bills_list_screen.dart';
import 'package:splitbalance/screens/duplicate_bills_screen.dart';
import 'package:splitbalance/services/duplicate_bills_service.dart';

Future<void> pumpBillsListScreen(
  WidgetTester tester, {
  required BillsProvider billsProvider,
  ConfigProvider? configProvider,
  CategoriesProvider? categoriesProvider,
  RecoveredAmountsProvider? recoveredAmountsProvider,
  DuplicateBillsProvider? duplicateBillsProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider ?? ConfigProvider()),
        ChangeNotifierProvider.value(
            value: categoriesProvider ?? CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
        ChangeNotifierProvider.value(
            value: duplicateBillsProvider ?? DuplicateBillsProvider()),
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

  testWidgets(
      'the filter modal shows the active date range and clearing it resets '
      'the filter', (tester) async {
    // Signed in (unlike the two tests above): clearing the filter here
    // happens interactively, via a tap, after the screen has already been
    // pumped - that goes through loadBills(), which only notifyListeners()
    // (and thus rebuilds the modal) when signed in with a household. The
    // GH issue #56 tests above only need the filter reflected in the
    // *initial* build, so they can get away with an unsigned-in provider.
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      config: AppConfig(
          householdId: 'household-1',
          person1Name: 'Alice',
          person2Name: 'Bob'),
    );
    final billsProvider = BillsProvider(
      fetchBillsPage: ({
        required String householdId,
        String? paidBy,
        String? category,
        DateTime? startDate,
        DateTime? endDate,
        required BillSortField sortField,
        required bool sortAscending,
        required int offset,
        required int limit,
      }) async =>
          const [],
      fetchRecoveredBreakdown: ({required billIds}) async => {},
    );
    await billsProvider.setDateRangeFilter(
        DateTime(2026, 1, 1), DateTime(2026, 1, 31), configProvider);
    expect(billsProvider.hasActiveFilters, isTrue);

    await pumpBillsListScreen(
      tester,
      billsProvider: billsProvider,
      configProvider: configProvider,
      categoriesProvider: CategoriesProvider(
          fetchCategories: ({required householdId}) async => []),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2026-01-01 – 2026-01-31'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(billsProvider.filterStartDate, isNull);
    expect(billsProvider.filterEndDate, isNull);
    expect(find.text('Any date'), findsOneWidget);
  });

  testWidgets(
      'the filter modal shows a single formatted date, not a range, when '
      'the date filter is an exact-date search (same start and end)',
      (tester) async {
    final billsProvider = BillsProvider();
    final exactDate = DateTime(2026, 1, 15);
    await billsProvider.setDateRangeFilter(
        exactDate, exactDate, ConfigProvider());

    await pumpBillsListScreen(tester, billsProvider: billsProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2026-01-15'), findsOneWidget);
    expect(find.text('2026-01-15 – 2026-01-15'), findsNothing);
  });

  testWidgets(
      'the filter modal shows just the one bound when only the start or '
      'end of the date range is set', (tester) async {
    final billsProvider = BillsProvider();
    await billsProvider.setDateRangeFilter(
        DateTime(2026, 2, 1), null, ConfigProvider());

    await pumpBillsListScreen(tester, billsProvider: billsProvider);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2026-02-01'), findsOneWidget);
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
          DateTime? startDate,
          DateTime? endDate,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [
              billRow('plain', '2026-01-01', amount: 50.0),
              billRow('recovered', '2026-01-02', amount: 100.0),
            ],
        fetchRecoveredBreakdown: ({required billIds}) async => {
          'recovered': {'Alice': 30.0},
        },
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
          DateTime? startDate,
          DateTime? endDate,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            [billRow('bill-1', '2026-01-01', amount: 80.0)],
        fetchRecoveredBreakdown: ({required billIds}) async => {},
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

    testWidgets(
        'shows no duplicate-bills banner when there are no potential '
        'duplicates', (tester) async {
      final duplicateBillsProvider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async => [],
        ),
      );

      await pumpBillsListScreen(
        tester,
        billsProvider: BillsProvider(
          fetchBillsPage: ({
            required String householdId,
            String? paidBy,
            String? category,
            DateTime? startDate,
            DateTime? endDate,
            required BillSortField sortField,
            required bool sortAscending,
            required int offset,
            required int limit,
          }) async =>
              const [],
          fetchRecoveredBreakdown: ({required billIds}) async => {},
        ),
        configProvider: signedInConfigProvider(),
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
        duplicateBillsProvider: duplicateBillsProvider,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets(
        'shows a duplicate-bills banner with the count, and "Review" opens '
        'DuplicateBillsScreen', (tester) async {
      final duplicateBillsProvider = DuplicateBillsProvider(
        service: DuplicateBillsService(
          fetchHouseholdBillRows: ({required householdId}) async => [
            billRow('bill-1', '2026-01-01', amount: 40.0),
            billRow('bill-2', '2026-01-01', amount: 40.0),
          ],
        ),
      );

      await pumpBillsListScreen(
        tester,
        billsProvider: BillsProvider(
          fetchBillsPage: ({
            required String householdId,
            String? paidBy,
            String? category,
            DateTime? startDate,
            DateTime? endDate,
            required BillSortField sortField,
            required bool sortAscending,
            required int offset,
            required int limit,
          }) async =>
              const [],
          fetchRecoveredBreakdown: ({required billIds}) async => {},
        ),
        configProvider: signedInConfigProvider(),
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
        duplicateBillsProvider: duplicateBillsProvider,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2 potential duplicate bill(s) found'),
          findsOneWidget);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DuplicateBillsScreen), findsOneWidget);
    });

    testWidgets(
        'tapping the date range field opens the picker, and confirming the '
        'suggested range (today, when no filter is active yet) applies it',
        (tester) async {
      final billsProvider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          DateTime? startDate,
          DateTime? endDate,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            const [],
        fetchRecoveredBreakdown: ({required billIds}) async => {},
      );
      expect(billsProvider.hasActiveFilters, isFalse);

      await pumpBillsListScreen(
        tester,
        billsProvider: billsProvider,
        configProvider: signedInConfigProvider(),
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // No filter active yet, so the field shows the "any date" placeholder
      // and a calendar icon rather than a clear button.
      expect(find.text('Any date'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);

      // Tapping anywhere in the field's InputDecorator (the calendar icon
      // included, since a plain Icon doesn't absorb the tap) hits the
      // InkWell wrapping it and opens showDateRangePicker.
      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // With no active filter, _pickDateRange seeds the picker with
      // today for both ends of the range - confirm that suggestion as-is,
      // without picking a different day, by tapping the dialog's "Save"
      // action (matched case-insensitively: Flutter's Material
      // localizations capitalize it as "Save").
      final saveButton = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data?.toLowerCase() == 'save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(billsProvider.filterStartDate, isNotNull);
      expect(billsProvider.filterStartDate!.year, today.year);
      expect(billsProvider.filterStartDate!.month, today.month);
      expect(billsProvider.filterStartDate!.day, today.day);
      // Same day for both ends (an exact-date search), since the dialog was
      // confirmed without changing the suggested range.
      expect(billsProvider.filterEndDate, billsProvider.filterStartDate);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tapping the date range field while a filter is already active '
        'seeds the picker with that range, and confirming it as-is keeps '
        'the filter unchanged', (tester) async {
      final configProvider = signedInConfigProvider();
      final billsProvider = BillsProvider(
        fetchBillsPage: ({
          required String householdId,
          String? paidBy,
          String? category,
          DateTime? startDate,
          DateTime? endDate,
          required BillSortField sortField,
          required bool sortAscending,
          required int offset,
          required int limit,
        }) async =>
            const [],
        fetchRecoveredBreakdown: ({required billIds}) async => {},
      );
      final activeDate = DateTime(2026, 1, 15);
      await billsProvider.setDateRangeFilter(
          activeDate, activeDate, configProvider);

      await pumpBillsListScreen(
        tester,
        billsProvider: billsProvider,
        configProvider: configProvider,
        categoriesProvider: CategoriesProvider(
            fetchCategories: ({required householdId}) async => []),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // A filter is already active, so the field shows the formatted date
      // (not the "Any date" placeholder) and a clear button rather than a
      // calendar icon - tap the date text itself to open the picker, since
      // that still lands inside the InkWell wrapping the whole field.
      expect(find.text('2026-01-15'), findsOneWidget);
      await tester.tap(find.text('2026-01-15'));
      await tester.pumpAndSettle();

      // _pickDateRange seeds the picker from the already-active filter in
      // this case (rather than today) - confirm that suggestion as-is.
      final saveButton = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data?.toLowerCase() == 'save');
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(billsProvider.filterStartDate, activeDate);
      expect(billsProvider.filterEndDate, activeDate);
      expect(tester.takeException(), isNull);
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

  test(
      'AppLocalizationsFr provides French translations for the date-range '
      'filter (no widget test exercises the fr locale, so this covers the '
      'getters directly)', () {
    expect(AppLocalizationsFr().filterByDateRange, 'Plage de dates');
    expect(AppLocalizationsFr().anyDate, 'Toutes les dates');
  });
}
