import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'l10n/app_localizations.dart';
import 'providers/config_provider.dart';
import 'providers/bills_provider.dart';
import 'providers/payment_splits_provider.dart';
import 'providers/categories_provider.dart';
import 'providers/calculation_provider.dart';
import 'providers/pending_payments_provider.dart';
import 'screens/config_screen.dart';
import 'screens/bills_list_screen.dart';
import 'screens/payment_splits_screen.dart';
import 'screens/summary_screen.dart';
import 'screens/pending_payments_screen.dart';
import 'screens/add_edit_bill_screen.dart';
import 'models/app_config.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // SupabaseConfig has no built-in default (see its doc comment) - catch a
  // missing --dart-define here with a clear message instead of letting it
  // silently try to connect to an empty URL.
  if (SupabaseConfig.url.isEmpty || SupabaseConfig.anonKey.isEmpty) {
    throw StateError(
      'Missing Supabase config: pass --dart-define=SUPABASE_URL=... and '
      '--dart-define=SUPABASE_ANON_KEY=... (see .vscode/launch.json for '
      'local runs, or the deploy workflows for CI).',
    );
  }
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const SplitBalanceApp());
}

class SplitBalanceApp extends StatelessWidget {
  const SplitBalanceApp({super.key});

  static ThemeData _getLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        actionsPadding: EdgeInsets.only(right: 8),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static ThemeData _getDarkTheme() {
    // Create a custom dark color scheme with better contrast
    final baseScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: baseScheme.copyWith(
        // Use a lighter surface color for better contrast
        surface: const Color(0xFF1E1E1E), // Lighter than pure black
        surfaceContainer: const Color(0xFF2D2D2D), // Medium surface
        onSurface: Colors.white,
        // Ensure cards stand out more
        surfaceContainerHighest:
            const Color(0xFF3A3A3A), // Even lighter for cards
        onSurfaceVariant: Colors.white70,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        actionsPadding: EdgeInsets.only(right: 8),
      ),
      scaffoldBackgroundColor:
          const Color(0xFF121212), // Very dark but not pure black
      cardTheme: CardThemeData(
        color: const Color(0xFF2D2D2D), // Lighter than scaffold for contrast
        elevation: 6, // Higher elevation for better separation
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // Improve divider contrast
      dividerColor: Colors.white.withValues(alpha: 0.2),
      // Improve list tile contrast
      listTileTheme: const ListTileThemeData(
        tileColor: Color(0xFF2D2D2D),
        selectedTileColor: Color(0xFF3A3A3A),
      ),
      // Improve input decoration in dark mode
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: baseScheme.primary, width: 2),
        ),
      ),
    );
  }

  static ThemeData _getPinkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.pink,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        actionsPadding: EdgeInsets.only(right: 8),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      scaffoldBackgroundColor: Colors.pink[50],
    );
  }

  static ThemeData _getTealTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        actionsPadding: EdgeInsets.only(right: 8),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      scaffoldBackgroundColor: Colors.teal[50],
    );
  }

  static ThemeData _getThemeForMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return _getLightTheme();
      case AppThemeMode.dark:
        return _getDarkTheme();
      case AppThemeMode.pink:
        return _getPinkTheme();
      case AppThemeMode.teal:
        return _getTealTheme();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConfigProvider()),
        ChangeNotifierProvider(create: (_) => BillsProvider()),
        ChangeNotifierProvider(create: (_) => PaymentSplitsProvider()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
        ChangeNotifierProvider(create: (_) => CalculationProvider()),
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
      ],
      child: Consumer<ConfigProvider>(
        builder: (context, configProvider, child) {
          return MaterialApp(
            title: 'SplitBalance',
            theme: _getThemeForMode(configProvider.themeMode),
            locale: configProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[
              Locale('en'),
              Locale('fr'),
            ],
            home: const MainNavigationScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool? _wasSignedIn;
  int? _previousBodyIndex;
  bool _hasAutoNavigatedToBills = false;
  late final ValueNotifier<int> _navigationNotifier = ValueNotifier<int>(0);
  late final List<Widget> _screens;

  // The tab selected before a refresh, so a reload can restore it instead of
  // always landing on Bills (see GH issue #59). Explicitly cleared on
  // sign-out (both in-memory and on disk - see _clearPersistedTabIndex), so
  // a fresh login still lands on Bills.
  static const _selectedTabStorageKey = 'selected_tab_index';
  int? _persistedTabIndex;
  bool _tabIndexLoaded = false;

  // Tracks whether we're still waiting on the household/categories lookups
  // for the current (isSignedIn, householdId) combo - see the settleKey
  // computation in build(). Re-arms on every sign-in/sign-out/household
  // change, not just at boot, so logging in doesn't show config-then-bills
  // either (see GH issue #21).
  String? _settledForKey;
  bool _forceSettledOverride = false;
  bool _settleTimerPending = false;
  Timer? _settleTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _screens = [
      const BillsListScreen(),
      const PaymentSplitsScreen(),
      SummaryScreen(navigationNotifier: _navigationNotifier),
      const ConfigScreen(),
    ];
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkPendingDeepLink());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForAppUpdate());
    _loadPersistedTabIndex();
  }

  // Must resolve before the "first settle" auto-navigation below runs, so
  // that decision can restore the previous tab instead of racing ahead and
  // forcing Bills. Gated into `rawSettled` for that reason.
  Future<void> _loadPersistedTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final stored = prefs.getInt(_selectedTabStorageKey);
    setState(() {
      // Guards against a stored index that's out of range for the current
      // _screens list (e.g. a tab was removed/reordered in a later release)
      // - falls back to the normal Bills default rather than crashing
      // IndexedStack.
      _persistedTabIndex =
          (stored != null && stored >= 0 && stored < _screens.length)
              ? stored
              : null;
      _tabIndexLoaded = true;
    });
  }

  Future<void> _persistTabIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedTabStorageKey, index);
  }

  // ConfigProvider.signOut() (the normal "Sign Out" button) only resets
  // in-memory config and re-saves it - unlike clearAllConfig(), it never
  // touches SharedPreferences keys it doesn't own, so the persisted tab
  // must be removed explicitly here. Otherwise a sign-out/refresh/sign-in
  // (no clean session in between) would read the stale value back and land
  // on the old tab instead of Bills.
  Future<void> _clearPersistedTabIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selectedTabStorageKey);
  }

  // Runs once per app launch (unlike the deep-link check, this doesn't need
  // to re-run on resume) so a sideloaded install still gets notified of new
  // releases without going through the Play Store.
  Future<void> _checkForAppUpdate() async {
    if (!UpdateService.isSupported) return;
    final updateService = UpdateService();
    final update = await updateService.checkForUpdate();
    if (update == null || !mounted) return;
    await showUpdateAvailableDialog(context, updateService, update);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimeoutTimer?.cancel();
    _navigationNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingDeepLink();
    }
  }

  // Handles the "Yes"/"See more" actions on a pending-bill system
  // notification: navigates straight to the relevant screen once the app is
  // fully configured (a stale notification tapped before sign-in/setup is
  // otherwise silently ignored rather than navigating into a broken state).
  Future<void> _checkPendingDeepLink() async {
    if (!mounted) return;
    final pendingPaymentsProvider = context.read<PendingPaymentsProvider>();
    if (!pendingPaymentsProvider.isSupported) return;

    final deepLink = await pendingPaymentsProvider.getPendingDeepLink();
    if (deepLink == null || !mounted) return;

    final configProvider = context.read<ConfigProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final isConfigComplete = configProvider.isSignedIn &&
        configProvider.householdId != null &&
        configProvider.config.person1Name.trim().isNotEmpty &&
        configProvider.config.person2Name.trim().isNotEmpty &&
        categoriesProvider.categories.isNotEmpty;
    if (!isConfigComplete) return;

    await pendingPaymentsProvider.clearPendingDeepLink();
    if (!mounted) return;

    final action = deepLink['action'] as String?;
    final id = deepLink['id'] as String?;

    if (action == 'OPEN_PENDING_PAYMENTS') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PendingPaymentsScreen(focusedId: id),
        ),
      );
    } else if (action == 'ADD_BILL') {
      final amount = deepLink['amount'] as double?;
      final details = deepLink['details'] as String?;
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AddEditBillScreen(
            prefillAmount: amount,
            prefillDetails: details,
          ),
        ),
      );
      if (result == true && id != null && mounted) {
        await context.read<PendingPaymentsProvider>().dismiss(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigProvider, CategoriesProvider>(
      builder: (context, configProvider, categoriesProvider, child) {
        final isSignedIn = configProvider.isSignedIn;

        // Check if configuration flow is complete
        // Required steps: Login -> Household -> Categories
        // (A second household member joining is no longer a gate here - a
        // household always has at least one named member as soon as it
        // exists, and the app is fully usable solo while waiting for the
        // other person to join via invite code.)
        final hasHousehold = configProvider.householdId != null;
        final hasCategories = categoriesProvider.categories.isNotEmpty;

        // Config is complete when all steps are done
        final isConfigComplete = isSignedIn && hasHousehold && hasCategories;

        // Allow partial navigation when household is set (to create categories)
        final canNavigateToCreateCategories =
            isSignedIn && hasHousehold && !hasCategories;

        // Determine if nav bar should be shown
        final shouldShowNavBar = isSignedIn && hasHousehold;

        // Wait for the session/household/categories lookups for the current
        // sign-in state to settle before deciding which screen to land on.
        // Without this, a restored session (or a fresh sign-in) briefly reads
        // as "not configured" (household and categories haven't loaded from
        // the network yet), we land on the config screen, and then flip to
        // bills a moment later once they do. Re-armed via _settledForKey
        // whenever isSignedIn/householdId changes, so this covers both app
        // boot and logging in mid-session.
        // Note: the screens below (in particular BillsListScreen) are what
        // actually kick off the household/categories fetches, so they must
        // stay mounted the whole time - only the splash overlay toggles.
        final settleKey = '$isSignedIn:${configProvider.householdId}';
        if (_settledForKey != settleKey) {
          _settledForKey = settleKey;
          _forceSettledOverride = false;
          _settleTimeoutTimer?.cancel();
          _settleTimerPending = false;
        }

        final configSettled = !configProvider.isInitializing;
        final needsCategories = configSettled && isSignedIn && hasHousehold;
        final categoriesSettled = !needsCategories ||
            categoriesProvider
                .hasLoadedForHousehold(configProvider.householdId);
        final rawSettled =
            configSettled && categoriesSettled && _tabIndexLoaded;

        if (rawSettled) {
          _settleTimeoutTimer?.cancel();
          _settleTimerPending = false;
          _forceSettledOverride = false;
        } else if (!_settleTimerPending) {
          // Fallback so a slow/offline network doesn't strand the user on
          // the splash screen forever - just fall through to whatever state
          // we have.
          _settleTimerPending = true;
          _settleTimeoutTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _forceSettledOverride = true;
                _settleTimerPending = false;
              });
            }
          });
        }

        final settled = rawSettled || _forceSettledOverride;

        // ABSOLUTE MINIMAL: Only initialize on first build, NO auto-navigation at all
        if (settled) {
          if (_wasSignedIn == null) {
            _wasSignedIn = isSignedIn;
            if (isSignedIn && isConfigComplete) {
              // Restore the tab open before a refresh; a fresh login has no
              // persisted value (cleared on sign-out) and lands on Bills.
              _selectedIndex = _persistedTabIndex ?? 0; // Bills screen
              _hasAutoNavigatedToBills = true;
            } else {
              _selectedIndex = 3; // Config screen
            }
          } else if (_wasSignedIn != isSignedIn) {
            _wasSignedIn = isSignedIn;
            if (!isSignedIn) {
              _selectedIndex = 3; // Config screen only on sign-out
              _hasAutoNavigatedToBills = false;
              // Clear both the in-memory and persisted tab so a re-login
              // (this session or a later one) doesn't restore a tab from
              // before the sign-out - see _clearPersistedTabIndex.
              _persistedTabIndex = null;
              _clearPersistedTabIndex();
            }
            // NO auto-navigation on sign-in
          }

          // A session restored on app launch (silent sign-in) resolves
          // asynchronously, often after the first build and sometimes after
          // categories finish loading from Drive. Once everything settles into
          // a fully-configured state for the first time this launch, land on
          // Bills instead of leaving the user stuck on whichever screen was
          // shown while things were still loading. Only happens once per
          // sign-in session so it never overrides manual navigation afterwards.
          if (!_hasAutoNavigatedToBills && isSignedIn && isConfigComplete) {
            // Same restore-or-Bills logic as the fresh-login branch above -
            // this is the path a restored session usually takes, since the
            // session/household/categories lookups resolve after the first
            // build.
            _selectedIndex = _persistedTabIndex ?? 0; // Bills screen
            _hasAutoNavigatedToBills = true;
          }
        }

        // Always use the same Scaffold structure to prevent widget tree changes
        // This prevents navigation bar flickering when providers notify
        final l10n = AppLocalizations.of(context)!;
        final isLimitedNav = canNavigateToCreateCategories;
        final safeIndex = isLimitedNav
            ? ((_selectedIndex == 1 || _selectedIndex == 3)
                ? _selectedIndex
                : 1)
            : _selectedIndex;

        // Always show ConfigScreen in body when nav bar should be hidden
        // but still use Scaffold structure to prevent widget tree changes
        final bodyIndex = shouldShowNavBar
            ? safeIndex
            : 3; // Force ConfigScreen (index 3) when no nav bar

        // Notify when navigation changes (for SummaryScreen to refresh).
        // Deferred to a post-frame callback rather than set inline here:
        // this can now fire from an automatic index change during build()
        // (restoring the previously-selected tab once settled, see GH issue
        // #59), and SummaryScreen's listener kicks off a calculation that
        // calls notifyListeners() on CalculationProvider - doing that
        // synchronously while this widget's build() is still on the stack
        // put it in the middle of another build pass, and the resulting
        // calculation never ran to completion, leaving Summary's loading
        // indicator spinning forever.
        if (settled && bodyIndex != _previousBodyIndex) {
          _previousBodyIndex = bodyIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _navigationNotifier.value = bodyIndex;
            }
          });
        }

        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: bodyIndex,
                children: _screens,
              ),
              // Covers the config/bills decision until it's fully resolved
              // (see the settling check above) so it never flashes on screen.
              if (!settled)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: (settled && shouldShowNavBar)
              ? NavigationBar(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (index) {
                    if (isLimitedNav) {
                      // Limited navigation: only allow Payment Splits (1) and Config (3)
                      if (index == 1 || index == 3) {
                        setState(() {
                          _selectedIndex = index;
                        });
                        _persistedTabIndex = index;
                        _persistTabIndex(index);
                      }
                    } else {
                      // Full navigation: allow all screens
                      setState(() {
                        _selectedIndex = index;
                      });
                      _persistedTabIndex = index;
                      _persistTabIndex(index);
                    }
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(
                        Icons.receipt_long_outlined,
                        color: isLimitedNav ? Colors.grey.shade400 : null,
                      ),
                      selectedIcon: Icon(
                        Icons.receipt_long,
                        color: isLimitedNav ? Colors.grey.shade400 : null,
                      ),
                      label: l10n.bills,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      selectedIcon: const Icon(Icons.account_balance_wallet),
                      label: l10n.splitsAndCategories,
                    ),
                    NavigationDestination(
                      icon: Icon(
                        Icons.calculate_outlined,
                        color: isLimitedNav ? Colors.grey.shade400 : null,
                      ),
                      selectedIcon: Icon(
                        Icons.calculate,
                        color: isLimitedNav ? Colors.grey.shade400 : null,
                      ),
                      label: l10n.summary,
                    ),
                    NavigationDestination(
                      icon: const Icon(Icons.settings_outlined),
                      selectedIcon: const Icon(Icons.settings),
                      label: l10n.settings,
                    ),
                  ],
                )
              : null, // Hide navigation bar instead of changing widget tree
        );
      },
    );
  }
}
