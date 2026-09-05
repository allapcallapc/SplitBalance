// Widget-level coverage for the searchable category icon picker added to
// PaymentSplitsScreen's "Add Category" dialog (_CategoryIconPicker in
// lib/screens/payment_splits_screen.dart): a small default set
// (commonCategoryIconKeys) shown in a Wrap, with a search field that
// filters across the full generated categoryIconOptions map (2000+
// entries, capped to the picker's _maxSearchResults per query).
//
// Same not-signed-in setup as test/bills_list_screen_test.dart: ConfigProvider
// talks directly to Supabase.instance.client with no DI seam, so
// PaymentSplitsScreen's _loadData() no-ops here, leaving the Categories tab
// in its normal empty state - which is enough to reach the "Add Category"
// dialog and its icon picker.

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
import 'package:splitbalance/providers/payment_splits_provider.dart';
import 'package:splitbalance/screens/payment_splits_screen.dart';
import 'package:splitbalance/utils/category_icons.dart';

Future<void> pumpPaymentSplitsScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => BillsProvider()),
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
}

Future<void> openAddCategoryDialog(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // AppBar title and the tab label are both literally "Categories" (see
  // splitsAndCategories in app_en.arb), so target the Tab specifically.
  await tester.tap(find.widgetWithText(Tab, 'Categories'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add Category'));
  await tester.pumpAndSettle();
}

int iconGridChildCount(WidgetTester tester) {
  final grid =
      tester.widget<Wrap>(find.byKey(const Key('categoryIconGrid')));
  return grid.children.length;
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
      'icon picker starts with the common icon set and narrows as you type',
      (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    expect(iconGridChildCount(tester), commonCategoryIconKeys.length);

    await tester.enterText(
        find.byKey(const Key('categoryIconSearchField')), 'zoom_out_map');
    await tester.pumpAndSettle();

    expect(iconGridChildCount(tester), 1);
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
  });

  testWidgets('icon picker shows an empty state when nothing matches',
      (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    await tester.enterText(
        find.byKey(const Key('categoryIconSearchField')), 'zzznotarealicon');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('categoryIconGrid')), findsNothing);
    expect(find.text('No icons found'), findsOneWidget);
  });

  testWidgets('tapping an icon selects it', (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    await tester.enterText(
        find.byKey(const Key('categoryIconSearchField')), 'zoom_out_map');
    await tester.pumpAndSettle();

    final colorBeforeTap =
        tester.widget<Icon>(find.byIcon(Icons.zoom_out_map)).color;

    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pumpAndSettle();

    final colorAfterTap =
        tester.widget<Icon>(find.byIcon(Icons.zoom_out_map)).color;
    expect(colorAfterTap, isNot(equals(colorBeforeTap)));
  });

  test(
      'AppLocalizationsFr provides French translations for the icon search '
      'field (no widget test exercises the fr locale, so this covers the '
      'getters directly)', () {
    expect(AppLocalizationsFr().searchIcons, 'Rechercher des icônes');
    expect(AppLocalizationsFr().noIconsFound, 'Aucune icône trouvée');
  });
}
