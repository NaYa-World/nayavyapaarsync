import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/bank_reconciliation.dart';
import '../../../providers/double_entry_provider.dart';

class BrsScreen extends ConsumerStatefulWidget {
  const BrsScreen({super.key});

  @override
  ConsumerState<BrsScreen> createState() => _BrsScreenState();
}

class _BrsScreenState extends ConsumerState<BrsScreen> {
  String? _selectedBankLedgerId;
  final DateFormat _dateFormatter = DateFormat('dd-MMM-yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledgersAsync = ref.watch(ledgersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank Reconciliation (BRS)'),
      ),
      body: ledgersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (ledgers) {
          // Filter bank accounts (Groups with "bank" in name/parent/nature)
          final bankLedgers = ledgers.where((l) => l.name.toUpperCase().contains('BANK') || l.groupId.toUpperCase().contains('BANK')).toList();

          if (bankLedgers.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_balance_rounded, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No Bank Ledgers Found',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a ledger under the Bank Accounts group first to enable BRS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            );
          }

          // Auto-select first bank ledger if none selected
          if (_selectedBankLedgerId == null && bankLedgers.isNotEmpty) {
            _selectedBankLedgerId = bankLedgers.first.id;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ledger Selector Bar
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBankLedgerId,
                    decoration: const InputDecoration(
                      labelText: 'Select Bank Ledger',
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                    items: bankLedgers.map((l) {
                      return DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedBankLedgerId = val;
                      });
                    },
                  ),
                ),
              ),

              if (_selectedBankLedgerId != null)
                Expanded(
                  child: Consumer(
                    builder: (context, ref, child) {
                      final brsAsync = ref.watch(brsProvider(_selectedBankLedgerId!));
                      return brsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Center(child: Text('Error computing BRS: $err')),
                        data: (brsData) => _buildBRSContent(context, brsData, theme),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBRSContent(BuildContext context, Map<String, dynamic> brsData, ThemeData theme) {
    final double bookBalance = brsData['book_balance'] as double;
    final double unclearedPayments = brsData['uncleared_payments'] as double;
    final double unclearedDeposits = brsData['uncleared_deposits'] as double;
    final double reconciledBalance = brsData['reconciled_balance'] as double;
    final List<dynamic> instruments = brsData['instruments'] as List<dynamic>;
    final BankReconciliation? latestReconciliation = brsData['latest_reconciliation'] as BankReconciliation?;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Reconciliation Summary Cards ───
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSummaryRow('Balance as per Company Books', bookBalance, isBold: true),
                  const Divider(height: 20),
                  _buildSummaryRow('Add: Uncleared Payments (Cheques Issued)', unclearedPayments, color: Colors.green),
                  _buildSummaryRow('Less: Uncleared Deposits (Cheques Received)', -unclearedDeposits, color: Colors.orange.shade800),
                  const Divider(height: 20),
                  _buildSummaryRow('Reconciled Bank Statement Balance', reconciledBalance, isBold: true, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action: Save Reconciliation Statement
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UNCLEARED INSTRUMENTS (${instruments.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text('Save Reconciliation Log', style: TextStyle(fontSize: 12)),
                onPressed: () => _showReconciliationDialog(reconciledBalance, bookBalance),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ─── Uncleared Instruments List ───
          if (instruments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.done_all_rounded, color: Colors.green.shade600, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'All instruments are cleared!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Book balance matches bank statement prediction.',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: instruments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final inst = instruments[idx];
                final String instId = inst['id'] as String;
                final double amount = (inst['amount'] as num).toDouble();
                final String type = inst['instrument_type'] as String;
                final String? instNo = inst['instrument_no'] as String?;
                final String? bank = inst['bank_name'] as String?;
                final String status = inst['status'] as String;
                final String voucherNo = inst['voucher_no'] as String;
                final DateTime voucherDate = DateTime.parse(inst['voucher_date'] as String);

                final isPayment = status == 'ISSUED';
                final Color flowColor = isPayment ? Colors.orange.shade800 : Colors.green;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: flowColor.withValues(alpha: 0.1),
                      foregroundColor: flowColor,
                      child: Icon(isPayment ? Icons.arrow_outward_rounded : Icons.call_received_rounded),
                    ),
                    title: Text(
                      '$type ${instNo ?? ""} • ${bank ?? "Unknown Bank"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Voucher No: $voucherNo (${_dateFormatter.format(voucherDate)})'),
                        Text(
                          isPayment ? 'Cheque Issued (Uncleared)' : 'Cheque Received (Uncleared)',
                          style: TextStyle(fontSize: 11, color: flowColor),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          IndianFormatUtils.formatCurrency(amount),
                          style: TextStyle(fontWeight: FontWeight.bold, color: flowColor),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.calendar_today_rounded, color: Colors.green),
                          tooltip: 'Clear Cheque',
                          onPressed: () => _clearCheque(instId),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 24),

          // ─── Latest Saved Reconciliation Statement ───
          if (latestReconciliation != null) ...[
            Text(
              'LATEST SAVED RECONCILIATION',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Statement Date:', style: TextStyle(color: Colors.grey.shade600)),
                        Text(_dateFormatter.format(latestReconciliation.statementDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Bank Closing Balance:', style: TextStyle(color: Colors.grey.shade600)),
                        Text(IndianFormatUtils.formatCurrency(latestReconciliation.closingBalanceBank), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Book Balance:', style: TextStyle(color: Colors.grey.shade600)),
                        Text(IndianFormatUtils.formatCurrency(latestReconciliation.closingBalanceBook), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Reconciliation Difference:', style: TextStyle(color: Colors.grey.shade600)),
                        Text(
                          IndianFormatUtils.formatCurrency(latestReconciliation.difference),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: latestReconciliation.difference.abs() > 0.01 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Audited By: ${latestReconciliation.reconciledBy}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                        Text('Reconciled At: ${DateFormat('dd-MMM HH:mm').format(latestReconciliation.reconciledAt)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String title, double amount, {bool isBold = false, Color? color}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: style),
          Text(IndianFormatUtils.formatCurrency(amount), style: style.copyWith(fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Future<void> _clearCheque(String instrumentId) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Select Statement Clearing Date',
    );

    if (pickedDate != null && _selectedBankLedgerId != null) {
      try {
        await ref
            .read(brsProvider(_selectedBankLedgerId!).notifier)
            .clearInstrument(instrumentId, pickedDate);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Instrument cleared successfully!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showReconciliationDialog(double reconciledBalance, double bookBalance) async {
    final statementBalanceController = TextEditingController(text: reconciledBalance.toStringAsFixed(2));
    final auditorController = TextEditingController(text: 'CA Auditor');
    DateTime selectedStatementDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Save Reconciliation Log'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Statement Date'),
                subtitle: Text(_dateFormatter.format(selectedStatementDate)),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedStatementDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() {
                      selectedStatementDate = picked;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: statementBalanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Bank Statement Closing Balance',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: auditorController,
                decoration: const InputDecoration(
                  labelText: 'Auditor Name / Reconciled By',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final double? bankStatementVal = double.tryParse(statementBalanceController.text);
                if (bankStatementVal == null || auditorController.text.trim().isEmpty) return;

                final double difference = bankStatementVal - reconciledBalance;

                final recon = BankReconciliation(
                  id: const Uuid().v4(),
                  ledgerId: _selectedBankLedgerId!,
                  statementDate: selectedStatementDate,
                  closingBalanceBank: bankStatementVal,
                  closingBalanceBook: bookBalance,
                  difference: difference,
                  reconciledBy: auditorController.text.trim(),
                  reconciledAt: DateTime.now(),
                );

                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(brsProvider(_selectedBankLedgerId!).notifier)
                      .saveReconciliation(recon);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Reconciliation log saved!'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
