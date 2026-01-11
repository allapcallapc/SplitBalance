import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../providers/bills_provider.dart';
import '../models/payment_split.dart';
import '../models/category.dart';

class PaymentSplitsScreen extends StatefulWidget {
  const PaymentSplitsScreen({super.key});

  @override
  State<PaymentSplitsScreen> createState() => _PaymentSplitsScreenState();
}

class _PaymentSplitsScreenState extends State<PaymentSplitsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingData = false;
  ConfigProvider? _configProvider;
  String? _lastLoadedFolderId; // Track which folder we loaded data for

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _checkNavigateToCategoriesTab();
    });
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configProvider = context.read<ConfigProvider>();
    
    // Set up listener only once
    if (_configProvider != configProvider) {
      _configProvider?.removeListener(_onConfigChanged);
      _configProvider = configProvider;
      _configProvider?.addListener(_onConfigChanged);
    }
  }

  void _onConfigChanged() {
    if (!mounted || _configProvider == null) return;
    
    final currentFolderId = _configProvider!.driveService.folderId;
    
    // Reload data if folder changes
    if (_configProvider!.isSignedIn && 
        currentFolderId != null && 
        currentFolderId != _lastLoadedFolderId) {
      // Folder changed or just selected - reload data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
          _checkNavigateToCategoriesTab();
        }
      });
    }
  }
  
  void _checkNavigateToCategoriesTab() {
    // Check if we should navigate to Categories tab (requested from "Go to Categories" button)
    final configProvider = context.read<ConfigProvider>();
    if (configProvider.navigateToCategoriesTabRequested) {
      // Switch to Categories tab (index 1)
      if (_tabController.index != 1) {
        _tabController.animateTo(1);
      }
      configProvider.clearNavigateToCategoriesTabRequest();
    }
  }

  Future<void> _loadData() async {
    // Prevent multiple simultaneous calls
    if (_isLoadingData) return;
    
    final configProvider = _configProvider ?? context.read<ConfigProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

    _lastLoadedFolderId = configProvider.driveService.folderId;
    _isLoadingData = true;
    try {
      // Load categories first, then splits
      await categoriesProvider.loadCategories(configProvider);
      await splitsProvider.loadPaymentSplits(configProvider);
    } finally {
      _isLoadingData = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Check if we should navigate to Categories tab (check once per build to avoid loops)
    final configProvider = context.read<ConfigProvider>();
    if (configProvider.navigateToCategoriesTabRequested) {
      // Schedule check after build to switch tabs
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkNavigateToCategoriesTab();
        }
      });
    }
    
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
            Text(l10n.splitsAndCategories),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.paymentSplits, icon: const Icon(Icons.account_balance_wallet)),
            Tab(text: l10n.categories, icon: const Icon(Icons.category)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PaymentSplitsTab(),
          _CategoriesTab(),
        ],
      ),
    );
  }
}

class _PaymentSplitsTab extends StatefulWidget {
  const _PaymentSplitsTab();

  @override
  State<_PaymentSplitsTab> createState() => _PaymentSplitsTabState();
}

class _PaymentSplitsTabState extends State<_PaymentSplitsTab> {
  // Track newly added periods that should be displayed even without splits
  final Set<DateTime> _pendingPeriods = {};
  List<PaymentSplit> _previousSplits = [];
  bool _cleanupScheduled = false;

  void _addPendingPeriod(DateTime date) {
    setState(() {
      _pendingPeriods.add(DateTime(date.year, date.month, date.day));
    });
  }

  void _removePendingPeriod(DateTime date) {
    setState(() {
      _pendingPeriods.remove(DateTime(date.year, date.month, date.day));
    });
  }

