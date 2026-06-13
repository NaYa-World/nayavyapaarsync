import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/expense.dart';
import '../../../providers/expense_provider.dart';

class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  String _selectedCategory = 'ALL';
  DateTime _selectedMonth = DateTime.now();

  final DateFormat _monthFormatter = DateFormat('MMMM yyyy');

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  Future<void> _showExpenseFormDialog([Expense? expenseToEdit]) async {
    await showDialog(
      context: context,
      builder: (context) => ExpenseFormDialog(expenseToEdit: expenseToEdit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenseState = ref.watch(expenseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expenses / ఖర్చులు',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Filter Bar
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  // Month navigation
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: _previousMonth,
                      ),
                      Text(
                        _monthFormatter.format(_selectedMonth),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                  const Divider(),
                  // Category dropdown filter
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Category',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Categories')),
                      DropdownMenuItem(value: 'RENT', child: Text('Rent (అద్దె)')),
                      DropdownMenuItem(value: 'ELECTRICITY', child: Text('Electricity (కరెంట్ బిల్లు)')),
                      DropdownMenuItem(value: 'SALARY', child: Text('Salaries (జీతాలు)')),
                      DropdownMenuItem(value: 'HAMALI', child: Text('Hamali (కూలీ / హమాలీ)')),
                      DropdownMenuItem(value: 'MAINTENANCE', child: Text('Maintenance (మెయింటెనెన్స్)')),
                      DropdownMenuItem(value: 'FUEL', child: Text('Fuel / Transport (రవాణా / ఇంధనం)')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other Expenses (ఇతర ఖర్చులు)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedCategory = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Total & List Area
          Expanded(
            child: expenseState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: ${err.toString()}')),
              data: (expenses) {
                // Filter expenses by month and category
                final filtered = expenses.where((e) {
                  final matchesMonth = e.date.year == _selectedMonth.year && e.date.month == _selectedMonth.month;
                  final matchesCategory = _selectedCategory == 'ALL' || e.category == _selectedCategory;
                  return matchesMonth && matchesCategory;
                }).toList();

                final double totalExpenses = filtered.fold(0.0, (sum, e) => sum + e.amount);

                return Column(
                  children: [
                    // Summary Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.errorContainer, width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TOTAL MONTHLY EXPENSES',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${filtered.length} entries',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                          Text(
                            IndianFormatUtils.formatCurrency(totalExpenses),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Expenses List
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'No expenses logged for this period.',
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6)),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 80),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final expense = filtered[index];
                                final dateStr = DateFormat('dd-MMM-yyyy').format(expense.date);
                                
                                return Card(
                                  elevation: 1,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _getCategoryColor(expense.category).withOpacity(0.12),
                                      foregroundColor: _getCategoryColor(expense.category),
                                      child: Icon(_getCategoryIcon(expense.category)),
                                    ),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _getCategoryLabel(expense.category),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          IndianFormatUtils.formatCurrency(expense.amount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        if (expense.description.isNotEmpty) ...[
                                          Text(
                                            expense.description,
                                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                                          ),
                                          const SizedBox(height: 2),
                                        ],
                                        Row(
                                          children: [
                                            Text(
                                              dateStr,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                expense.paymentMethod,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (action) {
                                        if (action == 'edit') {
                                          _showExpenseFormDialog(expense);
                                        } else if (action == 'delete') {
                                          _confirmDelete(expense.id);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_rounded, size: 18),
                                              SizedBox(width: 8),
                                              Text('Edit'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: Colors.red)),
                                            ],
                                          ),
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
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showExpenseFormDialog(),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  void _confirmDelete(String expenseId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: const Text('Are you sure you want to delete this expense record? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(expenseProvider.notifier).deleteExpense(expenseId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense deleted successfully'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'RENT':
        return Icons.home_rounded;
      case 'ELECTRICITY':
        return Icons.electric_bolt_rounded;
      case 'SALARY':
        return Icons.people_rounded;
      case 'HAMALI':
        return Icons.work_rounded;
      case 'MAINTENANCE':
        return Icons.build_rounded;
      case 'FUEL':
        return Icons.local_shipping_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  Color _getCategoryColor(String cat) {
    switch (cat) {
      case 'RENT':
        return Colors.blue;
      case 'ELECTRICITY':
        return Colors.amber.shade700;
      case 'SALARY':
        return Colors.purple;
      case 'HAMALI':
        return Colors.orange;
      case 'MAINTENANCE':
        return Colors.brown;
      case 'FUEL':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _getCategoryLabel(String cat) {
    switch (cat) {
      case 'RENT':
        return 'Rent / అద్దె';
      case 'ELECTRICITY':
        return 'Electricity / కరెంట్';
      case 'SALARY':
        return 'Salaries / జీతాలు';
      case 'HAMALI':
        return 'Hamali / కూలీ';
      case 'MAINTENANCE':
        return 'Maintenance / మెయింటెనెన్స్';
      case 'FUEL':
        return 'Fuel & Transport / రవాణా';
      default:
        return 'Other / ఇతర ఖర్చులు';
    }
  }
}

class ExpenseFormDialog extends ConsumerStatefulWidget {
  final Expense? expenseToEdit;

  const ExpenseFormDialog({super.key, this.expenseToEdit});

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _dateController = TextEditingController();

  String _category = 'RENT';
  String _paymentMethod = 'CASH';
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.expenseToEdit != null) {
      final e = widget.expenseToEdit!;
      _category = e.category;
      _amountController.text = e.amount.toString();
      _descController.text = e.description;
      _paymentMethod = e.paymentMethod;
      _selectedDate = e.date;
    }
    _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final double amount = double.parse(_amountController.text);
    final String description = _descController.text.trim();

    final isEdit = widget.expenseToEdit != null;
    final expense = Expense(
      id: widget.expenseToEdit?.id ?? const Uuid().v4(),
      category: _category,
      amount: amount,
      date: _selectedDate,
      description: description,
      paymentMethod: _paymentMethod,
      createdAt: widget.expenseToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      isDeleted: widget.expenseToEdit?.isDeleted ?? false,
    );

    if (isEdit) {
      await ref.read(expenseProvider.notifier).editExpense(expense);
    } else {
      await ref.read(expenseProvider.notifier).addExpense(expense);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.expenseToEdit != null;
    
    return AlertDialog(
      title: Text(isEdit ? 'Edit Expense Record' : 'Record New Expense'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Expense Category *'),
                items: const [
                  DropdownMenuItem(value: 'RENT', child: Text('Rent (అద్దె)')),
                  DropdownMenuItem(value: 'ELECTRICITY', child: Text('Electricity (కరెంట్ బిల్లు)')),
                  DropdownMenuItem(value: 'SALARY', child: Text('Salaries (జీతాలు)')),
                  DropdownMenuItem(value: 'HAMALI', child: Text('Hamali (హమాలీ / కూలీ)')),
                  DropdownMenuItem(value: 'MAINTENANCE', child: Text('Maintenance (మెయింటెనెన్స్)')),
                  DropdownMenuItem(value: 'FUEL', child: Text('Fuel / Transport (రవాణా)')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other (ఇతర ఖర్చులు)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _category = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (₹) *',
                  hintText: 'Enter amount',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Required';
                  if (double.tryParse(val) == null || double.parse(val) <= 0) return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Date picker
              TextFormField(
                controller: _dateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Expense Date *',
                  suffixIcon: Icon(Icons.calendar_month_rounded),
                ),
                onTap: _selectDate,
              ),
              const SizedBox(height: 12),

              // Payment method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment Method *'),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('CASH (నగదు)')),
                  DropdownMenuItem(value: 'BANK', child: Text('BANK / UPI (బ్యాంకు)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _paymentMethod = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Description
              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Narration / Description',
                  hintText: 'e.g. Paid shop rent for June',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: Text(isEdit ? 'Save Changes' : 'Record Expense')),
      ],
    );
  }
}
