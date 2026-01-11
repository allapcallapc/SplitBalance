import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../config/google_sign_in_config.dart';

/// Service for interacting with Google Drive API
class GoogleDriveService {
  static const List<String> _scopes = [
    drive.DriveApi.driveScope,
  ];

  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _folderId;

  GoogleDriveService() {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
      clientId: GoogleSignInConfig.webClientId,
      // For web, don't force code flow - use standard OAuth popup
      // This ensures full login flow instead of "Continue as" popup
    );
  }

  /// Sign in with Google - opens full OAuth login popup
  Future<bool> signIn() async {
    try {
      print('Starting Google Sign-In...');
      
      // Sign in - this opens the full OAuth popup
      // The package will show the full OAuth consent screen
      _currentUser = await _googleSignIn.signIn();
      
      if (_currentUser == null) {
        print('Sign-in cancelled by user');
        return false;
      }

      print('Sign-in successful: ${_currentUser!.email}');

      // Get authentication headers
      final authHeaders = await _currentUser!.authHeaders;
      
      if (authHeaders.isEmpty || !authHeaders.containsKey('Authorization')) {
        print('Failed to get authentication headers');
        _currentUser = null;
        return false;
      }

      // Validate token
      final authValue = authHeaders['Authorization'] ?? '';
      if (!authValue.startsWith('Bearer ') || authValue.length < 20) {
        print('Invalid authentication token');
        _currentUser = null;
        return false;
      }

      // Create authenticated client for Google Drive API
      final authenticatedClient = GoogleAuthClient(_currentUser!);
      _driveApi = drive.DriveApi(authenticatedClient);
      
      print('Drive API client initialized successfully');
      return true;
    } catch (e, stackTrace) {
      print('Error during sign-in: $e');
      print('Stack trace: $stackTrace');
      _currentUser = null;
      _driveApi = null;
      rethrow;
    }
  }

  /// Attempt to sign in silently (restore existing session)
  Future<bool> signInSilently() async {
    try {
      print('Attempting silent sign-in...');
      
      _currentUser = await _googleSignIn.signInSilently();
      
      if (_currentUser == null) {
        print('No existing session found');
        return false;
      }

      print('Silent sign-in successful: ${_currentUser!.email}');

      // Get authentication headers
      final authHeaders = await _currentUser!.authHeaders;
      
      if (authHeaders.isEmpty || !authHeaders.containsKey('Authorization')) {
        print('Failed to get authentication headers');
        _currentUser = null;
        return false;
      }

      // Create authenticated client for Google Drive API
      final authenticatedClient = GoogleAuthClient(_currentUser!);
      _driveApi = drive.DriveApi(authenticatedClient);
      
      print('Drive API client initialized successfully');
      return true;
    } catch (e) {
      print('Silent sign-in failed: $e');
      _currentUser = null;
      _driveApi = null;
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
    _folderId = null;
  }

  /// Check if signed in
  bool get isSignedIn => _currentUser != null && _driveApi != null;

  /// Get current user
  GoogleSignInAccount? get currentUser => _currentUser;

  /// Set folder ID
  void setFolderId(String folderId) {
    _folderId = folderId;
  }

  /// Get folder ID
  String? get folderId => _folderId;

  /// List folders in Drive (optionally in a specific parent folder)
  Future<List<drive.File>> listFolders([String? parentFolderId]) async {
    if (_driveApi == null) {
      throw StateError('Not signed in');
    }

    try {
      String query = "mimeType='application/vnd.google-apps.folder' and trashed=false";
      if (parentFolderId != null) {
        query += " and '$parentFolderId' in parents";
      } else {
        query += " and 'root' in parents";
      }
      
      final response = await _driveApi!.files.list(
        q: query,
        $fields: 'files(id, name)',
      );

      if (response.files == null || response.files!.isEmpty) {
        return <drive.File>[];
      }
      
      return List<drive.File>.from(response.files!);
    } catch (e, stackTrace) {
      print('Error listing folders: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Create a new folder in a parent folder (or root if parentId is null)
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

  /// Get folder information by ID
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

  /// Get or create a file in the folder
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

  /// Upload CSV content to Drive
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

  /// Download CSV content from Drive
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
      final authenticatedClient = GoogleAuthClient(_currentUser!);
      final downloadUrl = 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media';
      final downloadResponse = await authenticatedClient.get(Uri.parse(downloadUrl));
      
      if (downloadResponse.statusCode == 200) {
        // Try UTF-8 first, fall back to Latin1 if UTF-8 decoding fails
        try {
          return utf8.decode(downloadResponse.bodyBytes);
        } on FormatException {
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

  /// Upload bills.csv
  Future<void> uploadBills(String csvContent) async {
    await uploadCsv('bills.csv', csvContent);
  }

  /// Download bills.csv
  Future<String> downloadBills() async {
    return await downloadCsv('bills.csv');
  }

  /// Upload payment_splits.csv
  Future<void> uploadPaymentSplits(String csvContent) async {
    await uploadCsv('payment_splits.csv', csvContent);
  }

  /// Download payment_splits.csv
  Future<String> downloadPaymentSplits() async {
    return await downloadCsv('payment_splits.csv');
  }

  /// Upload categories.csv
  Future<void> uploadCategories(String csvContent) async {
    await uploadCsv('categories.csv', csvContent);
  }

  /// Download categories.csv
  Future<String> downloadCategories() async {
    return await downloadCsv('categories.csv');
  }

  /// Upload person_names.csv
  Future<void> uploadPersonNames(String csvContent) async {
    await uploadCsv('person_names.csv', csvContent);
  }

  /// Download person_names.csv
  Future<String> downloadPersonNames() async {
    return await downloadCsv('person_names.csv');
  }
}

/// Custom HTTP client for Google APIs with automatic token refresh
class GoogleAuthClient extends http.BaseClient {
  final GoogleSignInAccount _user;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._user);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Get fresh authentication headers before each request
    final authHeaders = await _user.authHeaders;
    
    if (authHeaders.isEmpty || !authHeaders.containsKey('Authorization')) {
      throw Exception('Failed to get auth headers - user may need to sign in again');
    }
    
    // Add authentication headers to the request
    request.headers.addAll(authHeaders);
    
    // Send the request
    return await _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}