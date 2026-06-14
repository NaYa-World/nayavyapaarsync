import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
// import '../../../core/utils/date_utils.dart';
import '../../../core/utils/gst_calculator.dart';
// import '../../../core/utils/indian_format.dart';
import '../../../data/models/item.dart';
import '../../../data/models/party.dart';
import '../../../data/models/purchase.dart';
// import '../../../data/repositories/purchase_repository.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/ocr_service.dart';
import '../../widgets/gst_row.dart';
import '../stock/stock_register_screen.dart';
import '../party/party_ledger_screen.dart';
import 'purchase_preview_screen.dart';

class PurchaseEntryScreen extends ConsumerStatefulWidget {
  final Purchase? purchaseToEdit;
  final String? category; // 'SEED' or 'FERTILISER'

  const PurchaseEntryScreen({super.key, this.purchaseToEdit, this.category});

  @override
  ConsumerState<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateController = TextEditingController(text: DateFormat('dd-MMM-yyyy').format(DateTime.now()));
  final _invoiceNoController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  Party? _selectedParty;
  String _paymentStatus = 'PENDING';
  bool _isScanning = false;

  String get _currentCategory => widget.purchaseToEdit?.category ?? widget.category ?? 'SEED';

  List<String> _manufacturersList = [];

  // Form row models
  final List<PurchaseItemRow> _itemRows = [];

  // Low confidence highlights from OCR
  final Map<String, bool> _uncertainFields = {}; // fieldName -> isUncertain

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

  Future<void> _loadManufacturers() async {
    final list = await ref.read(itemRepositoryProvider).getDistinctManufacturers();
    setState(() {
      _manufacturersList = list;
    });
  }

  Future<String?> showAddManufacturerDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Company / Manufacturer'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Company / Manufacturer Name',
            hintText: 'Enter name',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx, name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeForm() async {
    await _loadManufacturers();
    final isEdit = widget.purchaseToEdit != null;
    if (isEdit) {
      final p = widget.purchaseToEdit!;
      _selectedDate = p.date;
      _dateController.text = DateFormat('dd-MMM-yyyy').format(_selectedDate);
      _invoiceNoController.text = p.invoiceNo;
      _paymentStatus = p.paymentStatus;

      // Select party safely
      final partiesData = ref.read(partyProvider).value ?? [];
      final partyMatch = partiesData.where((element) => element.party.id == p.partyId);
      if (partyMatch.isNotEmpty) {
        _selectedParty = partyMatch.first.party;
      }

      // Load items
      final repo = ref.read(purchaseRepositoryProvider);
      final details = await repo.getPurchase(p.id);
      if (details != null) {
        final allItems = ref.read(itemProvider).value ?? [];
        for (final item in details.items) {
          final matchedItem = allItems.where((e) => e.item.id == item.itemId).firstOrNull?.item;
          _itemRows.add(PurchaseItemRow.createEmpty(
            selectedItem: matchedItem,
            lotNo: item.lotNo,
            hsnCode: item.hsnCode,
            noOfPkts: item.noOfPkts?.toString(),
            noOfBags: item.noOfBags?.toString(),
            totalQty: item.qty.toString(),
            rate: item.rate.toString(),
            perUnit: item.perUnit ?? 'kgs',
            discountPct: item.discountPct?.toString(),
            mfgDate: item.mfgDate,
            expDate: item.expDate,
            gstRate: item.gstRate,
            manufacturer: item.manufacturer,
            packing: item.packing,
          ));
        }
      }
    } else {
      // Auto-generate invoice number for today's date
      _generateInvoiceNumber();
      // Add one empty row to start with
      _addItemRow();
    }
  }

  Future<void> _generateInvoiceNumber() async {
    final repo = ref.read(purchaseRepositoryProvider);
    final String nextNo = await repo.getNextInvoiceNumber(_selectedDate);
    setState(() {
      _invoiceNoController.text = nextNo;
    });
  }

