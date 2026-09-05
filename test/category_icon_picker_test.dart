// Widget-level coverage for the searchable, infinite-scrolling category icon
// picker in PaymentSplitsScreen's "Add Category" dialog (_CategoryIconPicker
// in lib/screens/payment_splits_screen.dart): it shows a page of matches
// (all of categoryIconOptions by default, or a filtered subset once the
// user searches) in a Wrap, with a "Showing X of Y" caption, and loads
// another page when the dialog's own scroll view is scrolled near its
// bottom (rather than a GridView/ListView over the whole 2000+ entry set at
// once, which crashed the Flutter framework while the dialog animated in).
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

// Mirrors _CategoryIconPickerState._pageSize (private, so not importable).
const int _pageSize = 60;

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
      'icon picker starts with one page of icons and shows how many are '
      'loaded', (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    expect(iconGridChildCount(tester), _pageSize);
    expect(
      find.text('Showing $_pageSize of ${categoryIconOptions.length} icons'),
      findsOneWidget,
    );
  });

  testWidgets('scrolling near the bottom loads another page of icons',
      (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    expect(iconGridChildCount(tester), _pageSize);

    // Drag the dialog's own scroll view (its bounds are always within the
    // visible viewport, unlike its Wrap child once there's enough icons to
    // overflow) - the picker doesn't own a scrollable of its own and relies
    // on this ambient one (see Scrollable.maybeOf in
    // _CategoryIconPickerState) to know when to load another page.
    await tester.drag(find.byKey(const Key('categoryDialogScroll')),
        const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(iconGridChildCount(tester), greaterThan(_pageSize));
  });

  testWidgets('searching narrows the results and resets the page',
      (tester) async {
    await pumpPaymentSplitsScreen(tester);
    await openAddCategoryDialog(tester);

    await tester.enterText(
        find.byKey(const Key('categoryIconSearchField')), 'zoom_out_map');
    await tester.pumpAndSettle();

    expect(iconGridChildCount(tester), 1);
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
    expect(find.text('Showing 1 of 1 icons'), findsOneWidget);
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
    expect(AppLocalizationsFr().showingIconsCount(60, 2231),
        'Affichage de 60 sur 2231 icônes');
  });
}
