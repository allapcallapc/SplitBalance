import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/config_provider.dart';
import '../providers/bills_provider.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../services/csv_service.dart';
import '../models/app_config.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:package_info_plus/package_info_plus.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _person1Controller = TextEditingController();
  final _person2Controller = TextEditingController();
  List<drive.File> _folders = <drive.File>[];
  bool _loadingFolders = false;
  String? _selectedFolderId;
  String? _selectedFolderName;
  List<drive.File> _selectedFolderPath = <drive.File>[]; // Full path from root to selected folder
  bool _loadingSelectedFolderPath = false;
  ConfigProvider? _configProvider;
  bool _controllersInitialized = false;
  bool _hasShownFolderPrompt = false;
  bool _hasShownPersonNamePrompt = false;
  bool _hasShownCategoryPrompt = false;
  bool _isCheckingFolderData = false;
  bool _hasLoadedCategoriesInBuilder = false; // Flag to prevent infinite loadCategories calls
  String? _lastLoadedCategoriesFolderId; // Track which folder we loaded categories for
  // Navigation stack for folder browsing (breadcrumb)
  List<drive.File> _folderPath = <drive.File>[]; // Stack of folders we've navigated into
  String _appVersion = ''; // App version string
  bool _hasAttemptedLoadFolders = false; // Flag to prevent infinite retry loop when folder loading fails

  // Helper methods to safely check if lists are empty (for web compilation)
  // Use length instead of isEmpty/isNotEmpty to avoid undefined errors
  // This prevents "Cannot read properties of undefined" errors in web compilation
  bool get _hasFolders {
    try {
      // Use length property directly - if _folders is undefined, this will throw
      // In that case, we catch and reinitialize
      return _folders.isNotEmpty;
    } catch (e) {
      // If _folders is undefined or not accessible, reinitialize it
      _folders = <drive.File>[];
      return false;
    }
  }
  
  bool get _hasFolderPath {
    try {
      // Use length property directly - if _folderPath is undefined, this will throw
      // In that case, we catch and reinitialize
      return _folderPath.isNotEmpty;
    } catch (e) {
      // If _folderPath is undefined or not accessible, reinitialize it
      _folderPath = <drive.File>[];
      return false;
    }
  }
  
  bool get _hasSelectedFolderPath {
    try {
      // Use length property directly - if _selectedFolderPath is undefined, this will throw
      // In that case, we catch and reinitialize
      return _selectedFolderPath.isNotEmpty;
    } catch (e) {
      // If _selectedFolderPath is undefined or not accessible, reinitialize it
      _selectedFolderPath = <drive.File>[];
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize lists to avoid null/undefined errors
    _folders = <drive.File>[];
    _folderPath = <drive.File>[];
    _selectedFolderPath = <drive.File>[];
    // Load app version
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version;
      });
    } catch (e) {
      // If version loading fails, just leave it empty
      print('Error loading app version: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configProvider = context.read<ConfigProvider>();
    
    // Initialize controllers from provider once
    if (!_controllersInitialized && !configProvider.isLoading) {
      _person1Controller.text = configProvider.config.person1Name;
      _person2Controller.text = configProvider.config.person2Name;
      _selectedFolderId = configProvider.driveService.folderId;
      _controllersInitialized = true;
      _configProvider = configProvider;
      
      // Add listener to update controllers when provider changes
      configProvider.addListener(_onConfigChanged);
      
      // Load the full path of the selected folder if one is selected
      if (configProvider.isSignedIn && _selectedFolderId != null) {
        _loadSelectedFolderPath(configProvider);
        
        // Load person names from Drive folder when signed in and folder is selected
        // This ensures person names are loaded on initial app load
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted && configProvider.isSignedIn && configProvider.driveService.folderId != null) {
            // Force reload person names from Drive - this is the authoritative source
            await configProvider.reloadPersonNamesFromDrive();
            
            // Update controllers with loaded person names from Drive
            if (mounted) {
              setState(() {
                _person1Controller.text = configProvider.config.person1Name;
                _person2Controller.text = configProvider.config.person2Name;
              });
            }
          }
        });
        
        // Check folder data if folder is already selected (initial load)
        // This will also load categories so main.dart can check if config is complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && configProvider.isSignedIn && _selectedFolderId != null) {
            _checkFolderDataAndRestoreState(configProvider);
          }
        });
        
        // Also load categories directly to ensure they're available for main.dart check
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted && configProvider.isSignedIn && _selectedFolderId != null) {
            final categoriesProvider = context.read<CategoriesProvider>();
            await categoriesProvider.loadCategories(configProvider);
          }
        });
      }
      
      // Load folders if signed in and prompt for folder selection if needed
      // Only attempt once to prevent infinite retry loop on errors
      if (configProvider.isSignedIn && !_hasFolders && !_hasAttemptedLoadFolders) {
        _hasAttemptedLoadFolders = true; // Set flag immediately to prevent repeated attempts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadFolders(configProvider, null).then((_) {
              // After loading folders, prompt user to select if no folder is selected
              if (mounted && 
                  configProvider.isSignedIn && 
                  configProvider.driveService.folderId == null && 
                  _hasFolders && 
                  !_hasShownFolderPrompt) {
                _promptFolderSelection(configProvider);
              }
            });
          }
        });
      }
      
      // If user just signed in (was not signed in before) and folder is selected, load person names
      // Check if sign-in state changed by checking if controllers were initialized before
      if (configProvider.isSignedIn && _selectedFolderId != null && _controllersInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted && configProvider.isSignedIn && configProvider.driveService.folderId != null) {
            // Force reload person names from Drive when sign-in state changes
            await configProvider.reloadPersonNamesFromDrive();
            
            // Update controllers with loaded person names
            if (mounted) {
              setState(() {
                _person1Controller.text = configProvider.config.person1Name;
                _person2Controller.text = configProvider.config.person2Name;
              });
            }
          }
        });
      }
    } else if (_configProvider != configProvider) {
      // Provider instance changed - update listener
      _configProvider?.removeListener(_onConfigChanged);
      configProvider.addListener(_onConfigChanged);
      _configProvider = configProvider;
    }
  }

  void _onConfigChanged() {
    if (!mounted || _configProvider == null || _configProvider!.isLoading) return;
    
    final provider = _configProvider!;
    bool needsUpdate = false;
    
    if (_person1Controller.text != provider.config.person1Name) {
      _person1Controller.text = provider.config.person1Name;
      needsUpdate = true;
    }
    
    if (_person2Controller.text != provider.config.person2Name) {
      _person2Controller.text = provider.config.person2Name;
      needsUpdate = true;
    }
    
    // Check if user signed out - reset flags
    if (!provider.isSignedIn && (_hasShownFolderPrompt || _hasAttemptedLoadFolders)) {
      _hasShownFolderPrompt = false;
      _hasAttemptedLoadFolders = false; // Reset flag on sign out
      _folders.clear();
      _selectedFolderId = null;
      _selectedFolderName = null;
      _selectedFolderPath = <drive.File>[];
      needsUpdate = true;
    }
    
    final previousFolderId = _selectedFolderId;
    if (_selectedFolderId != provider.driveService.folderId) {
      // Folder changed - restore application state
      final newFolderId = provider.driveService.folderId;
      _selectedFolderId = newFolderId;
      needsUpdate = true;
      
      // If folder was selected (was null before, now has value), reset the prompt flags
      if (previousFolderId == null && newFolderId != null) {
        _hasShownFolderPrompt = false;
        _hasShownPersonNamePrompt = false;
        _hasShownCategoryPrompt = false;
      }
      
      // If folder changed (not just selected for first time), restore state
      if (previousFolderId != null && previousFolderId != newFolderId && newFolderId != null) {
        // Folder changed - clear person names and reset prompts
        _person1Controller.clear();
        _person2Controller.clear();
        _hasShownPersonNamePrompt = false;
        _hasShownCategoryPrompt = false;
        
        // Check folder data and restore/force person names
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && provider.isSignedIn) {
            _checkFolderDataAndRestoreState(provider);
          }
        });
      }
      
      // Load the full path of the selected folder
      if (provider.driveService.folderId != null && provider.isSignedIn) {
        _loadSelectedFolderPath(provider);
      } else {
        _selectedFolderPath = <drive.File>[];
      }
      
      // Only attempt to load folders once to prevent infinite retry loop
      if (provider.isSignedIn && !_hasFolders && !_hasAttemptedLoadFolders) {
        _hasAttemptedLoadFolders = true; // Set flag immediately to prevent repeated attempts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadFolders(provider, null).then((_) {
              // After loading folders, prompt user to select if not already selected
              if (mounted && provider.isSignedIn && provider.driveService.folderId == null && _hasFolders && !_hasShownFolderPrompt) {
                _promptFolderSelection(provider);
              }
            });
          }
        });
      } else if (provider.isSignedIn && provider.driveService.folderId != null && previousFolderId == null) {
        // Folder just selected for first time - check data
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkFolderDataAndRestoreState(provider);
          }
        });
      }
    }

    if (needsUpdate) {
      setState(() {});
    }
  }

  Future<void> _promptFolderSelection(ConfigProvider configProvider) async {
    if (_hasShownFolderPrompt || !configProvider.isSignedIn || configProvider.driveService.folderId != null) {
      return;
    }

    _hasShownFolderPrompt = true;

    // Wait a moment for UI to update, then show dialog
    await Future.delayed(const Duration(milliseconds: 500));

    // Use safe check to avoid isEmpty on undefined
    if (!mounted || !_hasFolders) {
      // Try loading folders first if not loaded
      await _loadFolders(configProvider, null);
      if (!mounted || !_hasFolders) {
        _hasShownFolderPrompt = false;
        return;
      }
    }

    if (!mounted) return;

    // Show dialog to prompt folder selection
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(AppLocalizations.of(context)!.selectStorageFolder)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context)!.selectGoogleDriveFolderPrompt,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: !_hasFolders
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final folder = _folders[index];
                          final isSelected = folder.id == _selectedFolderId;
                          return ListTile(
                            title: Text(folder.name ?? 'Unnamed'),
                            selected: isSelected,
                            leading: const Icon(Icons.folder),
                            trailing: isSelected
                                ? const Icon(Icons.check, color: Colors.green)
                                : null,
                            onTap: () async {
                              final previousFolderId = _selectedFolderId;
                              setState(() {
                                _selectedFolderId = folder.id;
                                _selectedFolderName = folder.name;
                              });
                              // Auto-save folder selection
                              if (folder.id != null) {
                                await configProvider.setFolderId(folder.id!);
                                _hasShownFolderPrompt = false; // Reset flag after selection
                                
                                // If folder changed (not just selected for first time), restore state
                                if (previousFolderId != null && previousFolderId != folder.id) {
                                  // Clear person names when folder changes
                                  _person1Controller.clear();
                                  _person2Controller.clear();
                                  _hasShownPersonNamePrompt = false;
                                  _hasShownCategoryPrompt = false;
                                }
                                
                                // Load the full path of the selected folder
                                _loadSelectedFolderPath(configProvider);
                                
                                // Check folder data and restore state
                                if (mounted) {
                                  _checkFolderDataAndRestoreState(configProvider);
                                }
                              }
                              if (context.mounted) {
                                Navigator.pop(context, 'selected'); // Return 'selected' to indicate folder was chosen
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Folder selected! Checking folder data...'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context, null); // Close folder dialog first
              // Allow sign out to go back to login step
              if (mounted) {
                final l10n = AppLocalizations.of(context)!;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l10n.signOut),
                    content: Text(l10n.signOutConfirmation),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l10n.cancel),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l10n.signOutButton),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await configProvider.signOut();
                  // Reset all flags when signing out
                  _hasShownFolderPrompt = false;
                  _hasShownPersonNamePrompt = false;
                  _hasShownCategoryPrompt = false;
                  _person1Controller.clear();
                  _person2Controller.clear();
                  setState(() {
                    _selectedFolderId = null;
                    _selectedFolderName = null;
                    _selectedFolderPath = <drive.File>[];
                    _folders.clear();
                  });
                }
              }
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, null); // Cancel - return null
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context, 'refresh'); // Refresh - return 'refresh' to indicate refresh was clicked
              _hasAttemptedLoadFolders = false; // Reset flag to allow manual refresh
              await _loadFolders(configProvider, null);
              if (mounted && _hasFolders && !_hasShownFolderPrompt) {
                // Only re-prompt if not already shown (avoid infinite loop)
                _hasShownFolderPrompt = false; // Reset to allow re-prompting
                _promptFolderSelection(configProvider);
              }
            },
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context)!.refreshFolders),
          ),
        ],
      ),
    );

    // Handle dialog dismissal (user tapped outside, cancelled, signed out, or selected folder)
    if (result == 'selected') {
      // Folder was selected - flag already reset in onTap handler, nothing to do
    } else if (result == 'refresh') {
      // Refresh button was clicked - will re-prompt if needed
      _hasShownFolderPrompt = false; // Reset to allow re-prompting after refresh
    } else {
      // Dialog was cancelled, dismissed, or user signed out - reset flag so it can be shown again if needed
      _hasShownFolderPrompt = false;
    }
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigChanged);
    _person1Controller.dispose();
    _person2Controller.dispose();
    super.dispose();
  }

  // Check folder data and restore/force person names based on data
  Future<void> _checkFolderDataAndRestoreState(ConfigProvider configProvider) async {
    if (_isCheckingFolderData || !mounted || !configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    _isCheckingFolderData = true;

    try {
      // Load data from the selected folder
      final billsProvider = context.read<BillsProvider>();
      final splitsProvider = context.read<PaymentSplitsProvider>();
      final categoriesProvider = context.read<CategoriesProvider>();

      await billsProvider.loadBills(configProvider);
      await splitsProvider.loadPaymentSplits(configProvider);
      await categoriesProvider.loadCategories(configProvider);

      // First, try to load person names from person_names.csv in Drive folder
      // This is the authoritative source - if it exists, use it
      List<String> personNamesFromCsv = [];
      String drivePerson1 = '';
      String drivePerson2 = '';
      bool hasDrivePersonNames = false;
      
      try {
        final personNamesCsv = await configProvider.driveService.downloadPersonNames();
        if (personNamesCsv.isNotEmpty) {
          final personNames = CsvService.personNamesFromCsv(personNamesCsv);
          drivePerson1 = personNames['person1Name']?.trim() ?? '';
          drivePerson2 = personNames['person2Name']?.trim() ?? '';
          
          // If Drive has person names, update the config provider with them
          if (drivePerson1.isNotEmpty || drivePerson2.isNotEmpty) {
            hasDrivePersonNames = true;
            await configProvider.setPersonNames(drivePerson1, drivePerson2);
            
            // Update UI controllers immediately
            if (mounted) {
              setState(() {
                _person1Controller.text = drivePerson1;
                _person2Controller.text = drivePerson2;
              });
            }
            
            print('Person names loaded from Drive folder and updated in UI: Person1=$drivePerson1, Person2=$drivePerson2');
          }
          
          // Add to list for comparison (only if not empty)
          if (drivePerson1.isNotEmpty) {
            personNamesFromCsv.add(drivePerson1);
          }
          if (drivePerson2.isNotEmpty) {
            personNamesFromCsv.add(drivePerson2);
          }
        }
      } catch (e) {
        print('Error loading person names from Drive: $e');
      }

      // Also extract person names from bills and payment splits as fallback
      final Set<String> personNamesFromData = {};
      // Add names from person_names.csv if available
      for (final name in personNamesFromCsv) {
        if (name.isNotEmpty) {
          personNamesFromData.add(name);
        }
      }
      // Extract from bills and payment splits
      for (final bill in billsProvider.bills) {
        if (bill.paidBy.isNotEmpty) {
          personNamesFromData.add(bill.paidBy);
        }
      }
      for (final split in splitsProvider.splits) {
        if (split.person1.isNotEmpty) {
          personNamesFromData.add(split.person1);
        }
        if (split.person2.isNotEmpty) {
          personNamesFromData.add(split.person2);
        }
      }

      final personNamesList = personNamesFromData.toList();
      final hasPersonData = personNamesList.isNotEmpty;
      
      // Use Drive person names if available (most authoritative), otherwise use config
      // If we loaded from Drive, use those (already applied to config above), otherwise use config
      final currentPerson1 = hasDrivePersonNames ? drivePerson1 : configProvider.config.person1Name.trim();
      final currentPerson2 = hasDrivePersonNames ? drivePerson2 : configProvider.config.person2Name.trim();
      final hasCurrentNames = currentPerson1.isNotEmpty && currentPerson2.isNotEmpty;

      // Check if current person names match what's in the folder
      bool namesMatch = false;
      if (hasPersonData && hasCurrentNames) {
        // Check if current names are in the folder data (order doesn't matter)
        // Person names from data might be in any order, so we check if both names exist in the set
        namesMatch = personNamesFromData.contains(currentPerson1) && 
                     personNamesFromData.contains(currentPerson2) &&
                     personNamesFromData.length == 2; // Ensure exactly 2 person names in folder data
      }

      // If folder has no person data OR names don't match OR no current names, force person name selection
      if (!hasPersonData || !namesMatch || !hasCurrentNames) {
        // Clear person names if they don't match or folder has no data
        if ((hasPersonData && !namesMatch) || !hasPersonData) {
          setState(() {
            _person1Controller.clear();
            _person2Controller.clear();
          });
          // Update provider to clear person names
          await configProvider.setPersonNames('', '');
        }

        // Force person name selection
        if (!_hasShownPersonNamePrompt && mounted) {
          _hasShownPersonNamePrompt = true;
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) {
            _promptPersonNameSelection(configProvider, personNamesList);
          }
        }
      } else {
        // Names match - check categories next
        if (mounted) {
          await _checkAndForceCategorySelection(configProvider, categoriesProvider);
        }
      }
    } catch (e) {
      print('Error checking folder data: $e');
    } finally {
      _isCheckingFolderData = false;
    }
  }

  // Check if categories exist and force selection if needed
  Future<void> _checkAndForceCategorySelection(ConfigProvider configProvider, CategoriesProvider categoriesProvider) async {
    if (!mounted || !configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    // Reload categories to ensure we have latest
    await categoriesProvider.loadCategories(configProvider);

    // Check if person names are set
    final person1Name = configProvider.config.person1Name.trim();
    final person2Name = configProvider.config.person2Name.trim();

    if (person1Name.isEmpty || person2Name.isEmpty) {
      // Person names not set yet - don't force categories
      return;
    }

    // Check if categories exist
    if (categoriesProvider.categories.isEmpty && !_hasShownCategoryPrompt && mounted) {
      _hasShownCategoryPrompt = true;
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _promptCategorySelection(configProvider, categoriesProvider);
      }
    }
  }

  // Prompt user to select person names (force selection)
  Future<void> _promptPersonNameSelection(ConfigProvider configProvider, List<String> suggestedNames) async {
    if (!mounted || !configProvider.isSignedIn) {
      return;
    }

    final person1Controller = TextEditingController();
    final person2Controller = TextEditingController();

    // Pre-fill with suggested names if available
    if (suggestedNames.isNotEmpty) {
      person1Controller.text = suggestedNames[0];
      if (suggestedNames.length > 1) {
        person2Controller.text = suggestedNames[1];
      }
    }

    // Pre-fill with current names if they exist
    if (person1Controller.text.isEmpty) {
      person1Controller.text = configProvider.config.person1Name;
    }
    if (person2Controller.text.isEmpty) {
      person2Controller.text = configProvider.config.person2Name;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(AppLocalizations.of(context)!.enterPersonNames)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                suggestedNames.isEmpty
                    ? 'Please enter the names of the two people for this folder:'
                    : 'The folder contains data with different person names. Please enter the correct names:',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: person1Controller,
                decoration: const InputDecoration(
                  labelText: 'Person 1 Name',
                  border: OutlineInputBorder(),
                  hintText: 'Enter first person\'s name',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: person2Controller,
                decoration: const InputDecoration(
                  labelText: 'Person 2 Name',
                  border: OutlineInputBorder(),
                  hintText: 'Enter second person\'s name',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              person1Controller.dispose();
              person2Controller.dispose();
              Navigator.pop(context, false); // Cancel
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Allow changing folder - go back to folder selection
              person1Controller.dispose();
              person2Controller.dispose();
              Navigator.pop(context, false);
              // Reset flags so user can change folder
              _hasShownPersonNamePrompt = false;
              _hasShownCategoryPrompt = false;
              
              // Clear person names when going back to folder selection
              if (mounted) {
                setState(() {
                  _person1Controller.clear();
                  _person2Controller.clear();
                });
                await configProvider.setPersonNames('', '');
                
                // Re-prompt folder selection after a delay to allow user to change folder
                await Future.delayed(const Duration(milliseconds: 300));
                if (mounted && configProvider.isSignedIn) {
                  // Load folders if not already loaded
                  if (!_hasFolders) {
                    await _loadFolders(configProvider, null);
                  }
                  // Show folder selection dialog
                  _hasShownFolderPrompt = false; // Reset to allow showing dialog
                  if (mounted) {
                    _promptFolderSelection(configProvider);
                  }
                }
              }
            },
            child: const Text('Change Folder'),
          ),
          ElevatedButton(
            onPressed: () async {
              final person1Name = person1Controller.text.trim();
              final person2Name = person2Controller.text.trim();

              if (person1Name.isEmpty || person2Name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter both person names'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Save person names
              setState(() {
                _person1Controller.text = person1Name;
                _person2Controller.text = person2Name;
              });
              await configProvider.setPersonNames(person1Name, person2Name);

              person1Controller.dispose();
              person2Controller.dispose();

              if (context.mounted) {
                Navigator.pop(context, true); // Success
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // Handle dialog result
    if (mounted && result == true) {
      _hasShownPersonNamePrompt = false; // Reset to allow re-prompting if needed

      // Check categories after person names are set
      final categoriesProvider = context.read<CategoriesProvider>();
      await _checkAndForceCategorySelection(configProvider, categoriesProvider);
    } else if (mounted && result == false) {
      // User cancelled - reset flag so they can try again later
      _hasShownPersonNamePrompt = false;
    }
  }

  // Prompt user to create at least one category (force selection)
  Future<void> _promptCategorySelection(ConfigProvider configProvider, CategoriesProvider categoriesProvider) async {
    if (!mounted || !configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
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
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.createCategoriesPrompt,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, 'cancel'); // Cancel - allow going back
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              // Allow changing person names - go back
              Navigator.pop(dialogContext, 'change_names');
            },
            child: Text(l10n.changePersonNames),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, 'navigate'); // Return 'navigate' to indicate we should navigate
            },
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

    // Handle dialog result after dialog is closed
    if (!mounted) return;
    
    if (result == 'navigate') {
      // User wants to go to categories page - reset flag
      _hasShownCategoryPrompt = false;
      
      // Request navigation to categories screen via ConfigProvider
      // This will trigger a rebuild in main.dart, which will handle the navigation
      configProvider.requestNavigateToCategories();
    } else if (result == 'change_names') {
      // Reset flags so user can change person names or folder
      _hasShownCategoryPrompt = false;
      _hasShownPersonNamePrompt = false;
      
      // Clear person names to allow re-entry
      if (mounted) {
        setState(() {
          _person1Controller.clear();
          _person2Controller.clear();
        });
        await configProvider.setPersonNames('', '');
        
        // Re-check folder data to prompt for person names again
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted && configProvider.isSignedIn && configProvider.driveService.folderId != null) {
          _checkFolderDataAndRestoreState(configProvider);
        }
      }
    } else if (result == 'cancel' || result == null) {
      // User cancelled or wants to go back - reset flag so they can try again later
      _hasShownCategoryPrompt = false;
    }
  }

  Future<void> _loadSelectedFolderPath(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn || _selectedFolderId == null) {
      return;
    }

    setState(() {
      _loadingSelectedFolderPath = true;
    });

    try {
      final path = <drive.File>[];
      String? currentFolderId = _selectedFolderId;
      
      // First, get the selected folder to at least have its name
      final selectedFolder = await configProvider.driveService.getFolder(currentFolderId!);
      if (selectedFolder == null) {
        // If we can't get the folder, try to set name from existing data or leave as is
        setState(() {
          _loadingSelectedFolderPath = false;
        });
        return;
      }
      
      // Ensure we have the folder name at minimum
      String? folderName = selectedFolder.name;
      
      // Build path from selected folder up to root
      while (currentFolderId != null) {
        final folder = await configProvider.driveService.getFolder(currentFolderId);
        if (folder == null) break;
        
        // Insert at beginning to maintain root -> selected order
        path.insert(0, folder);
        
        // Get parent folder ID
        // Use length check instead of isNotEmpty to avoid undefined errors in web
        if (folder.parents != null && folder.parents!.isNotEmpty) {
          final parentId = folder.parents!.first;
          // Stop if we reach root (parent is 'root')
          if (parentId == 'root') {
            break;
          }
          currentFolderId = parentId;
        } else {
          break; // No parent, we're at root
        }
      }
      
      setState(() {
        _selectedFolderPath = path;
        // Use folder name from path if available, otherwise use the one we fetched
        _selectedFolderName = path.isNotEmpty ? (path.last.name ?? folderName) : folderName;
        _loadingSelectedFolderPath = false;
      });
    } catch (e) {
      // Even if path building fails, try to get at least the folder name
      try {
        if (_selectedFolderId != null) {
          final folder = await configProvider.driveService.getFolder(_selectedFolderId!);
          if (folder != null && folder.name != null) {
            setState(() {
              _selectedFolderName = folder.name;
              _selectedFolderPath = <drive.File>[]; // Clear path if we couldn't build it
              _loadingSelectedFolderPath = false;
            });
            return;
          }
        }
      } catch (e2) {
        print('Error loading folder name: $e2');
      }
      
      setState(() {
        _loadingSelectedFolderPath = false;
      });
      print('Error loading selected folder path: $e');
    }
  }

  Future<void> _loadFolders(ConfigProvider configProvider, [String? parentFolderId]) async {
    if (!configProvider.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseSignInFirst)),
      );
      return;
    }

    setState(() {
      _loadingFolders = true;
    });

    try {
      final folders = await configProvider.driveService.listFolders(parentFolderId);
      setState(() {
        // Ensure folders is never null - listFolders should always return a list
        _folders = folders;
        _loadingFolders = false;
        // If there's a selected folder ID, find its name
        if (_selectedFolderId != null && parentFolderId == null && _hasFolders) {
          try {
            final folder = _folders.firstWhere(
              (f) => f.id == _selectedFolderId,
              orElse: () => drive.File(),
            );
            if (folder.name != null) {
              _selectedFolderName = folder.name;
              // Also load the full path
              _loadSelectedFolderPath(configProvider);
            }
          } catch (e) {
            // If folder not found, ignore
            print('Folder not found in list: $e');
          }
        }
      });
    } catch (e) {
      setState(() {
        _loadingFolders = false;
        // Ensure _folders is always a valid list, even on error
        if (!_hasFolders) {
          _folders = <drive.File>[];
        }
      });
      if (mounted) {
        // Check if this is a FedCM/"Continue as" authentication issue
        final errorString = e.toString();
        String errorMessage;
        if (errorString.contains('Bearer null') || 
            errorString.contains('Invalid authentication token') ||
            errorString.contains('invalid_token')) {
          errorMessage = 'Authentication failed: The "Continue as" sign-in method is not fully supported. Please sign out and sign in again using the full Google sign-in popup.';
        } else {
          errorMessage = 'Error loading folders: $e';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Sign Out',
              onPressed: () {
                configProvider.signOut();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _navigateIntoFolder(ConfigProvider configProvider, drive.File folder) async {
    // Add current folder to path stack
    if (folder.id != null) {
      setState(() {
        _folderPath.add(folder);
      });
      // Load subfolders
      await _loadFolders(configProvider, folder.id);
    }
  }

  Future<void> _navigateBack(ConfigProvider configProvider) async {
    if (!_hasFolderPath) return;
    
    // Remove current folder from path
    setState(() {
      _folderPath.removeLast();
    });
    
      // Load parent folder's children
      if (!_hasFolderPath) {
        await _loadFolders(configProvider, null); // Load root folders
      } else {
        final parentFolder = _folderPath.last;
        if (parentFolder.id != null) {
          await _loadFolders(configProvider, parentFolder.id);
        } else {
          await _loadFolders(configProvider, null);
        }
      }
  }

  Future<void> _createFolder(ConfigProvider configProvider) async {
    if (!configProvider.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseSignInFirst)),
      );
      return;
    }

    final nameController = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.createNewFolder),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.folderName,
            hintText: l10n.enterFolderName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final folderName = nameController.text.trim();
    if (folderName.isEmpty) return;

    setState(() {
      _loadingFolders = true;
    });

    try {
      String? parentFolderId;
      if (_hasFolderPath && _folderPath.last.id != null) {
        parentFolderId = _folderPath.last.id;
      }
      await configProvider.driveService.createFolder(folderName, parentFolderId);
      
      // Reload folders to show the new one
      await _loadFolders(configProvider, parentFolderId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder "$folderName" created successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingFolders = false;
        });
      }
    }
  }

  Future<void> _saveConfig(ConfigProvider configProvider) async {
    try {
      // Save person names (even if empty - user might add them later)
      final person1Name = _person1Controller.text.trim();
      final person2Name = _person2Controller.text.trim();
      
      await configProvider.setPersonNames(person1Name, person2Name);

      // Save folder selection if available
      if (_selectedFolderId != null) {
        await configProvider.setFolderId(_selectedFolderId!);
      }

      // Reload config to verify it was saved
      await configProvider.reloadConfig();
      
      // Verify the save worked
      final savedConfig = configProvider.config;
      final saved = savedConfig.person1Name == person1Name &&
          savedConfig.person2Name == person2Name;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved 
                ? 'Configuration saved successfully!'
                : 'Warning: Configuration may not have saved correctly'),
            duration: const Duration(seconds: 2),
            backgroundColor: saved ? Colors.green : Colors.orange,
          ),
        );
        
        // After saving person names, check categories if folder is selected and names are set
        if (saved && person1Name.isNotEmpty && person2Name.isNotEmpty && configProvider.driveService.folderId != null) {
          final categoriesProvider = context.read<CategoriesProvider>();
          await _checkAndForceCategorySelection(configProvider, categoriesProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving config: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            ),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context)!.configuration),
          ],
        ),
      ),
      body: Consumer2<ConfigProvider, CategoriesProvider>(
        builder: (context, configProvider, categoriesProvider, child) {
          // Ensure lists are always initialized (they should be from initState, but double-check)
          // This prevents null/undefined errors when accessing isEmpty/isNotEmpty in web compilation
          
          // Load categories if folder is selected (needed for main.dart to check if config is complete)
          // BUT: Only load once per folder, not on every rebuild to prevent infinite loops
          final currentFolderId = configProvider.driveService.folderId;
          
          // Check if folder changed - if so, reset flags
          if (currentFolderId != _lastLoadedCategoriesFolderId) {
            _lastLoadedCategoriesFolderId = currentFolderId;
            _hasLoadedCategoriesInBuilder = false;
          }
          
          // Only load if: signed in, folder selected, not currently loading, and haven't loaded for this folder yet
          if (configProvider.isSignedIn && 
              currentFolderId != null && 
              !categoriesProvider.isLoading &&
              !_hasLoadedCategoriesInBuilder) {
            // Schedule load once for this folder
            _hasLoadedCategoriesInBuilder = true; // Set flag immediately to prevent duplicate scheduling
            
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted && 
                  configProvider.isSignedIn && 
                  configProvider.driveService.folderId == currentFolderId) {
                await categoriesProvider.loadCategories(configProvider);
              }
            });
          }
          
          // Check if user just signed in and needs to select a folder
          // Use length check instead of isEmpty to avoid undefined errors in web compilation
          // IMPORTANT: Only attempt to load folders once to prevent infinite retry loop on errors
          if (configProvider.isSignedIn && 
              configProvider.driveService.folderId == null && 
              !_hasFolders && 
              !configProvider.isLoading &&
              !_loadingFolders &&
              !_hasShownFolderPrompt &&
              !_hasAttemptedLoadFolders) {
            // Automatically load folders when signed in and no folder selected (only once)
            _hasAttemptedLoadFolders = true; // Set flag immediately to prevent repeated attempts
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadFolders(configProvider, null).then((_) {
                  if (mounted && 
                      configProvider.isSignedIn &&
                      configProvider.driveService.folderId == null &&
                      _hasFolders &&
                      !_hasShownFolderPrompt) {
                    _promptFolderSelection(configProvider);
                  }
                });
              }
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Folder Selection Required Message
                if (configProvider.isSignedIn && configProvider.driveService.folderId == null) ...[
                  Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_open, color: Colors.orange[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.folderSelectionRequired,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.of(context)!.selectGoogleDriveFolderMessage,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Google Sign-In Section
                  Card(
                    child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              color: configProvider.isSignedIn ? Colors.green : Colors.blue,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context)!.googleDriveConnection,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (configProvider.isSignedIn) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green[700],
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Signed In',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        configProvider.currentUser?.email ?? 'Unknown',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.green[900],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (configProvider.currentUser?.displayName != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          configProvider.currentUser!.displayName!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green[700],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: configProvider.isLoading
                                ? null
                                : () async {
                                    await configProvider.signOut();
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: configProvider.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(AppLocalizations.of(context)!.signOutButton),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: configProvider.isLoading
                                ? null
                                : () async {
                                    final success = await configProvider.signIn();
                                    if (success && context.mounted) {
                                      _hasAttemptedLoadFolders = false; // Reset flag after successful sign-in
                                      await _loadFolders(configProvider);
                                    } else if (context.mounted && configProvider.error != null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(configProvider.error!),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.account_circle),
                            label: configProvider.isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(AppLocalizations.of(context)!.signInWithGoogle),
                          ),
                        ],
                        if (configProvider.error != null) ...[
                          const SizedBox(height: 8),
                          Card(
                            color: Colors.red[50],
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.error_outline, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text(
                                        'Sign In Error',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    configProvider.error!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Display restore error if session restoration failed on app load
                        if (configProvider.restoreError != null && !configProvider.isSignedIn) ...[
                          const SizedBox(height: 8),
                          Card(
                            color: Colors.orange[50],
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.orange[700]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Session Restoration Failed',
                                          style: TextStyle(
                                            color: Colors.orange[900],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.close, size: 18, color: Colors.orange[700]),
                                        onPressed: () => configProvider.clearRestoreError(),
                                        tooltip: AppLocalizations.of(context)!.dismiss,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Could not automatically restore your Google Sign-In session. Based on browser console logs, this is likely due to:',
                                    style: TextStyle(
                                      color: Colors.orange[900],
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8.0),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.orange[300]!),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.timer, size: 16, color: Colors.orange[800]),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Rate Limiting (Most Likely)',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.orange[900],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Google limits automatic re-authentication to once every 10 minutes. If you just signed in and refreshed immediately, you\'ll see this error.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[900],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '✓ Solution: Click "Sign In with Google" button (bypasses rate limit)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange[800],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '✓ Or wait 10 minutes before refreshing',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange[800],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Other possible causes: CORS headers issue, network error, or token expiration. Check error details below.',
                                    style: TextStyle(
                                      color: Colors.orange[800],
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  if (configProvider.restoreErrorDetails != null) ...[
                                    const SizedBox(height: 8),
                                    ExpansionTile(
                                      title: const Text(
                                        'Error Details (for debugging)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      childrenPadding: const EdgeInsets.all(8.0),
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8.0),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Error:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SelectableText(
                                                configProvider.restoreError ?? 'No error details',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontFamily: 'monospace',
                                                  color: Colors.grey[900],
                                                ),
                                              ),
                                              if (configProvider.restoreErrorDetails != null) ...[
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Details:',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                SelectableText(
                                                  configProvider.restoreErrorDetails!,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontFamily: 'monospace',
                                                    color: Colors.grey[900],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8.0),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.info_outline, size: 16, color: Colors.blue[800]),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Debugging Tip',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.blue[900],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Open browser console (F12 → Console) and look for:',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue[900],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '• "Auto re-authn was previously triggered less than 10 minutes ago"',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.blue[800],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '• "Server did not send the correct CORS headers"',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.blue[800],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '• "ERR_FAILED" or "Error retrieving a token"',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.blue[800],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 16),
                
                // Folder Selection Section
                if (configProvider.isSignedIn) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.googleDriveFolder,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Display currently selected folder with full path
                          if (_selectedFolderId != null) ...[
                            Card(
                              color: Colors.blue[50],
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.folder, color: Colors.blue[700], size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppLocalizations.of(context)!.currentlyUsedFolder,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (_loadingSelectedFolderPath) ...[
                                      Row(
                                        children: [
                                          const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            AppLocalizations.of(context)!.loadingPath,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ] else if (_hasSelectedFolderPath) ...[
                                      // Display full path
                                      Builder(
                                        builder: (context) {
                                          // Safe access with try-catch
                                          try {
                                            final pathLength = _selectedFolderPath.length;
                                            return Wrap(
                                              spacing: 4,
                                              children: [
                                                for (int i = 0; i < pathLength; i++) ...[
                                                  if (i > 0) ...[
                                                    Icon(Icons.chevron_right, size: 16, color: Colors.grey[600]),
                                                  ],
                                                  Text(
                                                    _selectedFolderPath[i].name ?? 'Unnamed',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: i == pathLength - 1
                                                          ? Colors.blue[900]
                                                          : Colors.grey[700],
                                                      fontWeight: i == pathLength - 1
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            );
                                          } catch (e) {
                                            // If error accessing path, show fallback
                                            _selectedFolderPath = <drive.File>[];
                                            return Text(
                                              _selectedFolderName ?? 'Folder',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.blue[900],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ] else ...[
                                      // Show folder name if available, otherwise try to load it
                                      Builder(
                                        builder: (context) {
                                          // Try to load folder name if we don't have it and not already loading
                                          if (_selectedFolderId != null && _selectedFolderName == null && !_loadingSelectedFolderPath) {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              if (mounted) {
                                                _loadSelectedFolderPath(configProvider);
                                              }
                                            });
                                          }
                                          
                                          // Show folder name if we have it
                                          if (_selectedFolderName != null) {
                                            return Text(
                                              _selectedFolderName!,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.blue[900],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            );
                                          }
                                          
                                          // Otherwise show loading indicator
                                          return Row(
                                            children: [
                                              const SizedBox(
                                                height: 14,
                                                width: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Loading folder name...',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    ElevatedButton.icon(
                                      onPressed: _loadingSelectedFolderPath || !_hasSelectedFolderPath
                                          ? null
                                          : () async {
                                              // Navigate to the selected folder's location
                                              try {
                                                final pathLength = _selectedFolderPath.length;
                                                setState(() {
                                                  _folderPath = pathLength > 1
                                                      ? List<drive.File>.from(_selectedFolderPath.sublist(0, pathLength - 1))
                                                      : <drive.File>[];
                                                });
                                                // Load the parent folder's children
                                                if (pathLength > 1) {
                                                  final parentFolder = _selectedFolderPath[pathLength - 2];
                                                  await _loadFolders(configProvider, parentFolder.id);
                                                } else {
                                                  await _loadFolders(configProvider, null);
                                                }
                                              } catch (e) {
                                                // If error accessing path, just reload root
                                                setState(() {
                                                  _folderPath = <drive.File>[];
                                                });
                                                await _loadFolders(configProvider, null);
                                              }
                                            },
                                      icon: const Icon(Icons.arrow_forward, size: 16),
                                      label: Text(AppLocalizations.of(context)!.navigateToFolder),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue[700],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _loadingFolders
                                      ? null
                                      : () async {
                                          // Reset to root when refreshing
                                          setState(() {
                                            _folderPath.clear();
                                          });
                                          await _loadFolders(configProvider, null);
                                        },
                                  icon: _loadingFolders
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                                  label: Text(_loadingFolders ? AppLocalizations.of(context)!.loading : AppLocalizations.of(context)!.refresh),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _loadingFolders
                                    ? null
                                    : () async {
                                        await _createFolder(configProvider);
                                      },
                                icon: const Icon(Icons.create_new_folder),
                                label: Text(AppLocalizations.of(context)!.create),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          // Breadcrumb navigation
                          if (_hasFolderPath) ...[
                            const SizedBox(height: 16),
                            Card(
                              color: Colors.blue[50],
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back, size: 20),
                                      onPressed: _loadingFolders
                                          ? null
                                          : () async {
                                              await _navigateBack(configProvider);
                                            },
                                      tooltip: AppLocalizations.of(context)!.goBack,
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            TextButton(
                                              onPressed: () async {
                                                setState(() {
                                                  _folderPath.clear();
                                                });
                                                await _loadFolders(configProvider, null);
                                              },
                                              child: const Text('My Drive'),
                                            ),
                                            for (var folder in _folderPath) ...[
                                              const Icon(Icons.chevron_right, size: 16),
                                              TextButton(
                                                onPressed: folder.id != null
                                                    ? () async {
                                                        final index = _folderPath.indexOf(folder);
                                                        setState(() {
                                                          _folderPath = _folderPath.sublist(0, index + 1);
                                                        });
                                                        await _loadFolders(configProvider, folder.id);
                                                      }
                                                    : null,
                                                child: Text(
                                                  folder.name ?? 'Unnamed',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (_hasFolders) ...[
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.selectOrNavigateFolder,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 300,
                              child: ListView.builder(
                                itemCount: _folders.length,
                                itemBuilder: (context, index) {
                                  final folder = _folders[index];
                                  final isSelected = folder.id == _selectedFolderId;
                                  final itemL10n = AppLocalizations.of(context)!;
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    color: isSelected ? Colors.blue[50] : null,
                                    child: ListTile(
                                      title: Text(folder.name ?? itemL10n.unnamed),
                                      leading: const Icon(Icons.folder, color: Colors.blue),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isSelected) ...[
                                            const Icon(Icons.check_circle, color: Colors.green, size: 24),
                                            const SizedBox(width: 8),
                                          ],
                                          IconButton(
                                            icon: const Icon(Icons.arrow_forward),
                                            onPressed: folder.id != null
                                                ? () async {
                                                    await _navigateIntoFolder(configProvider, folder);
                                                  }
                                                : null,
                                            tooltip: itemL10n.navigateIntoFolder,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.check),
                                            onPressed: folder.id != null
                                                ? () async {
                                                    final previousFolderId = _selectedFolderId;
                                                    setState(() {
                                                      _selectedFolderId = folder.id;
                                                      _selectedFolderName = folder.name;
                                                    });
                                                    // Auto-save folder selection
                                                    await configProvider.setFolderId(folder.id!);
                                                    
                                                    // If folder changed (not just selected for first time), restore state
                                                    if (previousFolderId != null && previousFolderId != folder.id) {
                                                      // Clear person names when folder changes
                                                      _person1Controller.clear();
                                                      _person2Controller.clear();
                                                      _hasShownPersonNamePrompt = false;
                                                      _hasShownCategoryPrompt = false;
                                                    }
                                                    
                                                    // Load the full path of the selected folder
                                                    _loadSelectedFolderPath(configProvider);
                                                    
                                                    // Check folder data and restore state
                                                    if (context.mounted) {
                                                      _checkFolderDataAndRestoreState(configProvider);
                                                    }
                                                    
                                                    if (context.mounted) {
                                                      final snackL10n = AppLocalizations.of(context)!;
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(snackL10n.folderSelectedAndSaved(folder.name ?? itemL10n.unnamed)),
                                                          backgroundColor: Colors.green,
                                                          duration: const Duration(seconds: 2),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                : null,
                                            tooltip: itemL10n.selectThisFolder,
                                            color: Colors.green,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Person Names Section - Only show if signed in
                if (configProvider.isSignedIn) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.personNames,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Show message if folder is not selected
                          if (configProvider.driveService.folderId == null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange[200]!),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 20, color: Colors.orange[700]),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      AppLocalizations.of(context)!.selectFolderFirstToEnterPersonNames,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.orange[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextField(
                            controller: _person1Controller,
                            enabled: configProvider.driveService.folderId != null,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.person1Name,
                              border: const OutlineInputBorder(),
                              hintText: configProvider.driveService.folderId == null
                                  ? AppLocalizations.of(context)!.selectFolderFirst
                                  : AppLocalizations.of(context)!.enterFirstName,
                              helperText: configProvider.driveService.folderId == null
                                  ? AppLocalizations.of(context)!.folderMustBeSelected
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _person2Controller,
                            enabled: configProvider.driveService.folderId != null,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.person2Name,
                              border: const OutlineInputBorder(),
                              hintText: configProvider.driveService.folderId == null
                                  ? AppLocalizations.of(context)!.selectFolderFirst
                                  : AppLocalizations.of(context)!.enterSecondName,
                              helperText: configProvider.driveService.folderId == null
                                  ? AppLocalizations.of(context)!.folderMustBeSelected
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: configProvider.driveService.folderId == null
                        ? null
                        : () async {
                            await _saveConfig(configProvider);
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.saveConfiguration,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
                        SegmentedButton<AppThemeMode>(
                          segments: [
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
                          ],
                          selected: {configProvider.themeMode},
                          onSelectionChanged: (Set<AppThemeMode> selected) {
                            if (selected.isNotEmpty) {
                              configProvider.setThemeMode(selected.first);
                            }
                          },
                        ),
                        const SizedBox(height: 24),
                        // Language Selection
                        Row(
                          children: [
                            Icon(Icons.language, color: Theme.of(context).colorScheme.primary),
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
                              label: Text(AppLocalizations.of(context)!.english),
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

                // Clear Configuration Button - Only show if signed in
                if (configProvider.isSignedIn) ...[
                  OutlinedButton.icon(
                  onPressed: configProvider.isLoading
                      ? null
                      : () async {
                          final l10n = AppLocalizations.of(context)!;
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(l10n.clearAllConfiguration),
                              content: Text(l10n.clearAllConfigMessage),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: Text(l10n.cancel),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: Text(l10n.clearAll),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true && context.mounted) {
                            await configProvider.clearAllConfig();
                            if (context.mounted) {
                              final snackL10n = AppLocalizations.of(context)!;
                              // Reset form fields
                              _person1Controller.clear();
                              _person2Controller.clear();
                              setState(() {
                                _selectedFolderId = null;
                                _selectedFolderName = null;
                                _selectedFolderPath = <drive.File>[];
                                _folders.clear();
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(snackL10n.allConfigCleared),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: Text(
                    AppLocalizations.of(context)!.clearAllConfigurationButton,
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
                ],
                
                // App Version Display
                if (_appVersion.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Version $_appVersion',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
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
