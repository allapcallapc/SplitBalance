import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../models/app_config.dart';

class ConfigProvider with ChangeNotifier {
  SupabaseClient get _supabase => Supabase.instance.client;

  AppConfig _config = AppConfig(person1Name: '', person2Name: '');
  bool _isLoading = false;
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

  AppConfig get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get navigateToCategoriesRequested => _navigateToCategoriesRequested;
  bool get navigateToCategoriesTabRequested =>
      _navigateToCategoriesTabRequested;
  bool get isSignedIn => _supabase.auth.currentSession != null;
  User? get currentUser => _supabase.auth.currentUser;
  String? get householdId => _config.householdId;
  String? get myPersonName =>
      currentUser == null ? null : _memberNamesByUserId[currentUser!.id];
  AppThemeMode get themeMode => _config.themeMode;
  AppLanguage get language => _config.language;
  Locale get locale => Locale(_config.language.localeCode);

  ConfigProvider() {
    // Load config asynchronously to ensure app is fully initialized
    Future.microtask(() => _loadConfig());
    // Supabase persists sessions itself; just react to changes (sign-in,
    // sign-out, token refresh) elsewhere in the app (e.g. a second tab).
    _supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  Future<void> _loadConfig() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString('app_config');

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
      notifyListeners();
    }
  }

  // Reload config from storage (useful after save to verify), then refresh
  // household membership from the server if signed in.
  Future<void> reloadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('app_config');

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

  // Clear all configuration
  Future<void> clearAllConfig() async {
    _isLoading = true;
    notifyListeners();

    try {
      try {
        await _supabase.auth.signOut();
      } catch (e) {
        // Ignore sign out errors
      }

      // Clear all SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Reset config to default (keep language preference)
      final currentLanguage = _config.language;
      _config = AppConfig(
          person1Name: '', person2Name: '', language: currentLanguage);
      _error = null;
    } catch (e) {
      _error = 'Failed to clear configuration: $e';
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
    if (!isSignedIn || _config.householdId == null || currentUser == null) {
      return;
    }

    try {
      await _supabase
          .from('household_members')
          .update({'person_name': name})
          .eq('household_id', _config.householdId!)
          .eq('user_id', currentUser!.id);
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
    if (!isSignedIn || currentUser == null) return;

    try {
      String? id = _config.householdId;
      if (id == null) {
        final row = await _supabase
            .from('household_members')
            .select('household_id')
            .eq('user_id', currentUser!.id)
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

      final names =
          members.map((m) => m['person_name'] as String).toList();
      _memberNamesByUserId = {
        for (final m in members)
          m['user_id'] as String: m['person_name'] as String,
      };

      _config = _config.copyWith(
        householdId: id,
        person1Name: names.isNotEmpty ? names[0] : '',
        person2Name: names.length > 1 ? names[1] : '',
      );
      await _saveConfig();
    } catch (e) {
      print('Error loading household: $e');
    }
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(_config.toJson());
      final success = await prefs.setString('app_config', configJson);

      if (!success) {
        throw Exception('Failed to write to SharedPreferences');
      }

      // Verify it was saved by reading it back
      final saved = prefs.getString('app_config');
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

  Future<void> setMePersonName(String name) async {
    _config = _config.copyWith(mePersonName: name);
    await _saveConfig();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
