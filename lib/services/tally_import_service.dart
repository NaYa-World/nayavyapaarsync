import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../data/database/db_helper.dart';
import '../data/models/item.dart';
import '../data/models/party.dart';
import '../data/models/purchase.dart';
import '../data/models/sale.dart';

class TallyImportResult {
  final int partiesImported;
  final int itemsImported;
  final int salesImported;
  final int purchasesImported;
  final List<String> logs;

  TallyImportResult({
    required this.partiesImported,
    required this.itemsImported,
    required this.salesImported,
    required this.purchasesImported,
    required this.logs,
  });
}

class TallyImportService {
  static final TallyImportService _instance = TallyImportService._internal();
  factory TallyImportService() => _instance;
  TallyImportService._internal();

  final DbHelper _dbHelper = DbHelper();
  final Uuid _uuid = const Uuid();

  /// Helper to extract XML tag value
  String? _extractTag(String block, String tagName) {
    final match = RegExp('<$tagName(?:\\s+[^>]*)?>([\\s\\S]*?)</$tagName>', caseSensitive: false).firstMatch(block);
    return match?.group(1)?.trim();
  }

  /// Helper to extract XML attribute value
  String? _extractAttribute(String openingTag, String attrName) {
    final match = RegExp('$attrName="([^"]*)"', caseSensitive: false).firstMatch(openingTag);
    return match?.group(1);
  }

