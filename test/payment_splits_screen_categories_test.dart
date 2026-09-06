// Widget-level coverage for the Categories tab's "in use (cannot delete)"
// flag in PaymentSplitsScreen (lib/screens/payment_splits_screen.dart). The
// flag is driven by BillsProvider.categoryNamesInUse, populated by
// loadCategoriesInUse() - a lightweight query over just the `category`
// column rather than every full bill row (see BillsProvider.loadAllBills) -
// so a category with a bill anywhere in the household shows as in use even
// when the Bills tab (the only other screen that used to populate this
// state) was never visited this session.
//
// Same not-signed-in setup limitation noted in test/category_icon_picker_test.dart
// doesn't apply here: ConfigProvider.forTesting lets this file drive the
// signed-in path without a real Supabase session, and CategoriesProvider/
// BillsProvider's own fetch injection points keep the rest of the screen
// off the network too.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/payment_splits_provider.dart';
import 'package:splitbalance/screens/payment_splits_screen.dart';

Future<void> pumpCategoriesTab(
  WidgetTester tester, {
  required ConfigProvider configProvider,
  required CategoriesProvider categoriesProvider,
  required BillsProvider billsProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider.value(value: categoriesProvider),
        ChangeNotifierProvider.value(value: billsProvider),
        ChangeNotifierProvider(create: (_) => PaymentSplitsProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: PaymentSplitsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // AppBar title and the tab label are both literally "Categories" (see
  // splitsAndCategories in app_en.arb), so target the Tab specifically.
  await tester.tap(find.widgetWithText(Tab, 'Categories'));
  await tester.pumpAndSettle();
}

ConfigProvider signedInConfigProvider() => ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserEmail: 'alice@example.com',
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
      memberNamesByUserId: const {'user-1': 'Alice', 'user-2': 'Bob'},
    );

void main() {
  setUpAll(() async {
    // ConfigProvider/PaymentSplitsProvider talk to Supabase.instance.client
    // as soon as the screen builds, so a client must exist first - same
    // setup as test/category_icon_picker_test.dart.
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
      'a category with a bill anywhere in the household shows "in use", '
      'even though this screen never loads BillsProvider.allBills',
      (tester) async {
    final categoriesProvider = CategoriesProvider(
      fetchCategories: ({required householdId}) async => const [
        {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
        {'id': 'cat-2', 'name': 'Rent', 'icon': null},
      ],
    );
    final billsProvider = BillsProvider(
      // Deliberately lowercase, unlike the "Groceries" category name above -
      // isCategoryInUse matches case-insensitively.
      fetchCategoriesInUse: ({required householdId}) async => {'groceries'},
    );

    await pumpCategoriesTab(
      tester,
      configProvider: signedInConfigProvider(),
      categoriesProvider: categoriesProvider,
      billsProvider: billsProvider,
    );

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    // Only Groceries is in categoryNamesInUse, so only its card shows the
    // flag - Rent's card has no subtitle at all.
    expect(find.text('In use (cannot delete)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(Card, 'Rent'),
        matching: find.text('In use (cannot delete)'),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'a category with no bills shows no "in use" flag and can be deleted',
      (tester) async {
    final categoriesProvider = CategoriesProvider(
      fetchCategories: ({required householdId}) async => const [
        {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
      ],
    );
    final billsProvider = BillsProvider(
      fetchCategoriesInUse: ({required householdId}) async => {},
    );

    await pumpCategoriesTab(
      tester,
      configProvider: signedInConfigProvider(),
      categoriesProvider: categoriesProvider,
      billsProvider: billsProvider,
    );

    expect(find.text('In use (cannot delete)'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton));
    await tester.pumpAndSettle();

    final deleteItem = tester.widget<PopupMenuItem>(
      find.ancestor(
        of: find.text('Delete'),
        matching: find.byType(PopupMenuItem),
      ),
    );
    expect(deleteItem.enabled, true);
  });
}
