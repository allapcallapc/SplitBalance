// Widget-level coverage for BillRecoveredAmountsScreen: the empty/list
// states, the add-recovered-amount sheet's validation, and the delete
// confirmation flow. RecoveredAmountsProvider is driven entirely through its
// injectable fetch/insert/delete points and ConfigProvider.forTesting, so
// none of this needs a real Supabase session - same pattern as
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
import 'package:splitbalance/providers/recovered_amounts_provider.dart';
import 'package:splitbalance/screens/bill_recovered_amounts_screen.dart';

Map<String, dynamic> recoveredAmountRow(
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
  String? householdId = 'household-1',
  Map<String, String> memberNamesByUserId = const {},
}) {
  return ConfigProvider.forTesting(
    isSignedIn: true,
    currentUserId: 'user-1',
    config: AppConfig(
      householdId: householdId,
      person1Name: person1Name,
      person2Name: person2Name,
    ),
    memberNamesByUserId: memberNamesByUserId,
  );
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required Bill bill,
  required RecoveredAmountsProvider recoveredAmountsProvider,
  ConfigProvider? configProvider,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
            value: configProvider ?? testConfigProvider()),
        ChangeNotifierProvider.value(value: recoveredAmountsProvider),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: BillRecoveredAmountsScreen(bill: bill),
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

  group('BillRecoveredAmountsScreen - empty/list states', () {
    testWidgets('shows the empty state and the full amount as remaining '
        'when there are no recovered amounts yet', (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      expect(tester.takeException(), isNull);
      expect(find.text('No recovered amounts yet'), findsOneWidget);
      expect(find.text('\$100.00'), findsWidgets); // original + remaining
      expect(find.text('Add Recovered Amount'), findsOneWidget); // the FAB
    });

    testWidgets(
        'never calls loadForBill when the bill has no saved id yet '
        '(defensive - real navigation only ever reaches this screen with '
        'an already-saved bill)', (tester) async {
      var loadForBillCalled = false;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async {
          loadForBillCalled = true;
          return [];
        },
      );
      final unsavedBill = Bill(
        date: DateTime(2024, 1, 1),
        amount: 50.0,
        paidBy: 'Alice',
        category: 'Food',
      );

      await pumpScreen(
          tester, bill: unsavedBill, recoveredAmountsProvider: provider);

      expect(tester.takeException(), isNull);
      expect(loadForBillCalled, isFalse);
      expect(find.text('No recovered amounts yet'), findsOneWidget);
    });

    testWidgets(
        'lists each recovered amount with its date, receiver, and note',
        (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [
          recoveredAmountRow('r1', 'bill-1', '2024-01-05',
              amount: 30.0, receivedBy: 'Bob', note: 'insurance'),
        ],
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      expect(find.text('\$30.00'), findsOneWidget);
      expect(find.text('2024-01-05 · Bob · insurance'), findsOneWidget);
      expect(find.text('No recovered amounts yet'), findsNothing);
    });

    testWidgets(
        'hides the add-recovered-amount FAB once the bill is fully '
        'recovered', (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-05', amount: 100.0)],
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      expect(find.text('Add Recovered Amount'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets(
        'shows a loading indicator while recovered amounts are loading',
        (tester) async {
      final completer = Completer<List<Map<String, dynamic>>>();
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) => completer.future,
      );

      // settle: false - a full pumpAndSettle would wait forever for the
      // unresolved completer, so this only pumps the one frame needed to
      // render the initial (loading) state.
      await pumpScreen(tester,
          bill: bill, recoveredAmountsProvider: provider, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('No recovered amounts yet'), findsNothing);

      completer.complete([]);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No recovered amounts yet'), findsOneWidget);
    });
  });

  group('BillRecoveredAmountsScreen - add recovered amount validation', () {
    testWidgets('rejects a zero/empty amount without calling the inserter',
        (tester) async {
      var insertCalled = false;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async {
          insertCalled = true;
          return recoveredAmountRow('r1', 'bill-1', '2024-01-01');
        },
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid amount'), findsOneWidget);
      expect(insertCalled, isFalse);
    });

    testWidgets('rejects an amount greater than what remains on the bill',
        (tester) async {
      var insertCalled = false;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-01', amount: 60.0)],
        insertRecoveredAmountRow: (data) async {
          insertCalled = true;
          return recoveredAmountRow('r2', 'bill-1', '2024-01-02');
        },
      );

      // Remaining is 100 - 60 = 40.
      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(find.text('Amount exceeds the remaining bill balance'),
          findsOneWidget);
      expect(insertCalled, isFalse);
    });

    testWidgets(
        'blocks saving when no one is available to select as the receiver',
        (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
      );

      // No configured person names, so the receiver dropdown starts empty
      // and has nothing to select - the validator should still catch it.
      await pumpScreen(
        tester,
        bill: bill,
        recoveredAmountsProvider: provider,
        configProvider: testConfigProvider(person1Name: '', person2Name: ''),
      );

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(find.text('Please select who received the money'),
          findsOneWidget);
    });

    testWidgets(
        'a valid amount and receiver saves the recovered amount and closes '
        'the sheet', (tester) async {
      Map<String, dynamic>? capturedInsert;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async {
          capturedInsert = data;
          return recoveredAmountRow('r1', 'bill-1', '2024-01-01',
              amount: 20.0, receivedBy: 'Alice');
        },
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(capturedInsert, isNotNull);
      expect(capturedInsert!['bill_id'], 'bill-1');
      expect(capturedInsert!['household_id'], 'household-1');
      expect(capturedInsert!['amount'], 20.0);
      expect(capturedInsert!['received_by'], 'Alice');
      // The sheet closed - its Save button is gone.
      expect(find.text('Save Recovered Amount'), findsNothing);
      expect(provider.recoveredAmounts, hasLength(1));
    });

    testWidgets(
        'an insert failure shows the provider\'s error and keeps the sheet '
        'open', (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async =>
            throw Exception('network error'),
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Failed to add recovered amount'),
          findsOneWidget);
      // The sheet stays open - saving failed, nothing to dismiss for.
      expect(find.text('Save Recovered Amount'), findsOneWidget);
      expect(provider.recoveredAmounts, isEmpty);
    });

    testWidgets('picking a date updates the date shown in the sheet',
        (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
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
          tester.element(find.byType(BillRecoveredAmountsScreen)));
      await tester.tap(find.text(localizations.okButtonLabel));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(todayLabel), findsOneWidget);
    });

    testWidgets(
        'saving does nothing when there is no household id (defensive - '
        'real navigation only ever reaches this screen once signed into a '
        'household)', (tester) async {
      var insertCalled = false;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async {
          insertCalled = true;
          return recoveredAmountRow('r1', 'bill-1', '2024-01-01');
        },
      );

      await pumpScreen(
        tester,
        bill: bill,
        recoveredAmountsProvider: provider,
        configProvider: testConfigProvider(householdId: null),
      );

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(insertCalled, isFalse);
      // Nothing happened, so the sheet just stays open.
      expect(find.text('Save Recovered Amount'), findsOneWidget);
    });

    testWidgets(
        'defaults the receiver to the signed-in member\'s own name when one '
        'is known', (tester) async {
      Map<String, dynamic>? capturedInsert;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async {
          capturedInsert = data;
          return recoveredAmountRow('r1', 'bill-1', '2024-01-01',
              amount: 20.0, receivedBy: 'Bob');
        },
      );

      // 'user-1' (the signed-in id baked into testConfigProvider) maps to
      // 'Bob' here, so the receiver dropdown should default to 'Bob' rather
      // than falling back to person1Name ('Alice').
      await pumpScreen(
        tester,
        bill: bill,
        recoveredAmountsProvider: provider,
        configProvider: testConfigProvider(
          memberNamesByUserId: const {'user-1': 'Bob'},
        ),
      );

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(capturedInsert, isNotNull);
      expect(capturedInsert!['received_by'], 'Bob');
    });

    testWidgets('changing the receiver dropdown updates who gets saved',
        (tester) async {
      Map<String, dynamic>? capturedInsert;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async => [],
        insertRecoveredAmountRow: (data) async {
          capturedInsert = data;
          return recoveredAmountRow('r1', 'bill-1', '2024-01-01',
              amount: 20.0, receivedBy: 'Bob');
        },
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.text('Add Recovered Amount'));
      await tester.pumpAndSettle();

      // Defaults to 'Alice' (person1Name); open the dropdown and pick 'Bob'.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '20');
      await tester.tap(find.text('Save Recovered Amount'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(capturedInsert, isNotNull);
      expect(capturedInsert!['received_by'], 'Bob');
    });
  });

  group('BillRecoveredAmountsScreen - delete', () {
    testWidgets('asks for confirmation and only deletes when confirmed',
        (tester) async {
      String? deletedId;
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-05', amount: 30.0)],
        deleteRecoveredAmountRow: (id) async => deletedId = id,
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();

      expect(find.text('Delete Recovered Amount'), findsOneWidget);
      expect(
          find.text('Are you sure you want to delete this recovered '
              'amount?'),
          findsOneWidget);

      // Cancelling must not delete anything.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deletedId, isNull);
      expect(provider.recoveredAmounts, hasLength(1));

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deletedId, 'r1');
      expect(provider.recoveredAmounts, isEmpty);
      expect(find.text('No recovered amounts yet'), findsOneWidget);
    });

    testWidgets(
        'a delete failure shows the provider\'s error and leaves the item '
        'in place', (tester) async {
      final provider = RecoveredAmountsProvider(
        fetchRecoveredAmountsForBill: ({required billId}) async =>
            [recoveredAmountRow('r1', 'bill-1', '2024-01-05', amount: 30.0)],
        deleteRecoveredAmountRow: (id) async =>
            throw Exception('network error'),
      );

      await pumpScreen(
          tester, bill: bill, recoveredAmountsProvider: provider);

      await tester.tap(find.byIcon(Icons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to delete recovered amount'),
          findsOneWidget);
      expect(provider.recoveredAmounts, hasLength(1));
    });
  });

  group('AppLocalizationsFr - recovered amount strings', () {
    // No widget test in this suite exercises the fr locale, so these cover
    // the new getters directly - same pattern as
    // test/bills_list_screen_test.dart's noBillsMatchFilters coverage.
    final fr = AppLocalizationsFr();

    test('recoveredAmounts',
        () => expect(fr.recoveredAmounts, 'Montants récupérés'));
    test('addRecoveredAmount',
        () => expect(fr.addRecoveredAmount, 'Ajouter un montant récupéré'));
    test('receivedBy', () => expect(fr.receivedBy, 'Reçu par'));
    test(
        'selectWhoReceived',
        () => expect(
            fr.selectWhoReceived, 'Veuillez sélectionner qui a reçu l\'argent'));
    test(
        'saveRecoveredAmount',
        () => expect(
            fr.saveRecoveredAmount, 'Enregistrer le montant récupéré'));
    test(
        'deleteRecoveredAmount',
        () => expect(
            fr.deleteRecoveredAmount, 'Supprimer le montant récupéré'));
    test(
        'areYouSureDeleteRecoveredAmount',
        () => expect(fr.areYouSureDeleteRecoveredAmount,
            'Êtes-vous sûr de vouloir supprimer ce montant récupéré ?'));
    test(
        'noRecoveredAmountsYet',
        () => expect(
            fr.noRecoveredAmountsYet, 'Aucun montant récupéré pour le moment'));
    test(
        'recoveredAmountExceedsRemaining',
        () => expect(fr.recoveredAmountExceedsRemaining,
            'Le montant dépasse le solde restant de la facture'));
    test('totalRecovered',
        () => expect(fr.totalRecovered, 'Total récupéré'));
    test('remainingAmount', () => expect(fr.remainingAmount, 'Restant'));
    test('originalAmount', () => expect(fr.originalAmount, 'Montant initial'));
  });
}