  void _addItemRow() {
    setState(() {
      _itemRows.add(PurchaseItemRow.createEmpty(
        totalQty: '1.0',
        rate: '0.0',
      ));
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
        final double qty = double.tryParse(row.totalQtyController.text) ?? 0.0;
        final double rate = double.tryParse(row.rateController.text) ?? 0.0;
        final double pkts = double.tryParse(row.noOfPktsController.text) ?? 0.0;
        final double bags = double.tryParse(row.noOfBagsController.text) ?? 0.0;
        final double discountPct = double.tryParse(row.discountPctController.text) ?? 0.0;

        double baseAmount = 0.0;
        if (row.perUnit == 'pkts') {
          baseAmount = pkts * rate;
        } else if (row.perUnit == 'bags') {
          baseAmount = bags * rate;
        } else {
          baseAmount = qty * rate; // default to kgs
        }

        double taxableValue = baseAmount * (1 - discountPct / 100.0);

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
      if (widget.purchaseToEdit == null) {
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
      final parties = ref.read(supplierProvider);
      final knownParties = parties.map((p) => p.party.name).toList();
      final items = ref.read(itemProvider).value ?? [];
      final knownItems = items.map((i) => i.item.name).toList();

      final ocrResult = await OcrService().scanInvoice(
        File(image.path),
        knownParties: knownParties,
        knownItems: knownItems,
      );
      
      // Match supplier party by name
      Party? matchedParty;
      if (ocrResult.partyName != null) {
        for (final p in parties) {
          if (p.party.name.toLowerCase().contains(ocrResult.partyName!.toLowerCase())) {
            matchedParty = p.party;
            break;
          }
        }
      }

      // Mark uncertainty highlights
      if (ocrResult.partyNameConfidence == 'low') {
        _uncertainFields['party'] = true;
      }
      if (ocrResult.dateConfidence == 'low') {
        _uncertainFields['date'] = true;
      }
      if (ocrResult.invoiceNoConfidence == 'low') {
        _uncertainFields['invoice_no'] = true;
      }

      // Update date
      DateTime parsedDate = DateTime.now();
      if (ocrResult.date != null) {
        try {
          parsedDate = DateTime.parse(ocrResult.date!);
        } catch (_) {}
      }

      // Update line items
      final allItems = ref.read(itemProvider).value ?? [];
      final List<PurchaseItemRow> newRows = [];

      for (int i = 0; i < ocrResult.lineItems.length; i++) {
        final ocrItem = ocrResult.lineItems[i];
        
        // Find best match in database items
        Item? matchedItem;
        for (final it in allItems) {
          if (it.item.name.toLowerCase().contains(ocrItem.name.toLowerCase())) {
            matchedItem = it.item;
            break;
          }
        }

        // Set row uncertainty highlights
        final String rowPrefix = 'item_row_$i';
        if (ocrItem.nameConfidence == 'low') _uncertainFields['${rowPrefix}_name'] = true;
        if (ocrItem.qtyConfidence == 'low') _uncertainFields['${rowPrefix}_qty'] = true;
        if (ocrItem.rateConfidence == 'low') _uncertainFields['${rowPrefix}_rate'] = true;
        if (ocrItem.gstRateConfidence == 'low') _uncertainFields['${rowPrefix}_gst'] = true;

        newRows.add(PurchaseItemRow.createEmpty(
          selectedItem: matchedItem,
          scannedItemName: ocrItem.name,
          totalQty: ocrItem.qty.toString(),
          rate: ocrItem.rate.toString(),
          gstRate: ocrItem.gstRate,
        ));
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

        // Replace item rows safely
        for (final row in _itemRows) {
          row.dispose();
        }
        _itemRows.clear();
        _itemRows.addAll(newRows);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invoice scanned. Please review highlighted yellow fields!'),
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
        const SnackBar(content: Text('Please select a supplier.'), backgroundColor: Colors.red),
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

    final isEdit = widget.purchaseToEdit != null;
    final totals = _calculateTotals();
    final String purchaseId = widget.purchaseToEdit?.id ?? const Uuid().v4();

    final purchase = Purchase(
      id: purchaseId,
      invoiceNo: _invoiceNoController.text.trim(),
      partyId: _selectedParty!.id,
      date: _selectedDate,
      subtotal: totals.subtotal,
      gstTotal: totals.cgst + totals.sgst + totals.igst,
      grandTotal: totals.grandTotal,
      paymentStatus: _paymentStatus,
      createdAt: widget.purchaseToEdit?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      isDeleted: widget.purchaseToEdit?.isDeleted ?? false,
      editHistory: widget.purchaseToEdit?.editHistory ?? const [],
      category: _currentCategory,
    );

    final List<PurchaseItem> itemsList = [];
    for (final row in _itemRows) {
      final double qty = double.parse(row.totalQtyController.text);
      final double rate = double.parse(row.rateController.text);
      final double pkts = double.tryParse(row.noOfPktsController.text) ?? 0.0;
      final double bags = double.tryParse(row.noOfBagsController.text) ?? 0.0;
      final double discountPct = double.tryParse(row.discountPctController.text) ?? 0.0;

      double baseAmount = 0.0;
      if (row.perUnit == 'pkts') {
        baseAmount = pkts * rate;
      } else if (row.perUnit == 'bags') {
        baseAmount = bags * rate;
      } else {
        baseAmount = qty * rate; // default to kgs
      }

      final double discountAmt = baseAmount * (discountPct / 100.0);
      final double taxableValue = baseAmount - discountAmt;
      final double gstAmt = taxableValue * (row.gstRate / 100.0);
      final double lineTotal = taxableValue + gstAmt;

      itemsList.add(PurchaseItem(
        id: const Uuid().v4(),
        purchaseId: purchaseId,
        itemId: row.selectedItem!.id,
        qty: qty,
        rate: rate,
        gstRate: row.gstRate,
        gstAmt: gstAmt,
        total: lineTotal,
        lotNo: row.lotNoController.text.trim(),
        hsnCode: row.hsnCodeController.text.trim(),
        noOfPkts: double.tryParse(row.noOfPktsController.text),
        noOfBags: double.tryParse(row.noOfBagsController.text),
        perUnit: row.perUnit,
        discountPct: double.tryParse(row.discountPctController.text),
        mfgDate: row.mfgDateController.text.trim().isEmpty ? null : row.mfgDateController.text.trim(),
        expDate: row.expDateController.text.trim().isEmpty ? null : row.expDateController.text.trim(),
        manufacturer: row.manufacturerController.text.trim().isEmpty ? null : row.manufacturerController.text.trim(),
        packing: row.packingController.text.trim().isEmpty ? null : row.packingController.text.trim(),
      ));
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PurchasePreviewScreen(
            purchase: purchase,
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
    final suppliers = ref.watch(supplierProvider);
    final itemsData = ref.watch(itemProvider).value ?? [];
    final isEdit = widget.purchaseToEdit != null;

    final totals = _calculateTotals();

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit 
            ? 'Edit Purchase (${_currentCategory == 'SEED' ? 'Seeds' : 'Fertilizers/Pest'})' 
            : 'New Purchase (${_currentCategory == 'SEED' ? 'Seeds' : 'Fertilizers/Pest'})'),
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
                  Text('Analyzing invoice with Claude Sonnet Vision API...', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Please wait, extracting form fields...'),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Invoice Meta Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Supplier select
                          DropdownButtonFormField<String>(
                            initialValue: suppliers.any((p) => p.party.id == _selectedParty?.id)
                                ? _selectedParty?.id
                                : (_selectedParty?.id),
                            decoration: InputDecoration(
                              labelText: 'Select Supplier / అమ్మకందారు *',
                              prefixIcon: const Icon(Icons.person_rounded),
                              fillColor: _uncertainFields['party'] == true ? Colors.yellow.shade100 : null,
                            ),
                            items: [
                              ...suppliers.map((p) {
                                return DropdownMenuItem(
                                  value: p.party.id,
                                  child: Text(p.party.name),
                                );
                              }),
                              if (_selectedParty != null && !suppliers.any((p) => p.party.id == _selectedParty?.id))
                                DropdownMenuItem(
                                  value: _selectedParty!.id,
                                  child: Text(_selectedParty!.name),
                                ),
                              DropdownMenuItem(
                                value: '__ADD_NEW_SUPPLIER__',
                                child: Text('+ Add details', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                              ),
                            ],
                            onChanged: (val) async {
                              if (val == '__ADD_NEW_SUPPLIER__') {
                                final oldParty = _selectedParty;
                                final newParty = await showDialog<Party>(
                                  context: context,
                                  builder: (context) => const PartyFormDialog(preselectedType: 'SUPPLIER'),
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
                                    _selectedParty = suppliers.firstWhere((p) => p.party.id == val).party;
                                  } else {
                                    _selectedParty = null;
                                  }
                                  _uncertainFields.remove('party');
                                });
                              }
                            },
                            validator: (val) => val == null ? 'Supplier is mandatory' : null,
                          ),
                          const SizedBox(height: 12),

                          Row(
                            children: [
                              // Date selection
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
                              // Invoice Number
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

                  // Line Items Title
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

                  // Line Items Form list
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _itemRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final row = _itemRows[index];
                      final rowPrefix = 'item_row_$index';

                      return Card(
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
                                    DropdownButtonFormField<String>(
                                      initialValue: itemsData.any((i) => i.item.id == row.selectedItem?.id && i.item.category == _currentCategory)
                                          ? row.selectedItem?.id
                                          : null,
                                      hint: const Text('Select Variety'),
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        fillColor: _uncertainFields['${rowPrefix}_name'] == true ? Colors.yellow.shade100 : null,
                                        filled: _uncertainFields['${rowPrefix}_name'] == true,
                                        helperText: row.selectedItem == null && row.scannedItemName != null ? 'Scanned: ${row.scannedItemName}' : null,
                                        helperStyle: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 10),
                                      ),
                                      items: [
                                        ...itemsData
                                            .where((i) => i.item.category == _currentCategory)
                                            .map((i) {
                                          return DropdownMenuItem(
                                            value: i.item.id,
                                            child: Text('${i.item.name} (${i.item.primaryUnit})'),
                                          );
                                        }),
                                        DropdownMenuItem(
                                          value: '__ADD_NEW__',
                                          child: Text('+ Add details', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                      onChanged: (val) async {
                                        if (val == '__ADD_NEW__') {
                                          final oldItem = row.selectedItem;
                                          final newItem = await showDialog<Item>(
                                            context: context,
                                            builder: (context) => ItemFormDialog(preselectedCategory: _currentCategory),
                                          );
                                          setState(() {
                                            if (newItem != null) {
                                              row.selectedItem = newItem;
                                              row.gstRate = newItem.gstRate;
                                              row.hsnCodeController.text = newItem.hsnCode;
                                            } else {
                                              row.selectedItem = oldItem;
                                            }
                                          });
                                        } else {
                                          setState(() {
                                            if (val != null) {
                                              final matched = itemsData.firstWhere((i) => i.item.id == val).item;
                                              row.selectedItem = matched;
                                              row.gstRate = matched.gstRate;
                                              row.hsnCodeController.text = matched.hsnCode;
                                            } else {
                                              row.selectedItem = null;
                                            }
                                            _uncertainFields.remove('${rowPrefix}_name');
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Manufacturer *',
                                    DropdownButtonFormField<String>(
                                      initialValue: _manufacturersList.contains(row.manufacturerController.text)
                                          ? row.manufacturerController.text
                                          : (row.manufacturerController.text.isNotEmpty ? row.manufacturerController.text : null),
                                      hint: const Text('Select Manufacturer'),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: [
                                        ..._manufacturersList.map((m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(m),
                                        )),
                                        DropdownMenuItem(
                                          value: '__ADD_NEW_MANUFACTURER__',
                                          child: Text('+ Add details', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                      onChanged: (val) async {
                                        if (val == '__ADD_NEW_MANUFACTURER__') {
                                          final oldM = row.manufacturerController.text;
                                          final newM = await showAddManufacturerDialog(context);
                                          setState(() {
                                            if (newM != null) {
                                              if (!_manufacturersList.contains(newM)) {
                                                _manufacturersList.add(newM);
                                                _manufacturersList.sort();
                                              }
                                              row.manufacturerController.text = newM;
                                            } else {
                                              row.manufacturerController.text = oldM;
                                            }
                                          });
                                        } else {
                                          setState(() {
                                            row.manufacturerController.text = val ?? '';
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Packing *',
                                    TextFormField(
                                      controller: row.packingController,
                                      decoration: const InputDecoration(
                                        hintText: 'e.g. 475 g, 10 kg',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Lot / Batch No *',
                                    TextFormField(
                                      controller: row.lotNoController,
                                      decoration: const InputDecoration(
                                        hintText: 'Lot number',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                  _buildFormRow(
                                    'HSN Code *',
                                    TextFormField(
                                      controller: row.hsnCodeController,
                                      decoration: const InputDecoration(
                                        hintText: 'HSN Code',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Per Unit *',
                                    DropdownButtonFormField<String>(
                                      initialValue: row.perUnit,
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'kgs', child: Text('kgs')),
                                        DropdownMenuItem(value: 'pkts', child: Text('pkts')),
                                        DropdownMenuItem(value: 'bags', child: Text('bags')),
                                        DropdownMenuItem(value: 'boxes', child: Text('boxes')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            row.perUnit = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  _buildFormRow(
                                    'No. of Pkts',
                                    TextFormField(
                                      controller: row.noOfPktsController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        hintText: 'Packets count',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) => setState(() {}),
                                    ),
                                  ),
                                  _buildFormRow(
                                    'No. of Bags',
                                    TextFormField(
                                      controller: row.noOfBagsController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        hintText: 'Bags count',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) => setState(() {}),
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Total Qty (${row.perUnit}) *',
                                    TextFormField(
                                      controller: row.totalQtyController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        hintText: 'Total quantity',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        fillColor: _uncertainFields['${rowPrefix}_qty'] == true ? Colors.yellow.shade100 : null,
                                        filled: _uncertainFields['${rowPrefix}_qty'] == true,
                                      ),
                                      onChanged: (val) {
                                        _uncertainFields.remove('${rowPrefix}_qty');
                                        setState(() {});
                                      },
                                      validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid' : null,
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Rate *',
                                    TextFormField(
                                      controller: row.rateController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        hintText: 'Rate per unit',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        fillColor: _uncertainFields['${rowPrefix}_rate'] == true ? Colors.yellow.shade100 : null,
                                        filled: _uncertainFields['${rowPrefix}_rate'] == true,
                                      ),
                                      onChanged: (val) {
                                        _uncertainFields.remove('${rowPrefix}_rate');
                                        setState(() {});
                                      },
                                      validator: (val) => val == null || double.tryParse(val) == null ? 'Invalid' : null,
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Discount (%)',
                                    TextFormField(
                                      controller: row.discountPctController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        hintText: 'Discount percentage',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) => setState(() {}),
                                    ),
                                  ),
                                  _buildFormRow(
                                    'GST % *',
                                    DropdownButtonFormField<double>(
                                      initialValue: row.gstRate,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: const OutlineInputBorder(),
                                        fillColor: _uncertainFields['${rowPrefix}_gst'] == true ? Colors.yellow.shade100 : null,
                                        filled: _uncertainFields['${rowPrefix}_gst'] == true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 0.0, child: Text('0%')),
                                        DropdownMenuItem(value: 5.0, child: Text('5%')),
                                        DropdownMenuItem(value: 12.0, child: Text('12%')),
                                        DropdownMenuItem(value: 18.0, child: Text('18%')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          _uncertainFields.remove('${rowPrefix}_gst');
                                          setState(() {
                                            row.gstRate = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Mfg Date',
                                    TextFormField(
                                      controller: row.mfgDateController,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        hintText: 'Select mfg date',
                                        prefixIcon: Icon(Icons.date_range_rounded, size: 18),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (date != null) {
                                          setState(() {
                                            row.mfgDateController.text = DateFormat('yyyy-MM-dd').format(date);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  _buildFormRow(
                                    'Expiry Date',
                                    TextFormField(
                                      controller: row.expDateController,
                                      readOnly: true,
                                      decoration: const InputDecoration(
                                        hintText: 'Select expiry date',
                                        prefixIcon: Icon(Icons.event_busy_rounded, size: 18),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(),
                                      ),
                                      onTap: () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now().add(const Duration(days: 365)),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (date != null) {
                                          setState(() {
                                            row.expDateController.text = DateFormat('yyyy-MM-dd').format(date);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final double qty = double.tryParse(row.totalQtyController.text) ?? 0.0;
                                  final double rate = double.tryParse(row.rateController.text) ?? 0.0;
                                  final double pkts = double.tryParse(row.noOfPktsController.text) ?? 0.0;
                                  final double bags = double.tryParse(row.noOfBagsController.text) ?? 0.0;
                                  final double discountPct = double.tryParse(row.discountPctController.text) ?? 0.0;

                                  double baseAmount = 0.0;
                                  if (row.perUnit == 'pkts') {
                                    baseAmount = pkts * rate;
                                  } else if (row.perUnit == 'bags') {
                                    baseAmount = bags * rate;
                                  } else {
                                    baseAmount = qty * rate; // default to kgs
                                  }

                                  final double discountAmt = baseAmount * (discountPct / 100.0);
                                  final double taxableAmt = baseAmount - discountAmt;
                                  final double gstAmt = taxableAmt * (row.gstRate / 100.0);
                                  final double totalAmt = taxableAmt + gstAmt;

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0, left: 4.0),
                                    child: Text(
                                      'Taxable: ₹${taxableAmt.toStringAsFixed(2)} | GST: ₹${gstAmt.toStringAsFixed(2)} | Net Total: ₹${totalAmt.toStringAsFixed(2)}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Invoice Summary
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

                  // Payment Status
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        initialValue: _paymentStatus,
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

                  // Save Button
                  ElevatedButton(
                    onPressed: _saveInvoice,
                    child: Text(isEdit ? 'Preview Changes PDF' : 'Preview Purchase PDF'),
                  ),
                ],
              ),
            ),
    );
  }
}

class PurchaseItemRow {
  Item? selectedItem;
  String? scannedItemName;
  final TextEditingController lotNoController;
  final TextEditingController hsnCodeController;
  final TextEditingController noOfPktsController;
  final TextEditingController noOfBagsController;
  final TextEditingController totalQtyController;
  final TextEditingController rateController;
  String perUnit; // 'kgs', 'pkts', 'bags', 'boxes'
  final TextEditingController discountPctController;
  final TextEditingController mfgDateController;
  final TextEditingController expDateController;
  double gstRate;
  final TextEditingController manufacturerController;
  final TextEditingController packingController;

  PurchaseItemRow({
    this.selectedItem,
    this.scannedItemName,
    required this.lotNoController,
    required this.hsnCodeController,
    required this.noOfPktsController,
    required this.noOfBagsController,
    required this.totalQtyController,
    required this.rateController,
    this.perUnit = 'kgs',
    required this.discountPctController,
    required this.mfgDateController,
    required this.expDateController,
    this.gstRate = 0.0,
    required this.manufacturerController,
    required this.packingController,
  });

  factory PurchaseItemRow.createEmpty({
    Item? selectedItem,
    String? scannedItemName,
    String? lotNo,
    String? hsnCode,
    String? noOfPkts,
    String? noOfBags,
    String? totalQty,
    String? rate,
    String perUnit = 'kgs',
    String? discountPct,
    String? mfgDate,
    String? expDate,
    double gstRate = 0.0,
    String? manufacturer,
    String? packing,
  }) {
    return PurchaseItemRow(
      selectedItem: selectedItem,
      scannedItemName: scannedItemName,
      lotNoController: TextEditingController(text: lotNo ?? ''),
      hsnCodeController: TextEditingController(text: hsnCode ?? selectedItem?.hsnCode ?? ''),
      noOfPktsController: TextEditingController(text: noOfPkts ?? ''),
      noOfBagsController: TextEditingController(text: noOfBags ?? ''),
      totalQtyController: TextEditingController(text: totalQty ?? ''),
      rateController: TextEditingController(text: rate ?? ''),
      perUnit: perUnit,
      discountPctController: TextEditingController(text: discountPct ?? ''),
      mfgDateController: TextEditingController(text: mfgDate ?? ''),
      expDateController: TextEditingController(text: expDate ?? ''),
      gstRate: gstRate,
      manufacturerController: TextEditingController(text: manufacturer ?? ''),
      packingController: TextEditingController(text: packing ?? ''),
    );
  }

  void dispose() {
    lotNoController.dispose();
    hsnCodeController.dispose();
    noOfPktsController.dispose();
    noOfBagsController.dispose();
    totalQtyController.dispose();
    rateController.dispose();
    discountPctController.dispose();
    mfgDateController.dispose();
    expDateController.dispose();
    manufacturerController.dispose();
    packingController.dispose();
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
