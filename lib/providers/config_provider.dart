import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import '../models/app_config.dart';
import '../services/google_drive_service.dart';
import '../services/csv_service.dart';

class ConfigProvider with ChangeNotifier {
  final GoogleDriveService _driveService = GoogleDriveService();
  AppConfig _config = AppConfig(person1Name: '', person2Name: '');
  bool _isLoading = false;
  String? _error;
  String? _restoreError; // Error from automatic session restoration
  String? _restoreErrorDetails; // Detailed error information
  bool _navigateToCategoriesRequested = false; // Flag to request navigation to categories screen
  bool _navigateToCategoriesTabRequested = false; // Flag to request navigation to Categories tab (index 1) within Payment Splits screen

  AppConfig get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get restoreError => _restoreError;
  String? get restoreErrorDetails => _restoreErrorDetails;
  bool get navigateToCategoriesRequested => _navigateToCategoriesRequested;
  bool get navigateToCategoriesTabRequested => _navigateToCategoriesTabRequested;
  GoogleDriveService get driveService => _driveService;
  bool get isSignedIn => _driveService.isSignedIn;
  GoogleSignInAccount? get currentUser => _driveService.currentUser;
  AppThemeMode get themeMode => _config.themeMode;
  AppLanguage get language => _config.language;
  Locale get locale => Locale(_config.language.localeCode);

  ConfigProvider() {
    // Load config asynchronously to ensure app is fully initialized
    Future.microtask(() => _loadConfig());
  }

  Future<void> _loadConfig() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Log configuration status for debugging
      print('=== ConfigProvider: Loading configuration ===');
      if (kIsWeb) {
        print('Running on Web platform');
      } else {
        print('Running on ${defaultTargetPlatform.toString()} platform');
      }
      
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString('app_config');
      
