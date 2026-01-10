import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/bill.dart';
import '../providers/bills_provider.dart';
import '../providers/config_provider.dart';
import '../providers/categories_provider.dart';

class AddEditBillScreen extends StatefulWidget {
  final Bill? bill;
  final int? index;

  const AddEditBillScreen({super.key, this.bill, this.index});

  @override
  State<AddEditBillScreen> createState() => _AddEditBillScreenState();
}

class _AddEditBillScreenState extends State<AddEditBillScreen> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  final _amountController = TextEditingController();
  String? _selectedPaidBy;
  String? _selectedCategory;
  final _detailsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final configProvider = context.read<ConfigProvider>();
    
    if (widget.bill != null) {
      _selectedDate = widget.bill!.date;
      _amountController.text = widget.bill!.amount.toStringAsFixed(2);
      _selectedPaidBy = widget.bill!.paidBy;
      _selectedCategory = widget.bill!.category;
      _detailsController.text = widget.bill!.details;
    } else {
      _selectedDate = DateTime.now();
      _amountController.text = '';
      _selectedPaidBy = configProvider.config.person1Name.isNotEmpty
          ? configProvider.config.person1Name
          : null;
      _selectedCategory = null;
      _detailsController.text = '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveBill() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    if (_selectedPaidBy == null || _selectedPaidBy!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectWhoPaid)),
      );
      return;
    }

    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.selectCategory)),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterValidAmount)),
      );
      return;
    }

    final configProvider = context.read<ConfigProvider>();
    final billsProvider = context.read<BillsProvider>();

    final bill = Bill(
      date: _selectedDate,
      amount: amount,
      paidBy: _selectedPaidBy!,
      category: _selectedCategory!,
      details: _detailsController.text.trim(),
    );

    try {
      if (widget.index != null) {
        await billsProvider.updateBill(widget.index!, bill, configProvider);
      } else {
        await billsProvider.addBill(bill, configProvider);
      }

      if (mounted) {
        if (billsProvider.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(billsProvider.error!)),
          );
        } else {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorSavingBill(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final configProvider = context.watch<ConfigProvider>();
    final categoriesProvider = context.watch<CategoriesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bill == null ? l10n.addBill : l10n.editBill),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date picker
              ListTile(
                title: Text(l10n.date),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
              const Divider(),

              // Amount
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: l10n.amount,
                  prefixText: '\$ ',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.enterAmount;
                  }
                  final amount = double.tryParse(value.trim());
                  if (amount == null || amount <= 0) {
                    return l10n.enterValidAmount;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Paid by dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedPaidBy,
                decoration: InputDecoration(
                  labelText: l10n.paidBy,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  if (configProvider.config.person1Name.isNotEmpty)
                    DropdownMenuItem(
                      value: configProvider.config.person1Name,
                      child: Text(configProvider.config.person1Name),
                    ),
                  if (configProvider.config.person2Name.isNotEmpty)
                    DropdownMenuItem(
                      value: configProvider.config.person2Name,
                      child: Text(configProvider.config.person2Name),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPaidBy = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n.selectWhoPaid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  labelText: l10n.category,
                  border: const OutlineInputBorder(),
                ),
                items: categoriesProvider.categories
                    .map((category) => DropdownMenuItem<String>(
                          value: category.name,
                          child: Text(category.name),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l10n.selectCategory;
                  }
                  return null;
                },
              ),
              if (categoriesProvider.categories.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.noCategoriesAvailable,
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Details
              TextFormField(
                controller: _detailsController,
                decoration: InputDecoration(
                  labelText: l10n.detailsOptional,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Save button
              ElevatedButton(
                onPressed: _saveBill,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  l10n.saveBill,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
