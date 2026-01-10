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
        surfaceContainerHighest: const Color(0xFF3A3A3A), // Even lighter for cards
        surfaceContainer: const Color(0xFF2D2D2D), // Medium surface
        onSurface: Colors.white,
        // Ensure cards stand out more
        surfaceVariant: const Color(0xFF2D2D2D),
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
  int? _previousSelectedIndex; // Track previous index to detect navigation
  bool? _wasSignedIn;
  bool _hasPersonNames = false; // Track if person names have been set
  bool _autoSwitchedToCategories = false; // Track if we've already auto-switched to categories screen
  bool? _wasConfigComplete; // Track previous config completion state to detect transitions

  final List<Widget> _screens = const [
    BillsListScreen(),
    PaymentSplitsScreen(),
    SummaryScreen(),
    ConfigScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer2<ConfigProvider, CategoriesProvider>(
      builder: (context, configProvider, categoriesProvider, child) {
        // Save the current index value for comparison (before any changes in this build)
        // This represents the index from the previous build
        final previousIndexForComparison = _previousSelectedIndex ?? _selectedIndex;
        
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
        // Payment Splits & Categories screen should be accessible even without categories
        final canNavigateToCreateCategories = isSignedIn && hasFolder && hasPersonNames && !hasCategories;
        
        // Detect when person names are first set (transition from false to true)
        final personNamesJustSet = hasPersonNames && !_hasPersonNames;
        
        // Reset auto-switch flag if categories are added (configuration becomes complete)
        if (hasCategories && _autoSwitchedToCategories) {
          _autoSwitchedToCategories = false;
        }
        
        // Update tracking state
        _hasPersonNames = hasPersonNames;

        // When transitioning from not signed in to signed in, reset to Config screen
        if (_wasSignedIn == false && isSignedIn) {
          // User just signed in - stay on config screen until flow is complete
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedIndex = 3; // Config screen is at index 3
                _wasSignedIn = true;
                // Reset auto-switch flag when signing in
                _autoSwitchedToCategories = false;
              });
            }
          });
        } else if (_wasSignedIn == null) {
          // First build - initialize the state
          _wasSignedIn = isSignedIn;
          _wasConfigComplete = isConfigComplete; // Initialize config completion state
          if (isSignedIn && isConfigComplete) {
            _selectedIndex = 0; // Bills screen
          } else {
            _selectedIndex = 3; // Config screen
          }
          _previousSelectedIndex = _selectedIndex; // Initialize previous index
        } else if (_wasSignedIn != isSignedIn) {
          // Sign-in state changed
          _wasSignedIn = isSignedIn;
          if (!isSignedIn) {
            // User signed out - show config screen
            _selectedIndex = 3; // Config screen
            _autoSwitchedToCategories = false; // Reset flag on sign out
          } else if (isConfigComplete) {
            // User signed in and config is complete - switch to Bills screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedIndex = 0; // Bills screen
                  _autoSwitchedToCategories = false; // Reset flag when config is complete
                });
              }
            });
          } else {
            // User signed in but config not complete - stay on config screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _selectedIndex = 3; // Config screen
                });
              }
            });
          }
        }
        
        // If config becomes complete (transitions from incomplete to complete), switch to Bills screen
        // BUT only if we're on the Config screen as part of the setup flow (not manual navigation to Settings)
        // Check if config just transitioned from incomplete to complete (skip if _wasConfigComplete is null on first build)
        // Also check that user was already on Config screen (not navigating to it)
        if (_wasConfigComplete != null && _wasConfigComplete == false && isConfigComplete && 
            _selectedIndex == 3 && previousIndexForComparison == 3 && _wasSignedIn == true) {
          // Only auto-redirect during initial setup flow when already on Config screen, 
          // not when user manually navigates to Settings from another screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedIndex = 0; // Bills screen
              });
            }
          });
        }
        
        // Update the previous config completion state for the next build
        // (Already initialized on first build in the _wasSignedIn == null branch)
        if (_wasConfigComplete != null || _wasSignedIn != null) {
          _wasConfigComplete = isConfigComplete;
        }
        
        // If config becomes incomplete, switch to Config screen
        // BUT: Allow user to stay on Payment Splits screen (index 1) if they're creating categories
        // Only force navigation to Config screen if:
        // 1. Config is incomplete (missing folder or person names, not just categories)
        // 2. User is not on Payment Splits screen (index 1) where they can create categories
        if (!isConfigComplete && _selectedIndex != 3 && isSignedIn && !canNavigateToCreateCategories) {
          // Config is incomplete due to missing folder or person names (not just categories)
          // Force navigation to Config screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedIndex = 3; // Config screen
              });
            }
          });
        }

        // Update the previous selected index before returning
        // This captures any direct changes to _selectedIndex made during the build
        _previousSelectedIndex = _selectedIndex;

        // If not signed in, show only the config screen (no navigation bar)
        // This forces the user to sign in before accessing any other pages
        if (!isSignedIn) {
          return const ConfigScreen();
        }

        // If folder or person names are missing, show only the config screen (no navigation bar)
        // This forces the user to complete: Login -> Folder -> Person Names
        if (!hasFolder || !hasPersonNames) {
          return const ConfigScreen();
        }

        // If person names are set but categories are missing, show limited navigation
        // Allow access to Payment Splits & Categories screen to create categories
        if (canNavigateToCreateCategories) {
          // Check if navigation to categories was requested (from "Go to Categories" button)
          if (configProvider.navigateToCategoriesRequested) {
            // User clicked "Go to Categories" button - navigate to Payment Splits screen
            // Clear the flag first to prevent multiple triggers, then navigate
            final shouldNavigate = configProvider.navigateToCategoriesRequested;
            configProvider.clearNavigateToCategoriesRequest();
            
            if (shouldNavigate && _selectedIndex == 3) {
              // Use post-frame callback to ensure dialog is fully closed before navigation
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _selectedIndex = 1; // Payment Splits & Categories screen
                  });
                }
              });
            }
          }
          // Only auto-switch from Config screen to Payment Splits screen ONCE when person names are first set
          // This prevents flickering caused by repeated rebuilds
          else if (personNamesJustSet && _selectedIndex == 3 && !_autoSwitchedToCategories) {
            _autoSwitchedToCategories = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && canNavigateToCreateCategories && _selectedIndex == 3) {
                setState(() {
                  _selectedIndex = 1; // Payment Splits & Categories screen
                });
              }
            });
          }
          
          // Map allowed indices: 1 (Payment Splits) and 3 (Config) are allowed
          // Prevent access to 0 (Bills) and 2 (Summary)
          // If we just navigated to index 1, use it; otherwise default to current selection or 1
          // Ensure we don't force back to Config screen if user is on Payment Splits
          final safeIndex = (_selectedIndex == 1 || _selectedIndex == 3) ? _selectedIndex : 1;
          final l10n = AppLocalizations.of(context)!;
          
          return Scaffold(
            body: IndexedStack(
              index: safeIndex,
              children: _screens,
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: safeIndex,
              onDestinationSelected: (index) {
                // Only allow navigation to Payment Splits (1) and Config (3) screens
                // Bills (0) and Summary (2) are disabled when categories are missing
                if (index == 1) {
                  // Payment Splits & Categories - allowed
                  setState(() {
                    _selectedIndex = 1;
                  });
                } else if (index == 3) {
                  // Config screen - allowed
                  setState(() {
                    _selectedIndex = 3;
                  });
                } else {
                  // Bills (0) or Summary (2) - disabled when no categories exist
                  // Navigation is prevented - buttons appear visually disabled (grey icons)
                  // User must create categories first before accessing these screens
                  // Do not change selected index - stay on current screen
                }
              },
              destinations: [
                // Bills - disabled when no categories
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined, 
                    color: Colors.grey.shade400), // Visually disabled
                  selectedIcon: Icon(Icons.receipt_long, 
                    color: Colors.grey.shade400), // Visually disabled
                  label: l10n.bills,
                ),
                // Payment Splits & Categories - enabled
                NavigationDestination(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: const Icon(Icons.account_balance_wallet),
                  label: l10n.splitsAndCategories,
                ),
                // Summary - disabled when no categories
                NavigationDestination(
                  icon: Icon(Icons.calculate_outlined, 
                    color: Colors.grey.shade400), // Visually disabled
                  selectedIcon: Icon(Icons.calculate, 
                    color: Colors.grey.shade400), // Visually disabled
                  label: l10n.summary,
                ),
                // Settings - enabled
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: l10n.settings,
                ),
              ],
            ),
          );
        }

        // If configuration is complete, show full navigation with all screens
        // Only allow access to other screens when all steps are done
        final l10n = AppLocalizations.of(context)!;
        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              // Only allow navigation if config is complete
              if (isConfigComplete) {
                setState(() {
                  _selectedIndex = index;
                });
              } else {
                // If config becomes incomplete during navigation, switch to config screen
                setState(() {
                  _selectedIndex = 3; // Config screen
                });
              }
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long),
                label: l10n.bills,
              ),
              NavigationDestination(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: const Icon(Icons.account_balance_wallet),
                label: l10n.splitsAndCategories,
              ),
              NavigationDestination(
                icon: const Icon(Icons.calculate_outlined),
                selectedIcon: const Icon(Icons.calculate),
                label: l10n.summary,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: l10n.settings,
              ),
            ],
          ),
        );
      },
    );
  }
}
