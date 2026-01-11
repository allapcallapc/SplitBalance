import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/config_provider.dart';
import 'providers/bills_provider.dart';
import 'providers/payment_splits_provider.dart';
import 'providers/categories_provider.dart';
import 'providers/calculation_provider.dart';
import 'screens/config_screen.dart';
import 'screens/bills_list_screen.dart';
import 'screens/payment_splits_screen.dart';
import 'screens/summary_screen.dart';
import 'models/app_config.dart';

void main() {
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
        surfaceVariant: const Color(0xFF3A3A3A), // Even lighter for cards
        onSurfaceVariant: Colors.white70,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF121212), // Very dark but not pure black
      cardTheme: CardThemeData(
        color: const Color(0xFF2D2D2D), // Lighter than scaffold for contrast
        elevation: 6, // Higher elevation for better separation
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // Improve divider contrast
      dividerColor: Colors.white.withOpacity(0.2),
      // Improve list tile contrast
      listTileTheme: ListTileThemeData(
        tileColor: const Color(0xFF2D2D2D),
        selectedTileColor: const Color(0xFF3A3A3A),
      ),
      // Improve input decoration in dark mode
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2D2D2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
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
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      scaffoldBackgroundColor: Colors.pink[50],
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
      ],
      child: Consumer<ConfigProvider>(
        builder: (context, configProvider, child) {
          return MaterialApp(
            title: 'SplitBalance',
            theme: _getThemeForMode(configProvider.themeMode),
            locale: configProvider.locale,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
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

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  bool? _wasSignedIn;
  int? _previousBodyIndex;
  late final ValueNotifier<int> _navigationNotifier = ValueNotifier<int>(0);
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const BillsListScreen(),
      const PaymentSplitsScreen(),
      SummaryScreen(navigationNotifier: _navigationNotifier),
      const ConfigScreen(),
    ];
  }

  @override
  void dispose() {
    _navigationNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigProvider, CategoriesProvider>(
      builder: (context, configProvider, categoriesProvider, child) {
        final isSignedIn = configProvider.isSignedIn;
        
        // Check if configuration flow is complete
        // Required steps: Login -> Folder -> Person Names -> Categories
        final hasFolder = configProvider.driveService.folderId != null;
        final hasPersonNames = configProvider.config.person1Name.trim().isNotEmpty &&
                               configProvider.config.person2Name.trim().isNotEmpty;
        final hasCategories = categoriesProvider.categories.isNotEmpty;
        
        // Config is complete when all steps are done
        final isConfigComplete = isSignedIn && hasFolder && hasPersonNames && hasCategories;
        
        // Allow partial navigation when person names are set (to create categories)
        final canNavigateToCreateCategories = isSignedIn && hasFolder && hasPersonNames && !hasCategories;
        
        // Determine if nav bar should be shown
        final shouldShowNavBar = isSignedIn && hasFolder && hasPersonNames;
        
        // ABSOLUTE MINIMAL: Only initialize on first build, NO auto-navigation at all
        if (_wasSignedIn == null) {
          _wasSignedIn = isSignedIn;
          if (isSignedIn && isConfigComplete) {
            _selectedIndex = 0; // Bills screen
          } else {
            _selectedIndex = 3; // Config screen
          }
        } else if (_wasSignedIn != isSignedIn) {
          _wasSignedIn = isSignedIn;
          if (!isSignedIn) {
            _selectedIndex = 3; // Config screen only on sign-out
          }
          // NO auto-navigation on sign-in
        }

        // Always use the same Scaffold structure to prevent widget tree changes
        // This prevents navigation bar flickering when providers notify
        final l10n = AppLocalizations.of(context)!;
        final isLimitedNav = canNavigateToCreateCategories;
        final safeIndex = isLimitedNav 
            ? ((_selectedIndex == 1 || _selectedIndex == 3) ? _selectedIndex : 1)
            : _selectedIndex;
        
        // Always show ConfigScreen in body when nav bar should be hidden
        // but still use Scaffold structure to prevent widget tree changes
        final bodyIndex = shouldShowNavBar ? safeIndex : 3; // Force ConfigScreen (index 3) when no nav bar
        
        // Notify when navigation changes (for SummaryScreen to refresh)
        if (bodyIndex != _previousBodyIndex) {
          _navigationNotifier.value = bodyIndex;
          _previousBodyIndex = bodyIndex;
        }
        
        return Scaffold(
          body: IndexedStack(
            index: bodyIndex,
            children: _screens,
          ),
          bottomNavigationBar: shouldShowNavBar 
              ? NavigationBar(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (index) {
                    if (isLimitedNav) {
                      // Limited navigation: only allow Payment Splits (1) and Config (3)
                      if (index == 1 || index == 3) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      }
                    } else {
                      // Full navigation: allow all screens
                      setState(() {
                        _selectedIndex = index;
                      });
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
