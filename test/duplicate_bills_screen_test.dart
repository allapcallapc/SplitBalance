// Widget-level coverage for DuplicateBillsScreen (GH issue #20): the empty
// state, rendering a duplicate group's bills side by side, and the
// edit/delete actions on each bill card.

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
import 'package:splitbalance/providers/duplicate_bills_provider.dart';
import 'package:splitbalance/screens/add_edit_bill_screen.dart';
import 'package:splitbalance/screens/duplicate_bills_screen.dart';
import 'package:splitbalance/services/duplicate_bills_service.dart';

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
  double amount = 10.0,
  String paidBy = 'Alice',
  String category = 'Groceries',
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

Future<void> pumpDuplicateBillsScreen(
  WidgetTester tester, {
  required ConfigProvider configProvider,
  required DuplicateBillsProvider duplicateBillsProvider,
  BillsProvider? billsProvider,
  CategoriesProvider? categoriesProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider.value(value: duplicateBillsProvider),
        ChangeNotifierProvider.value(value: billsProvider ?? BillsProvider()),
        ChangeNotifierProvider.value(
            value: categoriesProvider ?? CategoriesProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: DuplicateBillsScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('shows the empty state when there are no duplicate groups',
      (tester) async {
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [],
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No duplicate bills found'), findsOneWidget);
  });

  testWidgets(
      'shows a duplicate group with its bills side by side (date, amount, '
      'category, paid by)', (tester) async {
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01',
              amount: 50.0, paidBy: 'Alice', category: 'Rent'),
          billRow('bill-2', '2026-01-01',
              amount: 50.0, paidBy: 'Bob', category: 'Utilities'),
        ],
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No duplicate bills found'), findsNothing);
    expect(find.textContaining('\$50.00'), findsOneWidget);
    expect(find.text('Paid by: Alice'), findsOneWidget);
    expect(find.text('Paid by: Bob'), findsOneWidget);
    expect(find.text('Category: Rent'), findsOneWidget);
    expect(find.text('Category: Utilities'), findsOneWidget);
  });

  testWidgets('tapping edit on a bill opens AddEditBillScreen', (tester) async {
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01', amount: 50.0),
          billRow('bill-2', '2026-01-01', amount: 50.0),
        ],
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
      categoriesProvider:
          CategoriesProvider(fetchCategories: ({required householdId}) async => []),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AddEditBillScreen), findsOneWidget);
  });

  testWidgets(
      'tapping delete on a bill shows a confirmation, and confirming deletes '
      'it by id', (tester) async {
    String? deletedId;
    final billsProvider = BillsProvider(
      deleteBillRow: (id) async => deletedId = id,
    );
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01', amount: 50.0),
          billRow('bill-2', '2026-01-01', amount: 50.0),
        ],
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
      billsProvider: billsProvider,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();

    expect(find.text('Delete Bill'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(deletedId, 'bill-1');
  });
}
