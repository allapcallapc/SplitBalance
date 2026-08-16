// Widget-level coverage for ConfigScreen. ConfigProvider talks directly to
// Supabase.instance.client with no DI seam (see
// lib/providers/config_provider.dart), so a real signed-in state - and with
// it the Account/Household card split added for the household-section-split
// change - can't be driven here (same limitation documented in
// test/summary_screen_test.dart and test/main_navigation_screen_test.dart).
// This exercises everything reachable from the not-signed-in auth card:
// sign-in/sign-up mode toggling, client-side form validation, and the
// always-visible theme/language selectors.

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
import 'package:splitbalance/screens/config_screen.dart';

Future<void> pumpConfigScreen(
  WidgetTester tester, {
  required ConfigProvider configProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: configProvider),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()),
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

    await tester.tap(find.text('French'));
    await tester.pump();

    expect(configProvider.language, AppLanguage.french);
  });

  testWidgets('the "Clear All Configuration" button is hidden while signed out',
      (tester) async {
    await pumpConfigScreen(tester, configProvider: ConfigProvider());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Clear All Configuration'), findsNothing);
  });
}