      if (configJson != null && configJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(configJson);
          _config = AppConfig.fromJson(decoded);
          
          // Restore folder ID if available
          if (_config.googleDriveFolderId != null && _config.googleDriveFolderId!.isNotEmpty) {
            _driveService.setFolderId(_config.googleDriveFolderId!);
            
            // Try to load person names from Drive folder if signed in
            // Note: If not signed in yet, we'll load person names after sign-in is restored
            if (isSignedIn) {
              await _loadPersonNamesFromDrive();
            }
          }
          
          print('Config loaded: Person1=${_config.person1Name}, Person2=${_config.person2Name}, Folder=${_config.googleDriveFolderId}');
        } catch (e) {
          print('Error parsing config JSON: $e, JSON: $configJson');
          // If parsing fails, use defaults
          _config = AppConfig(person1Name: '', person2Name: '');
        }
      } else {
        // No saved config, use defaults
        _config = AppConfig(person1Name: '', person2Name: '');
        print('No saved config found, using defaults');
      }

      // Silent sign-in removed - users must sign in explicitly
      // Clear any restore errors since we're not attempting restoration
      _restoreError = null;
      _restoreErrorDetails = null;
      _error = null;
    } catch (e) {
      _error = 'Failed to load config: $e';
      print('Error loading config: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Reload config from storage (useful after save to verify)
  // This reloads from SharedPreferences and then from Drive if signed in
  Future<void> reloadConfig() async {
    // Load from SharedPreferences first
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString('app_config');
    
    if (configJson != null && configJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(configJson);
        final loadedConfig = AppConfig.fromJson(decoded);
        
        // Restore folder ID if available
        if (loadedConfig.googleDriveFolderId != null && loadedConfig.googleDriveFolderId!.isNotEmpty) {
          _driveService.setFolderId(loadedConfig.googleDriveFolderId!);
          _config = _config.copyWith(googleDriveFolderId: loadedConfig.googleDriveFolderId);
        }
        
        // If signed in and folder is selected, load person names from Drive (folder-specific data)
        // Otherwise, use person names from SharedPreferences
        if (isSignedIn && _driveService.folderId != null && _driveService.folderId!.isNotEmpty) {
          // Load from Drive - this will update config with Drive person names
          await _loadPersonNamesFromDrive();
          // Note: _loadPersonNamesFromDrive already updates _config and saves to SharedPreferences
        } else {
          // Not signed in or no folder - use SharedPreferences values
          _config = _config.copyWith(
            person1Name: loadedConfig.person1Name,
            person2Name: loadedConfig.person2Name,
          );
        }
      } catch (e) {
        print('Error parsing config JSON during reload: $e');
      }
    }
    
    notifyListeners();
  }
  
  // Force reload person names from Drive (useful after sign-in or folder selection)
  Future<void> reloadPersonNamesFromDrive() async {
    await _loadPersonNamesFromDrive();
    notifyListeners();
  }
  
  // Request navigation to categories screen (used when user clicks "Go to Categories" button)
  void requestNavigateToCategories() {
    _navigateToCategoriesRequested = true;
    _navigateToCategoriesTabRequested = true; // Also request to navigate to Categories tab
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

  Future<bool> signIn() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _driveService.signIn();
      if (!success) {
        _error = 'Sign in was cancelled. Please try again.';
        _isLoading = false;
        notifyListeners();
        // Clear sign-in flag
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('was_signed_in', false);
        return false;
      }

      // Save sign-in state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('was_signed_in', true);
      // Clear last restore attempt time so we can restore on next page load if needed
      await prefs.remove('last_restore_attempt_time');
      
      // Clear any previous errors (including restore errors)
      _error = null;
      _restoreError = null;
      _restoreErrorDetails = null;
      
      // After successful sign-in, load person names from Drive folder if folder is selected
      await _loadPersonNamesFromDrive();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      final errorMessage = e.toString();
      
      // Provide helpful error messages
      if (errorMessage.contains('popup_closed_by_user')) {
        _error = 'Sign in was cancelled. Please try again.';
      } else if (errorMessage.contains('network_error') || errorMessage.contains('network')) {
        _error = 'Network error. Please check your internet connection and try again.';
      } else if (errorMessage.contains('access_denied')) {
        _error = 'Access denied. Please grant the necessary permissions.';
      } else if (errorMessage.contains('redirect_uri_mismatch') || errorMessage.contains('redirect')) {
        _error = 'Configuration Error: Redirect URI mismatch.\n\nIn Google Cloud Console, edit your OAuth Client ID and add:\n\nAuthorized JavaScript origins:\n• http://localhost:8080\n• http://127.0.0.1:8080\n\nAuthorized redirect URIs:\n• http://localhost:8080\n• http://localhost:8080/\n• http://127.0.0.1:8080\n• http://127.0.0.1:8080/\n\nThen click SAVE and try again.';
      } else if (errorMessage.contains('origin') || errorMessage.contains('JavaScript') || errorMessage.contains('origins')) {
        _error = 'Configuration Error: JavaScript origin not authorized.\n\nIn Google Cloud Console:\n1. Edit your OAuth 2.0 Client ID (Web application)\n2. Under "Authorized JavaScript origins", add:\n   • http://localhost:8080\n   • http://127.0.0.1:8080\n3. Under "Authorized redirect URIs", add:\n   • http://localhost:8080\n   • http://localhost:8080/\n   • http://127.0.0.1:8080\n   • http://127.0.0.1:8080/\n4. Click SAVE and wait a few seconds\n5. Try signing in again';
      } else if (errorMessage.contains('invalid_client') || errorMessage.contains('client_id')) {
        _error = 'Configuration Error: Invalid or missing Client ID.\n\nPlease:\n1. Verify your Client ID in lib/config/google_sign_in_config.dart\n2. Verify web/index.html meta tag has the same Client ID\n3. Make sure you created a "Web application" OAuth client ID';
      } else if (errorMessage.contains('popup_blocked') || errorMessage.contains('popup')) {
        _error = 'Popup blocked! Please allow popups for this site and try again.';
      } else {
        _error = 'Sign in error: $errorMessage\n\nCommon fixes:\n1. Add http://localhost:8080 to "Authorized JavaScript origins"\n2. Add redirect URIs to "Authorized redirect URIs"\n3. Enable Google Drive API\n4. Wait a few seconds after saving changes';
      }
      
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _driveService.signOut();
      _config = _config.copyWith(googleDriveFolderId: null);
      // Clear sign-in flag
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('was_signed_in', false);
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
      // Sign out from Google if signed in
      try {
        await _driveService.signOut();
      } catch (e) {
        // Ignore sign out errors
      }

      // Clear all SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Reset config to default (keep language preference)
      final currentLanguage = _config.language;
      _config = AppConfig(person1Name: '', person2Name: '', language: currentLanguage);
      _error = null;
    } catch (e) {
      _error = 'Failed to clear configuration: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setPersonNames(String person1Name, String person2Name) async {
    _config = _config.copyWith(
      person1Name: person1Name,
      person2Name: person2Name,
    );
    await _saveConfig();
    
    // Also save person names to Drive folder if folder is selected and signed in
    if (isSignedIn && _driveService.folderId != null && 
        (person1Name.isNotEmpty || person2Name.isNotEmpty)) {
      try {
        final csvContent = CsvService.personNamesToCsv(person1Name, person2Name);
        await _driveService.uploadPersonNames(csvContent);
        print('Person names saved to Drive folder');
      } catch (e) {
        print('Error saving person names to Drive: $e');
        // Don't throw error - local save succeeded, Drive save is secondary
        // But we should still notify user if Drive save fails
        _error = 'Person names saved locally but failed to save to Drive: $e';
      }
    }
    
    notifyListeners();
  }

  Future<void> setFolderId(String folderId) async {
    _driveService.setFolderId(folderId);
    _config = _config.copyWith(googleDriveFolderId: folderId);
    await _saveConfig();
    
    // Try to load person names from Drive folder when folder is selected
    await _loadPersonNamesFromDrive();
    
    notifyListeners();
  }
  
  // Load person names from Drive folder if signed in and folder is selected
  Future<void> _loadPersonNamesFromDrive() async {
    if (!isSignedIn || _driveService.folderId == null || _driveService.folderId!.isEmpty) {
      return;
    }
    
    try {
      final personNamesCsv = await _driveService.downloadPersonNames();
      if (personNamesCsv.isNotEmpty) {
        final personNames = CsvService.personNamesFromCsv(personNamesCsv);
        final drivePerson1 = personNames['person1Name']?.trim() ?? '';
        final drivePerson2 = personNames['person2Name']?.trim() ?? '';
        
        // If Drive has person names, load them (folder-specific data)
        if (drivePerson1.isNotEmpty || drivePerson2.isNotEmpty) {
          // Always update with Drive names when loading from Drive
          // This ensures folder-specific data is loaded correctly
          _config = _config.copyWith(
            person1Name: drivePerson1,
            person2Name: drivePerson2,
          );
          // Update local storage to match Drive
          await _saveConfig();
          print('Person names loaded from Drive folder: Person1=$drivePerson1, Person2=$drivePerson2');
        } else {
          print('Person names CSV exists but is empty - no names to load');
        }
      } else {
        print('No person_names.csv found in Drive folder - folder may be new');
      }
    } catch (e) {
      print('Error loading person names from Drive folder: $e');
      // Don't fail if person names load fails - folder might be new and not have person names yet
      // File might not exist yet, which is normal for new folders
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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearRestoreError() {
    _restoreError = null;
    _restoreErrorDetails = null;
    notifyListeners();
  }
}