  void _cleanupPendingPeriods(List<PaymentSplit> currentSplits) {
    // Clean up pending periods that now have splits
    final splitsDates = <DateTime>{};
    for (final split in currentSplits) {
      if (split.endDate != null) {
        splitsDates.add(DateTime(
          split.endDate!.year,
          split.endDate!.month,
          split.endDate!.day,
        ));
      }
    }
    
    final toRemove = _pendingPeriods.where((pendingDate) {
      return splitsDates.any((splitDate) => 
        splitDate.year == pendingDate.year &&
        splitDate.month == pendingDate.month &&
        splitDate.day == pendingDate.day);
    }).toSet();
    
    if (toRemove.isNotEmpty) {
      setState(() {
        _pendingPeriods.removeAll(toRemove);
        _cleanupScheduled = false;
      });
    } else {
      _cleanupScheduled = false;
    }
    
    _previousSplits = List.from(currentSplits);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer2<PaymentSplitsProvider, CategoriesProvider>(
      builder: (context, splitsProvider, categoriesProvider, child) {
        if (splitsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (splitsProvider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.error(splitsProvider.error!),
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    splitsProvider.clearError();
                  },
                  child: Text(l10n.dismiss),
                ),
              ],
            ),
          );
        }

        final categories = ['all', ...categoriesProvider.categories.map((c) => c.name)];
        final splits = splitsProvider.splits;
        
        // Clean up pending periods when splits change (schedule once per change)
        final splitsChanged = splits.length != _previousSplits.length;
        if (splitsChanged && !_cleanupScheduled && _pendingPeriods.isNotEmpty) {
          _cleanupScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _cleanupPendingPeriods(splits);
            }
          });
        }
        if (!splitsChanged) {
          _previousSplits = List.from(splits);
        }
        
        // Collect all unique end dates, sorted
        final endDates = <DateTime>{};
        for (final split in splits) {
          if (split.endDate != null) {
            endDates.add(DateTime(
              split.endDate!.year,
              split.endDate!.month,
              split.endDate!.day,
            ));
          }
        }
        
        // Include pending periods that don't have splits yet
        for (final pendingDate in _pendingPeriods) {
          final hasSplits = endDates.any((splitDate) => 
            splitDate.year == pendingDate.year &&
            splitDate.month == pendingDate.month &&
            splitDate.day == pendingDate.day);
          if (!hasSplits) {
            endDates.add(pendingDate);
          }
        }
        
        final sortedEndDates = endDates.toList()..sort();
        
        // Add empty end date at the end (represents current/future)
        final allPeriods = [...sortedEndDates, null]; // null = empty/current period
        
        return Column(
          children: [
            Expanded(
              child: categories.length <= 1 && splits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.account_balance_wallet,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noPaymentSplits,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add categories first, then configure splits',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : _SplitConfigTable(
                      categories: categories,
                      periods: allPeriods,
                      splits: splits,
                      splitsProvider: splitsProvider,
                      categoriesProvider: categoriesProvider,
                      onCellTap: (category, periodEndDate) async {
                        // If this is a pending period (no splits yet), remove it from pending
                        // when a split is created for it
                        if (periodEndDate != null && _pendingPeriods.isNotEmpty) {
                          final normalizedDate = DateTime(
                            periodEndDate.year,
                            periodEndDate.month,
                            periodEndDate.day,
                          );
                          final isPending = _pendingPeriods.any((p) => 
                            p.year == normalizedDate.year &&
                            p.month == normalizedDate.month &&
                            p.day == normalizedDate.day);
                          
                          if (isPending) {
                            // Check if split was actually created by checking splits after dialog closes
                            final splitCountBefore = splits.length;
                            await _PaymentSplitsTabHelper.showAddEditSplitDialog(
                              context,
                              category,
                              periodEndDate,
                              sortedEndDates,
                            );
                            // If a split was added, remove from pending
                            if (context.mounted) {
                              final splitsAfter = splitsProvider.splits;
                              if (splitsAfter.length > splitCountBefore) {
                                _removePendingPeriod(normalizedDate);
                              }
                            }
                          } else {
                            await _PaymentSplitsTabHelper.showAddEditSplitDialog(
                              context,
                              category,
                              periodEndDate,
                              sortedEndDates,
                            );
                          }
                        } else {
                          await _PaymentSplitsTabHelper.showAddEditSplitDialog(
                            context,
                            category,
                            periodEndDate,
                            sortedEndDates,
                          );
                        }
                      },
                      onPeriodEdit: (periodEndDate) {
                        _PaymentSplitsTabHelper.showEditPeriodDialog(
                          context,
                          periodEndDate,
                          sortedEndDates,
                          splits,
                          splitsProvider,
                          categoriesProvider,
                        );
                      },
                      onPeriodAdd: () async {
                        final result = await _PaymentSplitsTabHelper.showAddPeriodDialog(
                          context,
                          sortedEndDates,
                          splitsProvider,
                          categoriesProvider,
                        );
                        if (result != null) {
                          _addPendingPeriod(result);
                        }
                      },
                      onPeriodDelete: (periodEndDate) {
                        _PaymentSplitsTabHelper.deletePeriod(
                          context,
                          periodEndDate,
                          splits,
                          splitsProvider,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PaymentSplitsTabHelper {
  static Future<void> deleteSplit(BuildContext context, int index) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePaymentSplit),
        content: Text(l10n.deletePaymentSplitMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final configProvider = context.read<ConfigProvider>();
      final splitsProvider = context.read<PaymentSplitsProvider>();
      await splitsProvider.deletePaymentSplit(index, configProvider);
      if (context.mounted && splitsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(splitsProvider.error!)),
        );
      }
    }
  }

  static Future<void> showAddEditSplitDialog(
    BuildContext context,
    String? category,
    DateTime? periodEndDate,
    List<DateTime> allEndDates,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();

    // Find existing split for this category and period
    PaymentSplit? existingSplit;
    int? existingIndex;
    for (int i = 0; i < splitsProvider.splits.length; i++) {
      final split = splitsProvider.splits[i];
      if (split.category == category && split.endDate == periodEndDate) {
        existingSplit = split;
        existingIndex = i;
        break;
      }
    }

    final dateFormat = DateFormat('yyyy-MM-dd');
    DateTime? endDate = periodEndDate ?? existingSplit?.endDate;
    String? selectedCategory = category ?? existingSplit?.category;
    double person1Percentage = existingSplit?.person1Percentage ?? 50.0;
    double person2Percentage = existingSplit?.person2Percentage ?? 50.0;

    // Ensure the current endDate is included in the dropdown items list
    // Normalize dates to just the date part (remove time) for proper comparison
    final normalizeDate = (DateTime dt) => DateTime(dt.year, dt.month, dt.day);
    final normalizedEndDate = endDate != null ? normalizeDate(endDate) : null;
    
    // Create a normalized list that includes the current date if it's not already there
    final availableDates = <DateTime>[...allEndDates];
    if (normalizedEndDate != null && !availableDates.any((d) => 
        normalizeDate(d) == normalizedEndDate)) {
      availableDates.add(normalizedEndDate);
      availableDates.sort();
    }
    
    // Normalize the endDate for dropdown comparison
    if (endDate != null) {
      endDate = normalizeDate(endDate);
    }

    final TextEditingController percentageController = TextEditingController(
      text: person1Percentage.toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
            title: Text(existingSplit == null ? l10n.addPaymentSplit : l10n.editPaymentSplit),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Display category and period as read-only information at the top
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.category,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.category,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedCategory == 'all' 
                                  ? l10n.allCategories 
                                  : selectedCategory ?? 'N/A',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.endDate,
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                () {
                                  if (endDate == null) return 'Current/Future';
                                  return dateFormat.format(endDate);
                                }(),
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(l10n.personPercentage(configProvider.config.person1Name)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: percentageController,
                    decoration: InputDecoration(
                      labelText: l10n.personPercentage(configProvider.config.person1Name),
                      suffixText: '%',
                      border: const OutlineInputBorder(),
                      helperText: '0-100',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed >= 0 && parsed <= 100) {
                        setState(() {
                          person1Percentage = parsed;
                          person2Percentage = 100 - parsed;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: person1Percentage.clamp(0.0, 100.0),
                    min: 0,
                    max: 100,
                    divisions: 1000,
                    label: '${person1Percentage.toStringAsFixed(2)}%',
                    onChanged: (value) {
                      setState(() {
                        person1Percentage = value;
                        person2Percentage = 100 - value;
                        percentageController.text = value.toStringAsFixed(2);
                      });
                    },
                  ),
                  Text(l10n.personPercentageDisplay(configProvider.config.person2Name, person2Percentage.toStringAsFixed(2))),
                ],
              ),
            ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                // Category and period are set from the cell - they're required
                final finalCategory = category ?? selectedCategory;
                if (finalCategory == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.selectCategory)),
                  );
                  return;
                }

                final finalEndDate = periodEndDate ?? endDate;
                // Note: endDate can be null for Current/Future period, which is valid

                // Validate percentage from text field
                final textValue = double.tryParse(percentageController.text);
                if (textValue != null && textValue >= 0 && textValue <= 100) {
                  person1Percentage = textValue;
                  person2Percentage = 100 - textValue;
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid percentage between 0 and 100')),
                  );
                  return;
                }

                try {
                  // Handle "all" category as bulk change - apply to all categories in this period
                  if (finalCategory == 'all') {
                    // Get all categories (excluding "all")
                    final categoryNames = categoriesProvider.categories.map((c) => c.name).toList();
                    
                    // Apply the percentages to all categories for this period
                    for (final catName in categoryNames) {
                      // Find existing split for this category and period
                      int? existingCatIndex;
                      for (int i = 0; i < splitsProvider.splits.length; i++) {
                        final split = splitsProvider.splits[i];
                        if (split.category == catName && split.endDate == finalEndDate) {
                          existingCatIndex = i;
                          break;
                        }
                      }
                      
                      final catSplit = PaymentSplit(
                        endDate: finalEndDate,
                        category: catName,
                        person1: configProvider.config.person1Name,
                        person1Percentage: person1Percentage,
                        person2: configProvider.config.person2Name,
                        person2Percentage: person2Percentage,
                      );
                      
                      if (existingCatIndex != null) {
                        await splitsProvider.updatePaymentSplit(
                          existingCatIndex,
                          catSplit,
                          configProvider,
                          categoriesProvider.categories,
                        );
                      } else {
                        await splitsProvider.addPaymentSplit(
                          catSplit,
                          configProvider,
                          categoriesProvider.categories,
                        );
                      }
                    }
                  } else {
                    // Regular category - save normally
                    final newSplit = PaymentSplit(
                      endDate: finalEndDate,
                      category: finalCategory,
                      person1: configProvider.config.person1Name,
                      person1Percentage: person1Percentage,
                      person2: configProvider.config.person2Name,
                      person2Percentage: person2Percentage,
                    );

                    if (existingIndex != null) {
                      await splitsProvider.updatePaymentSplit(
                        existingIndex,
                        newSplit,
                        configProvider,
                        categoriesProvider.categories,
                      );
                    } else {
                      await splitsProvider.addPaymentSplit(
                        newSplit,
                        configProvider,
                        categoriesProvider.categories,
                      );
                    }
                  }

                  if (context.mounted) {
                    if (splitsProvider.error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(splitsProvider.error!)),
                      );
                    } else {
                      Navigator.pop(context);
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.error(e.toString()))),
                    );
                  }
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    percentageController.dispose();
  }

  static Future<void> showEditPeriodDialog(
    BuildContext context,
    DateTime? periodEndDate,
    List<DateTime> allEndDates,
    List<PaymentSplit> allSplits,
    PaymentSplitsProvider splitsProvider,
    CategoriesProvider categoriesProvider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final configProvider = context.read<ConfigProvider>();
    DateTime? newEndDate = periodEndDate;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(periodEndDate == null ? 'Edit Current/Future Period' : 'Edit Period'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodEndDate == null 
                    ? 'Current/Future period cannot be edited. You can only change the date of other periods.'
                    : 'Change the end date for this period. All splits in this period will be updated.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (periodEndDate != null) ...[
                  ListTile(
                    title: const Text('Current date'),
                    subtitle: Text(dateFormat.format(periodEndDate)),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('New date'),
                    subtitle: Text(newEndDate == null ? 'Select a date' : dateFormat.format(newEndDate!)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: newEndDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          newEndDate = picked;
                        });
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            if (periodEndDate != null)
              ElevatedButton(
                onPressed: newEndDate == null || newEndDate == periodEndDate
                    ? null
                    : () async {
                        // Update all splits with the old endDate to the new endDate
                        final splitsToUpdate = allSplits
                            .where((s) => s.endDate == periodEndDate)
                            .toList();
                        
                        for (final split in splitsToUpdate) {
                          final index = allSplits.indexWhere((s) => s == split);
                          if (index >= 0) {
                            final updatedSplit = split.copyWith(endDate: newEndDate);
                            await splitsProvider.updatePaymentSplit(
                              index,
                              updatedSplit,
                              configProvider,
                              categoriesProvider.categories,
                            );
                          }
                        }
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                child: Text(l10n.save),
              ),
          ],
        ),
      ),
    );
  }

  static Future<DateTime?> showAddPeriodDialog(
    BuildContext context,
    List<DateTime> existingEndDates,
    PaymentSplitsProvider splitsProvider,
    CategoriesProvider categoriesProvider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd');
    DateTime? newEndDate;

    final result = await showDialog<DateTime?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Period'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select a date to create a new period. You will then be prompted to add a split for this period.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('End Date'),
                subtitle: Text(newEndDate == null ? 'Select a date' : dateFormat.format(newEndDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() {
                      newEndDate = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: newEndDate == null
                  ? null
                  : () {
                      Navigator.pop(context, newEndDate);
                    },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );

    // Return the new date so the caller can display it in the table
    return result;
  }

  static Future<void> deletePeriod(
    BuildContext context,
    DateTime? periodEndDate,
    List<PaymentSplit> allSplits,
    PaymentSplitsProvider splitsProvider,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final configProvider = context.read<ConfigProvider>();
    
    // Find all splits for this period
    final splitsToDelete = allSplits
        .where((s) => s.endDate == periodEndDate)
        .toList();
    
    if (splitsToDelete.isEmpty) {
      // No splits to delete, just confirm
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          String message;
          if (periodEndDate == null) {
            message = 'Are you sure you want to remove the Current/Future period column?';
          } else {
            message = 'Are you sure you want to remove the period ending ${dateFormat.format(periodEndDate)}? This will delete all splits in this period.';
          }
          
          return AlertDialog(
            title: Text(periodEndDate == null ? 'Remove Current/Future Period?' : 'Remove Period?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(l10n.delete),
              ),
            ],
          );
        },
      );
      
      if (confirmed == true && context.mounted) {
        // Period is already empty, nothing to do
        Navigator.pop(context);
      }
      return;
    }

    // Confirm deletion
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(periodEndDate == null ? 'Delete Current/Future Period?' : 'Delete Period?'),
        content: Text(
          'This will delete ${splitsToDelete.length} split(s) in this period. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Delete all splits for this period in reverse order to maintain indices
      for (int i = splitsToDelete.length - 1; i >= 0; i--) {
        final split = splitsToDelete[i];
        final index = splitsProvider.splits.indexWhere((s) => s == split);
        if (index >= 0) {
          await splitsProvider.deletePaymentSplit(index, configProvider);
        }
      }
      
      if (context.mounted && splitsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(splitsProvider.error!)),
        );
      }
    }
  }
}

