import 'package:flutter/foundation.dart';
import '../models/category.dart' as models;
import '../services/csv_service.dart';
import 'config_provider.dart';

class CategoriesProvider with ChangeNotifier {
  final List<models.Category> _categories = [];
  bool _isLoading = false;
  String? _error;
  String? _lastLoadedFolderId; // Track which folder we loaded categories for to prevent reload loops

  List<models.Category> get categories => List.unmodifiable(_categories);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load categories from Google Drive
  Future<void> loadCategories(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    final currentFolderId = configProvider.driveService.folderId;
    
    // Prevent multiple simultaneous calls
    if (_isLoading) {
      return;
    }
    
    // If we've already loaded for this folder and we have no error, don't reload
    // This prevents infinite reload loops when the file doesn't exist or is empty
    if (_lastLoadedFolderId != null && currentFolderId == _lastLoadedFolderId && _error == null) {
      // Already loaded for this folder (even if empty) - don't reload unless there's an error
      // This prevents infinite retries when the file doesn't exist
      print('Categories already loaded for folder $currentFolderId - skipping reload');
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = await configProvider.driveService.downloadCategories();
      if (csvContent.isEmpty || csvContent.trim().isEmpty) {
        // File doesn't exist - create an empty categories.csv file with just the header
        // This prevents infinite reload attempts and establishes the file in Drive
        print('categories.csv file not found - creating empty file with header');
        try {
          // Create empty CSV with just header row (e.g., "name\n")
          // This creates a file with just the header: "name\n"
          final emptyCsv = CsvService.categoriesToCsv([]);
          await configProvider.driveService.uploadCategories(emptyCsv);
          print('Successfully created empty categories.csv file in Drive folder');
          
          // Mark this folder as loaded IMMEDIATELY after successful creation
          // This must happen before notifyListeners() to prevent reload loops
          _lastLoadedFolderId = currentFolderId;
        } catch (uploadError) {
          print('Error creating empty categories.csv file: $uploadError');
          // Even if file creation fails, mark as loaded to prevent infinite retries
          // The file might exist but be empty, or there might be a permissions issue
          _lastLoadedFolderId = currentFolderId;
        }
        
        // Ensure categories are empty (in case of folder change)
        final hadCategories = _categories.isNotEmpty;
        if (hadCategories) {
          _categories.clear();
        }
        
        _isLoading = false;
        _error = null; // Clear any previous errors since we successfully initialized
        // Notify listeners that we've initialized for this folder (file now exists, even if empty)
        // This is needed so main.dart knows categories have been loaded (even if empty)
        // The _lastLoadedFolderId is already set, so subsequent calls will return early
        notifyListeners();
        return;
      }
      
      // File exists - parse and load categories
      final loadedCategories = CsvService.categoriesFromCsv(csvContent);
      final categoriesChanged = _categories.length != loadedCategories.length ||
          !_categories.every((c) => loadedCategories.any((lc) => lc.name == c.name));
      
      // Mark as loaded for this folder BEFORE processing changes
      // This prevents reload loops if notifyListeners() triggers a rebuild
      _lastLoadedFolderId = currentFolderId;
      
      if (categoriesChanged) {
        _categories.clear();
        _categories.addAll(loadedCategories);
        _error = null;
      }
      
      _isLoading = false;
      
      // Only notify if something changed
      if (categoriesChanged || _error != null) {
        notifyListeners();
      }
    } catch (e) {
      // Mark as loaded for this folder even on error to prevent infinite retries
      _lastLoadedFolderId = currentFolderId;
      
      // Only set error if we don't already have the same error to prevent unnecessary notifications
      final newError = 'Failed to load categories: $e';
      if (_error != newError) {
        _error = newError;
        _isLoading = false;
        notifyListeners();
      } else {
        _isLoading = false;
        // Error is the same - don't notify to prevent rebuilds
      }
    }
  }

  // Save categories to Google Drive
  Future<void> saveCategories(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      _error = 'Not signed in or folder not set';
      notifyListeners();
      return;
    }

    final currentFolderId = configProvider.driveService.folderId;
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final csvContent = CsvService.categoriesToCsv(_categories);
      await configProvider.driveService.uploadCategories(csvContent);
      _error = null;
      // Update folder ID after successful save to prevent reload loops
      _lastLoadedFolderId = currentFolderId;
    } catch (e) {
      _error = 'Failed to save categories: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add a category
  Future<void> addCategory(models.Category category, ConfigProvider configProvider) async {
    // Check if category already exists
    if (_categories.any((c) => c.name.toLowerCase() == category.name.toLowerCase())) {
      _error = 'Category "${category.name}" already exists';
      notifyListeners();
      return;
    }

    _categories.add(category);
    await saveCategories(configProvider);
  }

  // Update a category
  Future<void> updateCategory(int index, models.Category newCategory, ConfigProvider configProvider) async {
    if (index < 0 || index >= _categories.length) {
      _error = 'Invalid category index';
      notifyListeners();
      return;
    }

    final oldCategory = _categories[index];
    
    // Check if new name conflicts with another category
    if (oldCategory.name.toLowerCase() != newCategory.name.toLowerCase() &&
        _categories.any((c) => c.name.toLowerCase() == newCategory.name.toLowerCase())) {
      _error = 'Category "${newCategory.name}" already exists';
      notifyListeners();
      return;
    }

    _categories[index] = newCategory;
    await saveCategories(configProvider);
  }

  // Delete a category
  Future<void> deleteCategory(int index, ConfigProvider configProvider, {required bool isCategoryUsed}) async {
    if (index < 0 || index >= _categories.length) {
      _error = 'Invalid category index';
      notifyListeners();
      return;
    }

    if (isCategoryUsed) {
      _error = 'Cannot delete category that is in use';
      notifyListeners();
      return;
    }

    _categories.removeAt(index);
    await saveCategories(configProvider);
  }

  // Check if a category is in use (used by bills or splits)
  bool isCategoryInUse(String categoryName, List bills, List splits) {
    final categoryLower = categoryName.toLowerCase();
    
    // Check bills
    for (final bill in bills) {
      if (bill.category.toLowerCase() == categoryLower) {
        return true;
      }
    }

    // Check splits (only non-"all" categories)
    for (final split in splits) {
      if (split.category != 'all' && split.category.toLowerCase() == categoryLower) {
        return true;
      }
    }

    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
