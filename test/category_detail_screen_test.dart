// Coverage for CategoryDetailScreen's "view bills in this category" app bar
// action: it should set BillsProvider's category filter, ask
// TabNavigationProvider to switch to the Bills tab, and pop back to
// whichever screen is underneath - regardless of how many screens deep
// CategoryDetailScreen was pushed (SummaryScreen pushes it directly;
// TotalDetailScreen's ranked breakdown pushes it one level further in).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/tab_navigation_provider.dart';
import 'package:splitbalance/screens/category_detail_screen.dart';

Widget _buildCategoryDetailScreen() {
  return const CategoryDetailScreen(
    category: 'Food',
    person1Name: 'Alice',
    person2Name: 'Bob',
    total: 100.0,
    person1Paid: 50.0,
    person1Expected: 50.0,
    person2Paid: 50.0,
    person2Expected: 50.0,
  );
}

Future<void> _pumpHomeWithProviders(
  WidgetTester tester, {
  required BillsProvider billsProvider,
  required TabNavigationProvider tabNavigationProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider.value(value: billsProvider),
        ChangeNotifierProvider.value(value: tabNavigationProvider),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: Text('Root Marker')),
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
      'tapping "view bills" sets the category filter, requests the Bills '
      'tab, and pops back when pushed directly from one screen',
      (tester) async {
    final billsProvider = BillsProvider();
    final tabNavigationProvider = TabNavigationProvider();

    await _pumpHomeWithProviders(
      tester,
      billsProvider: billsProvider,
      tabNavigationProvider: tabNavigationProvider,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute(builder: (_) => _buildCategoryDetailScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CategoryDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('View bills in this category'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(billsProvider.filterCategory, 'Food');
    expect(tabNavigationProvider.requestedIndex, 0);
    expect(find.byType(CategoryDetailScreen), findsNothing);
    expect(find.text('Root Marker'), findsOneWidget);
  });

  testWidgets(
      'pops all the way back to the root even when pushed two screens deep '
      '(e.g. via TotalDetailScreen\'s ranked breakdown)', (tester) async {
    final billsProvider = BillsProvider();
    final tabNavigationProvider = TabNavigationProvider();

    await _pumpHomeWithProviders(
      tester,
      billsProvider: billsProvider,
      tabNavigationProvider: tabNavigationProvider,
    );

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Intermediate Screen')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.push(
      MaterialPageRoute(builder: (_) => _buildCategoryDetailScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('View bills in this category'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(billsProvider.filterCategory, 'Food');
    expect(tabNavigationProvider.requestedIndex, 0);
    expect(find.text('Intermediate Screen'), findsNothing);
    expect(find.text('Root Marker'), findsOneWidget);
  });
}
