import 'dart:convert';
import 'dart:typed_data';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../config/google_sign_in_config.dart';

class GoogleDriveService {
  static const List<String> _scopes = [
    drive.DriveApi.driveScope,
  ];

  late final GoogleSignIn _googleSignIn;

  GoogleDriveService() {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
      // For web, use the client ID from config - this enables popup-based sign-in
      // IMPORTANT: The Client ID must match between:
      // 1. lib/config/google_sign_in_config.dart
      // 2. web/index.html meta tag
      // 3. Google Cloud Console OAuth 2.0 Client ID configuration
      clientId: GoogleSignInConfig.webClientId,
      // Force code flow for better web session persistence
      // This ensures sessions are properly restored across page reloads
      forceCodeForRefreshToken: false, // Use default, let the package handle it
    );
  }

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _folderId;
  DateTime? _lastRestoreAttempt; // Track when we last attempted to restore session

  // Detailed error information for debugging
  String? _lastError;
  String? _lastErrorDetails;
  StackTrace? _lastErrorStackTrace;

  String? get lastError => _lastError;
  String? get lastErrorDetails => _lastErrorDetails;
  StackTrace? get lastErrorStackTrace => _lastErrorStackTrace;
  
  // Check if we should attempt silent sign-in (avoid rate limiting)
  bool _shouldAttemptRestore() {
    // If we already have a user and Drive API, we're signed in - no need to restore
    if (_currentUser != null && _driveApi != null) {
      print('✅ Already have active session - skipping restore attempt');
      return false;
    }
    
    // If we attempted restore recently (within 5 minutes), skip to avoid rate limiting
    if (_lastRestoreAttempt != null) {
      final timeSinceLastAttempt = DateTime.now().difference(_lastRestoreAttempt!);
      if (timeSinceLastAttempt.inMinutes < 5) {
        final minutesRemaining = 5 - timeSinceLastAttempt.inMinutes;
        print('⏱️  Last restore attempt was ${timeSinceLastAttempt.inMinutes} minutes ago');
        print('⏱️  Skipping restore attempt to avoid rate limiting (wait ${minutesRemaining} more minutes)');
        return false;
      }
    }
    
    return true;
  }

  // Sign in silently (restore existing session without popup)
  // IMPORTANT: This makes a network request to Google's servers.
  // Only call this when necessary - Google sessions persist in browser storage,
  // so we should avoid calling this on every page reload if we already have a session.
  Future<bool> signInSilently({bool forceAttempt = false}) async {
    // Check if we should skip this attempt (rate limiting protection)
    if (!forceAttempt && !_shouldAttemptRestore()) {
      // We already have a session or attempted recently - skip to avoid rate limiting
      return _currentUser != null && _driveApi != null;
    }
    
    // Clear previous errors
    _lastError = null;
    _lastErrorDetails = null;
    _lastErrorStackTrace = null;
    
    // Record this attempt to avoid rate limiting
    _lastRestoreAttempt = DateTime.now();

    try {
      print('═══════════════════════════════════════════════════════════');
      print('🔐 ATTEMPTING SILENT SIGN-IN (Session Restoration)');
      print('═══════════════════════════════════════════════════════════');
      print('Timestamp: ${DateTime.now().toIso8601String()}');
      final clientId = GoogleSignInConfig.webClientId;
      print('Client ID configured: true');
      print('Client ID: ${clientId.substring(0, clientId.indexOf('.'))}...${clientId.substring(clientId.lastIndexOf('.'))}');
      
      // Try to restore existing session without opening popup
      // For web, this uses cookies/storage stored by the browser to restore the session
      // Note: This makes a network request to Google's servers, which can trigger rate limiting
      // Google's session persists in browser cookies/storage, so we only need to call this
      // when the Dart objects (_currentUser, _driveApi) are null after a page reload
      print('');
      print('Step 1: Calling _googleSignIn.signInSilently()...');
      print('Note: Google session should persist in browser storage - this just restores our Dart objects');
      _currentUser = await _googleSignIn.signInSilently();
      
      if (_currentUser == null) {
        // No existing session found
        print('');
        print('❌ RESULT: signInSilently() returned null');
        print('No existing Google Sign-In session found');
        print('');
        print('Possible reasons:');
        print('  ✓ User has never signed in before');
        print('  ✓ User cleared browser cookies/storage');
        print('  ✓ Session expired (tokens expired)');
        print('  ✓ OAuth consent screen not published (for external users)');
        print('  ✓ User revoked access');
        print('  ✓ Different Google account session in browser');
        print('');
        
        _lastError = 'No existing session found';
        _lastErrorDetails = 'signInSilently() returned null. This means Google Sign-In library could not find a valid cached session.';
        return false;
      }

      print('✅ Step 1 SUCCESS: Found user session');
      print('   Email: ${_currentUser!.email}');
      print('   Display Name: ${_currentUser!.displayName ?? 'N/A'}');
      print('   ID: ${_currentUser!.id}');
      print('');

      // Get authentication headers (this requests the access token)
      // This may refresh the token if needed
      print('Step 2: Requesting authentication headers (access token)...');
      print('This may attempt to refresh the token if it expired...');
      
      final authHeaders = await _currentUser!.authHeaders;
      
      if (authHeaders.isEmpty) {
        print('');
        print('❌ RESULT: authHeaders is empty');
        print('Failed to get authentication headers');
        print('');
        print('This could indicate:');
        print('  ✗ Token refresh failed');
        print('  ✗ OAuth configuration issue');
        print('  ✗ Network connectivity problem');
        print('  ✗ Invalid or expired refresh token');
        print('  ✗ OAuth consent screen permissions revoked');
        print('');
        
        _lastError = 'Failed to get auth headers';
        _lastErrorDetails = 'authHeaders is empty after requesting from GoogleSignInAccount. This typically means token refresh failed.';
        return false;
      }

      print('✅ Step 2 SUCCESS: Obtained auth headers');
      print('   Headers keys: ${authHeaders.keys.join(', ')}');
      print('   Authorization header present: ${authHeaders.containsKey('Authorization')}');
      if (authHeaders.containsKey('Authorization')) {
        final authValue = authHeaders['Authorization'] ?? '';
        print('   Authorization type: ${authValue.startsWith('Bearer ') ? 'Bearer token' : 'Other'}');
        print('   Token length: ${authValue.length} characters');
      }
      print('');

      print('Step 3: Creating Drive API client...');
      // Create authenticated client for Google Drive API
      final authenticatedClient = GoogleAuthClient._(authHeaders);
      _driveApi = drive.DriveApi(authenticatedClient);
      print('✅ Step 3 SUCCESS: Drive API client created');
      print('');

      print('═══════════════════════════════════════════════════════════');
      print('✅ SESSION RESTORED SUCCESSFULLY');
      print('   User: ${_currentUser!.email}');
      print('   Session persisted in browser storage - no need to restore again unless it expires');
      print('═══════════════════════════════════════════════════════════');
      return true;
    } catch (e, stackTrace) {
      // FedCM errors are common on web and don't necessarily mean there's no session
      // They're just warnings that FedCM couldn't be used, but the session might still exist
      final errorStr = e.toString();
      print('');
      print('═══════════════════════════════════════════════════════════');
      print('❌ ERROR DURING SILENT SIGN-IN');
      print('═══════════════════════════════════════════════════════════');
      print('Error Type: ${e.runtimeType}');
      print('Error Message: $errorStr');
      print('');
      
      // Store detailed error information
      _lastError = errorStr;
      _lastErrorDetails = 'Exception during signInSilently(): ${e.runtimeType}';
      _lastErrorStackTrace = stackTrace;
      
      // Check for specific error patterns from browser console
      // Note: We can't directly access browser console messages, but we can detect patterns
      // in the error message or check if it's a known FedCM/IdentityCredentialError
      
      if (errorStr.contains('FedCM') || 
          errorStr.contains('IdentityCredentialError') ||
          errorStr.contains('unknown_reason')) {
        // FedCM errors are expected and can be ignored
        // The session might still be valid, but we can't restore it silently
        print('⚠️  FEDCM / IDENTITY CREDENTIAL ERROR');
        print('FedCM (Federated Credential Management) is a browser API.');
        print('Errors here don\'t necessarily mean there is no session.');
        print('');
        print('Based on browser console logs, possible causes:');
        print('  1. ⏱️  RATE LIMITING: Auto re-authn was triggered less than 10 minutes ago');
        print('     → Solution: Wait 10 minutes before refreshing, or click "Sign In" button');
        print('');
        print('  2. 🌐 CORS HEADERS: Server did not send correct CORS headers');
        print('     → Solution: Check OAuth configuration in Google Cloud Console');
        print('     → Verify authorized JavaScript origins match your URL exactly');
        print('     → Check authorized redirect URIs are configured');
        print('');
        print('  3. 🔌 NETWORK ERROR: ERR_FAILED when fetching ID assertion endpoint');
        print('     → Solution: Check network connectivity');
        print('     → Verify no browser extensions blocking requests');
        print('     → Try in incognito/private window');
        print('');
        print('  4. 🔑 TOKEN ERROR: Error retrieving a token');
        print('     → Solution: Session may have expired, user needs to sign in again');
        print('     → This is normal if session was cleared or expired');
        print('');
        print('What to try:');
        print('  ✓ Wait 10 minutes if you just signed in and refreshed immediately');
        print('  ✓ Click "Sign In with Google" button (this bypasses rate limiting)');
        print('  ✓ Check browser console for "Auto re-authn was previously triggered" message');
        print('  ✓ Verify OAuth consent screen and authorized origins in Google Cloud Console');
        print('');
        
        _lastErrorDetails = 'FedCM/IdentityCredential error. Common causes: rate limiting (10 min cooldown), CORS headers, network errors, or token retrieval failure. Check browser console for "Auto re-authn was previously triggered" message.';
      } else if (errorStr.contains('popup_closed') || 
                 errorStr.contains('popup_blocked')) {
        print('⚠️  POPUP ERROR');
        print('User interaction required but popup was blocked/closed');
        print('');
        
        _lastErrorDetails = 'Popup blocked/closed: $errorStr';
      } else if (errorStr.contains('access_denied') ||
                 errorStr.contains('access_denied')) {
        print('⚠️  ACCESS DENIED');
        print('User denied access or revoked permissions');
        print('');
        
        _lastErrorDetails = 'Access denied: $errorStr';
      } else if (errorStr.contains('network') || 
                 errorStr.contains('Network') ||
                 errorStr.contains('Failed host lookup') ||
                 errorStr.contains('Connection refused')) {
        print('⚠️  NETWORK ERROR');
        print('Network connectivity issue during sign-in');
        print('');
        
        _lastErrorDetails = 'Network error: $errorStr';
      } else if (errorStr.contains('redirect_uri_mismatch') ||
                 errorStr.contains('redirect')) {
        print('⚠️  REDIRECT URI MISMATCH');
        print('OAuth configuration error: Redirect URI doesn\'t match');
        print('Check Google Cloud Console → Credentials → Authorized redirect URIs');
        print('');
        
        _lastErrorDetails = 'Redirect URI mismatch: $errorStr';
      } else if (errorStr.contains('origin') || 
                 errorStr.contains('JavaScript') ||
                 errorStr.contains('origins')) {
        print('⚠️  ORIGIN MISMATCH');
        print('OAuth configuration error: JavaScript origin not authorized');
        print('Check Google Cloud Console → Credentials → Authorized JavaScript origins');
        print('');
        
        _lastErrorDetails = 'Origin mismatch: $errorStr';
      } else if (errorStr.contains('invalid_client') ||
                 errorStr.contains('client_id')) {
        print('⚠️  CLIENT ID ERROR');
        print('OAuth configuration error: Invalid or missing Client ID');
        print('Check that Client ID matches in:');
        print('  1. lib/config/google_sign_in_config.dart');
        print('  2. web/index.html meta tag');
        print('');
        
        _lastErrorDetails = 'Client ID error: $errorStr';
      } else {
        print('⚠️  UNEXPECTED ERROR');
        print('Unknown error type - may indicate OAuth configuration issue');
        print('');
        
        _lastErrorDetails = 'Unexpected error: $errorStr';
      }
      
      print('Stack Trace:');
      print(stackTrace);
      print('');
      print('═══════════════════════════════════════════════════════════');
      
      return false;
    }
  }

  // Sign in - opens a popup for user authorization
  Future<bool> signIn() async {
    try {
      // First try silent sign-in to restore existing session
      final silentSuccess = await signInSilently();
      if (silentSuccess) {
        return true; // Already signed in, no popup needed
      }

      // No existing session, open popup for user authorization
      _currentUser = await _googleSignIn.signIn();
      
      if (_currentUser == null) {
        // User closed the popup without signing in
        return false;
      }

      // Get authentication headers (this requests the access token)
      final authHeaders = await _currentUser!.authHeaders;
      if (authHeaders.isEmpty) {
        print('Failed to get auth headers - authentication may have failed');
        return false;
      }

      // Create authenticated client for Google Drive API
      final authenticatedClient = GoogleAuthClient._(authHeaders);
      _driveApi = drive.DriveApi(authenticatedClient);

      return true;
    } catch (e) {
      print('Error signing in: $e');
      rethrow; // Re-throw to get actual error message for better debugging
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
    _folderId = null;
  }

  // Check if signed in
  bool get isSignedIn => _currentUser != null && _driveApi != null;

  // Get current user
  GoogleSignInAccount? get currentUser => _currentUser;

  // Try to restore session by checking if user is already authenticated
  // This is an alternative to signInSilently() that might work better on web
  Future<bool> tryRestoreSession() async {
    try {
      // First, try the standard silent sign-in
      final silentSuccess = await signInSilently();
      if (silentSuccess) {
        return true;
      }

      // If silent sign-in failed (possibly due to FedCM errors),
      // try to check if there's a current user session
      // Note: This might not work on all platforms, but it's worth trying
      try {
        // On web, Google Sign-In might have a session even if signInSilently() failed
        // We can't directly check this, but we can try to get auth headers if a session exists
        // This is a workaround for FedCM issues
        return false; // If silent sign-in failed, we can't restore
      } catch (e) {
        print('Alternative session restore failed: $e');
        return false;
      }
    } catch (e) {
      print('Error in tryRestoreSession: $e');
      return false;
    }
  }

  // Set folder ID
  void setFolderId(String folderId) {
    _folderId = folderId;
  }

  // Get folder ID
  String? get folderId => _folderId;

  // List folders in Drive (optionally in a specific parent folder)
  Future<List<drive.File>> listFolders([String? parentFolderId]) async {
    if (_driveApi == null) {
      throw StateError('Not signed in');
    }

    try {
      String query = "mimeType='application/vnd.google-apps.folder' and trashed=false";
      if (parentFolderId != null) {
        query += " and '$parentFolderId' in parents";
      } else {
        // List root folders (folders with no parents or only in My Drive root)
        query += " and 'root' in parents";
      }
      
      final response = await _driveApi!.files.list(
        q: query,
        $fields: 'files(id, name)',
      );

      // Ensure we always return a non-null list
      // response.files can be null, so we need to handle that case
      if (response.files == null) {
        return <drive.File>[];
      }
      
      // Explicitly convert to List<drive.File> to avoid type issues
      // response.files is List<drive.File>?, so we need to handle null
      final filesList = response.files!;
      if (filesList.isEmpty) {
        return <drive.File>[];
      }
      
      return List<drive.File>.from(filesList);
    } catch (e) {
      print('Error listing folders: $e');
      rethrow;
    }
  }

  // Create a new folder in a parent folder (or root if parentId is null)
  Future<drive.File> createFolder(String folderName, [String? parentFolderId]) async {
    if (_driveApi == null) {
      throw StateError('Not signed in');
    }

    try {
      final folder = drive.File();
      folder.name = folderName;
      folder.mimeType = 'application/vnd.google-apps.folder';
      
      if (parentFolderId != null) {
        folder.parents = [parentFolderId];
      } else {
        folder.parents = ['root'];
      }

      final createdFolder = await _driveApi!.files.create(folder, $fields: 'id, name');
      return createdFolder;
    } catch (e) {
      print('Error creating folder: $e');
      rethrow;
    }
  }

  // Get folder information by ID
  Future<drive.File?> getFolder(String folderId) async {
    if (_driveApi == null) {
      throw StateError('Not signed in');
    }

    try {
      final folder = await _driveApi!.files.get(
        folderId,
        $fields: 'id, name, parents',
      ) as drive.File;
      return folder;
    } catch (e) {
      print('Error getting folder: $e');
      return null;
    }
  }

  // Get or create a file in the folder
  Future<String> _getOrCreateFile(String fileName, String mimeType) async {
    if (_driveApi == null || _folderId == null) {
      throw StateError('Not signed in or folder not set');
    }

    try {
      // Check if file exists
      final response = await _driveApi!.files.list(
        q: "name='$fileName' and parents in '$folderId' and trashed=false",
        $fields: 'files(id, name)',
      );

      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first.id!;
      }

      // Create file if it doesn't exist
      final file = drive.File();
      file.name = fileName;
      file.parents = [_folderId!];
      file.mimeType = mimeType;

      final createdFile = await _driveApi!.files.create(file);
      return createdFile.id!;
    } catch (e) {
      print('Error getting/creating file: $e');
      rethrow;
    }
  }

  // Upload CSV content to Drive
  Future<void> uploadCsv(String fileName, String csvContent) async {
    if (_driveApi == null || _folderId == null) {
      throw StateError('Not signed in or folder not set');
    }

    try {
      final fileId = await _getOrCreateFile(fileName, 'text/csv');
      final bytes = Uint8List.fromList(utf8.encode(csvContent));

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'text/csv',
      );

      await _driveApi!.files.update(
        drive.File(),
        fileId,
        uploadMedia: media,
      );
    } catch (e) {
      print('Error uploading CSV: $e');
      rethrow;
    }
  }

  // Download CSV content from Drive
  Future<String> downloadCsv(String fileName) async {
    if (_driveApi == null || _folderId == null) {
      throw StateError('Not signed in or folder not set');
    }

    try {
      final response = await _driveApi!.files.list(
        q: "name='$fileName' and parents in '$folderId' and trashed=false",
        $fields: 'files(id, name)',
      );

      if (response.files == null || response.files!.isEmpty) {
        return ''; // File doesn't exist yet, return empty string
      }

      final fileId = response.files!.first.id!;
      
      // Use the authenticated client to download the file
      final authHeaders = await _currentUser!.authHeaders;
      final authenticatedClient = GoogleAuthClient._(authHeaders);
      final downloadUrl = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
      final downloadResponse = await authenticatedClient.get(Uri.parse(downloadUrl));
      
      if (downloadResponse.statusCode == 200) {
        // Try UTF-8 first, fall back to Latin1 if UTF-8 decoding fails
        try {
          return utf8.decode(downloadResponse.bodyBytes);
        } on FormatException {
          // If UTF-8 decoding fails, try Latin1 (ISO-8859-1)
          // This handles files encoded in Windows-1252 or ISO-8859-1
          return latin1.decode(downloadResponse.bodyBytes);
        }
      } else {
        throw Exception('Failed to download file: ${downloadResponse.statusCode}');
      }
    } catch (e) {
      print('Error downloading CSV: $e');
      // If file doesn't exist, return empty string
      if (e.toString().contains('404')) {
        return '';
      }
      rethrow;
    }
  }

  // Upload bills.csv
  Future<void> uploadBills(String csvContent) async {
    await uploadCsv('bills.csv', csvContent);
  }

  // Download bills.csv
  Future<String> downloadBills() async {
    return await downloadCsv('bills.csv');
  }

  // Upload payment_splits.csv
  Future<void> uploadPaymentSplits(String csvContent) async {
    await uploadCsv('payment_splits.csv', csvContent);
  }

  // Download payment_splits.csv
  Future<String> downloadPaymentSplits() async {
    return await downloadCsv('payment_splits.csv');
  }

  // Upload categories.csv
  Future<void> uploadCategories(String csvContent) async {
    await uploadCsv('categories.csv', csvContent);
  }

  // Download categories.csv
  Future<String> downloadCategories() async {
    return await downloadCsv('categories.csv');
  }

  // Upload person_names.csv
  Future<void> uploadPersonNames(String csvContent) async {
    await uploadCsv('person_names.csv', csvContent);
  }

  // Download person_names.csv
  Future<String> downloadPersonNames() async {
    return await downloadCsv('person_names.csv');
  }
}

// Custom HTTP client for Google APIs
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient._(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
