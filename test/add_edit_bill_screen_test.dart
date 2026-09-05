// Widget-level coverage for AddEditBillScreen's duplicate-bill confirmation
// gate (GH issue #20): Save should go straight through when no bill shares
// the entered date+amount, and should block behind a confirmation dialog -
// respecting both "Cancel" and "Save Anyway" - when one does. Pushed via a
// real Navigator (like every production call site) so popping on a
// successful save is meaningful to assert on.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/duplicate_bills_provider.dart';
import 'package:splitbalance/screens/add_edit_bill_screen.dart';
import 'package:splitbalance/services/duplicate_bills_service.dart';

ConfigProvider signedInConfigProvider() => ConfigProvider.forTesting(
      isSignedIn: true,
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
    );

Future<CategoriesProvider> loadedCategoriesProvider(
    ConfigProvider configProvider) async {
  final provider = CategoriesProvider(
    fetchCategories: ({required householdId}) async => [
      {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
    ],
  );
  await provider.loadCategories(configProvider);
  return provider;
}

BillsProvider noOpBillsProvider({
  InsertBillRow? insertBillRow,
  UpdateBillRow? updateBillRow,
}) {
  return BillsProvider(
    insertBillRow: insertBillRow,
    updateBillRow: updateBillRow,
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
        [],
    fetchRecoveredBreakdown: ({required billIds}) async => {},
  );
}

// Pushes AddEditBillScreen via a real Navigator.push, from a placeholder
// "Open" button screen - matching every production call site, so a
// successful save's Navigator.pop(context, true) is meaningful to assert on
// instead of popping a route with nothing beneath it.
Future<void> pumpAndOpenAddEditBillScreen(
  WidgetTester tester, {
  required BillsProvider billsProvider,
  required ConfigProvider configProvider,
  required CategoriesProvider categoriesProvider,
  required DuplicateBillsProvider duplicateBillsProvider,
  Bill? bill,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider.value(value: categoriesProvider),
        ChangeNotifierProvider.value(value: billsProvider),
        ChangeNotifierProvider.value(value: duplicateBillsProvider),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddEditBillScreen(bill: bill),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> fillBillForm(WidgetTester tester, {required String amount}) async {
  await tester.enterText(find.byType(TextFormField).first, amount);

  // Paid by dropdown (first of the two DropdownButtonFormField<String>s).
  await tester.tap(find.byType(DropdownButtonFormField<String>).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Alice').last);
  await tester.pumpAndSettle();

  // Category dropdown (second one).
  await tester.tap(find.byType(DropdownButtonFormField<String>).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Groceries').last);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Save Bill'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('saves immediately and pops when no duplicate bill exists',
      (tester) async {
    Map<String, dynamic>? insertedData;
    final configProvider = signedInConfigProvider();
    final categoriesProvider = await loadedCategoriesProvider(configProvider);
    final billsProvider = noOpBillsProvider(
      insertBillRow: (data) async {
        insertedData = data;
        return {'id': 'new-bill', ...data};
      },
    );
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [],
      ),
    );

    await pumpAndOpenAddEditBillScreen(
      tester,
      billsProvider: billsProvider,
      configProvider: configProvider,
      categoriesProvider: categoriesProvider,
      duplicateBillsProvider: duplicateBillsProvider,
    );

    await fillBillForm(tester, amount: '25.00');

    expect(tester.takeException(), isNull);
    expect(find.text('Possible Duplicate Bill'), findsNothing);
    expect(insertedData, isNotNull);
    expect(insertedData!['amount'], 25.0);
    // The screen popped back to the placeholder "Open" button screen.
    expect(find.byType(AddEditBillScreen), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
      'blocks save behind a confirmation dialog when a duplicate exists, '
      'and Cancel keeps the bill unsaved', (tester) async {
    var insertCalled = false;
    final configProvider = signedInConfigProvider();
    final categoriesProvider = await loadedCategoriesProvider(configProvider);
    final billsProvider = noOpBillsProvider(
      insertBillRow: (data) async {
        insertCalled = true;
        return {'id': 'new-bill', ...data};
      },
    );
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [
              {
                'id': 'existing-bill',
                'date': DateTime.now().toIso8601String().split('T').first,
                'amount': 25.0,
                'paid_by': 'Bob',
                'category': 'Rent',
                'details': '',
              },
            ],
      ),
    );

    await pumpAndOpenAddEditBillScreen(
      tester,
      billsProvider: billsProvider,
      configProvider: configProvider,
      categoriesProvider: categoriesProvider,
      duplicateBillsProvider: duplicateBillsProvider,
    );

    await fillBillForm(tester, amount: '25.00');

    expect(tester.takeException(), isNull);
    expect(find.text('Possible Duplicate Bill'), findsOneWidget);
    // The conflicting bill's details are shown for the user to compare.
    expect(find.textContaining('Rent'), findsOneWidget);
    expect(find.textContaining('Bob'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(insertCalled, isFalse);
    expect(find.byType(AddEditBillScreen), findsOneWidget);
  });

  testWidgets('Save Anyway proceeds with the save after a duplicate warning',
      (tester) async {
    Map<String, dynamic>? insertedData;
    final configProvider = signedInConfigProvider();
    final categoriesProvider = await loadedCategoriesProvider(configProvider);
    final billsProvider = noOpBillsProvider(
      insertBillRow: (data) async {
        insertedData = data;
        return {'id': 'new-bill', ...data};
      },
    );
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [
              {
                'id': 'existing-bill',
                'date': DateTime.now().toIso8601String().split('T').first,
                'amount': 25.0,
                'paid_by': 'Bob',
                'category': 'Rent',
                'details': '',
              },
            ],
      ),
    );

    await pumpAndOpenAddEditBillScreen(
      tester,
      billsProvider: billsProvider,
      configProvider: configProvider,
      categoriesProvider: categoriesProvider,
      duplicateBillsProvider: duplicateBillsProvider,
    );

    await fillBillForm(tester, amount: '25.00');
    expect(find.text('Possible Duplicate Bill'), findsOneWidget);

    await tester.tap(find.text('Save Anyway'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(insertedData, isNotNull);
    expect(insertedData!['amount'], 25.0);
    expect(find.byType(AddEditBillScreen), findsNothing);
  });

  testWidgets(
      'editing an existing bill updates it by id, excluding itself from '
      'the duplicate check', (tester) async {
    String? updatedId;
    Map<String, dynamic>? updatedData;
    String? excludeIdSeen;
    final configProvider = signedInConfigProvider();
    final categoriesProvider = await loadedCategoriesProvider(configProvider);
    final billsProvider = noOpBillsProvider(
      updateBillRow: (id, data) async {
        updatedId = id;
        updatedData = data;
        return {'id': id, ...data};
      },
    );
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async {
          excludeIdSeen = excludeId;
          return [];
        },
      ),
    );
    final existingBill = Bill(
      id: 'bill-being-edited',
      date: DateTime(2026, 1, 1),
      amount: 20.0,
      paidBy: 'Bob',
      category: 'Groceries',
    );

    await pumpAndOpenAddEditBillScreen(
      tester,
      billsProvider: billsProvider,
      configProvider: configProvider,
      categoriesProvider: categoriesProvider,
      duplicateBillsProvider: duplicateBillsProvider,
      bill: existingBill,
    );

    expect(find.text('Edit Bill'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '30.00');
    await tester.tap(find.text('Save Bill'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(excludeIdSeen, 'bill-being-edited');
    expect(updatedId, 'bill-being-edited');
    expect(updatedData, isNotNull);
    expect(updatedData!['amount'], 30.0);
    expect(find.byType(AddEditBillScreen), findsNothing);
  });
}
