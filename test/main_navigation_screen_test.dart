// Widget-level coverage for the settle-gating/tab-restore behavior added to
// MainNavigationScreen (GH issue #59): settling now also waits on
// TabIndexStore.load() before deciding which screen to land on, made
// testable via the tabIndexStore constructor injection point.
//
// A fully signed-in-with-household scenario can't be driven here -
// ConfigProvider talks directly to Supabase.instance.client with no DI seam
// (same limitation documented in test/summary_screen_test.dart) - so this
// exercises the not-signed-in path, which still goes through the same
// `configSettled && categoriesSettled && _tabIndexLoaded` gate and the same
// TabIndexStore.load() call.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/main.dart';
import 'package:splitbalance/providers/bills_provider.dart';
import 'package:splitbalance/providers/calculation_provider.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
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
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => BillsProvider()),
        ChangeNotifierProvider(create: (_) => PaymentSplitsProvider()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => CalculationProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
        ChangeNotifierProvider(create: (_) => TabNavigationProvider()),
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
}
