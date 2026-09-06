// Widget-level coverage for the settle-gating/tab-restore behavior added to
// MainNavigationScreen (GH issue #59): settling now also waits on
// TabIndexStore.load() before deciding which screen to land on, made
// testable via the tabIndexStore constructor injection point.
//
// Most cases below exercise the not-signed-in path, which still goes through
// the same `configSettled && categoriesSettled && _tabIndexLoaded` gate and
// the same TabIndexStore.load() call. The pending-deep-link regression test
// further down drives a signed-in-with-household scenario via
// ConfigProvider.forTesting/CategoriesProvider's fetchCategories override
// (see test/bills_list_screen_test.dart for the same pattern), since that
// bug only reproduces once isConfigComplete flips true asynchronously.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/main.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/calculation_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/duplicate_bills_provider.dart';
import 'package:splitbalance/providers/payment_splits_provider.dart';
import 'package:splitbalance/providers/pending_payments_provider.dart';
import 'package:splitbalance/providers/tab_navigation_provider.dart';
import 'package:splitbalance/services/tab_index_store.dart';

/// Records calls and, when [loadDelay] is set, lets a test hold
/// TabIndexStore.load() open to observe the splash screen before it
/// resolves - a real SharedPreferences-backed load always resolves inside a
/// single microtask, too fast to observe that state otherwise.
class _FakeTabIndexStore implements TabIndexStore {
  _FakeTabIndexStore({this.loadDelay});

  final Completer<void>? loadDelay;
  int? storedIndex;
  int loadCallCount = 0;
  int saveCallCount = 0;
  int clearCallCount = 0;

  @override
  Future<int?> load({required int screenCount}) async {
    loadCallCount++;
    if (loadDelay != null) await loadDelay!.future;
    final stored = storedIndex;
    if (stored == null || stored < 0 || stored >= screenCount) return null;
    return stored;
  }

  @override
  Future<void> save(int index) async {
    saveCallCount++;
    storedIndex = index;
  }

  @override
  Future<void> clear() async {
    clearCallCount++;
    storedIndex = null;
  }
}