  /// Parses Tally XML string and imports masters and vouchers
  Future<TallyImportResult> importTallyXml(String xmlContent) async {
    final List<String> logs = [];
    int partiesImported = 0;
    int itemsImported = 0;
    int salesImported = 0;
    int purchasesImported = 0;

    final db = await _dbHelper.database;

    // 1. Parse LEDGER tags (Parties)
    final ledgerMatches = RegExp(r'<LEDGER([^>]*)>([\s\S]*?)</LEDGER>', caseSensitive: false).allMatches(xmlContent);
    final Map<String, String> partyNameToIdMap = {};

    // Get existing parties to avoid duplicates
    final List<Map<String, dynamic>> existingPartiesRows = await db.query('parties');
    final Map<String, String> existingParties = {
      for (final r in existingPartiesRows) (r['name'] as String).toLowerCase(): r['id'] as String
    };

    logs.add('Found ${ledgerMatches.length} potential Ledger Master records.');

    for (final m in ledgerMatches) {
      final openingTag = m.group(1) ?? '';
      final body = m.group(2) ?? '';

      // Tally names are either in a name tag or as an attribute
      String? name = _extractAttribute(openingTag, 'NAME') ?? _extractTag(body, 'NAME');
      if (name == null || name.trim().isEmpty) continue;
      name = name.trim();

      final parent = _extractTag(body, 'PARENT') ?? '';
      final String partyType;
      
      if (parent.toLowerCase().contains('creditor')) {
        partyType = 'SUPPLIER';
      } else if (parent.toLowerCase().contains('debtor')) {
        partyType = 'CUSTOMER';
      } else {
        // Skip ledgers that aren't customers/suppliers (like cash, bank, tax, etc.)
        continue;
      }

      final String key = name.toLowerCase();
      if (existingParties.containsKey(key)) {
        partyNameToIdMap[key] = existingParties[key]!;
        continue;
      }

      final address = _extractTag(body, 'ADDRESS') ?? '';
      final gstin = _extractTag(body, 'GSTIN') ?? _extractTag(body, 'PARTYGSTIN') ?? '';
      final phone = _extractTag(body, 'LEDGERPHONE') ?? _extractTag(body, 'PHONE') ?? '';

      final partyId = _uuid.v4();
      final party = Party(
        id: partyId,
        name: name,
        type: partyType,
        phone: phone.isNotEmpty ? phone : '9999999999',
        address: address.isNotEmpty ? address : 'Tally Import Address',
        gstin: gstin.isNotEmpty ? gstin : '36AAAAA1111A1Z1',
        createdAt: DateTime.now(),
      );

      await db.insert('parties', party.toMap());
      existingParties[key] = partyId;
      partyNameToIdMap[key] = partyId;
      partiesImported++;
    }

    // 2. Parse STOCKITEM tags (Products)
    final stockItemMatches = RegExp(r'<STOCKITEM([^>]*)>([\s\S]*?)</STOCKITEM>', caseSensitive: false).allMatches(xmlContent);
    final Map<String, String> itemNameToIdMap = {};

    // Get existing items to avoid duplicates
    final List<Map<String, dynamic>> existingItemsRows = await db.query('items');
    final Map<String, String> existingItems = {
      for (final r in existingItemsRows) (r['name'] as String).toLowerCase(): r['id'] as String
    };

    logs.add('Found ${stockItemMatches.length} potential Stock Item records.');

    for (final m in stockItemMatches) {
      final openingTag = m.group(1) ?? '';
      final body = m.group(2) ?? '';

      String? name = _extractAttribute(openingTag, 'NAME') ?? _extractTag(body, 'NAME');
      if (name == null || name.trim().isEmpty) continue;
      name = name.trim();

      final String key = name.toLowerCase();
      if (existingItems.containsKey(key)) {
        itemNameToIdMap[key] = existingItems[key]!;
        continue;
      }

      final uom = _extractTag(body, 'BASEUNITS') ?? _extractTag(body, 'UOM') ?? 'BAG';
      final hsn = _extractTag(body, 'HSNCODE') ?? '';
      final rateStr = _extractTag(body, 'GSTRATE') ?? _extractTag(body, 'RATE') ?? '5.0';
      
      // Clean rate
      final double gstRate = double.tryParse(rateStr.replaceAll(RegExp(r'[^\d\.]'), '')) ?? 5.0;

      final itemId = _uuid.v4();
      final item = Item(
        id: itemId,
        name: name,
        category: name.toLowerCase().contains('fertil') ? 'FERTILISER' : 'SEED',
        hsnCode: hsn.isNotEmpty ? hsn : '12099190',
        gstRate: gstRate,
        primaryUnit: uom.toUpperCase().contains('BOX') ? 'BOX' : 'BAG',
        bagWeightKg: 25.0,
        createdAt: DateTime.now(),
      );

      await db.insert('items', item.toMap());
      existingItems[key] = itemId;
      itemNameToIdMap[key] = itemId;
      itemsImported++;
    }

    // 3. Parse VOUCHER tags (Invoices)
    final voucherMatches = RegExp(r'<VOUCHER([^>]*)>([\s\S]*?)</VOUCHER>', caseSensitive: false).allMatches(xmlContent);
    logs.add('Found ${voucherMatches.length} total Vouchers to parse.');

    for (final m in voucherMatches) {
      final openingTag = m.group(1) ?? '';
      final body = m.group(2) ?? '';

      final vchType = _extractAttribute(openingTag, 'VCHTYPE') ?? _extractTag(body, 'VOUCHERTYPE') ?? '';
      final isSale = vchType.toLowerCase().contains('sale');
      final isPurchase = vchType.toLowerCase().contains('purchase');

      if (!isSale && !isPurchase) continue;

      final partyName = _extractTag(body, 'PARTYLEDGERNAME') ?? '';
      if (partyName.trim().isEmpty) continue;

      final dateStr = _extractTag(body, 'DATE') ?? ''; // e.g. "20260610"
      DateTime date = DateTime.now();
      if (dateStr.length == 8) {
        final year = int.tryParse(dateStr.substring(0, 4)) ?? 2026;
        final month = int.tryParse(dateStr.substring(4, 6)) ?? 6;
        final day = int.tryParse(dateStr.substring(6, 8)) ?? 10;
        date = DateTime(year, month, day);
      } else if (dateStr.isNotEmpty) {
        date = DateTime.tryParse(dateStr) ?? DateTime.now();
      }

      final invoiceNo = _extractAttribute(openingTag, 'VOUCHERNUMBER') ?? _extractTag(body, 'VOUCHERNUMBER') ?? _uuid.v4().substring(0, 8).toUpperCase();

      String? partyId = partyNameToIdMap[partyName.toLowerCase()];
      if (partyId == null) {
        // Create party on the fly
        partyId = _uuid.v4();
        final String partyType = isSale ? 'CUSTOMER' : 'SUPPLIER';
        final party = Party(
          id: partyId,
          name: partyName.trim(),
          type: partyType,
          phone: '9999999999',
          address: 'Tally Import Address',
          gstin: '36AAAAA1111A1Z1',
          createdAt: DateTime.now(),
        );
        await db.insert('parties', party.toMap());
        partyNameToIdMap[partyName.toLowerCase()] = partyId;
        partiesImported++;
      }

      // Parse item rows under ALLINVENTORYENTRIES.LIST
      final inventoryMatches = RegExp(r'<ALLINVENTORYENTRIES\.LIST>([\s\S]*?)</ALLINVENTORYENTRIES\.LIST>', caseSensitive: false).allMatches(body);
      
      final List<Map<String, dynamic>> parsedItems = [];
      double subtotal = 0.0;
      double gstTotal = 0.0;

      for (final inv in inventoryMatches) {
        final invBody = inv.group(1) ?? '';
        final itemName = _extractTag(invBody, 'STOCKITEMNAME') ?? '';
        if (itemName.trim().isEmpty) continue;

        String? itemId = itemNameToIdMap[itemName.toLowerCase()];
        if (itemId == null) {
          // Create item on the fly
          itemId = _uuid.v4();
          final item = Item(
            id: itemId,
            name: itemName.trim(),
            category: itemName.toLowerCase().contains('fertil') ? 'FERTILISER' : 'SEED',
            hsnCode: '12099190',
            gstRate: 5.0,
            primaryUnit: 'BAG',
            bagWeightKg: 25.0,
            createdAt: DateTime.now(),
          );
          await db.insert('items', item.toMap());
          itemNameToIdMap[itemName.toLowerCase()] = itemId;
          itemsImported++;
        }

        // Fetch target item for GST rate
        final itemRows = await db.query('items', where: 'id = ?', whereArgs: [itemId]);
        if (itemRows.isEmpty) continue;
        final dbItem = Item.fromMap(itemRows.first);

        final qtyStr = _extractTag(invBody, 'BILLEDQTY') ?? _extractTag(invBody, 'QTY') ?? '0.0';
        final rateStr = _extractTag(invBody, 'RATE') ?? '0.0';
        final amountStr = _extractTag(invBody, 'AMOUNT') ?? '0.0';

        // Extract numbers
        final double qty = (double.tryParse(qtyStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs();
        final double rate = (double.tryParse(rateStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs();
        final double amount = (double.tryParse(amountStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs();

        if (qty <= 0 || amount <= 0) continue;

        final double calculatedRate = rate > 0 ? rate : (amount / qty);
        final double gstAmt = amount * (dbItem.gstRate / 100.0);

        final batch = _extractTag(invBody, 'BATCHNAME') ?? 'LOT-TALLY';

        parsedItems.add({
          'item_id': itemId,
          'qty': qty,
          'rate': calculatedRate,
          'gst_rate': dbItem.gstRate,
          'gst_amt': gstAmt,
          'total': amount + gstAmt,
          'batch_no': batch,
          'hsn_code': dbItem.hsnCode,
          'manufacturer': 'Tally Import',
          'packing': '25 kg',
          'mfg_date': '01-May-2026',
          'exp_date': '30-Apr-2027',
        });

        subtotal += amount;
        gstTotal += gstAmt;
      }

      if (parsedItems.isEmpty) continue;

      final grandTotal = subtotal + gstTotal;
      final transactionId = _uuid.v4();

      if (isSale) {
        final sale = Sale(
          id: transactionId,
          invoiceNo: invoiceNo,
          partyId: partyId,
          date: date,
          subtotal: subtotal,
          gstTotal: gstTotal,
          grandTotal: grandTotal,
          paymentStatus: 'PAID',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          category: 'SEED',
        );

        await db.insert('sales', sale.toMap());

        for (final item in parsedItems) {
          final saleItem = SaleItem(
            id: _uuid.v4(),
            saleId: transactionId,
            itemId: item['item_id'],
            qty: item['qty'],
            rate: item['rate'],
            gstRate: item['gst_rate'],
            gstAmt: item['gst_amt'],
            total: item['total'],
            manufacturer: item['manufacturer'],
            packing: item['packing'],
            batchNo: item['batch_no'],
            hsnCode: item['hsn_code'],
            mfgDate: item['mfg_date'],
            expDate: item['exp_date'],
            unitPerCase: 25.0,
            noOfCases: (item['qty'] / 25.0),
            totalUnits: item['qty'],
            unitPrice: item['rate'],
          );
          await db.insert('sale_items', saleItem.toMap());
        }

        salesImported++;
      } else {
        final purchase = Purchase(
          id: transactionId,
          invoiceNo: invoiceNo,
          partyId: partyId,
          date: date,
          subtotal: subtotal,
          gstTotal: gstTotal,
          grandTotal: grandTotal,
          paymentStatus: 'PAID',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          category: 'SEED',
        );

        await db.insert('purchases', purchase.toMap());

        for (final item in parsedItems) {
          final purchaseItem = PurchaseItem(
            id: _uuid.v4(),
            purchaseId: transactionId,
            itemId: item['item_id'],
            qty: item['qty'],
            rate: item['rate'],
            gstRate: item['gst_rate'],
            gstAmt: item['gst_amt'],
            total: item['total'],
            lotNo: item['batch_no'],
            hsnCode: item['hsn_code'],
            noOfBags: (item['qty'] / 25.0),
            perUnit: 'kgs',
            discountPct: 0.0,
            mfgDate: item['mfg_date'],
            expDate: item['exp_date'],
            manufacturer: item['manufacturer'],
            packing: item['packing'],
          );
          await db.insert('purchase_items', purchaseItem.toMap());
        }

        purchasesImported++;
      }
    }

    return TallyImportResult(
      partiesImported: partiesImported,
      itemsImported: itemsImported,
      salesImported: salesImported,
      purchasesImported: purchasesImported,
      logs: logs,
    );
  }
}
