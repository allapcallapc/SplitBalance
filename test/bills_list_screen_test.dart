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
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/pending_payments_provider.dart';
import 'package:splitbalance/screens/bills_list_screen.dart';

Future<void> pumpBillsListScreen(
  WidgetTester tester, {
  required BillsProvider billsProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
        ChangeNotifierProvider.value(value: billsProvider),
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
