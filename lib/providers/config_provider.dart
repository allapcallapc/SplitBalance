import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../config/supabase_config.dart';
import '../models/app_config.dart';

class ConfigProvider with ChangeNotifier {
  SupabaseClient get _supabase => Supabase.instance.client;

  // Namespaced by the active Supabase project so this cache never leaks
  // across environments - e.g. testing a PR preview (staging project)
  // right after using the production site, both served from the same
  // GitHub Pages origin, would otherwise read back a householdId that
  // only exists in the other project's database. See the stale-household
  // check in _loadHousehold for the other half of this.
  String get _configStorageKey => 'app_config:${SupabaseConfig.url}';

  AppConfig _config = AppConfig(person1Name: '', person2Name: '');
  bool _isLoading = false;
  bool _initialLoadComplete = false;
  String? _error;
  bool _navigateToCategoriesRequested =
      false; // Flag to request navigation to categories screen
  bool _navigateToCategoriesTabRequested =
      false; // Flag to request navigation to Categories tab (index 1) within Payment Splits screen
  // Maps auth user id -> person_name for the current household's members,
  // so the UI can tell which of person1Name/person2Name belongs to whoever
  // is currently logged in (person1Name/person2Name are ordered by
  // join-order, not by "is this me").
  Map<String, String> _memberNamesByUserId = {};

  // Auth state normally comes straight from Supabase.instance.client, which
  // has no DI seam of its own. ConfigProvider.forTesting sets these instead
  // so widget tests can drive the signed-in UI (including household state)
  // without a real Supabase session - see isSignedIn/currentUserEmail/
  // _currentUserId below, which prefer these when set.
  final bool? _isSignedInOverride;
  final String? _currentUserEmailOverride;
  final String? _currentUserIdOverride;
  final Future<String?> Function()? _getInviteCodeOverride;

  AppConfig get config => _config;
  bool get isLoading => _isLoading;
  // True until the persisted session/config/household lookup that runs once
  // at app boot has resolved. The UI uses this to hold on a splash screen
  // instead of briefly showing the config screen before switching to bills
  // once the restored session turns out to be fully configured.
  bool get isInitializing => !_initialLoadComplete;
  String? get error => _error;
  bool get navigateToCategoriesRequested => _navigateToCategoriesRequested;
  bool get navigateToCategoriesTabRequested =>
      _navigateToCategoriesTabRequested;
  bool get isSignedIn =>
      _isSignedInOverride ?? (_supabase.auth.currentSession != null);
  String? get currentUserEmail => _isSignedInOverride != null
      ? _currentUserEmailOverride
      : _supabase.auth.currentUser?.email;
  String? get _currentUserId => _isSignedInOverride != null
      ? _currentUserIdOverride
      : _supabase.auth.currentUser?.id;
  String? get householdId => _config.householdId;
  String? get myPersonName =>
      _currentUserId == null ? null : _memberNamesByUserId[_currentUserId];
  AppThemeMode get themeMode => _config.themeMode;
  AppLanguage get language => _config.language;
  Locale get locale => Locale(_config.language.localeCode);

  ConfigProvider()
      : _isSignedInOverride = null,
        _currentUserEmailOverride = null,
        _currentUserIdOverride = null,
        _getInviteCodeOverride = null {
    // Load config asynchronously to ensure app is fully initialized
    Future.microtask(() => _loadConfig());
    // Supabase persists sessions itself; just react to changes (sign-in,
    // sign-out, token refresh) elsewhere in the app (e.g. a second tab).
    _supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  // Test-only constructor that fakes a signed-in (or not) session and
  // household state without touching Supabase.instance.client - the real
  // constructor's only other option, which requires a live/mocked backend.
  // Skips _loadConfig and the auth-state subscription entirely, so no
  // Supabase call happens unless a test goes on to invoke a method like
  // signOut() or getInviteCode() that necessarily needs the real client.
  @visibleForTesting
  ConfigProvider.forTesting({
    required bool isSignedIn,
    String? currentUserEmail,
    String? currentUserId,
    AppConfig? config,
    Map<String, String> memberNamesByUserId = const {},
    Future<String?> Function()? getInviteCode,
  })  : _isSignedInOverride = isSignedIn,
        _currentUserEmailOverride = currentUserEmail,
        _currentUserIdOverride = currentUserId,
        _getInviteCodeOverride = getInviteCode {
    _config = config ?? AppConfig(person1Name: '', person2Name: '');
    _memberNamesByUserId = memberNamesByUserId;
    _initialLoadComplete = true;
  }

  Future<void> _loadConfig() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configStorageKey);