Future<void> pumpMainNavigationScreen(
  WidgetTester tester, {
  required TabIndexStore tabIndexStore,
  TabNavigationProvider? tabNavigationProvider,
  ConfigProvider? configProvider,
  CategoriesProvider? categoriesProvider,
  BillsProvider? billsProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider ?? ConfigProvider()),
        ChangeNotifierProvider.value(value: billsProvider ?? BillsProvider()),
        ChangeNotifierProvider(create: (_) => PaymentSplitsProvider()),
        ChangeNotifierProvider.value(
          value: categoriesProvider ?? CategoriesProvider(),
        ),
        ChangeNotifierProvider(create: (_) => CalculationProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
        ChangeNotifierProvider(create: (_) => DuplicateBillsProvider()),
        ChangeNotifierProvider.value(
          value: tabNavigationProvider ?? TabNavigationProvider(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: MainNavigationScreen(tabIndexStore: tabIndexStore),
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

  // SummaryScreen renders its own (unrelated) CircularProgressIndicator
  // while its initial calculation is in flight, and it stays mounted
  // offstage in the IndexedStack even when the config screen is showing -
  // so `find.byType(CircularProgressIndicator)` alone can't distinguish the
  // splash overlay from it. main.dart keys the splash overlay specifically
  // so tests can find it unambiguously.
  final splashOverlay = find.byKey(const ValueKey('settleSplashOverlay'));

  testWidgets(
      'queries TabIndexStore.load with the screen count and settles on the '
      'config screen when not signed in', (tester) async {
    final store = _FakeTabIndexStore();

    await pumpMainNavigationScreen(tester, tabIndexStore: store);
    // CircularProgressIndicator's ticker animates indefinitely, so
    // pumpAndSettle would never terminate - pump a fixed duration instead,
    // matching test/widget_test.dart's existing pattern for this screen.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(store.loadCallCount, 1);
    expect(splashOverlay, findsNothing);
    expect(find.text('Configuration'), findsOneWidget);
  });

  testWidgets(
      'stays on the loading splash until TabIndexStore.load resolves, then '
      'settles (settle-gating added for GH issue #59)', (tester) async {
    final delay = Completer<void>();
    final store = _FakeTabIndexStore(loadDelay: delay);

    await pumpMainNavigationScreen(tester, tabIndexStore: store);
    await tester.pump();

    expect(store.loadCallCount, 1);
    expect(splashOverlay, findsOneWidget);

    delay.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(splashOverlay, findsNothing);
    expect(find.text('Configuration'), findsOneWidget);
  });

  testWidgets(
      'never calls save or clear on the store when the nav bar is never '
      'shown (not signed in, so there is nothing to persist)',
      (tester) async {
    final store = _FakeTabIndexStore();

    await pumpMainNavigationScreen(tester, tabIndexStore: store);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.saveCallCount, 0);
    expect(store.clearCallCount, 0);
  });

  testWidgets(
      'persists a tab requested via TabNavigationProvider and clears the '
      'request once handled', (tester) async {
    final store = _FakeTabIndexStore();
    final tabNavigationProvider = TabNavigationProvider();

    await pumpMainNavigationScreen(
      tester,
      tabIndexStore: store,
      tabNavigationProvider: tabNavigationProvider,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    tabNavigationProvider.requestTab(0);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(store.saveCallCount, 1);
    expect(store.storedIndex, 0);
    expect(tabNavigationProvider.requestedIndex, isNull);
  });

  testWidgets(
      'retries the settle-triggered auto-navigation (and so the pending '
      'deep-link check riding along with it) once config settles '
      'asynchronously after the first build - regression test for a cold '
      'start where household/categories were still loading on the first '
      'check, previously dropping any pending notification deep link for '
      'the rest of the session', (tester) async {
    final store = _FakeTabIndexStore();
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
    );
    // Starts empty so the first settle (once BillsListScreen's initial load
    // resolves) has isConfigComplete still false - categories only arrive on
    // the second, explicit loadCategories call below, mirroring a slow
    // network finishing after the app's first settled build. (Actually
    // exercising deep-link navigation itself would need
    // PendingPaymentsProvider.isSupported - platform-gated to Android with
    // no test seam - so this instead pins down the observable half of the
    // fix in main.dart: the settle logic retries _checkPendingDeepLink(),
    // which the diff being covered here schedules via the same branch that
    // also finally moves off the config screen.)
    var categoryRows = <Map<String, dynamic>>[];
    final categoriesProvider = CategoriesProvider(
      fetchCategories: ({required householdId}) async => categoryRows,
    );
    final billsProvider = BillsProvider(
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
          const [],
      fetchRecoveredBreakdown: ({required billIds}) async => {},
    );

    await pumpMainNavigationScreen(
      tester,
      tabIndexStore: store,
      configProvider: configProvider,
      categoriesProvider: categoriesProvider,
      billsProvider: billsProvider,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Settled with no categories yet, so isConfigComplete is false: signed
    // in with a household is enough to show the nav bar (just in the
    // limited "create categories" mode), but not enough to auto-navigate
    // off it, so it's still parked on the config tab (index 3). The nav
    // bar's selectedIndex - rather than which screen is visible - is what
    // distinguishes this from the post-fix state below, since every screen
    // in _screens (ConfigScreen included) stays mounted in the IndexedStack
    // regardless of which one is currently showing.
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );

    // Categories finish loading a moment later - isConfigComplete flips true
    // well after the first settled build, the exact timing this regression
    // covers. Without the fix, nothing but the (already-spent) first-settle
    // branch ever moves _selectedIndex, so the nav bar would stay parked on
    // the config tab forever; with it, the retried settle logic auto-
    // navigates to Bills (index 0) same as a fresh, fully-configured sign-in
    // would.
    categoryRows = [
      {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
    ];
    await categoriesProvider.loadCategories(configProvider);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
  });
}
