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
    _tabController.dispose();
    super.dispose();
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
    
    final configProvider = context.read<ConfigProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    
    if (!configProvider.isSignedIn || configProvider.driveService.folderId == null) {
      return;
    }

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

class _PaymentSplitsTab extends StatelessWidget {
  const _PaymentSplitsTab();

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
    PaymentSplit? split,
    int? index,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.read<ConfigProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();

    final dateFormat = DateFormat('yyyy-MM-dd');
    DateTime startDate = split?.startDate ?? DateTime.now();
    DateTime endDate = split?.endDate ?? DateTime.now();
    String? category = split?.category;
    double person1Percentage = split?.person1Percentage ?? 50.0;
    double person2Percentage = split?.person2Percentage ?? 50.0;

    final TextEditingController percentageController = TextEditingController(
      text: person1Percentage.toStringAsFixed(1),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
            title: Text(split == null ? l10n.addPaymentSplit : l10n.editPaymentSplit),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(l10n.startDate),
                    subtitle: Text(dateFormat.format(startDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          startDate = picked;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text(l10n.endDate),
                    subtitle: Text(dateFormat.format(endDate)),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          endDate = picked;
                        });
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(
                      labelText: l10n.category,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'all',
                        child: Text(l10n.allCategories),
                      ),
                      ...categoriesProvider.categories
                          .map((cat) => DropdownMenuItem<String>(
                                value: cat.name,
                                child: Text(cat.name),
                              )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        category = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
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
                    divisions: 100,
                    label: '${person1Percentage.toStringAsFixed(1)}%',
                    onChanged: (value) {
                      setState(() {
                        person1Percentage = value;
                        person2Percentage = 100 - value;
                        percentageController.text = value.toStringAsFixed(1);
                      });
                    },
                  ),
                  Text(l10n.personPercentageDisplay(configProvider.config.person2Name, person2Percentage.toStringAsFixed(1))),
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
                if (category == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.selectCategory)),
                  );
                  return;
                }

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
                  final newSplit = PaymentSplit(
                    startDate: startDate,
                    endDate: endDate,
                    category: category!,
                    person1: configProvider.config.person1Name,
                    person1Percentage: person1Percentage,
                    person2: configProvider.config.person2Name,
                    person2Percentage: person2Percentage,
                  );

                  if (index != null) {
                    await splitsProvider.updatePaymentSplit(
                      index,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<PaymentSplitsProvider>(
      builder: (context, splitsProvider, child) {
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

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: () => _PaymentSplitsTab.showAddEditSplitDialog(context, null, null),
                icon: const Icon(Icons.add),
                label: Text(l10n.addPaymentSplit),
              ),
            ),
            Expanded(
              child: splitsProvider.splits.isEmpty
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
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: splitsProvider.splits.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final split = splitsProvider.splits[index];
                        final dateFormat = DateFormat('yyyy-MM-dd');
                        final itemL10n = AppLocalizations.of(context)!;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              '${split.category} (${split.person1Percentage.toStringAsFixed(0)}% / ${split.person2Percentage.toStringAsFixed(0)}%)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${dateFormat.format(split.startDate)} ${itemL10n.to} ${dateFormat.format(split.endDate)}',
                                ),
                                Text(itemL10n.paymentSplitPersonDisplay(split.person1, split.person1Percentage.toStringAsFixed(1))),
                                Text(itemL10n.paymentSplitPersonDisplay(split.person2, split.person2Percentage.toStringAsFixed(1))),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit, size: 20),
                                      const SizedBox(width: 8),
                                      Text(itemL10n.edit),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _PaymentSplitsTab.showAddEditSplitDialog(
                                        context,
                                        split,
                                        index,
                                      ),
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete,
                                          size: 20, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Text(itemL10n.delete,
                                          style: const TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _PaymentSplitsTab.deleteSplit(context, index),
                                    );
                                  },
                                ),
                              ],
                            ),
                            isThreeLine: true,
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
        
        // Use read instead of watch to avoid unnecessary rebuilds
        // We only need bills and splits for the isCategoryInUse check, not to rebuild on changes
        // Get the values here after early returns to ensure they're in scope when used
        final billsData = context.read<BillsProvider>().bills;
        final splitsData = context.read<PaymentSplitsProvider>().splits;
        
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
                        // Check if category is in use using the bills and splits we read earlier
                        // This avoids reading from context during itemBuilder execution
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
      final configProvider = context.read<ConfigProvider>();
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
