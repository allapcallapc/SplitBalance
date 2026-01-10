import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/payment_splits_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../providers/bills_provider.dart';
import '../models/payment_split.dart';
import '../models/category.dart';
import '../widgets/google_sign_in_status.dart';

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
        title: const Text('Payment Splits & Categories'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Payment Splits', icon: Icon(Icons.account_balance_wallet)),
            Tab(text: 'Categories', icon: Icon(Icons.category)),
          ],
        ),
        actions: [
          const GoogleSignInStatus(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Payment Split'),
        content: const Text(
          'Are you sure you want to delete this payment split?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
    final configProvider = context.read<ConfigProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();
    final splitsProvider = context.read<PaymentSplitsProvider>();

    final dateFormat = DateFormat('yyyy-MM-dd');
    DateTime startDate = split?.startDate ?? DateTime.now();
    DateTime endDate = split?.endDate ?? DateTime.now();
    String? category = split?.category;
    double person1Percentage = split?.person1Percentage ?? 50.0;
    double person2Percentage = split?.person2Percentage ?? 50.0;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(split == null ? 'Add Payment Split' : 'Edit Payment Split'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Start Date'),
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
                  title: const Text('End Date'),
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
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('All Categories'),
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
                Text('${configProvider.config.person1Name} Percentage'),
                Slider(
                  value: person1Percentage,
                  min: 0,
                  max: 100,
                  divisions: 100,
                  label: '${person1Percentage.toStringAsFixed(1)}%',
                  onChanged: (value) {
                    setState(() {
                      person1Percentage = value;
                      person2Percentage = 100 - value;
                    });
                  },
                ),
                Text('${configProvider.config.person2Name} Percentage: ${person2Percentage.toStringAsFixed(1)}%'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (category == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a category')),
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
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  'Error: ${splitsProvider.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    splitsProvider.clearError();
                  },
                  child: const Text('Dismiss'),
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
                label: const Text('Add Payment Split'),
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
                          const Text(
                            'No payment splits yet',
                            style: TextStyle(
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
                                  '${dateFormat.format(split.startDate)} to ${dateFormat.format(split.endDate)}',
                                ),
                                Text('${split.person1}: ${split.person1Percentage.toStringAsFixed(1)}%'),
                                Text('${split.person2}: ${split.person2Percentage.toStringAsFixed(1)}%'),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: const Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Edit'),
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
                                  child: const Row(
                                    children: [
                                      Icon(Icons.delete,
                                          size: 20, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
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
                  'Error: ${categoriesProvider.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    categoriesProvider.clearError();
                  },
                  child: const Text('Dismiss'),
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
                      label: const Text('Add Category'),
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
                          const Text(
                            'No categories yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Add categories to organize your bills',
                            style: TextStyle(color: Colors.grey),
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
                                ? const Text(
                                    'In use (cannot delete)',
                                    style: TextStyle(color: Colors.orange),
                                  )
                                : null,
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: const Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Edit'),
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
                                        'Delete',
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
    final controller = TextEditingController();
    final categoriesProvider = context.read<CategoriesProvider>();
    final configProvider = context.read<ConfigProvider>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a category name')),
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
            child: const Text('Add'),
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
    final controller = TextEditingController(text: category.name);
    final categoriesProvider = context.read<CategoriesProvider>();
    final configProvider = context.read<ConfigProvider>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a category name')),
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
            child: const Text('Save'),
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
    if (isInUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete category that is in use'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
