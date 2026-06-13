import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/party.dart';
import '../../../data/repositories/party_repository.dart';
import '../../../providers/party_provider.dart';
import '../../../services/pdf_service.dart';

class PartyStatementScreen extends ConsumerStatefulWidget {
  final Party party;

  const PartyStatementScreen({super.key, required this.party});

  @override
  ConsumerState<PartyStatementScreen> createState() => _PartyStatementScreenState();
}

class _PartyStatementScreenState extends ConsumerState<PartyStatementScreen> {
  late Future<List<LedgerRow>> _statementFuture;

  @override
  void initState() {
    super.initState();
    _refreshStatement();
  }

  void _refreshStatement() {
    setState(() {
      _statementFuture = ref.read(partyRepositoryProvider).getLedgerStatement(widget.party.id);
    });
  }

  Future<void> _exportPdf(List<LedgerRow> rows) async {
    final pdfService = PdfService();
    
    final List<String> headers = ['Date', 'Narration', 'Debit (Rs)', 'Credit (Rs)', 'Balance'];
    
    final List<List<String>> dataRows = rows.map((r) {
      final String dateStr = DateFormat('dd-MMM-yyyy').format(r.date);
      final String debitStr = r.debit != null ? IndianFormatUtils.formatCurrency(r.debit!).replaceFirst('₹ ', '') : '-';
      final String creditStr = r.credit != null ? IndianFormatUtils.formatCurrency(r.credit!).replaceFirst('₹ ', '') : '-';
      final String balanceStr = '${IndianFormatUtils.formatCurrency(r.runningBalance).replaceFirst('₹ ', '')} ${r.runningBalanceType}';
      
      return [
        dateStr,
        r.narration,
        debitStr,
        creditStr,
        balanceStr,
      ];
    }).toList();

    try {
      final file = await pdfService.generateReportPdf(
        title: '${widget.party.name} - Account Statement',
        headers: headers,
        rows: dataRows,
      );
      
      await pdfService.sharePdfFile(file, '${widget.party.name} Ledger');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: ${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustomer = widget.party.type == 'CUSTOMER';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.party.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshStatement,
          ),
        ],
      ),
      body: FutureBuilder<List<LedgerRow>>(
        future: _movementFutureWrapper(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error.toString()}'));
          }

          final rows = snapshot.data ?? [];

          // Calculate current balance info
          final latestRow = rows.isNotEmpty ? rows.first : null;
          final double outstandingBal = latestRow?.runningBalance ?? 0.0;
          final String outstandingType = latestRow?.runningBalanceType ?? 'CR';
          
          final bool isReceivable = (isCustomer && outstandingType == 'DR') || (!isCustomer && outstandingType == 'DR');
          final Color balanceColor = isReceivable ? Colors.green : Colors.amber.shade800;

          return Column(
            children: [
              // Party Info & Summary Card
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.party.type == 'CUSTOMER' ? 'CUSTOMER PROFILE' : 'SUPPLIER PROFILE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(widget.party.address, style: const TextStyle(fontSize: 13)),
                                Text('Phone: ${widget.party.phone}', style: const TextStyle(fontSize: 13)),
                                if (widget.party.gstin != null && widget.party.gstin!.isNotEmpty)
                                  Text('GSTIN: ${widget.party.gstin}', style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Net Balance',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                IndianFormatUtils.formatCurrency(outstandingBal),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: balanceColor,
                                ),
                              ),
                              Text(
                                outstandingType == 'DR' ? 'DR (Receivable)' : 'CR (Payable)',
                                style: TextStyle(
                                  color: balanceColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Export Statement PDF'),
                        onPressed: rows.isEmpty ? null : () => _exportPdf(rows),
                      ),
                    ],
                  ),
                ),
              ),

              // Ledger Table Header
              Container(
                color: theme.colorScheme.primary.withOpacity(0.08),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 3, child: Text('Narration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                    Expanded(flex: 2, child: Text('Debit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text('Credit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text('Balance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                  ],
                ),
              ),

              // Ledger List
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    final String dateStr = DateFormat('dd-MMM').format(r.date);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(dateStr, style: const TextStyle(fontSize: 12)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              r.narration,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              r.debit != null ? IndianFormatUtils.formatCurrency(r.debit!).replaceFirst('₹ ', '') : '-',
                              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              r.credit != null ? IndianFormatUtils.formatCurrency(r.credit!).replaceFirst('₹ ', '') : '-',
                              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${IndianFormatUtils.formatCurrency(r.runningBalance).replaceFirst('₹ ', '')} ${r.runningBalanceType}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
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

  Future<List<LedgerRow>> _movementFutureWrapper() {
    return _statementFuture;
  }
}
