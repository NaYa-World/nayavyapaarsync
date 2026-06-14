import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../data/models/party.dart';
import '../../../data/models/sale.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/pdf_service.dart';

class SalePreviewScreen extends ConsumerWidget {
  final Sale sale;
  final List<SaleItem> items;
  final Party party;
  final bool isEdit;

  const SalePreviewScreen({
    super.key,
    required this.sale,
    required this.items,
    required this.party,
    required this.isEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale Preview'),
      ),
      body: settings == null
          ? const Center(child: Text('Settings not loaded'))
          : PdfPreview(
              build: (format) async {
                final allItems = ref.read(itemProvider).value ?? [];
                final List<Map<String, dynamic>> pdfItems = items.map((item) {
                  final matchedItem = allItems.where((e) => e.item.id == item.itemId).firstOrNull?.item;
                  final itemName = matchedItem?.name ?? 'Unknown';
                  return {
                    'name': itemName,
                    'hsnCode': item.hsnCode,
                    'qty': item.qty,
                    'unit': item.packing ?? 'kgs',
                    'rate': item.rate,
                    'gstRate': item.gstRate,
                  };
                }).toList();

                final file = await PdfService().generateInvoicePdf(
                  settings: settings,
                  party: party,
                  invoiceNo: sale.invoiceNo,
                  date: sale.date,
                  type: 'SALE',
                  items: pdfItems,
                );
                return await file.readAsBytes();
              },
              allowPrinting: true,
              allowSharing: true,
              canChangePageFormat: false,
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: const Text('Confirm & Save Sale'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _save(context, ref),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    try {
      if (isEdit) {
        await ref.read(transactionProvider.notifier).editSale(sale, items);
      } else {
        await ref.read(transactionProvider.notifier).addSale(sale, items);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sale saved successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Pop preview screen
        Navigator.pop(context); // Pop entry screen
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save sale: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
