import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/database/db_helper.dart';
import '../../../providers/settings_provider.dart';

class GSTReportScreen extends ConsumerStatefulWidget {
  const GSTReportScreen({super.key});

  @override
  ConsumerState<GSTReportScreen> createState() => _GSTReportScreenState();
}

class _GSTReportScreenState extends ConsumerState<GSTReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;

  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _purchases = [];

  final DateFormat _monthFormatter = DateFormat('MMMM yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadGstData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
    _loadGstData();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
    _loadGstData();
  }

  Future<void> _loadGstData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DbHelper().database;
      final String monthStr = DateFormat('yyyy-MM').format(_selectedMonth);

      // Query sales items joined with sale details and party details
      final salesRows = await db.rawQuery('''
        SELECT s.id as sale_id, s.invoice_no, s.date, s.party_id, p.name as party_name, p.gstin as party_gstin,
               si.qty, si.rate, si.gst_rate, si.gst_amt, si.total, si.hsn_code, si.total_units, si.unit_price
        FROM sales s
        JOIN sale_items si ON si.sale_id = s.id
        JOIN parties p ON s.party_id = p.id
        WHERE s.is_deleted = 0 AND s.date LIKE ?
        ORDER BY s.date ASC, s.invoice_no ASC
      ''', ['$monthStr%']);

      // Query purchase items joined with purchase details and party details
      final purchasesRows = await db.rawQuery('''
        SELECT pr.id as purchase_id, pr.invoice_no, pr.date, pr.party_id, p.name as party_name, p.gstin as party_gstin,
               pi.qty, pi.rate, pi.gst_rate, pi.gst_amt, pi.total, pi.hsn_code, pi.total_units, pi.unit_price
        FROM purchases pr
        JOIN purchase_items pi ON pi.purchase_id = pr.id
        JOIN parties p ON pr.party_id = p.id
        WHERE pr.is_deleted = 0 AND pr.date LIKE ?
        ORDER BY pr.date ASC, pr.invoice_no ASC
      ''', ['$monthStr%']);

      setState(() {
        _sales = salesRows;
        _purchases = purchasesRows;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load GST data: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _getPartyStateCode(String? gstin, String defaultStateCode) {
    if (gstin != null && gstin.trim().length >= 2) {
      final firstTwo = gstin.trim().substring(0, 2);
      if (RegExp(r'^\d{2}$').hasMatch(firstTwo)) {
        return firstTwo;
      }
    }
    return defaultStateCode;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final String firmStateCode = settings?.stateCode ?? '36';

    // Calculate Output GST split
    double totalOutputGst = 0.0;
    double totalOutputCgst = 0.0;
    double totalOutputSgst = 0.0;
    double totalOutputIgst = 0.0;
    double totalOutputTaxable = 0.0;

    for (final item in _sales) {
      final double gstAmt = (item['gst_amt'] as num).toDouble();
      final double qty = (item['qty'] as num).toDouble();
      final double rate = (item['rate'] as num).toDouble();
      final double totalUnits = item['total_units'] != null ? (item['total_units'] as num).toDouble() : qty;
      final double unitPrice = item['unit_price'] != null ? (item['unit_price'] as num).toDouble() : rate;
      final double taxable = totalUnits * unitPrice;
      final String partyGstin = item['party_gstin'] as String? ?? '';
      final String partyState = _getPartyStateCode(partyGstin, firmStateCode);

      totalOutputGst += gstAmt;
      totalOutputTaxable += taxable;

      if (partyState == firmStateCode) {
        totalOutputCgst += gstAmt / 2.0;
        totalOutputSgst += gstAmt / 2.0;
      } else {
        totalOutputIgst += gstAmt;
      }
    }

    // Calculate Input GST split
    double totalInputGst = 0.0;
    double totalInputCgst = 0.0;
    double totalInputSgst = 0.0;
    double totalInputIgst = 0.0;
    double totalInputTaxable = 0.0;

    for (final item in _purchases) {
      final double gstAmt = (item['gst_amt'] as num).toDouble();
      final double qty = (item['qty'] as num).toDouble();
      final double rate = (item['rate'] as num).toDouble();
      final double totalUnits = item['total_units'] != null ? (item['total_units'] as num).toDouble() : qty;
      final double unitPrice = item['unit_price'] != null ? (item['unit_price'] as num).toDouble() : rate;
      final double taxable = totalUnits * unitPrice;
      final String partyGstin = item['party_gstin'] as String? ?? '';
      final String partyState = _getPartyStateCode(partyGstin, firmStateCode);

      totalInputGst += gstAmt;
      totalInputTaxable += taxable;

      if (partyState == firmStateCode) {
        totalInputCgst += gstAmt / 2.0;
        totalInputSgst += gstAmt / 2.0;
      } else {
        totalInputIgst += gstAmt;
      }
    }

    final double netGstPayable = totalOutputGst - totalInputGst;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Returns Report / జి.ఎస్.టి రిటర్న్స్'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'GSTR-1 (Sales)'),
            Tab(text: 'GSTR-2 (Purchases)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Disclaimer Banner
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Disclaimer: GST figures are generated from local data and are under verification. Do not use for final filing without CA approval.',
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Month Selector Bar
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
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
                  ),
                ),

                // Net GST Payable Banner Card
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: netGstPayable >= 0
                        ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
                        : Colors.green.shade50.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: netGstPayable >= 0 ? theme.colorScheme.errorContainer : Colors.green.shade200,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            netGstPayable >= 0 ? 'NET GST PAYABLE' : 'NET ITC TAX REFUND',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: netGstPayable >= 0 ? theme.colorScheme.error : Colors.green.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Based on Sales & Purchases tax splits',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      Text(
                        IndianFormatUtils.formatCurrency(netGstPayable.abs()),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: netGstPayable >= 0 ? theme.colorScheme.error : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Tab Content Area
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSummaryTab(
                        theme,
                        totalOutputTaxable,
                        totalOutputGst,
                        totalOutputCgst,
                        totalOutputSgst,
                        totalOutputIgst,
                        totalInputTaxable,
                        totalInputGst,
                        totalInputCgst,
                        totalInputSgst,
                        totalInputIgst,
                      ),
                      _buildInvoiceGrid(theme, _sales, firmStateCode, true),
                      _buildInvoiceGrid(theme, _purchases, firmStateCode, false),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryTab(
    ThemeData theme,
    double outTaxable,
    double outGst,
    double outCgst,
    double outSgst,
    double outIgst,
    double inTaxable,
    double inGst,
    double inCgst,
    double inSgst,
    double inIgst,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Sales Output Tax details
          _buildSummaryCard(
            theme: theme,
            title: 'Output GST (Tax Collected on Sales)',
            taxable: outTaxable,
            gst: outGst,
            cgst: outCgst,
            sgst: outSgst,
            igst: outIgst,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),

          // Purchases Input Tax details
          _buildSummaryCard(
            theme: theme,
            title: 'Input GST (Tax Paid on Purchases)',
            taxable: inTaxable,
            gst: inGst,
            cgst: inCgst,
            sgst: inSgst,
            igst: inIgst,
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required ThemeData theme,
    required String title,
    required double taxable,
    required double gst,
    required double cgst,
    required double sgst,
    required double igst,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildRowSummary('Taxable Amount', IndianFormatUtils.formatCurrency(taxable), isBold: true),
                const Divider(),
                _buildRowSummary('CGST Amount (Central)', IndianFormatUtils.formatCurrency(cgst)),
                _buildRowSummary('SGST Amount (State)', IndianFormatUtils.formatCurrency(sgst)),
                _buildRowSummary('IGST Amount (Inter-State)', IndianFormatUtils.formatCurrency(igst)),
                const Divider(),
                _buildRowSummary('Total GST Tax', IndianFormatUtils.formatCurrency(gst), isBold: true, valueColor: color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowSummary(String title, String val, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
          Text(
            val,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.bold,
              fontSize: 13,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceGrid(ThemeData theme, List<Map<String, dynamic>> items, String firmStateCode, bool isSale) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          isSale ? 'No Sales recorded in this month.' : 'No Purchases recorded in this month.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final double qty = (item['qty'] as num).toDouble();
        final double rate = (item['rate'] as num).toDouble();
        final double totalUnits = item['total_units'] != null ? (item['total_units'] as num).toDouble() : qty;
        final double unitPrice = item['unit_price'] != null ? (item['unit_price'] as num).toDouble() : rate;
        final double taxable = totalUnits * unitPrice;
        final double gstAmt = (item['gst_amt'] as num).toDouble();
        final double gstRate = (item['gst_rate'] as num).toDouble();
        
        final String partyGstin = item['party_gstin'] as String? ?? '';
        final String partyState = _getPartyStateCode(partyGstin, firmStateCode);
        final bool isIntra = partyState == firmStateCode;

        final dateStr = DateFormat('dd-MMM').format(DateTime.parse(item['date'] as String));

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Inv: ${item['invoice_no']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Party: ${item['party_name']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                if (partyGstin.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'GSTIN: $partyGstin',
                    style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                  ),
                ],
                const Divider(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'HSN: ${item['hsn_code'] ?? 'N/A'} (GST ${gstRate.toStringAsFixed(0)}%)',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    Text(
                      'Taxable: ${IndianFormatUtils.formatCurrency(taxable)}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isIntra
                          ? 'CGST: ${IndianFormatUtils.formatCurrency(gstAmt / 2)} | SGST: ${IndianFormatUtils.formatCurrency(gstAmt / 2)}'
                          : 'IGST: ${IndianFormatUtils.formatCurrency(gstAmt)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                    Text(
                      'GST Tax: ${IndianFormatUtils.formatCurrency(gstAmt)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSale ? theme.colorScheme.primary : Colors.teal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
