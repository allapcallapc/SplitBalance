import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/bills_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/config_provider.dart';
import '../providers/pending_payments_provider.dart';
import '../models/bill.dart';
import '../utils/category_icons.dart';
import '../widgets/app_bar_action_icon_button.dart';
import 'add_edit_bill_screen.dart';
import 'bill_recovered_amounts_screen.dart';
import 'pending_payments_screen.dart';

class BillsListScreen extends StatefulWidget {
  const BillsListScreen({super.key});

  @override
  State<BillsListScreen> createState() => _BillsListScreenState();
}

class _BillsListScreenState extends State<BillsListScreen>
    with WidgetsBindingObserver {
  ConfigProvider? _configProvider;
  String? _lastLoadedHouseholdId; // Track which household we loaded data for
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadPendingPayments();
    });
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

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Start loading the next page a bit before hitting the bottom so it's
    // ready by the time the user gets there.
    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      final configProvider = _configProvider ?? context.read<ConfigProvider>();
      context.read<BillsProvider>().loadMoreBills(configProvider);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPendingPayments();
    }
  }

  Future<void> _loadPendingPayments() async {
    final pendingPaymentsProvider = context.read<PendingPaymentsProvider>();
    if (pendingPaymentsProvider.isSupported) {
      await pendingPaymentsProvider.loadPending();
    }
  }

  void _onConfigChanged() {
    if (!mounted || _configProvider == null) return;

    final currentHouseholdId = _configProvider!.householdId;

    // Reload data if household changes
    if (_configProvider!.isSignedIn &&
        currentHouseholdId != null &&
        currentHouseholdId != _lastLoadedHouseholdId) {
      // Household changed or just joined/created - reload data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadData() async {
    final configProvider = _configProvider ?? context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();
    final categoriesProvider = context.read<CategoriesProvider>();

    if (configProvider.isSignedIn && configProvider.householdId != null) {
      _lastLoadedHouseholdId = configProvider.householdId;
      await billsProvider.loadBills(configProvider);
      await categoriesProvider.loadCategories(configProvider);
      unawaited(billsProvider.loadFilterOptions(configProvider));
    }
  }

  // Bills only store the category name (not an id/reference), so look up
  // the matching Category to get its icon. Falls back to the default icon
  // if the category was since renamed/deleted or has no icon set.
  IconData _iconForCategory(
      String categoryName, CategoriesProvider categoriesProvider) {
    for (final category in categoriesProvider.categories) {
      if (category.name == categoryName) {
        return category.iconData;
      }
    }
    return defaultCategoryIcon;
  }

  // Filters live behind a single icon button in the app bar, which opens a
  // modal bottom sheet with the person/category dropdowns. Both filters are
  // independent and combinable; "All" (null) clears a given filter.
  void _showFilterModal(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Without this, Material 3 clamps the sheet to a centered, capped
      // width on wide viewports, which reads as a floating dialog stranded
      // in the middle of the screen rather than an edge-to-edge sheet.
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Consumer2<BillsProvider, ConfigProvider>(
              builder: (context, billsProvider, configProvider, child) {
                // billsProvider.paidByOptions/categoryOptions come from a
                // dedicated distinct-values query (loadFilterOptions), so
                // renamed/removed payers and categories stay filterable even
                // though bills themselves are now fetched page-by-page.
                final personOptions = <String>{
                  if (configProvider.config.person1Name.isNotEmpty)
                    configProvider.config.person1Name,
                  if (configProvider.config.person2Name.isNotEmpty)
                    configProvider.config.person2Name,
                  ...billsProvider.paidByOptions,
                  if (billsProvider.filterPaidBy != null)
                    billsProvider.filterPaidBy!,
                }.toList()
                  ..sort();

                return Consumer<CategoriesProvider>(
                  builder: (context, categoriesProvider, child) {
                    final categoryOptions = <String>{
                      for (final category in categoriesProvider.categories)
                        category.name,
                      ...billsProvider.categoryOptions,
                      // Keep the currently active filter selectable even if
                      // it no longer matches a live category or a value
                      // loadFilterOptions() has picked up yet.
                      if (billsProvider.filterCategory != null)
                        billsProvider.filterCategory!,
                    }.toList()
                      ..sort();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              l10n.filters,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            if (billsProvider.hasActiveFilters)
                              TextButton(
                                onPressed: () =>
                                    billsProvider.clearFilters(configProvider),
                                child: Text(l10n.clearFilters),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: billsProvider.filterPaidBy,
                          decoration: InputDecoration(
                            labelText: l10n.filterByPerson,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(l10n.allPeople),
                            ),
                            for (final person in personOptions)
                              DropdownMenuItem<String?>(
                                value: person,
                                child: Text(person),
                              ),
                          ],
                          onChanged: (value) {
                            billsProvider.setPaidByFilter(
                                value, configProvider);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String?>(
                          initialValue: billsProvider.filterCategory,
                          decoration: InputDecoration(
                            labelText: l10n.filterByCategory,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(l10n.allCategories),
                            ),
                            for (final category in categoryOptions)
                              DropdownMenuItem<String?>(
                                value: category,
                                child: Text(category),
                              ),
                          ],
                          onChanged: (value) {
                            billsProvider.setCategoryFilter(
                                value, configProvider);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Sort lives behind a tonal chip in the app bar (next to the filter
  // icon) that always shows the current order. Tapping it opens a modal
  // bottom sheet with segmented buttons for field and direction, mirroring
  // the filter sheet above.
  String _sortLabel(AppLocalizations l10n, BillsProvider billsProvider) {
    if (billsProvider.sortField == BillSortField.date) {
      return billsProvider.sortAscending ? l10n.sortOldest : l10n.sortNewest;
    }
    return billsProvider.sortAscending ? l10n.sortLowest : l10n.sortHighest;
  }

  void _showSortModal(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Consumer2<BillsProvider, ConfigProvider>(
              builder: (context, billsProvider, configProvider, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.sortBy,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<BillSortField>(
                      segments: [
                        ButtonSegment(
                          value: BillSortField.date,
                          label: Text(l10n.date),
                          icon: const Icon(Icons.calendar_today),
                        ),
                        ButtonSegment(
                          value: BillSortField.amount,
                          label: Text(l10n.amount),
                          icon: const Icon(Icons.attach_money),
                        ),
                      ],
                      selected: {billsProvider.sortField},
                      onSelectionChanged: (selection) {
                        billsProvider.setSort(
                          selection.first,
                          billsProvider.sortAscending,
                          configProvider,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(
                              billsProvider.sortField == BillSortField.date
                                  ? l10n.sortNewest
                                  : l10n.sortHighest),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(
                              billsProvider.sortField == BillSortField.date
                                  ? l10n.sortOldest
                                  : l10n.sortLowest),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                      selected: {billsProvider.sortAscending},
                      onSelectionChanged: (selection) {
                        billsProvider.setSort(
                          billsProvider.sortField,
                          selection.first,
                          configProvider,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteBill(BuildContext context, int index, Bill bill) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteBill),
        content: Text(
            '${l10n.areYouSureDeleteBill}\n\n${bill.details.isNotEmpty ? bill.details : "${DateFormat('yyyy-MM-dd').format(bill.date)} - \$${bill.amount.toStringAsFixed(2)}"}'),
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
      final billsProvider = context.read<BillsProvider>();
      await billsProvider.deleteBill(index, configProvider);
      if (context.mounted && billsProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(billsProvider.error!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              width: 32,
              cacheWidth: 96,
              cacheHeight: 96,
            ),
            const SizedBox(width: 12),
            // Flexible so a long sort label doesn't push the title into
            // overflowing behind the actions on narrow screens/locales; it
            // truncates with an ellipsis instead.
            Flexible(
              child: Text(
                l10n.bills,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Consumer<BillsProvider>(
            builder: (context, billsProvider, child) {
              final scheme = Theme.of(context).colorScheme;
              // Built by hand rather than with ActionChip: Chip's built-in
              // avatar slot carries extra asymmetric internal spacing that
              // padding/labelPadding can't fully override, which left the
              // icon and label unevenly spaced from the pill's edges.
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Tooltip(
                  message: l10n.sortByTooltip,
                  child: Material(
                    color: scheme.secondaryContainer,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => _showSortModal(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              billsProvider.sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                              color: scheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortLabel(l10n, billsProvider),
                              style:
                                  TextStyle(color: scheme.onSecondaryContainer),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Consumer<BillsProvider>(
            builder: (context, billsProvider, child) => AppBarActionIconButton(
              icon: Badge(
                isLabelVisible: billsProvider.hasActiveFilters,
                smallSize: 8,
                alignment: AlignmentDirectional.topEnd,
                offset: const Offset(2, -2),
                child: const Icon(Icons.filter_list),
              ),
              onPressed: () => _showFilterModal(context),
              tooltip: l10n.filters,
            ),
          ),
          const SizedBox(width: 4),
          AppBarActionIconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddEditBillScreen(),
                ),
              );
              if (result == true && mounted) {
                await _loadData();
              }
            },
            tooltip: l10n.addBillTooltip,
          ),
          const SizedBox(width: 4),
          AppBarActionIconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: l10n.refreshTooltip,
          ),
        ],
      ),
      body: Column(
        children: [
          Consumer<PendingPaymentsProvider>(
            builder: (context, pendingPaymentsProvider, child) {
              final pendingCount =
                  pendingPaymentsProvider.pendingPayments.length;
              if (!pendingPaymentsProvider.isSupported || pendingCount == 0) {
                return const SizedBox.shrink();
              }

              return MaterialBanner(
                content: Text(l10n.pendingPaymentsBannerMessage(pendingCount)),
                leading: const Icon(Icons.payments_outlined),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PendingPaymentsScreen(),
                        ),
                      );
                      if (mounted) {
                        await _loadData();
                      }
                    },
                    child: Text(l10n.review),
                  ),
                ],
              );
            },
          ),
          Expanded(
            child: Consumer2<BillsProvider, CategoriesProvider>(
              builder: (context, billsProvider, categoriesProvider, child) {
                if (billsProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (billsProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.error(billsProvider.error!),
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            billsProvider.clearError();
                            _loadData();
                          },
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  );
                }

                if (billsProvider.bills.isEmpty) {
                  if (billsProvider.hasActiveFilters) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.filter_alt_off,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noBillsMatchFilters,
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => billsProvider
                                .clearFilters(context.read<ConfigProvider>()),
                            icon: const Icon(Icons.filter_alt_off),
                            label: Text(l10n.clearFilters),
                          ),
                        ],
                      ),
                    );
                  }

                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.noBillsYet,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddEditBillScreen(),
                              ),
                            );
                            if (result == true && mounted) {
                              await _loadData();
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: Text(l10n.addYourFirstBill),
                        ),
                      ],
                    ),
                  );
                }

                final visibleBills = billsProvider.bills;

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: visibleBills.length +
                      (billsProvider.isLoadingMore ? 1 : 0),
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, listIndex) {
                    if (listIndex >= visibleBills.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final bill = visibleBills[listIndex];
                    // Provider mutation methods (update/delete) address bills
                    // by their index in the currently loaded list, which
                    // matches listIndex since visibleBills is billsProvider.bills.
                    final index = listIndex;
                    final dateFormat = DateFormat('yyyy-MM-dd');
                    final currencyFormat = NumberFormat.currency(symbol: '\$');

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Icon(
                            _iconForCategory(bill.category, categoriesProvider),
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                                '${l10n.date}: ${dateFormat.format(bill.date)}'),
                            if (bill.recoveredAmount > 0)
                              Row(
                                children: [
                                  Text(
                                    '${l10n.amount}: ',
                                  ),
                                  Text(
                                    currencyFormat.format(bill.amount),
                                    style: const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    currencyFormat.format(bill.netAmount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                  '${l10n.amount}: ${currencyFormat.format(bill.amount)}'),
                            Text('${l10n.paidBy}: ${bill.paidBy}'),
                            Text('${l10n.category}: ${bill.category}'),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(l10n.edit,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () async {
                                    if (!context.mounted) return;
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddEditBillScreen(
                                          bill: bill,
                                          index: index,
                                        ),
                                      ),
                                    );
                                    if (result == true && context.mounted) {
                                      await _loadData();
                                    }
                                  },
                                );
                              },
                            ),
                            PopupMenuItem(
                              child: Row(
                                children: [
                                  const Icon(Icons.currency_exchange,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(l10n.recoveredAmounts,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () async {
                                    if (!context.mounted) return;
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            BillRecoveredAmountsScreen(
                                                bill: bill),
                                      ),
                                    );
                                    if (context.mounted) {
                                      // Recovered amounts are added/deleted
                                      // through RecoveredAmountsProvider,
                                      // which BillsProvider knows nothing
                                      // about - _loadData() below only
                                      // refreshes the paginated `bills` list,
                                      // so force a fresh allBills fetch too,
                                      // otherwise the Summary screen's
                                      // monthly/cumulative spend charts
                                      // (which read allBills, cached since
                                      // it's normally only refetched on bill
                                      // add/edit/delete) keep showing
                                      // pre-recovery totals until something
                                      // else happens to invalidate that
                                      // cache.
                                      final configProvider =
                                          context.read<ConfigProvider>();
                                      await billsProvider
                                          .loadAllBills(configProvider);
                                      await _loadData();
                                    }
                                  },
                                );
                              },
                            ),
                            PopupMenuItem(
                              child: Row(
                                children: [
                                  const Icon(Icons.delete,
                                      size: 20, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(l10n.delete,
                                        style: const TextStyle(
                                            color: Colors.red),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () {
                                    if (context.mounted) {
                                      _deleteBill(context, index, bill);
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