// Table widget for displaying split configuration
class _SplitConfigTable extends StatelessWidget {
  final List<String> categories;
  final List<DateTime?> periods;
  final List<PaymentSplit> splits;
  final PaymentSplitsProvider splitsProvider;
  final CategoriesProvider categoriesProvider;
  final Function(String category, DateTime? periodEndDate) onCellTap;
  final Function(DateTime? periodEndDate) onPeriodEdit;
  final Function() onPeriodAdd;
  final Function(DateTime? periodEndDate) onPeriodDelete;

  const _SplitConfigTable({
    required this.categories,
    required this.periods,
    required this.splits,
    required this.splitsProvider,
    required this.categoriesProvider,
    required this.onCellTap,
    required this.onPeriodEdit,
    required this.onPeriodAdd,
    required this.onPeriodDelete,
  });

  // Find split for category and period
  // For "all" category, compute a representative split based on all categories in that period
  PaymentSplit? findSplit(String category, DateTime? periodEndDate) {
    // Handle "all" category specially - compute from individual category splits
    if (category == 'all') {
      // Find all splits for this period (excluding "all" category)
      final periodSplits = splits.where((s) => 
        s.category != 'all' && s.endDate == periodEndDate
      ).toList();
      
      if (periodSplits.isEmpty) {
        return null; // No splits for this period
      }
      
      // Check if all categories have the same percentages
      final firstPercentage = periodSplits[0].person1Percentage;
      final allSame = periodSplits.every((s) => 
        (s.person1Percentage - firstPercentage).abs() < 0.01
      );
      
      if (allSame && periodSplits.length == categoriesProvider.categories.length) {
        // All categories have the same percentage - return representative split
        return PaymentSplit(
          endDate: periodEndDate,
          category: 'all',
          person1: periodSplits[0].person1,
          person1Percentage: firstPercentage,
          person2: periodSplits[0].person2,
          person2Percentage: periodSplits[0].person2Percentage,
        );
      }
      
      // Not all categories have the same percentage - return null (show as empty)
      return null;
    }
    
    // Regular category - find exact match
    for (final split in splits) {
      if (split.category == category && split.endDate == periodEndDate) {
        return split;
      }
    }
    return null;
  }

