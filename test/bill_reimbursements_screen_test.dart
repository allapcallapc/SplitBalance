// Widget-level coverage for BillReimbursementsScreen: the empty/list states,
// the add-reimbursement sheet's validation, and the delete confirmation
// flow. ReimbursementsProvider is driven entirely through its injectable
// fetch/insert/delete points and ConfigProvider.forTesting, so none of this
// needs a real Supabase session - same pattern as
// test/bills_list_screen_test.dart and test/category_detail_screen_test.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/l10n/app_localizations_fr.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/models/bill.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/reimbursements_provider.dart';
import 'package:splitbalance/screens/bill_reimbursements_screen.dart';

Map<String, dynamic> reimbursementRow(
  String id,
  String billId,
  String date, {
  double amount = 10.0,
  String receivedBy = 'Alice',
  String note = '',
}) {
  return {
    'id': id,
    'bill_id': billId,
    'date': date,
    'amount': amount,
    'received_by': receivedBy,
    'note': note,
  };
}

ConfigProvider testConfigProvider({
  String person1Name = 'Alice',
  String person2Name = 'Bob',
}) {
  return ConfigProvider.forTesting(
    isSignedIn: true,
    currentUserId: 'user-1',
    config: AppConfig(
      householdId: 'household-1',
      person1Name: person1Name,
      person2Name: person2Name,
    ),
  );
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required Bill bill,
  required ReimbursementsProvider reimbursementsProvider,
  ConfigProvider? configProvider,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
            value: configProvider ?? testConfigProvider()),
        ChangeNotifierProvider.value(value: reimbursementsProvider),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: BillReimbursementsScreen(bill: bill),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  final bill = Bill(
    id: 'bill-1',
    date: DateTime(2024, 1, 1),
    amount: 100.0,
    paidBy: 'Alice',
    category: 'Food',
  );

  group('BillReimbursementsScreen - empty/list states', () {
    testWidgets('shows the empty state and the full amount as remaining '
        'when there are no reimbursements yet', (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      expect(tester.takeException(), isNull);
      expect(find.text('No reimbursements yet'), findsOneWidget);
      expect(find.text('\$100.00'), findsWidgets); // original + remaining
      expect(find.text('Add Reimbursement'), findsOneWidget); // the FAB
    });

    testWidgets('lists each reimbursement with its date, receiver, and note',
        (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [
          reimbursementRow('r1', 'bill-1', '2024-01-05',
              amount: 30.0, receivedBy: 'Bob', note: 'insurance'),
        ],
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      expect(find.text('\$30.00'), findsOneWidget);
      expect(find.text('2024-01-05 · Bob · insurance'), findsOneWidget);
      expect(find.text('No reimbursements yet'), findsNothing);
    });

    testWidgets('hides the add-reimbursement FAB once the bill is fully '
        'reimbursed', (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-05', amount: 100.0)],
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      expect(find.text('Add Reimbursement'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('shows a loading indicator while reimbursements are loading',
        (tester) async {
      final completer = Completer<List<Map<String, dynamic>>>();
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) => completer.future,
      );

      // settle: false - a full pumpAndSettle would wait forever for the
      // unresolved completer, so this only pumps the one frame needed to
      // render the initial (loading) state.
      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider,
          settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No reimbursements yet'), findsNothing);

      completer.complete([]);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No reimbursements yet'), findsOneWidget);
    });
  });

  group('BillReimbursementsScreen - add reimbursement validation', () {
    testWidgets('rejects a zero/empty amount without calling the inserter',
        (tester) async {
      var insertCalled = false;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
        insertReimbursementRow: (data) async {
          insertCalled = true;
          return reimbursementRow('r1', 'bill-1', '2024-01-01');
        },
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Reimbursement'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid amount'), findsOneWidget);
      expect(insertCalled, isFalse);
    });

    testWidgets('rejects an amount greater than what remains on the bill',
        (tester) async {
      var insertCalled = false;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-01', amount: 60.0)],
        insertReimbursementRow: (data) async {
          insertCalled = true;
          return reimbursementRow('r2', 'bill-1', '2024-01-02');
        },
      );

      // Remaining is 100 - 60 = 40.
      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.tap(find.text('Save Reimbursement'));
      await tester.pumpAndSettle();

      expect(find.text('Amount exceeds the remaining bill balance'),
          findsOneWidget);
      expect(insertCalled, isFalse);
    });

    testWidgets(
        'blocks saving when no one is available to select as the receiver',
        (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
      );

      // No configured person names, so the receiver dropdown starts empty
      // and has nothing to select - the validator should still catch it.
      await pumpScreen(
        tester,
        bill: bill,
        reimbursementsProvider: provider,
        configProvider: testConfigProvider(person1Name: '', person2Name: ''),
      );

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Reimbursement'));
      await tester.pumpAndSettle();

      expect(find.text('Please select who received the reimbursement'),
          findsOneWidget);
    });

    testWidgets(
        'a valid amount and receiver saves the reimbursement and closes '
        'the sheet', (tester) async {
      Map<String, dynamic>? capturedInsert;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
        insertReimbursementRow: (data) async {
          capturedInsert = data;
          return reimbursementRow('r1', 'bill-1', '2024-01-01',
              amount: 20.0, receivedBy: 'Alice');
        },
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Reimbursement'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(capturedInsert, isNotNull);
      expect(capturedInsert!['bill_id'], 'bill-1');
      expect(capturedInsert!['household_id'], 'household-1');
      expect(capturedInsert!['amount'], 20.0);
      expect(capturedInsert!['received_by'], 'Alice');
      // The sheet closed - its Save button is gone.
      expect(find.text('Save Reimbursement'), findsNothing);
      expect(provider.reimbursements, hasLength(1));
    });

    testWidgets(
        'an insert failure shows the provider\'s error and keeps the sheet '
        'open', (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
        insertReimbursementRow: (data) async =>
            throw Exception('network error'),
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Reimbursement'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Failed to add reimbursement'),
          findsOneWidget);
      // The sheet stays open - saving failed, nothing to dismiss for.
      expect(find.text('Save Reimbursement'), findsOneWidget);
      expect(provider.reimbursements, isEmpty);
    });

    testWidgets('picking a date updates the date shown in the sheet',
        (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async => [],
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.text('Add Reimbursement'));
      await tester.pumpAndSettle();

      final todayLabel = DateFormat('yyyy-MM-dd').format(DateTime.now());
      expect(find.text(todayLabel), findsOneWidget);

      await tester.tap(find.text(todayLabel));
      await tester.pumpAndSettle();

      // Confirm the date picker with its default (today) selection - looking
      // up the actual localized button label rather than hardcoding it,
      // since that's what the code under test does too. Enough to exercise
      // the showDatePicker/setSheetState round trip without needing to
      // navigate the calendar to a different day.
      final localizations = MaterialLocalizations.of(
          tester.element(find.byType(BillReimbursementsScreen)));
      await tester.tap(find.text(localizations.okButtonLabel));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(todayLabel), findsOneWidget);
    });
  });

  group('BillReimbursementsScreen - delete', () {
    testWidgets('asks for confirmation and only deletes when confirmed',
        (tester) async {
      String? deletedId;
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-05', amount: 30.0)],
        deleteReimbursementRow: (id) async => deletedId = id,
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Reimbursement'), findsOneWidget);
      expect(find.text('Are you sure you want to delete this reimbursement?'),
          findsOneWidget);

      // Cancelling must not delete anything.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletedId, isNull);
      expect(provider.reimbursements, hasLength(1));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deletedId, 'r1');
      expect(provider.reimbursements, isEmpty);
      expect(find.text('No reimbursements yet'), findsOneWidget);
    });

    testWidgets(
        'a delete failure shows the provider\'s error and leaves the item '
        'in place', (tester) async {
      final provider = ReimbursementsProvider(
        fetchReimbursementsForBill: ({required billId}) async =>
            [reimbursementRow('r1', 'bill-1', '2024-01-05', amount: 30.0)],
        deleteReimbursementRow: (id) async =>
            throw Exception('network error'),
      );

      await pumpScreen(tester, bill: bill, reimbursementsProvider: provider);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to delete reimbursement'),
          findsOneWidget);
      expect(provider.reimbursements, hasLength(1));
    });
  });

  group('AppLocalizationsFr - reimbursement strings', () {
    // No widget test in this suite exercises the fr locale, so these cover
    // the new getters directly - same pattern as
    // test/bills_list_screen_test.dart's noBillsMatchFilters coverage.
    final fr = AppLocalizationsFr();

    test('reimbursements', () => expect(fr.reimbursements, 'Remboursements'));
    test('addReimbursement',
        () => expect(fr.addReimbursement, 'Ajouter un remboursement'));
    test('receivedBy', () => expect(fr.receivedBy, 'Reçu par'));
    test(
        'selectWhoReceived',
        () => expect(fr.selectWhoReceived,
            'Veuillez sélectionner qui a reçu le remboursement'));
    test('saveReimbursement',
        () => expect(fr.saveReimbursement, 'Enregistrer le remboursement'));
    test('deleteReimbursement',
        () => expect(fr.deleteReimbursement, 'Supprimer le remboursement'));
    test(
        'areYouSureDeleteReimbursement',
        () => expect(fr.areYouSureDeleteReimbursement,
            'Êtes-vous sûr de vouloir supprimer ce remboursement ?'));
    test('noReimbursementsYet',
        () => expect(fr.noReimbursementsYet, 'Aucun remboursement pour le moment'));
    test(
        'reimbursementExceedsRemaining',
        () => expect(fr.reimbursementExceedsRemaining,
            'Le montant dépasse le solde restant de la facture'));
    test('totalReimbursed',
        () => expect(fr.totalReimbursed, 'Total remboursé'));
    test('remainingAmount', () => expect(fr.remainingAmount, 'Restant'));
    test('originalAmount', () => expect(fr.originalAmount, 'Montant initial'));
  });
}
