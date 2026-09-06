// Widget-level coverage for DuplicateBillsScreen (GH issue #20): the empty
// state, rendering a duplicate group's bills side by side, and the
// edit/delete actions on each bill card.

import 'dart:async';

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
  String details = '',
}) {
  return {
    'id': id,
    'date': date,
    'amount': amount,
    'paid_by': paidBy,
    'category': category,
    'details': details,
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

  testWidgets('shows a loading spinner while duplicate detection is in '
      'flight', (tester) async {
    final completer = Completer<List<Map<String, dynamic>>>();
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) => completer.future,
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
    );
    // A single pump (not pumpAndSettle) lets initState's postFrameCallback
    // kick off the load without waiting for completer.future to resolve.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'shows a duplicate group with its bills side by side (date, amount, '
      'category, paid by)', (tester) async {
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async => [
          billRow('bill-1', '2026-01-01',
              amount: 50.0,
              paidBy: 'Alice',
              category: 'Rent',
              details: 'January rent'),
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
    // Bill-1's non-empty details render as an extra line on its card.
    expect(find.text('January rent'), findsOneWidget);
  });

  testWidgets(
      'tapping edit on a bill opens AddEditBillScreen, and saving it reloads '
      'duplicate detection', (tester) async {
    var duplicatesFetchCount = 0;
    final billsProvider = BillsProvider(
      updateBillRow: (id, data) async => {'id': id, ...data},
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
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async {
          duplicatesFetchCount++;
          return [
            billRow('bill-1', '2026-01-01', amount: 50.0),
            billRow('bill-2', '2026-01-01', amount: 50.0),
          ];
        },
        fetchMatchingBillRows: ({
          required householdId,
          required date,
          required amount,
          excludeId,
        }) async =>
            [],
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
      billsProvider: billsProvider,
      categoriesProvider:
          CategoriesProvider(fetchCategories: ({required householdId}) async => []),
    );
    await tester.pumpAndSettle();

    final fetchesBeforeEdit = duplicatesFetchCount;
    expect(fetchesBeforeEdit, greaterThan(0));

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AddEditBillScreen), findsOneWidget);

    await tester.tap(find.text('Save Bill'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AddEditBillScreen), findsNothing);
    // Saving the edited bill must re-trigger duplicate detection.
    expect(duplicatesFetchCount, greaterThan(fetchesBeforeEdit));
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

  testWidgets('tapping Cancel on the delete confirmation leaves the bill in '
      'place', (tester) async {
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

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(deletedId, isNull);
    expect(find.text('Delete Bill'), findsNothing);
  });

  testWidgets(
      'a delete failure shows the provider\'s error and leaves the group in '
      'place', (tester) async {
    final billsProvider = BillsProvider(
      deleteBillRow: (id) async => throw Exception('network error'),
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
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Failed to delete bill: Exception: network error'),
        findsOneWidget);
  });

  testWidgets('the refresh button reloads duplicate groups', (tester) async {
    var fetchCount = 0;
    final duplicateBillsProvider = DuplicateBillsProvider(
      service: DuplicateBillsService(
        fetchHouseholdBillRows: ({required householdId}) async {
          fetchCount++;
          return [];
        },
      ),
    );

    await pumpDuplicateBillsScreen(
      tester,
      configProvider: signedInConfigProvider(),
      duplicateBillsProvider: duplicateBillsProvider,
    );
    await tester.pumpAndSettle();

    final fetchesAfterInitialLoad = fetchCount;
    expect(fetchesAfterInitialLoad, greaterThan(0));

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(fetchCount, greaterThan(fetchesAfterInitialLoad));
  });
}
