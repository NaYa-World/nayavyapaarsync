import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/gst_calculator.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/item.dart';
import '../../../data/models/party.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/item_repository.dart';
import '../../../data/repositories/sale_repository.dart';
import '../../../providers/connectivity_provider.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/ocr_service.dart';
import '../../widgets/gst_row.dart';
import '../party/party_ledger_screen.dart';
import 'sale_preview_screen.dart';

class SaleEntryScreen extends ConsumerStatefulWidget {
  final Sale? saleToEdit;
  final String? category; // 'SEED' or 'FERTILISER'

  const SaleEntryScreen({super.key, this.saleToEdit, this.category});

  @override
  ConsumerState<SaleEntryScreen> createState() => _SaleEntryScreenState();
}

class _SaleEntryScreenState extends ConsumerState<SaleEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController(text: DateFormat('dd-MMM-yyyy').format(DateTime.now()));
  final _invoiceNoController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  Party? _selectedParty;
  String _paymentStatus = 'PENDING';
  bool _isScanning = false;

  String get _currentCategory => widget.saleToEdit?.category ?? widget.category ?? 'SEED';

  // Form row models
  final List<SaleItemRow> _itemRows = [];

  // Low confidence highlights from OCR
  final Map<String, bool> _uncertainFields = {};

  TableRow _buildFormRow(String label, Widget inputWidget) {
    return TableRow(
      children: [
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: inputWidget,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    final isEdit = widget.saleToEdit != null;
    if (isEdit) {
      final s = widget.saleToEdit!;
      _selectedDate = s.date;
      _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
      _invoiceNoController.text = s.invoiceNo;
      _paymentStatus = s.paymentStatus;

      // Select party
      final partiesData = ref.read(partyProvider).value ?? [];
      final partyMatch = partiesData.where((element) => element.party.id == s.partyId);
      if (partyMatch.isNotEmpty) {
        _selectedParty = partyMatch.first.party;
      }

      // Load items
      final repo = ref.read(saleRepositoryProvider);
      final itemRepo = ref.read(itemRepositoryProvider);
      final details = await repo.getSale(s.id);
      if (details != null) {
        final allItems = ref.read(itemProvider).value ?? [];
        for (final item in details.items) {
          final matchedItem = allItems.where((e) => e.item.id == item.itemId).firstOrNull?.item;

          // Fetch batches
          final batches = await itemRepo.getAvailableBatchesForItem(
            item.itemId,
            excludeSaleId: s.id,
          );

          final matchedBatch = batches.where((b) => b.batchNo == item.batchNo).firstOrNull;

          _itemRows.add(SaleItemRow(
            selectedItem: matchedItem,
            selectedBatch: matchedBatch,
            availableBatches: batches,
            manufacturerController: TextEditingController(text: item.manufacturer ?? ''),
            packingController: TextEditingController(text: item.packing ?? ''),
            batchNoController: TextEditingController(text: item.batchNo ?? ''),
            hsnCodeController: TextEditingController(text: item.hsnCode ?? ''),
            mfgDateController: TextEditingController(text: item.mfgDate ?? ''),
            expDateController: TextEditingController(text: item.expDate ?? ''),
            unitPerCaseController: TextEditingController(text: item.unitPerCase?.toString() ?? '25.0'),
            noOfCasesController: TextEditingController(text: item.noOfCases?.toString() ?? '1.0'),
            totalQtyController: TextEditingController(text: item.qty.toString()),
            totalUnitsController: TextEditingController(text: item.totalUnits?.toString() ?? '25.0'),
            unitPriceController: TextEditingController(text: item.unitPrice?.toString() ?? item.rate.toString()),
            amountController: TextEditingController(text: item.total.toString()),
            gstRate: item.gstRate,
          ));
        }
      }
    } else {
      // Auto-generate invoice number
      _generateInvoiceNumber();
      // Add one empty row
      _addItemRow();
    }
  }

  Future<void> _generateInvoiceNumber() async {
    final repo = ref.read(saleRepositoryProvider);
    final String nextNo = await repo.getNextInvoiceNumber(_selectedDate);
    setState(() {
      _invoiceNoController.text = nextNo;
    });
  }

  void _addItemRow() {
    setState(() {
      _itemRows.add(SaleItemRow.createEmpty());
    });
  }

  void _removeItemRow(int index) {
    setState(() {
      _itemRows[index].dispose();
      _itemRows.removeAt(index);
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _invoiceNoController.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  double parsePackingWeight(String packingStr) {
    final regex = RegExp(r'([\d.]+)\s*([a-zA-Z]+)');
    final match = regex.firstMatch(packingStr);
    if (match != null) {
      final double? value = double.tryParse(match.group(1) ?? '');
      final String unit = (match.group(2) ?? '').toLowerCase();
      if (value != null) {
        if (unit == 'g' || unit == 'gm') {
          return value / 1000.0;
        } else if (unit == 'ml') {
          return value / 1000.0;
        }
        return value; // default to kg/L
      }
    }
    return 1.0;
  }

  void _recalculateRow(SaleItemRow row) {
    final double unitPerCase = double.tryParse(row.unitPerCaseController.text) ?? 0.0;
    final double noOfCases = double.tryParse(row.noOfCasesController.text) ?? 0.0;
    final double unitPrice = double.tryParse(row.unitPriceController.text) ?? 0.0;

    final double totalUnits = unitPerCase * noOfCases;
    row.totalUnitsController.text = totalUnits.toStringAsFixed(2);

    final double packingWeight = parsePackingWeight(row.packingController.text);
    final double totalQty = totalUnits * packingWeight;
    row.totalQtyController.text = totalQty.toStringAsFixed(3);

    final double amount = totalUnits * unitPrice;
    row.amountController.text = amount.toStringAsFixed(2);

    setState(() {});
  }

  void _onItemChanged(SaleItemRow row, Item? val) async {
    row.selectedItem = val;
    row.selectedBatch = null;
    row.availableBatches = [];
    row.manufacturerController.clear();
    row.packingController.clear();
    row.batchNoController.clear();
    row.hsnCodeController.clear();
    row.mfgDateController.clear();
    row.expDateController.clear();
    row.totalQtyController.text = '0.0';
    row.totalUnitsController.text = '0.0';
    row.amountController.text = '0.0';

    final index = _itemRows.indexOf(row);
    if (index != -1) {
      _uncertainFields.remove('item_row_${index}_name');
    }

    if (val != null) {
      row.gstRate = val.gstRate;
      row.hsnCodeController.text = val.hsnCode;

      final repo = ref.read(itemRepositoryProvider);
      final batches = await repo.getAvailableBatchesForItem(
        val.id,
        excludeSaleId: widget.saleToEdit?.id,
      );

      setState(() {
        row.availableBatches = batches;
        if (batches.isNotEmpty) {
          final firstBatch = batches.where((b) => b.remainingStock > 0).firstOrNull ?? batches.first;
          _selectBatch(row, firstBatch);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No purchased stock available for item: ${val.name}!'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      });
    }
  }

  void _selectBatch(SaleItemRow row, BatchStockDetails batch) {
    row.selectedBatch = batch;
    row.batchNoController.text = batch.batchNo;
    row.hsnCodeController.text = batch.hsnCode;
    row.manufacturerController.text = batch.manufacturer ?? '';
    row.packingController.text = batch.packing ?? '';
    row.mfgDateController.text = batch.mfgDate ?? '';
    row.expDateController.text = batch.expDate ?? '';
    _recalculateRow(row);
  }

  // Calculate totals
  InvoiceTotals _calculateTotals() {
    final settings = ref.read(settingsProvider);
    final String firmCode = settings?.stateCode ?? '36';
    String destCode = firmCode;
    final String? partyGstin = _selectedParty?.gstin;
    if (partyGstin != null && partyGstin.trim().length >= 2) {
      final String firstTwo = partyGstin.trim().substring(0, 2);
      if (RegExp(r'^\d{2}$').hasMatch(firstTwo)) {
        destCode = firstTwo;
      }
    }

    final List<Map<String, dynamic>> calcRows = [];
    for (final row in _itemRows) {
      if (row.selectedItem != null) {
        final double totalUnits = double.tryParse(row.totalUnitsController.text) ?? 0.0;
        final double unitPrice = double.tryParse(row.unitPriceController.text) ?? 0.0;
        final double taxableValue = totalUnits * unitPrice;

        calcRows.add({
          'qty': 1.0,
          'rate': taxableValue,
          'gstRate': row.gstRate,
        });
      }
    }

    final breakup = GstCalculator.calculateInvoiceBreakup(
      items: calcRows,
      destinationStateCode: destCode,
      firmStateCode: firmCode,
    );

    return InvoiceTotals(
      subtotal: breakup.subtotal,
      cgst: breakup.cgstTotal,
      sgst: breakup.sgstTotal,
      igst: breakup.igstTotal,
      grandTotal: breakup.grandTotal,
    );
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
      if (widget.saleToEdit == null) {
        _generateInvoiceNumber();
      }
    }
  }

  Future<void> _scanInvoice() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Photo Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final image = await picker.pickImage(source: source);
    if (image == null) return;

    setState(() {
      _isScanning = true;
      _uncertainFields.clear();
    });

    try {
      final parties = ref.read(customerProvider);
      final knownParties = parties.map((p) => p.party.name).toList();
      final items = ref.read(itemProvider).value ?? [];
      final knownItems = items.map((i) => i.item.name).toList();

      final ocrResult = await OcrService().scanInvoice(
        File(image.path),
        knownParties: knownParties,
        knownItems: knownItems,
      );
      Party? matchedParty;
      if (ocrResult.partyName != null) {
        for (final p in parties) {
          if (p.party.name.toLowerCase().contains(ocrResult.partyName!.toLowerCase())) {
            matchedParty = p.party;
            break;
          }
        }
      }

      if (ocrResult.partyNameConfidence == 'low') _uncertainFields['party'] = true;
      if (ocrResult.dateConfidence == 'low') _uncertainFields['date'] = true;
      if (ocrResult.invoiceNoConfidence == 'low') _uncertainFields['invoice_no'] = true;

      DateTime parsedDate = DateTime.now();
      if (ocrResult.date != null) {
        try {
          parsedDate = DateTime.parse(ocrResult.date!);
        } catch (_) {}
      }

      final allItems = ref.read(itemProvider).value ?? [];
      final List<SaleItemRow> newRows = [];

      for (int i = 0; i < ocrResult.lineItems.length; i++) {
        final ocrItem = ocrResult.lineItems[i];
        
        Item? matchedItem;
        for (final it in allItems) {
          if (it.item.name.toLowerCase().contains(ocrItem.name.toLowerCase())) {
            matchedItem = it.item;
            break;
          }
        }

        final String rowPrefix = 'item_row_$i';
        if (ocrItem.nameConfidence == 'low') _uncertainFields['${rowPrefix}_name'] = true;
        if (ocrItem.qtyConfidence == 'low') _uncertainFields['${rowPrefix}_qty'] = true;
        if (ocrItem.rateConfidence == 'low') _uncertainFields['${rowPrefix}_rate'] = true;
        if (ocrItem.gstRateConfidence == 'low') _uncertainFields['${rowPrefix}_gst'] = true;

        final newRow = SaleItemRow.createEmpty(
          selectedItem: matchedItem,
          scannedItemName: ocrItem.name,
          totalQty: ocrItem.qty.toString(),
          unitPrice: ocrItem.rate.toString(),
          gstRate: ocrItem.gstRate,
        );

        if (matchedItem != null) {
          final repo = ref.read(itemRepositoryProvider);
          final batches = await repo.getAvailableBatchesForItem(
            matchedItem.id,
            excludeSaleId: widget.saleToEdit?.id,
          );
          newRow.availableBatches = batches;
          if (batches.isNotEmpty) {
            final firstBatch = batches.where((b) => b.remainingStock > 0).firstOrNull ?? batches.first;
            newRow.selectedBatch = firstBatch;
            newRow.batchNoController.text = firstBatch.batchNo;
            newRow.hsnCodeController.text = firstBatch.hsnCode;
            newRow.manufacturerController.text = firstBatch.manufacturer ?? '';
            newRow.packingController.text = firstBatch.packing ?? '';
            newRow.mfgDateController.text = firstBatch.mfgDate ?? '';
            newRow.expDateController.text = firstBatch.expDate ?? '';
            
            final double packingWeight = parsePackingWeight(firstBatch.packing ?? '');
            final double qty = double.tryParse(ocrItem.qty.toString()) ?? 0.0;
            final double totalUnits = packingWeight > 0 ? (qty / packingWeight) : qty;
            newRow.unitPerCaseController.text = '25.0';
            newRow.noOfCasesController.text = (totalUnits / 25.0).toStringAsFixed(2);
            newRow.totalUnitsController.text = totalUnits.toStringAsFixed(2);
            newRow.totalQtyController.text = qty.toStringAsFixed(3);
            newRow.unitPriceController.text = ocrItem.rate.toString();
            newRow.amountController.text = (totalUnits * ocrItem.rate).toStringAsFixed(2);
          }
        }
        newRows.add(newRow);
      }

      setState(() {
        if (matchedParty != null) {
          _selectedParty = matchedParty;
        }
        _selectedDate = parsedDate;
        _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
        if (ocrResult.invoiceNo != null) {
          _invoiceNoController.text = ocrResult.invoiceNo!;
        }

        for (final row in _itemRows) {
          row.dispose();
        }
        _itemRows.clear();
        _itemRows.addAll(newRows);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice scanned. Review yellow fields!'),
          backgroundColor: Colors.amber,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR Scan failed: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<void> _saveInvoice() async {
    if (_selectedParty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a customer.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_itemRows.isEmpty || _itemRows.any((row) => row.selectedItem == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item and fill all details.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final List<String> stockDeficitItems = [];

    for (final row in _itemRows) {
      if (row.selectedItem != null && row.selectedBatch != null) {
        final double qty = double.tryParse(row.totalQtyController.text) ?? 0.0;
        final double availableStock = row.selectedBatch!.remainingStock;

        if (qty > availableStock) {
          stockDeficitItems.add(
              '${row.selectedItem!.name} [Batch: ${row.selectedBatch!.batchNo}] (Request: ${qty.toStringAsFixed(2)} kg/L, Available: ${availableStock.toStringAsFixed(2)} kg/L)');
        }
      } else if (row.selectedItem != null && row.selectedBatch == null) {
        stockDeficitItems.add('${row.selectedItem!.name} (No Lot/Batch selected or no stock available!)');
      }
    }

    if (stockDeficitItems.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Insufficient Stock'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('The following items do not have sufficient stock on hand:'),
              const SizedBox(height: 8),
              ...stockDeficitItems.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $item', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                  )),
              const SizedBox(height: 12),
              const Text('We cannot sell items without having purchased stock. Please review purchase register or select a different lot.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    final isEdit = widget.saleToEdit != null;
    final totals = _calculateTotals();
    final String saleId = widget.saleToEdit?.id ?? const Uuid().v4();

    final sale = Sale(
      id: saleId,
      invoiceNo: _invoiceNoController.text.trim(),
      partyId: _selectedParty!.id,
      date: _selectedDate,
      subtotal: totals.subtotal,
      gstTotal: totals.cgst + totals.sgst + totals.igst,
      grandTotal: totals.grandTotal,
      paymentStatus: _paymentStatus,
      createdAt: widget.saleToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      isDeleted: widget.saleToEdit?.isDeleted ?? false,
      editHistory: widget.saleToEdit?.editHistory ?? const [],
      category: _currentCategory,
    );

    final List<SaleItem> itemsList = [];
    for (final row in _itemRows) {
      final double qty = double.parse(row.totalQtyController.text);
      final double unitPrice = double.parse(row.unitPriceController.text);
      final double totalUnits = double.parse(row.totalUnitsController.text);
      final double taxableVal = totalUnits * unitPrice;
      final double gstAmt = taxableVal * (row.gstRate / 100.0);
      final double lineTotal = taxableVal + gstAmt;

      itemsList.add(SaleItem(
        id: const Uuid().v4(),
        saleId: saleId,
        itemId: row.selectedItem!.id,
        qty: qty,
        rate: unitPrice,
        gstRate: row.gstRate,
        gstAmt: gstAmt,
        total: lineTotal,
        manufacturer: row.manufacturerController.text.trim(),
        packing: row.packingController.text.trim(),
        batchNo: row.batchNoController.text.trim(),
        hsnCode: row.hsnCodeController.text.trim(),
        mfgDate: row.mfgDateController.text.trim().isEmpty ? null : row.mfgDateController.text.trim(),
        expDate: row.expDateController.text.trim().isEmpty ? null : row.expDateController.text.trim(),
        unitPerCase: double.tryParse(row.unitPerCaseController.text),
        noOfCases: double.tryParse(row.noOfCasesController.text),
        totalUnits: totalUnits,
        unitPrice: unitPrice,
      ));
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SalePreviewScreen(
            sale: sale,
            items: itemsList,
            party: _selectedParty!,
            isEdit: isEdit,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOnline = ref.watch(isOnlineProvider);
    final customers = ref.watch(customerProvider);
    final itemsData = ref.watch(itemProvider).value ?? [];
    final isEdit = widget.saleToEdit != null;

    final totals = _calculateTotals();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit 
            ? 'Edit Sale (${_currentCategory == 'SEED' ? 'Seeds' : 'Fertilizers/Pest'})' 
            : 'New Sale (${_currentCategory == 'SEED' ? 'Seeds' : 'Fertilizers/Pest'})'),
        actions: [
          if (!isEdit)
            Tooltip(
              message: 'Scan invoice using camera/gallery',
              child: IconButton(
                icon: const Icon(Icons.document_scanner_rounded),
                onPressed: _scanInvoice,
                color: Colors.white,
              ),
            ),
        ],
      ),
      body: _isScanning
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing invoice with Vision API...', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Please wait, extracting form fields...'),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            value: customers.any((p) => p.party.id == _selectedParty?.id)
                                ? _selectedParty?.id
                                : (_selectedParty != null ? _selectedParty!.id : null),
                            decoration: InputDecoration(
                              labelText: 'Select Customer / కొనుగోలుదారు *',
                              prefixIcon: const Icon(Icons.person_rounded),
                              fillColor: _uncertainFields['party'] == true ? Colors.yellow.shade100 : null,
                            ),
                            items: [
                              ...customers.map((p) {
                                return DropdownMenuItem(
                                  value: p.party.id,
                                  child: Text(p.party.name),
                                );
                              }),
                              if (_selectedParty != null && !customers.any((p) => p.party.id == _selectedParty?.id))
                                DropdownMenuItem(
                                  value: _selectedParty!.id,
                                  child: Text(_selectedParty!.name),
                                ),
                              DropdownMenuItem(
                                value: '__ADD_NEW_CUSTOMER__',
                                child: Text('+ Add details', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            onChanged: (val) async {
                              if (val == '__ADD_NEW_CUSTOMER__') {
                                final oldParty = _selectedParty;
                                final newParty = await showDialog<Party>(
                                  context: context,
                                  builder: (context) => const PartyFormDialog(preselectedType: 'CUSTOMER'),
                                );
                                setState(() {
                                  if (newParty != null) {
                                    _selectedParty = newParty;
                                  } else {
                                    _selectedParty = oldParty;
                                  }
                                  _uncertainFields.remove('party');
                                });
                              } else {
                                setState(() {
                                  if (val != null) {
                                    _selectedParty = customers.firstWhere((p) => p.party.id == val).party;
                                  } else {
                                    _selectedParty = null;
                                  }
                                  _uncertainFields.remove('party');
                                });
                              }
                            },
                            validator: (val) => val == null ? 'Customer is mandatory' : null,
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _dateController,
                                  readOnly: true,
                                  onTap: _selectDate,
                                  decoration: InputDecoration(
                                    labelText: 'Invoice Date / తేదీ *',
                                    prefixIcon: const Icon(Icons.calendar_today_rounded),
                                    fillColor: _uncertainFields['date'] == true ? Colors.yellow.shade100 : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _invoiceNoController,
                                  decoration: InputDecoration(
                                    labelText: 'Invoice No / ఇన్వాయిస్ సంఖ్య *',
                                    prefixIcon: const Icon(Icons.tag_rounded),
                                    fillColor: _uncertainFields['invoice_no'] == true ? Colors.yellow.shade100 : null,
                                  ),
                                  onChanged: (value) {
                                    _uncertainFields.remove('invoice_no');
                                  },
                                  validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'INVOICE LINE ITEMS',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Row'),
                        onPressed: _addItemRow,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _itemRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final row = _itemRows[index];
                      final rowPrefix = 'item_row_$index';

                      final double enteredQty = double.tryParse(row.totalQtyController.text) ?? 0.0;
                      final double availableStock = row.selectedBatch?.remainingStock ?? 0.0;
                      final bool isStockDeficit = row.selectedItem != null && enteredQty > availableStock;

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isStockDeficit ? Colors.red.shade300 : theme.dividerColor,
                            width: isStockDeficit ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: theme.colorScheme.secondaryContainer,
                                        child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Item Row #${index + 1}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                    onPressed: () => _removeItemRow(index),
                                  ),
                                ],
                              ),
                              const Divider(),
                              const SizedBox(height: 8),
                              Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.2),
                                  1: FlexColumnWidth(2.0),
                                },
                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                children: [
                                  _buildFormRow(
                                    'Variety / సరుకు *',
                                    DropdownButtonFormField<Item>(
                                      value: row.selectedItem,
                                      hint: const Text('Select Variety'),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        fillColor: _uncertainFields['${rowPrefix}_name'] == true ? Colors.yellow.shade100 : null,
                                        filled: _uncertainFields['${rowPrefix}_name'] == true,
                                        helperText: row.selectedItem == null && row.scannedItemName != null ? 'Scanned: ${row.scannedItemName}' : null,
                                        helperStyle: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 10),
                                      ),
                                      items: itemsData
                                          .where((i) => i.item.category == _currentCategory)
                                          .map((i) {
                                        return DropdownMenuItem(
                                          value: i.item,
                                          child: Text('${i.item.name} (${i.item.primaryUnit})'),
                                        );
                                      }).toList(),
                                      onChanged: (val) => _onItemChanged(row, val),
                                    ),
                                  ),
                                  if (row.selectedItem != null) ...[
                                    _buildFormRow(
                                      'Lot / Batch No *',
                                      DropdownButtonFormField<BatchStockDetails>(
                                        value: row.availableBatches.contains(row.selectedBatch)
                                            ? row.selectedBatch
                                            : null,
                                        hint: const Text('Select Lot / Batch No *'),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: row.availableBatches.map((b) {
                                          return DropdownMenuItem(
                                            value: b,
                                            child: Text('Batch: ${b.batchNo} (Stock: ${b.remainingStock.toStringAsFixed(2)} kg/L)'),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            _selectBatch(row, val);
                                          }
                                        },
                                        validator: (val) => val == null ? 'Required' : null,
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Manufacturer',
                                      TextFormField(
                                        controller: row.manufacturerController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Packing',
                                      TextFormField(
                                        controller: row.packingController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'HSN Code',
                                      TextFormField(
                                        controller: row.hsnCodeController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Batch No.',
                                      TextFormField(
                                        controller: row.batchNoController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Mfg Date',
                                      TextFormField(
                                        controller: row.mfgDateController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Exp Date',
                                      TextFormField(
                                        controller: row.expDateController,
                                        readOnly: true,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                          filled: true,
                                        ),
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Unit/Case *',
                                      TextFormField(
                                        controller: row.unitPerCaseController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => _recalculateRow(row),
                                        validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid' : null,
                                      ),
                                    ),
                                    _buildFormRow(
                                      'No. Cases *',
                                      TextFormField(
                                        controller: row.noOfCasesController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => _recalculateRow(row),
                                        validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid' : null,
                                      ),
                                    ),
                                    _buildFormRow(
                                      'Unit Price *',
                                      TextFormField(
                                        controller: row.unitPriceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        onChanged: (_) => _recalculateRow(row),
                                        validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid' : null,
                                      ),
                                    ),
                                    _buildFormRow(
                                      'GST %',
                                      DropdownButtonFormField<double>(
                                        value: row.gstRate,
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 0.0, child: Text('0%')),
                                          DropdownMenuItem(value: 5.0, child: Text('5%')),
                                          DropdownMenuItem(value: 12.0, child: Text('12%')),
                                          DropdownMenuItem(value: 18.0, child: Text('18%')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              row.gstRate = val;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (row.selectedItem != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Units: ${row.totalUnitsController.text}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                      Text(
                                        'Qty: ${row.totalQtyController.text} kg/L',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                      Text(
                                        'Amount: ₹${row.amountController.text}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (isStockDeficit) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Exceeds available batch stock of ${row.selectedBatch?.remainingStock.toStringAsFixed(2)} kg/L!',
                                      style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'TAX SUMMARY',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GstRow(
                            subtotal: totals.subtotal,
                            cgst: totals.cgst,
                            sgst: totals.sgst,
                            igst: totals.igst,
                            grandTotal: totals.grandTotal,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        value: _paymentStatus,
                        decoration: const InputDecoration(
                          labelText: 'Payment Status / చెల్లింపు స్థితి',
                          prefixIcon: Icon(Icons.payment_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'PAID', child: Text('PAID (చెల్లించబడింది)')),
                          DropdownMenuItem(value: 'PARTIAL', child: Text('PARTIAL (కొంత భాగం)')),
                          DropdownMenuItem(value: 'PENDING', child: Text('PENDING (బాకీ)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _paymentStatus = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: _saveInvoice,
                    child: Text(isEdit ? 'Preview Changes PDF' : 'Preview Sale PDF'),
                  ),
                ],
              ),
            ),
    );
  }
}

class SaleItemRow {
  Item? selectedItem;
  String? scannedItemName;
  BatchStockDetails? selectedBatch;
  List<BatchStockDetails> availableBatches = [];

  final TextEditingController manufacturerController;
  final TextEditingController packingController;
  final TextEditingController batchNoController;
  final TextEditingController hsnCodeController;
  final TextEditingController mfgDateController;
  final TextEditingController expDateController;
  final TextEditingController unitPerCaseController;
  final TextEditingController noOfCasesController;
  final TextEditingController totalQtyController;
  final TextEditingController totalUnitsController;
  final TextEditingController unitPriceController;
  final TextEditingController amountController;
  double gstRate;

  SaleItemRow({
    this.selectedItem,
    this.scannedItemName,
    this.selectedBatch,
    this.availableBatches = const [],
    required this.manufacturerController,
    required this.packingController,
    required this.batchNoController,
    required this.hsnCodeController,
    required this.mfgDateController,
    required this.expDateController,
    required this.unitPerCaseController,
    required this.noOfCasesController,
    required this.totalQtyController,
    required this.totalUnitsController,
    required this.unitPriceController,
    required this.amountController,
    this.gstRate = 0.0,
  });

  factory SaleItemRow.createEmpty({
    Item? selectedItem,
    String? scannedItemName,
    String? manufacturer,
    String? packing,
    String? batchNo,
    String? hsnCode,
    String? mfgDate,
    String? expDate,
    String? unitPerCase,
    String? noOfCases,
    String? totalQty,
    String? totalUnits,
    String? unitPrice,
    String? amount,
    double gstRate = 0.0,
  }) {
    return SaleItemRow(
      selectedItem: selectedItem,
      scannedItemName: scannedItemName,
      manufacturerController: TextEditingController(text: manufacturer ?? ''),
      packingController: TextEditingController(text: packing ?? ''),
      batchNoController: TextEditingController(text: batchNo ?? ''),
      hsnCodeController: TextEditingController(text: hsnCode ?? selectedItem?.hsnCode ?? ''),
      mfgDateController: TextEditingController(text: mfgDate ?? ''),
      expDateController: TextEditingController(text: expDate ?? ''),
      unitPerCaseController: TextEditingController(text: unitPerCase ?? '25.0'),
      noOfCasesController: TextEditingController(text: noOfCases ?? '1.0'),
      totalQtyController: TextEditingController(text: totalQty ?? '0.0'),
      totalUnitsController: TextEditingController(text: totalUnits ?? '25.0'),
      unitPriceController: TextEditingController(text: unitPrice ?? '0.0'),
      amountController: TextEditingController(text: amount ?? '0.0'),
      gstRate: gstRate,
    );
  }

  void dispose() {
    manufacturerController.dispose();
    packingController.dispose();
    batchNoController.dispose();
    hsnCodeController.dispose();
    mfgDateController.dispose();
    expDateController.dispose();
    unitPerCaseController.dispose();
    noOfCasesController.dispose();
    totalQtyController.dispose();
    totalUnitsController.dispose();
    unitPriceController.dispose();
    amountController.dispose();
  }
}

class InvoiceTotals {
  final double subtotal;
  final double cgst;
  final double sgst;
  final double igst;
  final double grandTotal;

  InvoiceTotals({
    required this.subtotal,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.grandTotal,
  });
}
