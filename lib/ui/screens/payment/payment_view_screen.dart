import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/party.dart';
import '../../../data/models/payment.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/transaction_provider.dart';

class PaymentViewScreen extends ConsumerStatefulWidget {
  final Party? initialParty;

  const PaymentViewScreen({super.key, this.initialParty});

  @override
  ConsumerState<PaymentViewScreen> createState() => _PaymentViewScreenState();
}

class _PaymentViewScreenState extends ConsumerState<PaymentViewScreen> {
  Party? _filterParty;

  @override
  void initState() {
    super.initState();
    _filterParty = widget.initialParty;
  }

  void _showAddPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) => AddPaymentDialog(initialParty: _filterParty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactionState = ref.watch(transactionProvider);
    final parties = ref.watch(partyProvider).value ?? [];

    // Filter payments
    final filteredPayments = transactionState.payments.where((p) {
      if (_filterParty == null) return true;
      return p.partyId == _filterParty!.id;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments Ledger / చెల్లింపులు'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card_rounded),
            tooltip: 'Record Payment',
            onPressed: _showAddPaymentDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Party?>(
                    initialValue: _filterParty,
                    decoration: const InputDecoration(
                      labelText: 'Filter by Party / ఖాతాదారుని వడపోత',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Parties (అన్ని ఖాతాలు)')),
                      ...parties.map((p) => DropdownMenuItem(value: p.party, child: Text('${p.party.name} (${p.party.type == 'CUSTOMER' ? 'Cust' : 'Supp'})'))),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _filterParty = val;
                      });
                    },
                  ),
                ),
                if (_filterParty != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      setState(() {
                        _filterParty = null;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          // Payments List
          Expanded(
            child: filteredPayments.isEmpty
                ? Center(
                    child: Text(
                      'No payments recorded.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filteredPayments.length,
                    itemBuilder: (context, index) {
                      final payment = filteredPayments[index];
                      final isReceived = payment.direction == 'RECEIVED';
                      final color = isReceived ? Colors.green : Colors.orange.shade800;

                      // Find party name
                      final partyName = parties
                          .firstWhere((p) => p.party.id == payment.partyId,
                              orElse: () => PartyWithBalance(
                                  party: Party(
                                      id: '',
                                      name: 'Unknown Party',
                                      type: 'CUSTOMER',
                                      phone: '',
                                      address: '',
                                      createdAt: DateTime.now()),
                                  outstandingBalance: 0.0,
                                  balanceType: 'DR'))
                          .party
                          .name;

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            foregroundColor: color,
                            child: Icon(
                              isReceived ? Icons.call_received_rounded : Icons.call_made_rounded,
                              size: 18,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  partyName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                IndianFormatUtils.formatCurrency(payment.amount),
                                style: TextStyle(fontWeight: FontWeight.bold, color: color),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Mode: ${payment.mode} | Date: ${DateFormat('dd-MMM-yyyy').format(payment.date)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (payment.mode == 'CHEQUE') ...[
                                  Text(
                                    'Cheque No: ${payment.chequeNo ?? "N/A"} | Bank: ${payment.chequeBank ?? "N/A"}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  Text(
                                    'Cheque Date: ${payment.chequeDate != null ? DateFormat('dd-MMM-yyyy').format(payment.chequeDate!) : "N/A"} | Status: ${payment.chequeStatus ?? "N/A"}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                                if (payment.referenceNo != null && payment.referenceNo!.isNotEmpty)
                                  Text('Ref: ${payment.referenceNo}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                if (payment.notes != null && payment.notes!.isNotEmpty)
                                  Text('Notes: ${payment.notes}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Payment'),
                                  content: const Text('Are you sure you want to delete this payment record?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await ref.read(transactionProvider.notifier).deletePayment(payment.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Payment deleted successfully.')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AddPaymentDialog extends ConsumerStatefulWidget {
  final Party? initialParty;

  const AddPaymentDialog({super.key, this.initialParty});

  @override
  ConsumerState<AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends ConsumerState<AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  final _notesController = TextEditingController();
  final _dateController = TextEditingController(text: DateFormat('dd-MMM-yyyy').format(DateTime.now()));

  final _chequeNoController = TextEditingController();
  final _chequeBankController = TextEditingController();
  final _chequeDateController = TextEditingController(text: DateFormat('dd-MMM-yyyy').format(DateTime.now()));
  String _chequeStatus = 'ISSUED';
  DateTime _selectedChequeDate = DateTime.now();

  Party? _selectedParty;
  String _direction = 'RECEIVED'; // RECEIVED for customer, PAID for supplier
  String _mode = 'CASH'; // CASH, UPI, BANK, CHEQUE
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final parties = ref.read(partyProvider).value ?? [];
    if (widget.initialParty != null) {
      _selectedParty = parties.firstWhere((p) => p.party.id == widget.initialParty!.id).party;
      _direction = _selectedParty!.type == 'CUSTOMER' ? 'RECEIVED' : 'PAID';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _notesController.dispose();
    _dateController.dispose();
    _chequeNoController.dispose();
    _chequeBankController.dispose();
    _chequeDateController.dispose();
    super.dispose();
  }

  Future<void> _selectChequeDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedChequeDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedChequeDate) {
      setState(() {
        _selectedChequeDate = picked;
        _chequeDateController.text = DateFormat('dd-MMM-yyyy').format(_selectedChequeDate);
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a party.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final isModeCheque = _mode == 'CHEQUE';
    final payment = Payment(
      id: const Uuid().v4(),
      partyId: _selectedParty!.id,
      direction: _direction,
      amount: double.parse(_amountController.text.trim()),
      mode: _mode,
      date: _selectedDate,
      referenceNo: _refController.text.trim().isEmpty ? null : _refController.text.trim(),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: DateTime.now(),
      chequeNo: isModeCheque ? _chequeNoController.text.trim() : null,
      chequeBank: isModeCheque ? _chequeBankController.text.trim() : null,
      chequeDate: isModeCheque ? _selectedChequeDate : null,
      chequeStatus: isModeCheque ? _chequeStatus : null,
    );

    try {
      await ref.read(transactionProvider.notifier).addPayment(payment);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record payment: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parties = ref.watch(partyProvider).value ?? [];

    return AlertDialog(
      title: const Text('Record Payment'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Party Dropdown
              DropdownButtonFormField<Party>(
                initialValue: _selectedParty,
                decoration: const InputDecoration(labelText: 'Select Party *'),
                items: parties.map((p) {
                  return DropdownMenuItem(
                    value: p.party,
                    child: Text('${p.party.name} (${p.party.type == 'CUSTOMER' ? 'Cust' : 'Supp'})'),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedParty = val;
                    if (val != null) {
                      _direction = val.type == 'CUSTOMER' ? 'RECEIVED' : 'PAID';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // Direction
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: const InputDecoration(labelText: 'Transaction Direction'),
                items: const [
                  DropdownMenuItem(value: 'RECEIVED', child: Text('RECEIVED (వసూలు - Customer)')),
                  DropdownMenuItem(value: 'PAID', child: Text('PAID (చెల్లింపు - Supplier)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _direction = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (Rs) / మొత్తం *'),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter a valid amount' : null,
              ),
              const SizedBox(height: 12),

              // Mode
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Payment Mode / చెల్లింపు విధానం'),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('CASH (నగదు)')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI (జిపే/ఫోన్‌పే)')),
                  DropdownMenuItem(value: 'BANK', child: Text('BANK TRANSFER (బ్యాంకు బదిలీ)')),
                  DropdownMenuItem(value: 'CHEQUE', child: Text('CHEQUE (చెక్)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _mode = val;
                    });
                  }
                },
              ),
              if (_mode == 'CHEQUE') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _chequeNoController,
                  decoration: const InputDecoration(labelText: 'Cheque Number *'),
                  validator: (val) {
                    if (_mode == 'CHEQUE' && (val == null || val.trim().isEmpty)) {
                      return 'Enter cheque number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _chequeBankController,
                  decoration: const InputDecoration(labelText: 'Bank Name *'),
                  validator: (val) {
                    if (_mode == 'CHEQUE' && (val == null || val.trim().isEmpty)) {
                      return 'Enter bank name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _chequeDateController,
                  readOnly: true,
                  onTap: _selectChequeDate,
                  decoration: const InputDecoration(labelText: 'Cheque Date *'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _chequeStatus,
                  decoration: const InputDecoration(labelText: 'Cheque Status'),
                  items: const [
                    DropdownMenuItem(value: 'ISSUED', child: Text('ISSUED / RECEIVED (జారీ/స్వీకరించబడింది)')),
                    DropdownMenuItem(value: 'CLEARED', child: Text('CLEARED (క్లియర్ అయింది)')),
                    DropdownMenuItem(value: 'BOUNCED', child: Text('BOUNCED (బౌన్స్ అయింది)')),
                    DropdownMenuItem(value: 'CANCELLED', child: Text('CANCELLED (రద్దు చేయబడింది)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _chequeStatus = val;
                      });
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),

              // Date
              TextFormField(
                controller: _dateController,
                readOnly: true,
                onTap: _selectDate,
                decoration: const InputDecoration(labelText: 'Payment Date / తేదీ *'),
              ),
              const SizedBox(height: 12),

              // Reference No
              TextFormField(
                controller: _refController,
                decoration: const InputDecoration(
                  labelText: 'Reference No (Cheque/UPI ID)',
                  helperText: 'Optional.',
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / ఇతర వివరాలు',
                  helperText: 'Optional.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