  // Calculate total percentage for a period
  // Only count individual category splits, not "all" category (which is UI-only)
  double calculatePeriodTotal(DateTime? periodEndDate) {
    double total = 0.0;
    // Only count actual category splits, exclude "all" category
    final categoryNames = categories.where((c) => c != 'all').toList();
    for (final category in categoryNames) {
      final split = findSplit(category, periodEndDate);
      if (split != null) {
        total += split.person1Percentage;
      }
    }
    return total;
  }

  // Check if period has missing percentages
  // A period has missing percentages if not all categories have splits defined
  bool hasMissingPercentages(DateTime? periodEndDate) {
    // Get all actual categories (excluding "all")
    final categoryNames = categoriesProvider.categories.map((c) => c.name).toList();
    
    // Check if all categories have splits for this period
    for (final category in categoryNames) {
      final hasSplit = splits.any((s) => 
        s.category == category && s.endDate == periodEndDate
      );
      if (!hasSplit) {
        return true; // At least one category is missing
      }
    }
    
    return false; // All categories have splits
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final configProvider = context.read<ConfigProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with theme colors
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    // Category header cell
                    Container(
                      width: 160,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        l10n.category,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    // Period header cells - editable columns
                    ...periods.map((periodEndDate) {
                      final isMissing = hasMissingPercentages(periodEndDate);
                      final missingAmount = 100.0 - calculatePeriodTotal(periodEndDate);
                      return PeriodHeader(
                        periodEndDate: periodEndDate,
                        dateFormat: dateFormat,
                        isMissing: isMissing,
                        missingAmount: missingAmount,
                        theme: theme,
                        colorScheme: colorScheme,
                        onTap: () => onPeriodEdit(periodEndDate),
                        onDelete: () => onPeriodDelete(periodEndDate),
                      );
                    }),
                    // Add column button
                    Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colorScheme.outline.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onPeriodAdd,
                          borderRadius: BorderRadius.circular(4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                color: colorScheme.primary,
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add Period',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Divider
              Divider(height: 1, color: colorScheme.outline.withOpacity(0.2)),
              // Data rows
              ...categories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final isLast = index == categories.length - 1;
                
                return Column(
                  children: [
                    Row(
                      children: [
                        // Category name cell
                        Container(
                          width: 160,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: index % 2 == 0 
                              ? colorScheme.surface 
                              : colorScheme.surfaceVariant.withOpacity(0.3),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                category == 'all' ? Icons.category : Icons.label,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  category == 'all' ? l10n.allCategories : category,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Percentage cells for each period
                        ...periods.map((periodEndDate) {
                          final split = findSplit(category, periodEndDate);
                          final splitIndex = split != null 
                            ? splits.indexWhere((s) => s == split) 
                            : -1;
                          
                          return _SplitCell(
                            split: split,
                            periodEndDate: periodEndDate,
                            dateFormat: dateFormat,
                            configProvider: configProvider,
                            onTap: () => onCellTap(category, periodEndDate),
                            onDelete: splitIndex >= 0 
                              ? () => _PaymentSplitsTabHelper.deleteSplit(context, splitIndex)
                              : null,
                            theme: theme,
                            colorScheme: colorScheme,
                            index: index,
                          );
                        }),
                      ],
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        indent: 0,
                        endIndent: 0,
                        color: colorScheme.outline.withOpacity(0.1),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// Period header widget - editable column header
class PeriodHeader extends StatelessWidget {
  final DateTime? periodEndDate;
  final DateFormat dateFormat;
  final bool isMissing;
  final double missingAmount;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const PeriodHeader({
    required this.periodEndDate,
    required this.dateFormat,
    required this.isMissing,
    required this.missingAmount,
    required this.theme,
    required this.colorScheme,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      () {
                        if (periodEndDate == null) return 'Current/Future';
                        return dateFormat.format(periodEndDate!);
                      }(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isMissing 
                          ? colorScheme.error 
                          : colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (periodEndDate != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: colorScheme.error.withOpacity(0.7),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 20,
                        minHeight: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      tooltip: 'Delete period',
                    ),
                  ],
                  if (isMissing) ...[
                    const SizedBox(width: 2),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Individual cell widget for better organization
class _SplitCell extends StatelessWidget {
  final PaymentSplit? split;
  final DateTime? periodEndDate;
  final DateFormat dateFormat;
  final ConfigProvider configProvider;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final int index;

  const _SplitCell({
    required this.split,
    required this.periodEndDate,
    required this.dateFormat,
    required this.configProvider,
    required this.onTap,
    this.onDelete,
    required this.theme,
    required this.colorScheme,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final cellColor = index % 2 == 0 
      ? colorScheme.surface 
      : colorScheme.surfaceVariant.withOpacity(0.3);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cellColor,
            border: Border(
              left: BorderSide(
                color: colorScheme.outline.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: split == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: colorScheme.primary.withOpacity(0.5),
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Person 1 row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${split!.person1Percentage.toStringAsFixed(2)}%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            Text(
                              configProvider.config.person1Name,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (onDelete != null)
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 14,
                            color: colorScheme.error.withOpacity(0.7),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                          tooltip: 'Delete',
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Person 2 row
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${split!.person2Percentage.toStringAsFixed(2)}%',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.secondary,
                        ),
                      ),
                      Text(
                        configProvider.config.person2Name,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _CategoriesTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<CategoriesProvider>(
      builder: (context, categoriesProvider, child) {
        // Show loading indicator only if there are no categories yet and we're loading
        // If we have categories, show them even during loading to prevent flickering
        final isEmptyAndLoading = categoriesProvider.categories.isEmpty && categoriesProvider.isLoading;

        if (isEmptyAndLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (categoriesProvider.error != null && categoriesProvider.categories.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.error(categoriesProvider.error!),
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    categoriesProvider.clearError();
                  },
                  child: Text(l10n.dismiss),
                ),
              ],
            ),
          );
        }
        
        // Use watch to rebuild when bills or splits change so "in use" status updates correctly
        final billsData = context.watch<BillsProvider>().bills;
        final splitsData = context.watch<PaymentSplitsProvider>().splits;
        
        // Show error banner if there's an error but we have categories to display
        final hasError = categoriesProvider.error != null;

        return Column(
          children: [
            // Show error banner at top if there's an error (but don't block the list)
            if (hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                color: Colors.red.shade100,
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        categoriesProvider.error!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: Colors.red.shade700,
                      onPressed: () => categoriesProvider.clearError(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: categoriesProvider.isLoading ? null : () => _showAddCategoryDialog(context),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addCategory),
                    ),
                  ),
                  // Show loading indicator next to button if loading
                  if (categoriesProvider.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: categoriesProvider.categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.category,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noCategories,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.addCategoriesToOrganize,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: categoriesProvider.categories.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final category = categoriesProvider.categories[index];
                        // Check if category is in use using the bills and splits watched in build method
                        // billsData and splitsData are watched, so the widget rebuilds when they change
                        final isInUse = categoriesProvider.isCategoryInUse(
                          category.name,
                          billsData,
                          splitsData,
                        );

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.category),
                            title: Text(category.name),
                            subtitle: isInUse
                                ? Text(
                                    l10n.inUseCannotDelete,
                                    style: const TextStyle(color: Colors.orange),
                                  )
                                : null,
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit, size: 20),
                                      const SizedBox(width: 8),
                                      Text(l10n.edit),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _showEditCategoryDialog(
                                        context,
                                        category,
                                        index,
                                      ),
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  enabled: !isInUse,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        size: 20,
                                        color: isInUse ? Colors.grey : Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.delete,
                                        style: TextStyle(
                                          color: isInUse ? Colors.grey : Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: isInUse
                                      ? null
                                      : () {
                                          Future.delayed(
                                            const Duration(milliseconds: 100),
                                            () => _deleteCategory(
                                              context,
                                              category,
                                              index,
                                              isInUse,
                                            ),
                                          );
                                        },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final categoriesProvider = context.read<CategoriesProvider>();
    final configProvider = context.read<ConfigProvider>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addCategory),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.category,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.enterCategoryName)),
                );
                return;
              }

              await categoriesProvider.addCategory(
                Category(name: name),
                configProvider,
              );

              if (context.mounted) {
                if (categoriesProvider.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(categoriesProvider.error!)),
                  );
                } else {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showEditCategoryDialog(
    BuildContext context,
    Category category,
    int index,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: category.name);
    final categoriesProvider = context.read<CategoriesProvider>();
    final configProvider = context.read<ConfigProvider>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.editCategory),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.category,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.enterCategoryName)),
                );
                return;
              }

              await categoriesProvider.updateCategory(
                index,
                Category(name: name),
                configProvider,
              );

              if (context.mounted) {
                if (categoriesProvider.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(categoriesProvider.error!)),
                  );
                } else {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _deleteCategory(
    BuildContext context,
    Category category,
    int index,
    bool isInUse,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (isInUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.categoryInUse),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteCategory),
        content: Text(l10n.deleteCategoryMessage(category.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final categoriesProvider = context.read<CategoriesProvider>();
      final splitsProvider = context.read<PaymentSplitsProvider>();
      final configProvider = context.read<ConfigProvider>();
      
      // Remove payment splits that reference this category
      await splitsProvider.removeSplitsByCategory(category.name, configProvider);
      
      // Delete the category
      await categoriesProvider.deleteCategory(
        index,
        configProvider,
        isCategoryUsed: isInUse,
      );
      if (context.mounted && categoriesProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(categoriesProvider.error!)),
        );
      }
    }
  }
}
