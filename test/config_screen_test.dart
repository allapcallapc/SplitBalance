// Widget-level coverage for ConfigScreen. ConfigProvider normally talks
// directly to Supabase.instance.client with no DI seam, which is why
// test/summary_screen_test.dart and test/main_navigation_screen_test.dart
// can only drive the not-signed-in path. ConfigProvider.forTesting (see
// lib/providers/config_provider.dart) closes that gap for this screen by
// faking the signed-in/household state directly, so the tests below cover
// both the not-signed-in auth card (sign-in/sign-up mode toggling,
// client-side form validation, the always-visible theme/language selectors)
// and the signed-in Account/Household card split.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:splitbalance/l10n/app_localizations.dart';
import 'package:splitbalance/models/app_config.dart';
import 'package:splitbalance/providers/categories_provider.dart';
import 'package:splitbalance/providers/config_provider.dart';
import 'package:splitbalance/providers/pending_payments_provider.dart';
import 'package:splitbalance/screens/config_screen.dart';

Future<void> pumpConfigScreen(
  WidgetTester tester, {
  required ConfigProvider configProvider,
  CategoriesProvider? categoriesProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider.value(
          value: categoriesProvider ?? CategoriesProvider(),
        ),
        // ConfigScreen always renders GooglePayDetectionSection, which
        // reads PendingPaymentsProvider directly - without this the whole
        // screen throws ProviderNotFoundException regardless of auth state.
        ChangeNotifierProvider(create: (_) => PendingPaymentsProvider()),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('en')],
        home: ConfigScreen(),
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
      'not signed in: shows the auth card (email/password fields) and no '
      'Account/Household sections', (tester) async {
    await pumpConfigScreen(tester, configProvider: ConfigProvider());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    // Title and submit button both read "Sign in" while not in sign-up mode.
    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm password'), findsNothing);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Household'), findsNothing);
  });

  testWidgets(
      'tapping the mode toggle switches to sign-up mode: title, submit '
      'button, and confirm-password field all update', (tester) async {
    await pumpConfigScreen(tester, configProvider: ConfigProvider());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pump();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign up'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Confirm password'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);

    // And back again.
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pump();

    expect(find.text('Sign in'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'Confirm password'), findsNothing);
  });

  testWidgets(
      'submitting sign-in with empty fields shows a validation snackbar '
      "without calling the provider", (tester) async {
    final configProvider = ConfigProvider();
    await pumpConfigScreen(tester, configProvider: configProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Enter an email and password'), findsOneWidget);
    expect(configProvider.isSignedIn, isFalse);
  });

  testWidgets(
      'submitting sign-up with mismatched passwords shows a validation '
      'snackbar without calling the provider', (tester) async {
    final configProvider = ConfigProvider();
    await pumpConfigScreen(tester, configProvider: configProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'test@example.com');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'password1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'), 'password2');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(configProvider.isSignedIn, isFalse);
  });

  testWidgets(
      'theme selector is available while signed out and updates '
      'ConfigProvider.themeMode', (tester) async {
    final configProvider = ConfigProvider();
    await pumpConfigScreen(tester, configProvider: configProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(configProvider.themeMode, AppThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pump();

    expect(configProvider.themeMode, AppThemeMode.dark);
  });

  testWidgets(
      'language selector is available while signed out and updates '
      'ConfigProvider.language', (tester) async {
    final configProvider = ConfigProvider();
    await pumpConfigScreen(tester, configProvider: configProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(configProvider.language, AppLanguage.english);

    // The language selector sits below the theme selector, past the
    // default 800x600 test viewport while signed out - scroll it into view
    // before tapping (unlike the theme selector's "Dark" segment, which is
    // high enough up to already be on-screen). Can't use pumpAndSettle to
    // wait out the scroll animation: GooglePayDetectionSection shows its
    // own CircularProgressIndicator until its platform-channel query
    // resolves, which never happens in a test environment, so its ticker
    // animates indefinitely and pumpAndSettle would hang forever (same
    // constraint documented in main_navigation_screen_test.dart).
    await tester.ensureVisible(find.text('French'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('French'));
    await tester.pump();

    expect(configProvider.language, AppLanguage.french);
  });

  testWidgets(
      'signed in without a household: shows the Account card (email, sign '
      'out) and the household setup card (create/join), not the Household '
      'card', (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserEmail: 'alice@example.com',
      currentUserId: 'user-1',
    );
    await pumpConfigScreen(tester, configProvider: configProvider);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Out'), findsOneWidget);
    expect(find.text('Set up your household'), findsOneWidget);
    expect(find.text('Household'), findsNothing);
  });

  testWidgets(
      'signed in with a household waiting for the second person: shows the '
      'Account card and a Household card with the fetched invite code',
      (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserEmail: 'alice@example.com',
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: '',
      ),
      memberNamesByUserId: const {'user-1': 'Alice'},
      getInviteCode: () async => 'AB12CD',
    );
    await pumpConfigScreen(
      tester,
      configProvider: configProvider,
      // Non-empty on purpose: an empty result triggers ConfigScreen's
      // "create some categories?" prompt dialog, an unrelated flow this
      // test isn't exercising.
      categoriesProvider: CategoriesProvider(
        fetchCategories: ({required householdId}) async => const [
          {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Alice (waiting for the other person to join)'),
        findsOneWidget);
    expect(find.text('AB12CD'), findsOneWidget);
  });

  testWidgets(
      'signed in with a complete household: shows the Account card and a '
      "Household card with both names and the current user's name "
      'pre-filled', (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserEmail: 'alice@example.com',
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
      memberNamesByUserId: const {'user-1': 'Alice', 'user-2': 'Bob'},
    );
    await pumpConfigScreen(
      tester,
      configProvider: configProvider,
      // Non-empty on purpose: an empty result triggers ConfigScreen's
      // "create some categories?" prompt dialog, an unrelated flow this
      // test isn't exercising.
      categoriesProvider: CategoriesProvider(
        fetchCategories: ({required householdId}) async => const [
          {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Alice & Bob'), findsOneWidget);

    final nameField = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Your name'));
    expect(nameField.controller?.text, 'Alice');
  });

  testWidgets(
      'the Account card shows a spinner and disables the sign-out button '
      'while ConfigProvider.isLoading is true', (tester) async {
    // A complete household (rather than the default no-household state)
    // keeps the household-setup card's own isLoading-gated "Create
    // household" spinner button off screen, so the sign-out button's
    // spinner is the only new one this test needs to reason about.
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserEmail: 'alice@example.com',
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
      memberNamesByUserId: const {'user-1': 'Alice', 'user-2': 'Bob'},
    );
    await pumpConfigScreen(
      tester,
      configProvider: configProvider,
      categoriesProvider: CategoriesProvider(
        fetchCategories: ({required householdId}) async => const [
          {'id': 'cat-1', 'name': 'Groceries', 'icon': null},
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final spinnerInButton = find.descendant(
      of: find.byType(ElevatedButton),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinnerInButton, findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Sign Out'), findsOneWidget);

    // Driven directly via setLoadingForTesting rather than a real
    // isLoading-setting operation (signOut, createHousehold, ...): a real
    // network call's timing can't be relied on to still be in flight by
    // the next pump (CI showed both a hang against the GoTrue auth
    // endpoint and, going the other way, an RPC call that had already
    // failed by the time of the very next pump) - matches
    // CalculationProvider.setCalculating's existing use for the same kind
    // of assertion in test/summary_screen_test.dart.
    configProvider.setLoadingForTesting(true);
    await tester.pump();

    expect(spinnerInButton, findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Sign Out'), findsNothing);
    final signOutButton = tester.widget<ElevatedButton>(
      find.ancestor(of: spinnerInButton, matching: find.byType(ElevatedButton)),
    );
    expect(signOutButton.onPressed, isNull);

    configProvider.setLoadingForTesting(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      "currentUserEmail and myPersonName fall back to reading Supabase's "
      "real auth client when not using ConfigProvider.forTesting's "
      'override (both null while signed out, since nothing more than the '
      'real branch itself is reachable without a live Supabase session)',
      (tester) async {
    final configProvider = ConfigProvider();

    expect(configProvider.currentUserEmail, isNull);
    expect(configProvider.myPersonName, isNull);

    // Flush the constructor's background _loadConfig() microtask so
    // nothing is left pending past the end of the test.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'updateMyPersonName falls back to the real Supabase update when not '
      'using the override-only test double, and safely records the '
      'failure instead of throwing (offline test environment)',
      (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
    );

    await configProvider.updateMyPersonName('New Name');

    expect(configProvider.error, isNotNull);
  });

  testWidgets(
      'reloadHouseholdMembers falls back to the real Supabase household '
      'lookup and safely completes instead of throwing (offline test '
      'environment)', (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserId: 'user-1',
    );

    await configProvider.reloadHouseholdMembers();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'CategoriesProvider.loadCategories falls back to the real Supabase '
      'query when no fetchCategories override is given, and safely '
      'records the failure instead of throwing (offline test environment)',
      (tester) async {
    final configProvider = ConfigProvider.forTesting(
      isSignedIn: true,
      currentUserId: 'user-1',
      config: AppConfig(
        householdId: 'household-1',
        person1Name: 'Alice',
        person2Name: 'Bob',
      ),
    );
    final categoriesProvider = CategoriesProvider();

    await categoriesProvider.loadCategories(configProvider);

    expect(categoriesProvider.categories, isEmpty);
    expect(categoriesProvider.error, isNotNull);
  });
}