      if (configJson != null && configJson.isNotEmpty) {
        try {
          _config = AppConfig.fromJson(jsonDecode(configJson));
        } catch (e) {
          print('Error parsing config JSON: $e, JSON: $configJson');
          _config = AppConfig(person1Name: '', person2Name: '');
        }
      } else {
        _config = AppConfig(person1Name: '', person2Name: '');
      }

      // Supabase.initialize() (called in main.dart before runApp) already
      // recovers any persisted session from local storage, so there's no
      // manual silent sign-in step needed here - isSignedIn already
      // reflects the restored session by the time this provider builds.
      if (isSignedIn) {
        await _loadHousehold();
      }

      _error = null;
    } catch (e) {
      _error = 'Failed to load config: $e';
      print('Error loading config: $e');
    } finally {
      _isLoading = false;
      _initialLoadComplete = true;
      notifyListeners();
    }
  }

  // Reload config from storage (useful after save to verify), then refresh
  // household membership from the server if signed in.
  Future<void> reloadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_configStorageKey);

    if (configJson != null && configJson.isNotEmpty) {
      try {
        final loadedConfig = AppConfig.fromJson(jsonDecode(configJson));
        _config = _config.copyWith(householdId: loadedConfig.householdId);
      } catch (e) {
        print('Error parsing config JSON during reload: $e');
      }
    }

    if (isSignedIn && _config.householdId != null) {
      await _loadHousehold();
    }

    notifyListeners();
  }

  // Force reload household member names from Supabase (useful after
  // sign-in, creating/joining a household, or a member renaming themself)
  Future<void> reloadHouseholdMembers() async {
    await _loadHousehold();
    notifyListeners();
  }

  // Request navigation to categories screen (used when user clicks "Go to Categories" button)
  void requestNavigateToCategories() {
    _navigateToCategoriesRequested = true;
    _navigateToCategoriesTabRequested =
        true; // Also request to navigate to Categories tab
    notifyListeners();
  }

  // Clear navigation request flag (called by main.dart after handling navigation)
  void clearNavigateToCategoriesRequest() {
    _navigateToCategoriesRequested = false;
    notifyListeners();
  }

  // Clear Categories tab navigation request flag (called by Payment Splits screen after switching tabs)
  void clearNavigateToCategoriesTabRequest() {
    _navigateToCategoriesTabRequested = false;
    notifyListeners();
  }

  Future<bool> signUp(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response =
          await _supabase.auth.signUp(email: email, password: password);
      if (response.user == null) {
        _error = 'Sign up failed. Please try again.';
        return false;
      }
      if (response.session == null) {
        // Project has email confirmation enabled - the account exists but
        // isn't usable until the user clicks the link in their inbox.
        _error = 'Check your email to confirm your account, then sign in.';
        return false;
      }
      _error = null;
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Sign up error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _supabase.auth
          .signInWithPassword(email: email, password: password);
      if (response.user == null) {
        _error = 'Sign in was unsuccessful. Please try again.';
        return false;
      }

      await _loadHousehold();
      _error = null;
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Sign in error: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _supabase.auth.signOut();
      // Built directly (not via copyWith) so householdId/person names are
      // actually cleared - copyWith's `x ?? this.x` pattern can't null out
      // a field once set. Device-local prefs (language/theme/mePersonName)
      // are preserved since they're independent of who's logged in.
      _config = AppConfig(
        person1Name: '',
        person2Name: '',
        themeMode: _config.themeMode,
        language: _config.language,
        mePersonName: _config.mePersonName,
      );
      _memberNamesByUserId = {};
      await _saveConfig();
      _error = null;
    } catch (e) {
      _error = 'Sign out error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new household and join it as its first member.
  Future<bool> createHousehold(String personName) async {
    if (!isSignedIn) {
      _error = 'Not signed in';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final id = await _supabase
          .rpc('create_household', params: {'name': personName}) as String;
      _config = _config.copyWith(
        householdId: id,
        person1Name: personName,
        person2Name: '',
      );
      await _saveConfig();
      _error = null;
      return true;
    } catch (e) {
      _error = 'Failed to create household: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Join an existing household using the invite code the other person shared.
  Future<bool> joinHousehold(String inviteCode, String personName) async {
    if (!isSignedIn) {
      _error = 'Not signed in';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final id = await _supabase.rpc('join_household', params: {
        'code': inviteCode.trim(),
        'name': personName,
      }) as String;
      _config = _config.copyWith(householdId: id);
      await _saveConfig();
      await _loadHousehold();
      _error = null;
      return true;
    } catch (e) {
      _error = 'Failed to join household: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch the current household's invite code, to share with the other person.
  Future<String?> getInviteCode() async {
    if (_getInviteCodeOverride != null) return _getInviteCodeOverride!();
    if (_config.householdId == null) return null;
    try {
      final row = await _supabase
          .from('households')
          .select('invite_code')
          .eq('id', _config.householdId!)
          .single();
      return row['invite_code'] as String?;
    } catch (e) {
      print('Error fetching invite code: $e');
      return null;
    }
  }

  // Update the current user's own display name within the household.
  Future<void> updateMyPersonName(String name) async {
    final userId = _currentUserId;
    if (!isSignedIn || _config.householdId == null || userId == null) {
      return;
    }

    try {
      await _supabase
          .from('household_members')
          .update({'person_name': name})
          .eq('household_id', _config.householdId!)
          .eq('user_id', userId);
      await _loadHousehold();
      _error = null;
    } catch (e) {
      _error = 'Failed to update name: $e';
    }
    notifyListeners();
  }

  // Load household membership (id + both people's names) from Supabase.
  // Falls back to discovering the household from household_members when no
  // household id is cached locally yet (e.g. fresh install, cache cleared).
  Future<void> _loadHousehold() async {
    final userId = _currentUserId;
    if (!isSignedIn || userId == null) return;

    try {
      String? id = _config.householdId;
      if (id == null) {
        final row = await _supabase
            .from('household_members')
            .select('household_id')
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle();
        id = row?['household_id'] as String?;
        if (id == null) {
          // Not part of a household yet - nothing more to load.
          return;
        }
      }

      final members = await _supabase
          .from('household_members')
          .select('user_id, person_name, joined_at')
          .eq('household_id', id)
          .order('joined_at', ascending: true);

      _config = applyHouseholdMembers(_config, id, members);
      if (members.isEmpty) {
        _memberNamesByUserId = {};
        await _saveConfig();
        return;
      }

      _memberNamesByUserId = {
        for (final m in members)
          m['user_id'] as String: m['person_name'] as String,
      };
      await _saveConfig();
    } catch (e) {
      print('Error loading household: $e');
    }
  }

  // RLS only returns household_members rows for households the caller is
  // actually a member of, so an empty result here means the id passed in
  // doesn't correspond to a real membership for this user/environment
  // (e.g. a leftover id from a different Supabase project - see
  // _configStorageKey above). Resets instead of getting stuck treating a
  // bogus id as a real household. Extracted as a pure function (no
  // Supabase/auth dependency) so this branching is directly unit
  // testable - see _loadHousehold above for the query that feeds it.
  @visibleForTesting
  static AppConfig applyHouseholdMembers(
    AppConfig current,
    String householdId,
    List<Map<String, dynamic>> members,
  ) {
    if (members.isEmpty) {
      return AppConfig(
        person1Name: '',
        person2Name: '',
        themeMode: current.themeMode,
        language: current.language,
        mePersonName: current.mePersonName,
      );
    }

    final names = members.map((m) => m['person_name'] as String).toList();
    return current.copyWith(
      householdId: householdId,
      person1Name: names.isNotEmpty ? names[0] : '',
      person2Name: names.length > 1 ? names[1] : '',
    );
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(_config.toJson());
      final success = await prefs.setString(_configStorageKey, configJson);

      if (!success) {
        throw Exception('Failed to write to SharedPreferences');
      }

      // Verify it was saved by reading it back
      final saved = prefs.getString(_configStorageKey);
      if (saved == null || saved != configJson) {
        throw Exception('Config was not saved correctly');
      }

      _error = null;
      notifyListeners(); // Notify listeners after saving
    } catch (e) {
      _error = 'Failed to save config: $e';
      print('Error saving config: $e');
      notifyListeners();
    }
  }

  Future<void> setThemeMode(AppThemeMode themeMode) async {
    _config = _config.copyWith(themeMode: themeMode);
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    _config = _config.copyWith(language: language);
    await _saveConfig();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
