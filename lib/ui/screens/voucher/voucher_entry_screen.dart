import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/ledger.dart';
import '../../../data/models/voucher.dart';
import '../../../data/models/voucher_line.dart';
import '../../../providers/double_entry_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/auth_provider.dart';

class VoucherEntryScreen extends ConsumerStatefulWidget {
  const VoucherEntryScreen({super.key});

  @override
  ConsumerState<VoucherEntryScreen> createState() => _VoucherEntryScreenState();
}

class _VoucherEntryScreenState extends ConsumerState<VoucherEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _voucherNoController = TextEditingController();
  final _narrationController = TextEditingController();
  final _dateController = TextEditingController(text: DateFormat('dd-MMM-yyyy').format(DateTime.now()));

  DateTime _selectedDate = DateTime.now();
  String _selectedType = 'JOURNAL'; // Default to JOURNAL
  AppUser? _selectedUser;
  
  final List<_VoucherLineRow> _lineRows = [];
  final DateFormat _dateFormatter = DateFormat('dd-MMM-yyyy');

  @override
  void initState() {
    super.initState();
    // Start with 2 empty rows (a double entry needs at least two lines)
    _addLineRow();
    _addLineRow();
    _generateVoucherNumber();
  }

  @override
  void dispose() {
    _voucherNoController.dispose();
    _narrationController.dispose();
    _dateController.dispose();
    for (final row in _lineRows) {
      row.dispose();
    }
    super.dispose();
  }

  void _generateVoucherNumber() {
    final prefix = _selectedType.substring(0, 3).toUpperCase();
    final randomPart = const Uuid().v4().substring(0, 4).toUpperCase();
    _voucherNoController.text = '$prefix/$randomPart';
  }

  void _addLineRow() {
    setState(() {
      _lineRows.add(_VoucherLineRow.createEmpty());
    });
  }

  void _removeLineRow(int index) {
    if (_lineRows.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A double-entry voucher requires at least 2 lines.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _lineRows[index].dispose();
      _lineRows.removeAt(index);
    });
  }

  double get _totalDr {
    return _lineRows.fold(0.0, (sum, row) => sum + (double.tryParse(row.drController.text) ?? 0.0));
  }

  double get _totalCr {
    return _lineRows.fold(0.0, (sum, row) => sum + (double.tryParse(row.crController.text) ?? 0.0));
  }

  double get _difference {
    return (_totalDr - _totalCr).abs();
  }

  bool get _isBalanced {
    return _difference < 0.001 && _totalDr > 0;
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
        _dateController.text = _dateFormatter.format(_selectedDate);
      });
    }
  }

  Future<void> _saveVoucher() async {
    if (!_formKey.currentState!.validate()) return;

    if (_lineRows.any((row) => row.selectedLedger == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a ledger for all lines.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_isBalanced) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voucher is unbalanced! Total DR: $_totalDr must equal Total CR: $_totalCr.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Determine current user role for lock bypassing
    final userRole = _selectedUser?.role;

    // Build models
    final company = ref.read(activeCompanyProvider);
    final fy = ref.read(activeFinancialYearProvider);

    if (company == null || fy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active company or financial year configured.'), backgroundColor: Colors.red),
      );
      return;
    }

    final String voucherId = const Uuid().v4();
    final voucher = Voucher(
      id: voucherId,
      voucherNo: _voucherNoController.text.trim(),
      type: _selectedType,
      date: _selectedDate,
      narration: _narrationController.text.trim().isEmpty ? null : _narrationController.text.trim(),
      companyId: company.id,
      fyId: fy.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final List<VoucherLine> lines = _lineRows.map((row) {
      return VoucherLine(
        id: const Uuid().v4(),
        voucherId: voucherId,
        ledgerId: row.selectedLedger!.id,
        drAmount: double.tryParse(row.drController.text) ?? 0.0,
        crAmount: double.tryParse(row.crController.text) ?? 0.0,
        narration: row.narrationController.text.trim().isEmpty ? null : row.narrationController.text.trim(),
      );
    }).toList();

    // Challenge PIN if selected user is configured
    if (_selectedUser != null) {
      final pin = await _promptForPin(context, _selectedUser!.name);
      if (pin == null) return; // Cancelled

      final authenticatedUser = await ref.read(userProvider.notifier).authenticate(_selectedUser!.id, pin);
      if (authenticatedUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid PIN! Authentication failed.'), backgroundColor: Colors.red),
          );
        }
        return;
      }
    }

    try {
      final deviceId = ref.read(authProvider).deviceId;
      final engine = ref.read(voucherEngineProvider);
      await engine.postVoucher(
        voucher: voucher,
        lines: lines,
        userRole: userRole,
        deviceId: deviceId,
      );

      // Refresh providers
      ref.invalidate(trialBalanceProvider);
      ref.invalidate(profitLossProvider);
      ref.invalidate(balanceSheetProvider);
      ref.read(ledgersProvider.notifier).loadLedgers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voucher posted successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post voucher: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _promptForPin(BuildContext context, String username) {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enter PIN for $username'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '4-Digit PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, pinController.text), child: const Text('Verify')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledgersState = ref.watch(ledgersProvider);
    final usersState = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Double-Entry Voucher Input'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Header Bar
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedType,
                            decoration: const InputDecoration(labelText: 'Voucher Type'),
                            items: const [
                              DropdownMenuItem(value: 'JOURNAL', child: Text('Journal (రోజూవారీ పద్దు)')),
                              DropdownMenuItem(value: 'CONTRA', child: Text('Contra (వ్యతిరేక పద్దు)')),
                              DropdownMenuItem(value: 'RECEIPT', child: Text('Receipt (వసూలు)')),
                              DropdownMenuItem(value: 'PAYMENT', child: Text('Payment (చెల్లింపు)')),
                              DropdownMenuItem(value: 'SALE', child: Text('Sale Voucher (అమ్మకం)')),
                              DropdownMenuItem(value: 'PURCHASE', child: Text('Purchase Voucher (కొనుగోలు)')),
                              DropdownMenuItem(value: 'CREDIT_NOTE', child: Text('Credit Note')),
                              DropdownMenuItem(value: 'DEBIT_NOTE', child: Text('Debit Note')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedType = val;
                                  _generateVoucherNumber();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _voucherNoController,
                            decoration: const InputDecoration(labelText: 'Voucher No'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _dateController,
                            readOnly: true,
                            onTap: _selectDate,
                            decoration: const InputDecoration(
                              labelText: 'Date',
                              prefixIcon: Icon(Icons.calendar_today_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: usersState.maybeWhen(
                            data: (users) => DropdownButtonFormField<AppUser>(
                              initialValue: _selectedUser,
                              decoration: const InputDecoration(
                                labelText: 'User / Auditor (Bypass Role)',
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                              hint: const Text('None (Default User)'),
                              items: users.map((u) {
                                return DropdownMenuItem(
                                  value: u,
                                  child: Text('${u.name} (${u.role})'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedUser = val;
                                });
                              },
                            ),
                            orElse: () => const SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _narrationController,
                      decoration: const InputDecoration(
                        labelText: 'Narration (Optional)',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Dynamic Rows Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TRANSACTION DETAILS',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Add Row'),
                    onPressed: _addLineRow,
                  ),
                ],
              ),
            ),

            // Dynamic Rows list
            Expanded(
              child: ledgersState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error loading ledgers: $err')),
                data: (ledgers) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _lineRows.length,
                  itemBuilder: (ctx, idx) {
                    final row = _lineRows[idx];
                    return Card(
                      key: ValueKey(row.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: theme.colorScheme.secondaryContainer,
                                  child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<Ledger>(
                                    initialValue: row.selectedLedger,
                                    decoration: const InputDecoration(labelText: 'Select Ledger'),
                                    items: ledgers.map((l) {
                                      return DropdownMenuItem(
                                        value: l,
                                        child: Text('${l.name} (${l.balanceType})'),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        row.selectedLedger = val;
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                  onPressed: () => _removeLineRow(idx),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: row.drController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'Debit Amount (Dr)'),
                                    onChanged: (v) {
                                      if (v.isNotEmpty) {
                                        row.crController.text = '0.0';
                                      }
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: row.crController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(labelText: 'Credit Amount (Cr)'),
                                    onChanged: (v) {
                                      if (v.isNotEmpty) {
                                        row.drController.text = '0.0';
                                      }
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: row.narrationController,
                              decoration: const InputDecoration(labelText: 'Item Narration (Optional)'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Footer Balance Indicator Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Dr: ₹ ${_totalDr.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Total Cr: ₹ ${_totalCr.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isBalanced ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _isBalanced ? 'Balanced' : 'Unbalanced (Diff: ₹ ${_difference.toStringAsFixed(2)})',
                            style: TextStyle(
                              color: _isBalanced ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Post Voucher'),
                          onPressed: _saveVoucher,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoucherLineRow {
  final String id;
  Ledger? selectedLedger;
  final TextEditingController drController;
  final TextEditingController crController;
  final TextEditingController narrationController;

  _VoucherLineRow({
    required this.id,
    required this.drController,
    required this.crController,
    required this.narrationController,
  });

  factory _VoucherLineRow.createEmpty() {
    return _VoucherLineRow(
      id: const Uuid().v4(),
      drController: TextEditingController(text: '0.0'),
      crController: TextEditingController(text: '0.0'),
      narrationController: TextEditingController(),
    );
  }

  void dispose() {
    drController.dispose();
    crController.dispose();
    narrationController.dispose();
  }
}
