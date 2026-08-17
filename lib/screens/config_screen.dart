import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/categories_provider.dart';
import '../models/app_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../widgets/google_pay_detection_section.dart';
import '../widgets/native_credential_fields.dart';
import '../widgets/update_dialog.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _createHouseholdNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  final _joinNameController = TextEditingController();
  final _myNameController = TextEditingController();

  bool _isSignUpMode = false;
  bool _isJoinMode = false;
  bool _hasLoadedCategoriesForHousehold = false;
  bool _categoriesLoadCompleted = false;
  String? _lastLoadedCategoriesHouseholdId;
  bool _hasShownCategoryPrompt = false;
  String _appVersion = '';
  String? _inviteCode;
  bool _loadingInviteCode = false;
  bool _inviteCodeLoadFailed = false;
  String? _lastInviteCodeHouseholdId;
  String? _lastMyNameSyncedFrom;
  final _updateService = UpdateService();
  bool _checkingForUpdate = false;
  String? _updateStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (e) {
      // If version loading fails, just leave it empty
      print('Error loading app version: $e');
    }
  }

  Future<void> _checkForUpdates() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _checkingForUpdate = true;
      _updateStatusMessage = l10n.checkingForUpdates;
    });

    final update = await _updateService.checkForUpdate();

    if (!mounted) return;
    setState(() {
      _checkingForUpdate = false;
      _updateStatusMessage = update == null ? l10n.upToDate : null;
    });

    if (update != null) {
      await showUpdateAvailableDialog(context, _updateService, update);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _createHouseholdNameController.dispose();
    _joinCodeController.dispose();
    _joinNameController.dispose();
    _myNameController.dispose();
    super.dispose();
  }

  Future<void> _loadInviteCode(ConfigProvider configProvider) async {
    if (_loadingInviteCode) return;
    setState(() => _loadingInviteCode = true);
    final code = await configProvider.getInviteCode();
    if (mounted) {
      setState(() {
        _inviteCode = code;
        _loadingInviteCode = false;
        // Stop auto-retrying on failure (code == null) - without this, a
        // persistently failing fetch (e.g. a stale/invalid household id)
        // gets rescheduled on every single frame forever. The user can
        // still retry manually via the button shown below.
        _inviteCodeLoadFailed = code == null;
      });
    }
  }

  Future<void> _promptCategorySelection(ConfigProvider configProvider) async {
    if (!mounted || !configProvider.isSignedIn) return;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.category, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.createCategories)),
            ],
          ),
          content: Text(l10n.createCategoriesPrompt,
              style: const TextStyle(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'navigate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.goToCategories),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (result == 'navigate') {
      configProvider.requestNavigateToCategories();
    }
    // Either way, don't re-show automatically this session - the user can
    // always add categories from the Payment Splits tab.
  }

  Future<void> _handleAuthSubmit(ConfigProvider configProvider) async {
    if (configProvider.isLoading) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an email and password')),
      );
      return;
    }
    if (_isSignUpMode && password != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }
    final success = _isSignUpMode
        ? await configProvider.signUp(email, password)
        : await configProvider.signIn(email, password);
    // Prompts the password manager (e.g. Bitwarden) to offer saving these
    // credentials on success, or just ends the autofill session without
    // saving on failure. No-op on web, where NativeCredentialFields bypasses
    // Flutter's own autofill machinery in favor of real DOM inputs.
    TextInput.finishAutofillContext(shouldSave: success);
    if (!success && mounted && configProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(configProvider.error!)),
      );
    }
  }

  // Below this screen width the theme picker switches from a single 1x4 row
  // to a 2x2 grid so the segments don't get squeezed on small phones.
  // 600 is the standard Material breakpoint between compact and medium
  // window sizes.
  static const double _themeGridBreakpoint = 600;

  Widget _buildThemeSelector(ConfigProvider configProvider) {
    final segments = <ButtonSegment<AppThemeMode>>[
      ButtonSegment<AppThemeMode>(
        value: AppThemeMode.light,
        label: Text(AppLocalizations.of(context)!.light),
        icon: const Icon(Icons.light_mode),
      ),
      ButtonSegment<AppThemeMode>(
        value: AppThemeMode.dark,
        label: Text(AppLocalizations.of(context)!.dark),
        icon: const Icon(Icons.dark_mode),
      ),
      ButtonSegment<AppThemeMode>(
        value: AppThemeMode.pink,
        label: Text(AppLocalizations.of(context)!.pink),
        icon: const Icon(Icons.favorite),
      ),
      ButtonSegment<AppThemeMode>(
        value: AppThemeMode.teal,
        label: Text(AppLocalizations.of(context)!.teal),
        icon: const Icon(Icons.water_drop),
      ),
    ];

    void onSelectionChanged(Set<AppThemeMode> selected) {
      if (selected.isNotEmpty) {
        configProvider.setThemeMode(selected.first);
      }
    }

    final isSmallScreen =
        MediaQuery.sizeOf(context).width < _themeGridBreakpoint;

    if (isSmallScreen) {
      // Small screens: lay the 4 options out as a 2x2 grid (two rows of two
      // segments each) instead of squeezing them into one row. Stretch to
      // full width so it lines up with the Language selector below it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AppThemeMode>(
            segments: segments.sublist(0, 2),
            selected: {configProvider.themeMode}
                .intersection({segments[0].value, segments[1].value}),
            emptySelectionAllowed: true,
            onSelectionChanged: onSelectionChanged,
          ),
          const SizedBox(height: 8),
          SegmentedButton<AppThemeMode>(
            segments: segments.sublist(2, 4),
            selected: {configProvider.themeMode}
                .intersection({segments[2].value, segments[3].value}),
            emptySelectionAllowed: true,
            onSelectionChanged: onSelectionChanged,
          ),
        ],
      );
    }

    // Larger screens: keep all 4 options on a single 1x4 row.
    return SegmentedButton<AppThemeMode>(
      segments: segments,
      selected: {configProvider.themeMode},
      onSelectionChanged: onSelectionChanged,
    );
  }

  Widget _buildAuthCard(ConfigProvider configProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle,
                    color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                Text(
                  _isSignUpMode ? 'Create an account' : 'Sign in',
                  style:
                      const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            NativeCredentialFields(
              emailController: _emailController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              isSignUp: _isSignUpMode,
              onSubmit: () => _handleAuthSubmit(configProvider),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: configProvider.isLoading
                  ? null
                  : () => _handleAuthSubmit(configProvider),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: configProvider.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isSignUpMode ? 'Sign up' : 'Sign in'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: configProvider.isLoading
                  ? null
                  : () => setState(() {
                        _isSignUpMode = !_isSignUpMode;
                        _confirmPasswordController.clear();
                      }),
              child: Text(_isSignUpMode
                  ? 'Already have an account? Sign in'
                  : "Don't have an account? Sign up"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdSetupCard(ConfigProvider configProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.home,
                    color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Set up your household',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'A household is shared between the two of you. Create one, or '
              'join the one the other person already created using their '
              'invite code.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Create')),
                ButtonSegment(value: true, label: Text('Join')),
              ],
              selected: {_isJoinMode},
              onSelectionChanged: (selected) =>
                  setState(() => _isJoinMode = selected.first),
            ),
            const SizedBox(height: 16),
            if (!_isJoinMode) ...[
              TextField(
                controller: _createHouseholdNameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                  hintText: "How you'll appear in bills and splits",
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: configProvider.isLoading
                    ? null
                    : () async {
                        final name = _createHouseholdNameController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter your name')),
                          );
                          return;
                        }
                        final success =
                            await configProvider.createHousehold(name);
                        if (!success && context.mounted &&
                            configProvider.error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(configProvider.error!)),
                          );
                        }
                      },
                style:
                    ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: configProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create household'),
              ),
            ] else ...[
              TextField(
                controller: _joinCodeController,
                decoration: const InputDecoration(
                  labelText: 'Invite code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _joinNameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  border: OutlineInputBorder(),
                  hintText: "How you'll appear in bills and splits",
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: configProvider.isLoading
                    ? null
                    : () async {
                        final code = _joinCodeController.text.trim();
                        final name = _joinNameController.text.trim();
                        if (code.isEmpty || name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Enter the invite code and your name')),
                          );
                          return;
                        }
                        final success =
                            await configProvider.joinHousehold(code, name);
                        if (!success && context.mounted &&
                            configProvider.error != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(configProvider.error!)),
                          );
                        }
                      },
                style:
                    ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: configProvider.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Join household'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard(ConfigProvider configProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.account_circle,
                    color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Account',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      configProvider.currentUserEmail ?? 'Signed in',
                      style: TextStyle(
                          fontSize: 14, color: Colors.green[900]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: configProvider.isLoading
                  ? null
                  // coverage:ignore-start
                  // Widget tests can't tap this without either hanging (a
                  // real signOut() call blocks on Supabase's GoTrue auth
                  // endpoint indefinitely against the offline test project,
                  // unlike the Postgrest-backed calls elsewhere on this
                  // screen, which fail fast - see
                  // test/config_screen_test.dart) or faking the tap
                  // instead of invoking onPressed for real, which
                  // wouldn't actually exercise this line.
                  : () async {
                      await configProvider.signOut();
                    },
                  // coverage:ignore-end
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: configProvider.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(AppLocalizations.of(context)!.signOutButton),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdInfoCard(ConfigProvider configProvider) {
    final person1 = configProvider.config.person1Name;
    final person2 = configProvider.config.person2Name;
    final waitingForSecondPerson = person2.trim().isEmpty;
    final myName = configProvider.myPersonName ?? '';

    if (_myNameController.text.isEmpty ||
        _lastMyNameSyncedFrom != configProvider.householdId) {
      _myNameController.text = myName;
      _lastMyNameSyncedFrom = configProvider.householdId;
    }

    // Reset per-household bookkeeping when the household changes, so a
    // previous failure doesn't linger and block a legitimately different
    // household from ever being tried.
    if (configProvider.householdId != _lastInviteCodeHouseholdId) {
      _lastInviteCodeHouseholdId = configProvider.householdId;
      _inviteCode = null;
      _inviteCodeLoadFailed = false;
    }

    if (waitingForSecondPerson &&
        _inviteCode == null &&
        !_loadingInviteCode &&
        !_inviteCodeLoadFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadInviteCode(configProvider);
      });
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.home, color: Colors.green, size: 24),
                SizedBox(width: 12),
                Text(
                  'Household',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      waitingForSecondPerson
                          ? '$person1 (waiting for the other person to join)'
                          : '$person1 & $person2',
                      style: TextStyle(
                          fontSize: 14, color: Colors.green[900]),
                    ),
                  ),
                ],
              ),
            ),
            if (waitingForSecondPerson) ...[
              const SizedBox(height: 16),
              const Text(
                'Share this invite code with the other person so they can join:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _loadingInviteCode
                          ? '...'
                          : (_inviteCode ?? '—'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    if (_inviteCodeLoadFailed && !_loadingInviteCode) ...[
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Retry',
                        onPressed: () {
                          setState(() => _inviteCodeLoadFailed = false);
                          _loadInviteCode(configProvider);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _myNameController,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: configProvider.isLoading
                  ? null
                  : () async {
                      final name = _myNameController.text.trim();
                      if (name.isEmpty) return;
                      await configProvider.updateMyPersonName(name);
                    },
              child: const Text('Update my name'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              width: 32,
              cacheWidth: 96,
              cacheHeight: 96,
            ),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context)!.configuration),
          ],
        ),
      ),
      body: Consumer2<ConfigProvider, CategoriesProvider>(
        builder: (context, configProvider, categoriesProvider, child) {
          final householdId = configProvider.householdId;

          // Reset per-household bookkeeping when the household changes.
          if (householdId != _lastLoadedCategoriesHouseholdId) {
            _lastLoadedCategoriesHouseholdId = householdId;
            _hasLoadedCategoriesForHousehold = false;
            _categoriesLoadCompleted = false;
            _hasShownCategoryPrompt = false;
          }

          // Load categories once per household (main.dart needs this to
          // know whether the config flow is complete).
          if (configProvider.isSignedIn &&
              householdId != null &&
              !categoriesProvider.isLoading &&
              !_hasLoadedCategoriesForHousehold) {
            _hasLoadedCategoriesForHousehold = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted && configProvider.householdId == householdId) {
                await categoriesProvider.loadCategories(configProvider);
                if (mounted && configProvider.householdId == householdId) {
                  setState(() {
                    _categoriesLoadCompleted = true;
                  });
                }
              }
            });
          }

          // Only consider prompting once a load has actually finished for
          // this household - otherwise this fires on the same frame the
          // load above is merely scheduled, seeing a still-empty list that
          // hasn't been fetched yet and never gets re-checked afterwards.
          if (configProvider.isSignedIn &&
              householdId != null &&
              _categoriesLoadCompleted &&
              !categoriesProvider.isLoading &&
              categoriesProvider.categories.isEmpty &&
              !_hasShownCategoryPrompt) {
            _hasShownCategoryPrompt = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _promptCategorySelection(configProvider);
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!configProvider.isSignedIn)
                  _buildAuthCard(configProvider)
                else ...[
                  _buildAccountCard(configProvider),
                  const SizedBox(height: 16),
                  if (householdId == null)
                    _buildHouseholdSetupCard(configProvider)
                  else
                    _buildHouseholdInfoCard(configProvider),
                ],

                const SizedBox(height: 16),

                // Theme Selection Section - Available for all users
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.palette,
                              color: Theme.of(context).colorScheme.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context)!.theme,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildThemeSelector(configProvider),
                        const SizedBox(height: 24),
                        // Language Selection
                        Row(
                          children: [
                            Icon(Icons.language,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context)!.language,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<AppLanguage>(
                          segments: [
                            ButtonSegment<AppLanguage>(
                              value: AppLanguage.english,
                              label:
                                  Text(AppLocalizations.of(context)!.english),
                              icon: const Icon(Icons.flag),
                            ),
                            ButtonSegment<AppLanguage>(
                              value: AppLanguage.french,
                              label: Text(AppLocalizations.of(context)!.french),
                              icon: const Icon(Icons.flag),
                            ),
                          ],
                          selected: {configProvider.language},
                          onSelectionChanged: (Set<AppLanguage> selected) {
                            if (selected.isNotEmpty) {
                              configProvider.setLanguage(selected.first);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const GooglePayDetectionSection(),

                // App Version Display
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Version $_appVersion',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
                if (UpdateService.isSupported) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: _checkingForUpdate
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _checkForUpdates,
                            child: Text(
                              AppLocalizations.of(context)!.checkForUpdates,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                  ),
                  if (_updateStatusMessage != null)
                    Center(
                      child: Text(
                        _updateStatusMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
