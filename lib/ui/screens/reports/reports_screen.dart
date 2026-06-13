import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/party.dart';
import '../../../data/repositories/party_repository.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/pdf_service.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _selectedReportType = 'DAY_BOOK'; // 'DAY_BOOK', 'STOCK', 'OUTSTANDING', 'PURCHASES', 'SALES'
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  final DateFormat _dateFormatter = DateFormat('dd-MMM-yyyy');

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  // Set date filter to current Indian Financial Year
  void _setFinancialYearFilter() {
    final range = AppDateUtils.getFinancialYearRange(DateTime.now());
    setState(() {
      _startDate = range.start;
      _endDate = DateTime.now().isBefore(range.end) ? DateTime.now() : range.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Registers / నివేదికలు'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_rounded),
            tooltip: 'Indian Financial Year Filter',
            onPressed: _setFinancialYearFilter,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedReportType,
                    decoration: const InputDecoration(
                      labelText: 'Select Report Type / నివేదిక రకం',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'DAY_BOOK', child: Text('Day Book (దినసరి పుస్తకం)')),
                      DropdownMenuItem(value: 'STOCK', child: Text('Stock Status Report (సరుకు నిల్వ నివేదిక)')),
                      DropdownMenuItem(value: 'OUTSTANDING', child: Text('Party Outstanding Ledger (బాకీల పట్టిక)')),
                      DropdownMenuItem(value: 'PURCHASES', child: Text('Purchase Register (కొనుగోలు రిజిస్టర్)')),
                      DropdownMenuItem(value: 'SALES', child: Text('Sale Register (అమ్మకాల రిజిస్టర్)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedReportType = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Date filters (hide for stock report since it's current snapshot)
                  if (_selectedReportType != 'STOCK')
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _selectStartDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'From Date', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                              child: Text(_dateFormatter.format(_startDate), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: _selectEndDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'To Date', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                              child: Text(_dateFormatter.format(_endDate), style: const TextStyle(fontSize: 13)),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Report Content Area
          Expanded(
            child: _buildReportContent(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent(ThemeData theme) {
    switch (_selectedReportType) {
      case 'DAY_BOOK':
        return _buildDayBookReport(theme);
      case 'STOCK':
        return _buildStockReport(theme);
      case 'OUTSTANDING':
        return _buildOutstandingReport(theme);
      case 'PURCHASES':
        return _buildRegisterReport(theme, isPurchase: true);
      case 'SALES':
        return _buildRegisterReport(theme, isPurchase: false);
      default:
        return const SizedBox();
    }
  }

  // ================= DAY BOOK =================

  Widget _buildDayBookReport(ThemeData theme) {
    final transactionState = ref.watch(transactionProvider);
    final parties = ref.watch(partyProvider).value ?? [];

    final List<Map<String, dynamic>> items = [];

    // Filter sales in range
    for (final sale in transactionState.sales) {
      if (sale.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
          sale.date.isBefore(_endDate.add(const Duration(days: 1)))) {
        final partyName = parties.firstWhere((p) => p.party.id == sale.partyId, orElse: () => _mockParty()).party.name;
        items.add({
          'date': sale.date,
          'type': 'SALE',
          'particulars': 'Sale: $partyName (Inv: ${sale.invoiceNo})',
          'debit': sale.grandTotal, // debited customer account
          'credit': 0.0,
        });
      }
    }

    // Filter purchases in range
    for (final purchase in transactionState.purchases) {
      if (purchase.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
          purchase.date.isBefore(_endDate.add(const Duration(days: 1)))) {
        final partyName = parties.firstWhere((p) => p.party.id == purchase.partyId, orElse: () => _mockParty()).party.name;
        items.add({
          'date': purchase.date,
          'type': 'PURCHASE',
          'particulars': 'Purchase: $partyName (Inv: ${purchase.invoiceNo})',
          'debit': 0.0,
          'credit': purchase.grandTotal, // credited supplier account
        });
      }
    }

    // Filter payments in range
    for (final payment in transactionState.payments) {
      if (payment.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
          payment.date.isBefore(_endDate.add(const Duration(days: 1)))) {
        final partyName = parties.firstWhere((p) => p.party.id == payment.partyId, orElse: () => _mockParty()).party.name;
        final isReceived = payment.direction == 'RECEIVED';
        items.add({
          'date': payment.date,
          'type': isReceived ? 'RECEIPT' : 'PAYMENT',
          'particulars': 'Payment ${isReceived ? 'Received' : 'Paid'} [$partyName] (${payment.mode})',
          'debit': isReceived ? payment.amount : 0.0,
          'credit': isReceived ? 0.0 : payment.amount,
        });
      }
    }

    // Sort oldest to newest for chronological flow
    items.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    double totalDebit = 0.0;
    double totalCredit = 0.0;
    for (final row in items) {
      totalDebit += row['debit'];
      totalCredit += row['credit'];
    }

    return _buildPreviewTable(
      title: 'Day Book Report',
      headers: ['Date', 'Particulars', 'Debit (Dr)', 'Credit (Cr)'],
      dataRows: items.map((r) {
        return [
          _dateFormatter.format(r['date'] as DateTime),
          r['particulars'] as String,
          r['debit'] > 0 ? IndianFormatUtils.formatCurrency(r['debit'] as double) : '-',
          r['credit'] > 0 ? IndianFormatUtils.formatCurrency(r['credit'] as double) : '-',
        ];
      }).toList(),
      totalsRow: [
        'Total',
        'Summary',
        IndianFormatUtils.formatCurrency(totalDebit),
        IndianFormatUtils.formatCurrency(totalCredit),
      ],
    );
  }

  // ================= STOCK REPORT =================

  Widget _buildStockReport(ThemeData theme) {
    final itemsState = ref.watch(itemProvider);

    return itemsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (items) {
        double totalBags = 0.0;
        double totalBoxes = 0.0;

        for (final item in items) {
          if (item.item.primaryUnit == 'BAG') totalBags += item.currentStock;
          if (item.item.primaryUnit == 'BOX') totalBoxes += item.currentStock;
        }

        return _buildPreviewTable(
          title: 'Stock Status Report',
          headers: ['Item Name', 'Category', 'HSN Code', 'Unit', 'Current Stock', 'Weight (kg)'],
          dataRows: items.map((i) {
            double? conversionWeight = i.item.primaryUnit == 'BAG' ? i.item.bagWeightKg : i.item.boxWeightKg;
            double? totalWeight = conversionWeight != null ? (i.currentStock * conversionWeight) : null;

            return [
              i.item.name,
              i.item.category,
              i.item.hsnCode,
              i.item.primaryUnit,
              IndianFormatUtils.formatNumber(i.currentStock),
              totalWeight != null ? '${IndianFormatUtils.formatNumber(totalWeight)} kg' : '-',
            ];
          }).toList(),
          totalsRow: [
            'Total Summary',
            '-',
            '-',
            '-',
            'Bags: ${IndianFormatUtils.formatNumber(totalBags)} | Boxes: ${IndianFormatUtils.formatNumber(totalBoxes)}',
            '-',
          ],
        );
      },
    );
  }

  // ================= PARTY OUTSTANDING =================

  Widget _buildOutstandingReport(ThemeData theme) {
    final partyState = ref.watch(partyProvider);

    return partyState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (parties) {
        // Filter parties that have a non-zero outstanding balance
        final outstandingParties = parties.where((p) => p.outstandingBalance > 0).toList();

        double totalReceivables = 0.0;
        double totalPayables = 0.0;

        for (final p in outstandingParties) {
          if (p.balanceType == 'DR') {
            totalReceivables += p.outstandingBalance;
          } else {
            totalPayables += p.outstandingBalance;
          }
        }

        return _buildPreviewTable(
          title: 'Party Outstanding Report',
          headers: ['Party Name', 'Contact', 'Type', 'GSTIN', 'Outstanding Balance', 'Balance Sign'],
          dataRows: outstandingParties.map((p) {
            return [
              p.party.name,
              p.party.phone,
              p.party.type,
              p.party.gstin ?? '-',
              IndianFormatUtils.formatCurrency(p.outstandingBalance),
              p.balanceType == 'DR' ? 'DR (Receivable)' : 'CR (Payable)',
            ];
          }).toList(),
          totalsRow: [
            'Total Summary',
            '-',
            '-',
            '-',
            'Receivable: ${IndianFormatUtils.formatCurrencyNoDecimals(totalReceivables)} | Payable: ${IndianFormatUtils.formatCurrencyNoDecimals(totalPayables)}',
            '-',
          ],
        );
      },
    );
  }

  // ================= REGISTER REPORT =================

  Widget _buildRegisterReport(ThemeData theme, {required bool isPurchase}) {
    final transactionState = ref.watch(transactionProvider);
    final parties = ref.watch(partyProvider).value ?? [];

    double subtotalSum = 0.0;
    double gstSum = 0.0;
    double grandSum = 0.0;

    final List<Map<String, dynamic>> itemsList = [];

    if (isPurchase) {
      for (final tx in transactionState.purchases) {
        if (tx.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
            tx.date.isBefore(_endDate.add(const Duration(days: 1)))) {
          final partyName = parties.firstWhere((p) => p.party.id == tx.partyId, orElse: () => _mockParty()).party.name;
          itemsList.add({
            'date': tx.date,
            'invoice_no': tx.invoiceNo,
            'party': partyName,
            'subtotal': tx.subtotal,
            'gst': tx.gstTotal,
            'total': tx.grandTotal,
            'status': tx.paymentStatus,
          });
          subtotalSum += tx.subtotal;
          gstSum += tx.gstTotal;
          grandSum += tx.grandTotal;
        }
      }
    } else {
      for (final tx in transactionState.sales) {
        if (tx.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
            tx.date.isBefore(_endDate.add(const Duration(days: 1)))) {
          final partyName = parties.firstWhere((p) => p.party.id == tx.partyId, orElse: () => _mockParty()).party.name;
          itemsList.add({
            'date': tx.date,
            'invoice_no': tx.invoiceNo,
            'party': partyName,
            'subtotal': tx.subtotal,
            'gst': tx.gstTotal,
            'total': tx.grandTotal,
            'status': tx.paymentStatus,
          });
          subtotalSum += tx.subtotal;
          gstSum += tx.gstTotal;
          grandSum += tx.grandTotal;
        }
      }
    }

    itemsList.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    final String title = isPurchase ? 'Purchase Register' : 'Sale Register';

    return _buildPreviewTable(
      title: title,
      headers: ['Date', 'Invoice No', 'Party Name', 'Subtotal', 'Tax (GST)', 'Grand Total', 'Status'],
      dataRows: itemsList.map((r) {
        return [
          _dateFormatter.format(r['date'] as DateTime),
          r['invoice_no'] as String,
          r['party'] as String,
          IndianFormatUtils.formatCurrency(r['subtotal'] as double),
          IndianFormatUtils.formatCurrency(r['gst'] as double),
          IndianFormatUtils.formatCurrency(r['total'] as double),
          r['status'] as String,
        ];
      }).toList(),
      totalsRow: [
        'Total Summary',
        '-',
        '-',
        IndianFormatUtils.formatCurrency(subtotalSum),
        IndianFormatUtils.formatCurrency(gstSum),
        IndianFormatUtils.formatCurrency(grandSum),
        '-',
      ],
    );
  }

  // ================= GENERAL UI RENDER HELPER =================

  Widget _buildPreviewTable({
    required String title,
    required List<String> headers,
    required List<List<String>> dataRows,
    required List<String> totalsRow,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'REPORT DATA PREVIEW',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: dataRows.isEmpty
                    ? null
                    : () async {
                        try {
                          final file = await PdfService().generateReportPdf(
                            title: title,
                            headers: headers,
                            rows: [...dataRows, totalsRow],
                          );
                          await PdfService().sharePdfFile(file, title);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to generate PDF: ${e.toString()}'), backgroundColor: Colors.red),
                          );
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: dataRows.isEmpty
                ? Center(
                    child: Text(
                      'No entries match date criteria.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
                    ),
                  )
                : Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                          rows: [
                            ...dataRows.map((row) {
                              return DataRow(
                                cells: row.map((cell) => DataCell(Text(cell))).toList(),
                              );
                            }),
                            // Totals Row
                            DataRow(
                              color: MaterialStateProperty.all(theme.colorScheme.primaryContainer.withOpacity(0.2)),
                              cells: totalsRow.map((cell) => DataCell(Text(cell, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // Mock party helper for deleted references
  PartyWithBalance _mockParty() {
    return PartyWithBalance(
      party: Party(
        id: '',
        name: 'Deleted Party',
        type: 'CUSTOMER',
        phone: '',
        address: '',
        createdAt: DateTime.now(),
      ),
      outstandingBalance: 0.0,
      balanceType: 'DR',
    );
  }
}
