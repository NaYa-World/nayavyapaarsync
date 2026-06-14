import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../core/utils/gst_calculator.dart';
import '../../core/utils/indian_format.dart';
import '../data/models/party.dart';
import '../data/models/settings.dart';

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  final DateFormat _dateFormatter = DateFormat('dd-MMM-yyyy');

  /// Shares a PDF file using share_plus
  Future<void> sharePdfFile(File file, String subject) async {
    final XFile xFile = XFile(file.path);
    await Share.shareXFiles([xFile], subject: subject);
  }

  /// Generates a PDF invoice file
  Future<File> generateInvoicePdf({
    required Settings settings,
    required Party party,
    required String invoiceNo,
    required DateTime date,
    required String type, // 'PURCHASE' or 'SALE'
    required List<Map<String, dynamic>> items, // keys: name, hsnCode, qty, unit, rate, gstRate
  }) async {
    final pdf = pw.Document();

    // Map items for GST calculations
    final List<Map<String, dynamic>> calcItems = items.map((item) {
      return {
        'qty': item['qty'],
        'rate': item['rate'],
        'gstRate': item['gstRate'],
      };
    }).toList();

    // Compute tax breakup
    final taxBreakup = GstCalculator.calculateInvoiceBreakup(
      items: calcItems,
      destinationStateCode: settings.stateCode, // Assuming intra-state or matching customer state
      firmStateCode: settings.stateCode,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      settings.firmName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(settings.address),
                    pw.Text('Phone: ${settings.phone}'),
                    if (settings.gstin != null && settings.gstin!.isNotEmpty)
                      pw.Text('GSTIN: ${settings.gstin}'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      type == 'SALE' ? 'TAX INVOICE' : 'PURCHASE RECORD',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Invoice No: $invoiceNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${_dateFormatter.format(date)}'),
                  ],
                ),
              ],
            ),
            pw.Divider(thickness: 1, height: 24),

            // Party details section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      type == 'SALE' ? 'BILL TO (CUSTOMER):' : 'RECEIVED FROM (SUPPLIER):',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      party.name,
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(party.address),
                    pw.Text('Phone: ${party.phone}'),
                    if (party.gstin != null && party.gstin!.isNotEmpty)
                      pw.Text('GSTIN: ${party.gstin}'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Item details table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5), // S.No
                1: const pw.FlexColumnWidth(3.0), // Item Name
                2: const pw.FlexColumnWidth(1.0), // HSN Code
                3: const pw.FlexColumnWidth(1.2), // Qty
                4: const pw.FlexColumnWidth(1.2), // Rate
                5: const pw.FlexColumnWidth(1.0), // GST %
                6: const pw.FlexColumnWidth(1.5), // Total (Rs)
              },
              children: [
                // Table Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableHeaderCell('#'),
                    _tableHeaderCell('Item Name'),
                    _tableHeaderCell('HSN'),
                    _tableHeaderCell('Qty'),
                    _tableHeaderCell('Rate'),
                    _tableHeaderCell('GST %'),
                    _tableHeaderCell('Total (Rs)'),
                  ],
                ),
                // Table Rows
                ...List.generate(items.length, (index) {
                  final item = items[index];
                  final double qty = (item['qty'] as num).toDouble();
                  final double rate = (item['rate'] as num).toDouble();
                  final double gstRate = (item['gstRate'] as num).toDouble();
                  final double lineTotal = qty * rate * (1 + gstRate / 100.0);

                  final String qtyStr = '${IndianFormatUtils.formatNumber(qty)} ${(item['unit'] as String).toLowerCase()}';

                  return pw.TableRow(
                    children: [
                      _tableBodyCell((index + 1).toString(), alignCenter: true),
                      _tableBodyCell(item['name'] as String),
                      _tableBodyCell(item['hsnCode'] as String, alignCenter: true),
                      _tableBodyCell(qtyStr, alignRight: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(rate).replaceFirst('₹ ', ''), alignRight: true),
                      _tableBodyCell('${gstRate.toInt()}%', alignCenter: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(lineTotal).replaceFirst('₹ ', ''), alignRight: true),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),

            // Calculation and summary block
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Empty spacer or notes
                pw.SizedBox(width: 200),
                // Invoice summary table
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    children: [
                      _summaryRow('Subtotal (Rs):', taxBreakup.subtotal),
                      _summaryRow('CGST Total (Rs):', taxBreakup.cgstTotal),
                      _summaryRow('SGST Total (Rs):', taxBreakup.sgstTotal),
                      if (taxBreakup.igstTotal > 0)
                        _summaryRow('IGST Total (Rs):', taxBreakup.igstTotal),
                      pw.Divider(thickness: 1, color: PdfColors.grey500),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Grand Total:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                          ),
                          pw.Text(
                            IndianFormatUtils.formatCurrency(taxBreakup.grandTotal),
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // GST Rate Breakup Table
            pw.Text(
              'TAX BREAKUP DETAILS:',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // GST Rate
                1: const pw.FlexColumnWidth(2.0), // Taxable Value
                2: const pw.FlexColumnWidth(1.0), // CGST Rate
                3: const pw.FlexColumnWidth(1.8), // CGST Amount
                4: const pw.FlexColumnWidth(1.0), // SGST Rate
                5: const pw.FlexColumnWidth(1.8), // SGST Amount
                6: const pw.FlexColumnWidth(2.2), // Total Tax
              },
              children: [
                // Breakup Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _tableHeaderCell('GST Rate'),
                    _tableHeaderCell('Taxable Amt'),
                    _tableHeaderCell('CGST %'),
                    _tableHeaderCell('CGST Amt'),
                    _tableHeaderCell('SGST %'),
                    _tableHeaderCell('SGST Amt'),
                    _tableHeaderCell('Total Tax'),
                  ],
                ),
                // Breakup Rows
                ...taxBreakup.rateSummary.entries.map((entry) {
                  final double rate = entry.key;
                  final summary = entry.value;
                  final double halfRate = rate / 2.0;
                  final double totalTax = summary.cgstAmount + summary.sgstAmount + summary.igstAmount;

                  return pw.TableRow(
                    children: [
                      _tableBodyCell('${rate.toInt()}%', alignCenter: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(summary.taxableAmount).replaceFirst('₹ ', ''), alignRight: true),
                      _tableBodyCell('${halfRate.toStringAsFixed(1)}%', alignCenter: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(summary.cgstAmount).replaceFirst('₹ ', ''), alignRight: true),
                      _tableBodyCell('${halfRate.toStringAsFixed(1)}%', alignCenter: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(summary.sgstAmount).replaceFirst('₹ ', ''), alignRight: true),
                      _tableBodyCell(IndianFormatUtils.formatCurrency(totalTax).replaceFirst('₹ ', ''), alignRight: true),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    // Save PDF locally
    final String tempDir = (await getTemporaryDirectory()).path;
    final String cleanInvoiceNo = invoiceNo.replaceAll('/', '_');
    final String filePath = '$tempDir/invoice_$cleanInvoiceNo.pdf';
    final File file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Helper to generate Table cells
  static pw.Widget _tableHeaderCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableBodyCell(String text, {bool alignRight = false, bool alignCenter = false}) {
    pw.TextAlign align = pw.TextAlign.left;
    if (alignRight) align = pw.TextAlign.right;
    if (alignCenter) align = pw.TextAlign.center;

    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
        textAlign: align,
      ),
    );
  }

  pw.Widget _summaryRow(String label, double val) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            IndianFormatUtils.formatCurrency(val),
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  /// Generates a simple PDF Report file
  Future<File> generateReportPdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
              ),
              pw.Text('Generated on: ${DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())}'),
              pw.Divider(thickness: 1, height: 16),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: headers.map((h) => _tableHeaderCell(h)).toList(),
                ),
                // Data rows
                ...rows.map((row) {
                  return pw.TableRow(
                    children: row.map((cell) => _tableBodyCell(cell)).toList(),
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    final String tempDir = (await getTemporaryDirectory()).path;
    final String cleanTitle = title.toLowerCase().replaceAll(' ', '_');
    final String filePath = '$tempDir/report_$cleanTitle.pdf';
    final File file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
