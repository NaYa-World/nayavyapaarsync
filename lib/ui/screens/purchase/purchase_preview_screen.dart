import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../data/models/party.dart';
import '../../../data/models/purchase.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/pdf_service.dart';

class PurchasePreviewScreen extends ConsumerWidget {
  final Purchase purchase;
  final List<PurchaseItem> items;
  final Party party;
  final bool isEdit;

  const PurchasePreviewScreen({
    super.key,
    required this.purchase,
    required this.items,
    required this.party,
    required this.isEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Preview'),
      ),
      body: settings == null
          ? const Center(child: Text('Settings not loaded'))
          : PdfPreview(
              build: (format) async {
                // Map the items to match PdfService expected format
                final allItems = ref.read(itemProvider).value ?? [];
                final List<Map<String, dynamic>> pdfItems = items.map((item) {
                  final matchedItem = allItems.where((e) => e.item.id == item.itemId).firstOrNull?.item;
                  final itemName = matchedItem?.name ?? 'Unknown';
                  return {
                    'name': itemName,
                    'hsnCode': item.hsnCode,
                    'qty': item.qty,
                    'unit': item.perUnit ?? 'kgs',
                    'rate': item.rate,
                    'gstRate': item.gstRate,
                  };
                }).toList();

                final file = await PdfService().generateInvoicePdf(
                  settings: settings,
                  party: party,
                  invoiceNo: purchase.invoiceNo,
                  date: purchase.date,
                  type: 'PURCHASE',
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
            label: const Text('Confirm & Save Purchase'),
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
        await ref.read(transactionProvider.notifier).editPurchase(purchase, items);
      } else {
        await ref.read(transactionProvider.notifier).addPurchase(purchase, items);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase saved successfully!'), backgroundColor: Colors.green),
        );
        // Pop back to the PurchaseEntryScreen first, then pop that as well to return to the purchases list
        Navigator.pop(context); // Pop preview screen
        Navigator.pop(context); // Pop entry screen
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save purchase: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
