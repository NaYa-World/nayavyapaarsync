import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../data/database/db_helper.dart';
import '../data/models/item.dart';
import '../data/models/party.dart';
import '../data/models/purchase.dart';
import '../data/models/sale.dart';
import '../data/models/voucher.dart';
import '../data/models/voucher_line.dart';
import '../data/models/stock_movement.dart';

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

  /// Helper to ensure default groups, ledgers, and godowns exist for double-entry tracking
  Future<void> _ensureDefaultGroupsAndLedgers(Transaction txn) async {
    // 1. Ensure basic ledger groups exist
    final List<Map<String, dynamic>> groups = [
      {'id': 'grp_assets', 'name': 'Current Assets', 'parent_id': null, 'nature': 'ASSETS'},
      {'id': 'grp_debtors', 'name': 'Sundry Debtors', 'parent_id': 'grp_assets', 'nature': 'ASSETS'},
      {'id': 'grp_cash', 'name': 'Cash-in-hand', 'parent_id': 'grp_assets', 'nature': 'ASSETS'},
      {'id': 'grp_bank', 'name': 'Bank Accounts', 'parent_id': 'grp_assets', 'nature': 'ASSETS'},
      {'id': 'grp_liabilities', 'name': 'Current Liabilities', 'parent_id': null, 'nature': 'LIABILITIES'},
      {'id': 'grp_creditors', 'name': 'Sundry Creditors', 'parent_id': 'grp_liabilities', 'nature': 'LIABILITIES'},
      {'id': 'grp_income', 'name': 'Sales Accounts', 'parent_id': null, 'nature': 'INCOME'},
      {'id': 'grp_expenses', 'name': 'Purchase Accounts', 'parent_id': null, 'nature': 'EXPENSES'},
    ];

    for (final grp in groups) {
      final existing = await txn.query('ledger_groups', where: 'id = ?', whereArgs: [grp['id']]);
      if (existing.isEmpty) {
        await txn.insert('ledger_groups', grp);
      }
    }

    // 2. Ensure standard ledgers exist
    final String nowStr = DateTime.now().toIso8601String();
    final List<Map<String, dynamic>> ledgers = [
      {
        'id': 'led_cash',
        'name': 'Cash Account',
        'group_id': 'grp_cash',
        'opening_balance': 0.0,
        'balance_type': 'DR',
        'company_id': 'company_default',
        'is_active': 1,
        'created_at': nowStr,
      },
      {
        'id': 'led_sales_ac',
        'name': 'Product Sales',
        'group_id': 'grp_income',
        'opening_balance': 0.0,
        'balance_type': 'CR',
        'company_id': 'company_default',
        'is_active': 1,
        'created_at': nowStr,
      },
      {
        'id': 'led_purchases_ac',
        'name': 'Product Purchases',
        'group_id': 'grp_expenses',
        'opening_balance': 0.0,
        'balance_type': 'DR',
        'company_id': 'company_default',
        'is_active': 1,
        'created_at': nowStr,
      },
      {
        'id': 'led_gst_output',
        'name': 'GST Output',
        'group_id': 'grp_liabilities',
        'opening_balance': 0.0,
        'balance_type': 'CR',
        'company_id': 'company_default',
        'is_active': 1,
        'created_at': nowStr,
      },
      {
        'id': 'led_gst_input',
        'name': 'GST Input',
        'group_id': 'grp_assets',
        'opening_balance': 0.0,
        'balance_type': 'DR',
        'company_id': 'company_default',
        'is_active': 1,
        'created_at': nowStr,
      },
    ];

    for (final led in ledgers) {
      final existing = await txn.query('ledgers', where: 'id = ?', whereArgs: [led['id']]);
      if (existing.isEmpty) {
        await txn.insert('ledgers', led);
      }
    }

    // 3. Ensure a default godown exists
    final existingGodown = await txn.query('godowns', where: 'id = ?', whereArgs: ['godown_default']);
    if (existingGodown.isEmpty) {
      await txn.insert('godowns', {
        'id': 'godown_default',
        'company_id': 'company_default',
        'name': 'Main Godown',
        'is_active': 1,
        'created_at': nowStr,
      });
    }
  }

  /// Parses Tally XML string and imports masters and vouchers in a single transaction
  Future<TallyImportResult> importTallyXml(String xmlContent) async {
    final List<String> logs = [];
    int partiesImported = 0;
    int itemsImported = 0;
    int salesImported = 0;
    int purchasesImported = 0;

    // 1. Version detection
    String tallyVersion = 'Tally Prime';
    final buildMatch = RegExp(r'TALLYBUILDNO="([^"]*)"', caseSensitive: false).firstMatch(xmlContent);
    if (buildMatch != null) {
      final buildNo = buildMatch.group(1) ?? '';
      final num = double.tryParse(buildNo.replaceAll(RegExp(r'[^\d\.]'), ''));
      if (num != null) {
        if (num < 80) {
          tallyVersion = 'Tally 7.2';
        } else if (num < 100) {
          tallyVersion = 'Tally 9';
        } else if (num < 200) {
          tallyVersion = 'Tally Prime';
        } else {
          tallyVersion = 'Tally Prime 2.0';
        }
      } else {
        if (buildNo.toLowerCase().contains('prime 2')) {
          tallyVersion = 'Tally Prime 2.0';
        } else if (buildNo.toLowerCase().contains('prime')) {
          tallyVersion = 'Tally Prime';
        } else if (buildNo.contains('9')) {
          tallyVersion = 'Tally 9';
        } else if (buildNo.contains('7.2')) {
          tallyVersion = 'Tally 7.2';
        }
      }
      logs.add('Detected Tally Version: $tallyVersion (Build: $buildNo)');
    } else {
      logs.add('No Tally build version detected. Defaulting to Tally Prime parser.');
    }

    // 2. Company detection
    final Set<String> companiesFound = {};
    final companyMatches = RegExp(r'<COMPANY([^>]*)>([\s\S]*?)</COMPANY>', caseSensitive: false).allMatches(xmlContent);
    for (final cm in companyMatches) {
      final opTag = cm.group(1) ?? '';
      final body = cm.group(2) ?? '';
      String? cName = _extractAttribute(opTag, 'NAME') ?? _extractTag(body, 'NAME');
      if (cName != null && cName.trim().isNotEmpty) {
        companiesFound.add(cName.trim());
      }
    }
    if (companiesFound.isEmpty) {
      final currentCompanyMatch = RegExp(r'<SVCURRENTCOMPANY>([^<]*)</SVCURRENTCOMPANY>', caseSensitive: false).firstMatch(xmlContent);
      if (currentCompanyMatch != null) {
        final cName = currentCompanyMatch.group(1)?.trim();
        if (cName != null && cName.isNotEmpty) {
          companiesFound.add(cName);
        }
      }
      final companyNameMatch = RegExp(r'<COMPANYNAME>([^<]*)</COMPANYNAME>', caseSensitive: false).firstMatch(xmlContent);
      if (companyNameMatch != null) {
        final cName = companyNameMatch.group(1)?.trim();
        if (cName != null && cName.isNotEmpty) {
          companiesFound.add(cName);
        }
      }
    }

    String companyName = 'Default Company';
    if (companiesFound.isNotEmpty) {
      final list = companiesFound.toList();
      if (list.length > 1) {
        logs.add('Found multiple companies: ${list.join(", ")}.');
        logs.add('Selected company for import: ${list.first}');
      } else {
        logs.add('Company detected: ${list.first}');
      }
      companyName = list.first;
    } else {
      logs.add('No company name detected in import metadata.');
    }

    final db = await _dbHelper.database;

    // Run everything in a single transaction
    await db.transaction((txn) async {
      // 0. Ensure default groups, ledgers, and godowns exist
      await _ensureDefaultGroupsAndLedgers(txn);

      // Ensure existing parties have corresponding ledgers
      final List<Map<String, dynamic>> allParties = await txn.query('parties');
      for (final p in allParties) {
        final pId = p['id'] as String;
        final pName = p['name'] as String;
        final pType = p['type'] as String;
        final ledgerId = 'led_$pId';
        final existingLedger = await txn.query('ledgers', where: 'id = ?', whereArgs: [ledgerId]);
        if (existingLedger.isEmpty) {
          await txn.insert('ledgers', {
            'id': ledgerId,
            'name': pName,
            'group_id': pType == 'CUSTOMER' ? 'grp_debtors' : 'grp_creditors',
            'opening_balance': p['opening_balance'] ?? 0.0,
            'balance_type': p['balance_type'] ?? (pType == 'CUSTOMER' ? 'DR' : 'CR'),
            'company_id': 'company_default',
            'is_active': 1,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // 1. Parse LEDGER tags (Parties)
      final ledgerMatches = RegExp(r'<LEDGER([^>]*)>([\s\S]*?)</LEDGER>', caseSensitive: false).allMatches(xmlContent);

      // Get existing parties to avoid duplicates and map them
      final List<Map<String, dynamic>> existingPartiesRows = await txn.query('parties');
      final Map<String, String> partyNameToIdMap = {
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
        if (partyNameToIdMap.containsKey(key)) {
          continue;
        }

        final addressVal = _extractTag(body, 'ADDRESS') ?? '';
        final address = addressVal.isNotEmpty ? addressVal : (_extractTag(body, 'LEDSTATENAME') ?? '');

        final gstinVal = _extractTag(body, 'GSTIN') ?? '';
        final gstin = gstinVal.isNotEmpty ? gstinVal : (_extractTag(body, 'PARTYGSTIN') ?? '');

        final phoneVal = _extractTag(body, 'LEDGERPHONE') ?? '';
        final phone = phoneVal.isNotEmpty ? phoneVal : (_extractTag(body, 'PHONE') ?? '');

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

        await txn.insert('parties', party.toMap());

        // Insert corresponding ledger
        final String ledgerId = 'led_$partyId';
        await txn.insert('ledgers', {
          'id': ledgerId,
          'name': name,
          'group_id': partyType == 'CUSTOMER' ? 'grp_debtors' : 'grp_creditors',
          'opening_balance': 0.0,
          'balance_type': partyType == 'CUSTOMER' ? 'DR' : 'CR',
          'company_id': 'company_default',
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
        });

        partyNameToIdMap[key] = partyId;
        partiesImported++;
      }

      // 2. Parse STOCKITEM tags (Products)
      final stockItemMatches = RegExp(r'<STOCKITEM([^>]*)>([\s\S]*?)</STOCKITEM>', caseSensitive: false).allMatches(xmlContent);
      // Get existing items to avoid duplicates and map them
      final List<Map<String, dynamic>> existingItemsRows = await txn.query('items');
      final Map<String, String> itemNameToIdMap = {
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
        if (itemNameToIdMap.containsKey(key)) {
          continue;
        }

        final uom = _extractTag(body, 'BASEUNITS') ?? _extractTag(body, 'UOM') ?? 'BAG';
        final hsn = _extractTag(body, 'HSNCODE') ?? '';

        // Try extracting nested GST rate first if present
        String? rateStr;
        final gstDetailsList = _extractTag(body, 'GSTDETAILS.LIST');
        if (gstDetailsList != null) {
          final stateGstDetailsList = _extractTag(gstDetailsList, 'STATEGSTDETAILS.LIST');
          if (stateGstDetailsList != null) {
            final rateDetailsList = _extractTag(stateGstDetailsList, 'RATEDETAILS.LIST');
            if (rateDetailsList != null) {
              rateStr = _extractTag(rateDetailsList, 'GSTRATE');
            }
          }
          if (rateStr == null) {
            rateStr = _extractTag(gstDetailsList, 'GSTRATE');
          }
        }
        rateStr ??= _extractTag(body, 'GSTRATE') ?? _extractTag(body, 'RATE') ?? '5.0';
        
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
          stockGroup: _extractTag(body, 'PARENT') ?? 'General',
        );

        await txn.insert('items', item.toMap());
        itemNameToIdMap[key] = itemId;
        itemsImported++;

        // Parse opening stock balances for the item (e.g. from stksum.xml)
        final openingBalanceStr = _extractTag(body, 'OPENINGBALANCE') ?? '';
        final openingValueStr = _extractTag(body, 'OPENINGVALUE') ?? '';
        final openingRateStr = _extractTag(body, 'OPENINGRATE') ?? '';

        final double openingQty = (double.tryParse(openingBalanceStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs();
        final double openingValue = (double.tryParse(openingValueStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs();
        final double openingRate = openingRateStr.isNotEmpty
            ? (double.tryParse(openingRateStr.split('/').first.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0).abs()
            : (openingQty > 0 ? openingValue / openingQty : 0.0);

        if (openingQty > 0) {
          // Ensure the opening stock journal voucher exists
          final existingVoucher = await txn.query('vouchers', where: "id = ?", whereArgs: ['opening_stock_voucher']);
          if (existingVoucher.isEmpty) {
            await txn.insert('vouchers', {
              'id': 'opening_stock_voucher',
              'voucher_no': 'OP-STOCK',
              'type': 'JOURNAL',
              'date': '2026-04-01',
              'narration': 'Opening Stock Balance from Import',
              'company_id': 'company_default',
              'fy_id': 'fy_default',
              'is_locked': 0,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
              'is_deleted': 0,
            });
          }

          // Create opening batch
          final String batchId = 'op_batch_$itemId';
          final existingBatch = await txn.query('batches', where: 'id = ?', whereArgs: [batchId]);
          if (existingBatch.isEmpty) {
            await txn.insert('batches', {
              'id': batchId,
              'stock_item_id': itemId,
              'batch_no': 'OP-BATCH',
              'mfg_date': '2026-04-01',
              'expiry_date': '2027-03-31',
            });
          }

          // Create opening stock movement
          final String movementId = 'op_sm_$itemId';
          final existingMovement = await txn.query('stock_movements', where: 'id = ?', whereArgs: [movementId]);
          if (existingMovement.isEmpty) {
            await txn.insert('stock_movements', {
              'id': movementId,
              'stock_item_id': itemId,
              'godown_id': 'godown_default',
              'ref_voucher_id': 'opening_stock_voucher',
              'qty': openingQty,
              'rate': openingRate,
              'movement_type': 'IN',
              'created_at': '2026-04-01',
            });
          }
        }
      }

      // 3. Parse VOUCHER tags (Invoices)
      final voucherMatches = RegExp(r'<VOUCHER([^>]*)>([\s\S]*?)</VOUCHER>', caseSensitive: false).allMatches(xmlContent);
      logs.add('Found ${voucherMatches.length} total Vouchers to parse.');

      for (final m in voucherMatches) {
        final openingTag = m.group(1) ?? '';
        final body = m.group(2) ?? '';

        final vchType = _extractAttribute(openingTag, 'VCHTYPE') ?? _extractTag(body, 'VOUCHERTYPE') ?? '';
        final String vchTypeLower = vchType.toLowerCase();

        final isSale = vchTypeLower.contains('sale');
        final isPurchase = vchTypeLower.contains('purchase') ||
            vchTypeLower.contains('stockin') ||
            vchTypeLower.contains('stock in') ||
            vchTypeLower.contains('receipt note');
        final isReceipt = vchTypeLower.contains('receipt') && !vchTypeLower.contains('receipt note');
        final isPayment = vchTypeLower.contains('payment');
        final isContra = vchTypeLower.contains('contra');
        final isJournal = vchTypeLower.contains('journal') && !vchTypeLower.contains('goods');
        final isCreditNote = vchTypeLower.contains('credit note') || vchTypeLower.contains('creditnote');
        final isDebitNote = vchTypeLower.contains('debit note') || vchTypeLower.contains('debitnote');

        if (!isSale && !isPurchase && !isReceipt && !isPayment && !isContra && !isJournal && !isCreditNote && !isDebitNote) {
          continue;
        }

        // Determine mapped voucher type for DB entry
        final String mappedType;
        if (isSale) {
          mappedType = 'SALE';
        } else if (isPurchase) {
          mappedType = 'PURCHASE';
        } else if (isReceipt) {
          mappedType = 'RECEIPT';
        } else if (isPayment) {
          mappedType = 'PAYMENT';
        } else if (isContra) {
          mappedType = 'CONTRA';
        } else if (isCreditNote) {
          mappedType = 'CREDIT_NOTE';
        } else if (isDebitNote) {
          mappedType = 'DEBIT_NOTE';
        } else {
          mappedType = 'JOURNAL';
        }

        String partyName = (_extractTag(body, 'PARTYLEDGERNAME') ?? '').trim();
        if (partyName.isEmpty) {
          if (isPurchase) {
            partyName = 'Stock Adjustment Supplier';
          } else {
            partyName = 'General Party';
          }
        }

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

        // Idempotency Key Duplicate Guard
        final idempotencyKey = '$invoiceNo+$dateStr+$companyName';
        final existingSales = await txn.query('sales', where: 'invoice_no = ?', whereArgs: [invoiceNo]);
        final existingPurchases = await txn.query('purchases', where: 'invoice_no = ?', whereArgs: [invoiceNo]);
        final existingVouchers = await txn.query('vouchers', where: 'voucher_no = ? AND date = ?', whereArgs: [invoiceNo, date.toIso8601String()]);
        
        if (existingSales.isNotEmpty || existingPurchases.isNotEmpty || existingVouchers.isNotEmpty) {
          logs.add('Duplicate voucher skipped (Idempotency Key: $idempotencyKey)');
          continue;
        }

        String? partyId = partyNameToIdMap[partyName.toLowerCase()];
        if (partyId == null && partyName != 'General Party') {
          // Create party on the fly
          partyId = _uuid.v4();
          final String partyType = (isSale || isCreditNote) ? 'CUSTOMER' : 'SUPPLIER';
          final party = Party(
            id: partyId,
            name: partyName.trim(),
            type: partyType,
            phone: '9999999999',
            address: 'Tally Import Address',
            gstin: '36AAAAA1111A1Z1',
            createdAt: DateTime.now(),
          );
          await txn.insert('parties', party.toMap());

          // Insert corresponding ledger
          final String ledgerId = 'led_$partyId';
          await txn.insert('ledgers', {
            'id': ledgerId,
            'name': partyName.trim(),
            'group_id': partyType == 'CUSTOMER' ? 'grp_debtors' : 'grp_creditors',
            'opening_balance': 0.0,
            'balance_type': partyType == 'CUSTOMER' ? 'DR' : 'CR',
            'company_id': 'company_default',
            'is_active': 1,
            'created_at': DateTime.now().toIso8601String(),
          });

          partyNameToIdMap[partyName.toLowerCase()] = partyId;
          partiesImported++;
        }

        // Parse ledger entries under LEDGERENTRIES.LIST or ALLLEDGERENTRIES.LIST
        final ledgerEntriesMatches = RegExp(
          r'<(?:LEDGERENTRIES|ALLLEDGERENTRIES)\.LIST>([\s\S]*?)</(?:LEDGERENTRIES|ALLLEDGERENTRIES)\.LIST>',
          caseSensitive: false
        ).allMatches(body);

        final List<Map<String, dynamic>> parsedVoucherLines = [];
        for (final led in ledgerEntriesMatches) {
          final ledBody = led.group(1) ?? '';
          String ledgerName = (_extractTag(ledBody, 'LEDGERNAME') ?? '').trim();
          if (ledgerName.isEmpty) continue;

          final deemedPositive = _extractTag(ledBody, 'ISDEEMEDPOSITIVE') ?? '';
          final amountStr = _extractTag(ledBody, 'AMOUNT') ?? '0.0';
          final double rawAmount = double.tryParse(amountStr.replaceAll(RegExp(r'[^\d\.\-]'), '')) ?? 0.0;
          
          final bool isDebit;
          if (deemedPositive.isNotEmpty) {
            isDebit = deemedPositive.toLowerCase() == 'yes';
          } else {
            isDebit = rawAmount < 0;
          }
          final double amount = rawAmount.abs();
          if (amount == 0.0) continue;

          parsedVoucherLines.add({
            'ledger_name': ledgerName,
            'is_debit': isDebit,
            'amount': amount,
            'narration': _extractTag(ledBody, 'NARRATION'),
          });
        }

        // Resolve Financial Year dynamically
        String fyId = 'fy_default';
        final List<Map<String, dynamic>> fyRows = await txn.query(
          'financial_years',
          where: 'company_id = ? AND start_date <= ? AND end_date >= ?',
          whereArgs: ['company_default', date.toIso8601String().substring(0, 10), date.toIso8601String().substring(0, 10)],
          limit: 1,
        );
        if (fyRows.isNotEmpty) {
          fyId = fyRows.first['id'] as String;
        }

        final transactionId = _uuid.v4();

        // Resolve or create ledgers on the fly for the voucher lines
        final List<VoucherLine> dbVoucherLines = [];
        double totalDr = 0.0;
        double totalCr = 0.0;

        for (final line in parsedVoucherLines) {
          final String name = line['ledger_name'];
          final bool isDebit = line['is_debit'];
          final double amt = line['amount'];
          final String? lineNarration = line['narration'];

          String? ledgerId;
          final key = name.toLowerCase();
          final String? mappedPartyId = partyNameToIdMap[key];
          if (mappedPartyId != null) {
            ledgerId = 'led_$mappedPartyId';
          } else {
            final existing = await txn.query('ledgers', where: 'name = ?', whereArgs: [name]);
            if (existing.isNotEmpty) {
              ledgerId = existing.first['id'] as String;
            } else {
              final String groupId;
              final String balType;
              if (name.toLowerCase().contains('cash')) {
                groupId = 'grp_cash';
                balType = 'DR';
              } else if (name.toLowerCase().contains('bank')) {
                groupId = 'grp_bank';
                balType = 'DR';
              } else if (isDebit) {
                groupId = 'grp_assets';
                balType = 'DR';
              } else {
                groupId = 'grp_liabilities';
                balType = 'CR';
              }

              ledgerId = 'led_${_uuid.v4().substring(0, 8)}';
              await txn.insert('ledgers', {
                'id': ledgerId,
                'name': name,
                'group_id': groupId,
                'opening_balance': 0.0,
                'balance_type': balType,
                'company_id': 'company_default',
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          }

          if (isDebit) {
            totalDr += amt;
          } else {
            totalCr += amt;
          }

          dbVoucherLines.add(VoucherLine(
            id: _uuid.v4(),
            voucherId: transactionId,
            ledgerId: ledgerId,
            drAmount: isDebit ? amt : 0.0,
            crAmount: isDebit ? 0.0 : amt,
            narration: lineNarration,
          ));
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
            await txn.insert('items', item.toMap());
            itemNameToIdMap[itemName.toLowerCase()] = itemId;
            itemsImported++;
          }

          // Fetch target item for GST rate
          final itemRows = await txn.query('items', where: 'id = ?', whereArgs: [itemId]);
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

        double finalGstTotal = gstTotal;
        double finalGrandTotal = subtotal + gstTotal;
        double finalSubtotal = subtotal;

        if (parsedVoucherLines.isNotEmpty) {
          double exactGst = 0.0;
          for (final line in parsedVoucherLines) {
            final String name = line['ledger_name'].toLowerCase();
            if (name.contains('cgst') || name.contains('sgst') || name.contains('igst') || name.contains('utgst') || name.contains('gst')) {
              exactGst += line['amount'];
            }
          }

          double exactGrand = 0.0;
          for (final line in parsedVoucherLines) {
            final String name = line['ledger_name'].toLowerCase();
            if (name == partyName.toLowerCase()) {
              exactGrand = line['amount'];
              break;
            }
          }
          if (exactGrand == 0.0) {
            double debitsSum = 0.0;
            double creditsSum = 0.0;
            for (final line in parsedVoucherLines) {
              if (line['is_debit'] as bool) {
                debitsSum += line['amount'] as double;
              } else {
                creditsSum += line['amount'] as double;
              }
            }
            exactGrand = debitsSum > creditsSum ? debitsSum : creditsSum;
          }

          finalGstTotal = exactGst;
          finalGrandTotal = exactGrand;
          finalSubtotal = finalGrandTotal - finalGstTotal;
        }

        if (isSale) {
          final sale = Sale(
            id: transactionId,
            invoiceNo: invoiceNo,
            partyId: partyId ?? 'company_default',
            date: date,
            subtotal: finalSubtotal,
            gstTotal: finalGstTotal,
            grandTotal: finalGrandTotal,
            paymentStatus: 'PAID',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            category: 'SEED',
          );

          await txn.insert('sales', sale.toMap());

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
            await txn.insert('sale_items', saleItem.toMap());
          }

          // ─── Double-Entry Voucher Seeding ───
          final doubleEntryVoucher = Voucher(
            id: transactionId,
            voucherNo: invoiceNo,
            type: 'SALE',
            date: date,
            narration: _extractTag(body, 'NARRATION') ?? 'Tally Import: $invoiceNo',
            companyId: 'company_default',
            fyId: fyId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await txn.insert('vouchers', doubleEntryVoucher.toMap());

          if (dbVoucherLines.isNotEmpty) {
            if ((totalDr - totalCr).abs() > 0.01) {
              final diff = (totalDr - totalCr).abs();
              final isDrDiff = totalCr > totalDr;
              final lineDiff = VoucherLine(
                id: _uuid.v4(),
                voucherId: transactionId,
                ledgerId: 'led_cash',
                drAmount: isDrDiff ? diff : 0.0,
                crAmount: isDrDiff ? 0.0 : diff,
                narration: 'Rounding adjustment on import',
              );
              dbVoucherLines.add(lineDiff);
            }
            for (final line in dbVoucherLines) {
              await txn.insert('voucher_lines', line.toMap());
            }
          } else {
            // DR Customer
            final lineParty = VoucherLine(
              id: _uuid.v4(),
              voucherId: transactionId,
              ledgerId: partyId != null ? 'led_$partyId' : 'led_cash',
              drAmount: finalGrandTotal,
              crAmount: 0.0,
              narration: 'To party account',
            );
            await txn.insert('voucher_lines', lineParty.toMap());

            // CR Product Sales
            final lineSales = VoucherLine(
              id: _uuid.v4(),
              voucherId: transactionId,
              ledgerId: 'led_sales_ac',
              drAmount: 0.0,
              crAmount: finalSubtotal,
              narration: 'Sales revenue',
            );
            await txn.insert('voucher_lines', lineSales.toMap());

            // CR GST Output
            if (finalGstTotal > 0) {
              final lineGst = VoucherLine(
                id: _uuid.v4(),
                voucherId: transactionId,
                ledgerId: 'led_gst_output',
                drAmount: 0.0,
                crAmount: finalGstTotal,
                narration: 'GST tax collected',
              );
              await txn.insert('voucher_lines', lineGst.toMap());
            }
          }

          // ─── Stock Movements Seeding ───
          for (final item in parsedItems) {
            final movement = StockMovement(
              id: _uuid.v4(),
              stockItemId: item['item_id'] as String,
              godownId: 'godown_default',
              refVoucherId: transactionId,
              qty: item['qty'] as double,
              rate: item['rate'] as double,
              movementType: 'OUT',
              createdAt: date,
            );
            await txn.insert('stock_movements', movement.toMap());
          }

          salesImported++;
        } else if (isPurchase) {
          final purchase = Purchase(
            id: transactionId,
            invoiceNo: invoiceNo,
            partyId: partyId ?? 'company_default',
            date: date,
            subtotal: finalSubtotal,
            gstTotal: finalGstTotal,
            grandTotal: finalGrandTotal,
            paymentStatus: 'PAID',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            category: 'SEED',
          );

          await txn.insert('purchases', purchase.toMap());

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
            await txn.insert('purchase_items', purchaseItem.toMap());
          }

          // ─── Double-Entry Voucher Seeding ───
          final doubleEntryVoucher = Voucher(
            id: transactionId,
            voucherNo: invoiceNo,
            type: 'PURCHASE',
            date: date,
            narration: _extractTag(body, 'NARRATION') ?? 'Tally Import: $invoiceNo',
            companyId: 'company_default',
            fyId: fyId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await txn.insert('vouchers', doubleEntryVoucher.toMap());

          if (dbVoucherLines.isNotEmpty) {
            if ((totalDr - totalCr).abs() > 0.01) {
              final diff = (totalDr - totalCr).abs();
              final isDrDiff = totalCr > totalDr;
              final lineDiff = VoucherLine(
                id: _uuid.v4(),
                voucherId: transactionId,
                ledgerId: 'led_cash',
                drAmount: isDrDiff ? diff : 0.0,
                crAmount: isDrDiff ? 0.0 : diff,
                narration: 'Rounding adjustment on import',
              );
              dbVoucherLines.add(lineDiff);
            }
            for (final line in dbVoucherLines) {
              await txn.insert('voucher_lines', line.toMap());
            }
          } else {
            // CR Supplier
            final lineParty = VoucherLine(
              id: _uuid.v4(),
              voucherId: transactionId,
              ledgerId: partyId != null ? 'led_$partyId' : 'led_cash',
              drAmount: 0.0,
              crAmount: finalGrandTotal,
              narration: 'From supplier account',
            );
            await txn.insert('voucher_lines', lineParty.toMap());

            // DR Product Purchases
            final linePurchases = VoucherLine(
              id: _uuid.v4(),
              voucherId: transactionId,
              ledgerId: 'led_purchases_ac',
              drAmount: finalSubtotal,
              crAmount: 0.0,
              narration: 'Purchase cost',
            );
            await txn.insert('voucher_lines', linePurchases.toMap());

            // DR GST Input
            if (finalGstTotal > 0) {
              final lineGst = VoucherLine(
                id: _uuid.v4(),
                voucherId: transactionId,
                ledgerId: 'led_gst_input',
                drAmount: finalGstTotal,
                crAmount: 0.0,
                narration: 'GST tax input credit',
              );
              await txn.insert('voucher_lines', lineGst.toMap());
            }
          }

          // ─── Stock Movements Seeding ───
          for (final item in parsedItems) {
            final movement = StockMovement(
              id: _uuid.v4(),
              stockItemId: item['item_id'] as String,
              godownId: 'godown_default',
              refVoucherId: transactionId,
              qty: item['qty'] as double,
              rate: item['rate'] as double,
              movementType: 'IN',
              createdAt: date,
            );
            await txn.insert('stock_movements', movement.toMap());
          }

          purchasesImported++;
        } else {
          // Process double-entry accounting entries for other voucher types (Payment, Receipt, Contra, Journal, Debit Note, Credit Note)
          final doubleEntryVoucher = Voucher(
            id: transactionId,
            voucherNo: invoiceNo,
            type: mappedType,
            date: date,
            narration: _extractTag(body, 'NARRATION') ?? 'Tally Import: $invoiceNo',
            companyId: 'company_default',
            fyId: fyId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await txn.insert('vouchers', doubleEntryVoucher.toMap());

          if (dbVoucherLines.isNotEmpty) {
            if ((totalDr - totalCr).abs() > 0.01) {
              final diff = (totalDr - totalCr).abs();
              final isDrDiff = totalCr > totalDr;
              final lineDiff = VoucherLine(
                id: _uuid.v4(),
                voucherId: transactionId,
                ledgerId: 'led_cash',
                drAmount: isDrDiff ? diff : 0.0,
                crAmount: isDrDiff ? 0.0 : diff,
                narration: 'Rounding adjustment on import',
              );
              dbVoucherLines.add(lineDiff);
            }
            for (final line in dbVoucherLines) {
              await txn.insert('voucher_lines', line.toMap());
            }
          }

          // Handle stock movements for Credit Notes and Debit Notes if inventory lists exist
          if (mappedType == 'CREDIT_NOTE' || mappedType == 'DEBIT_NOTE') {
            final String movementType = mappedType == 'CREDIT_NOTE' ? 'IN' : 'OUT';
            for (final item in parsedItems) {
              final movement = StockMovement(
                id: _uuid.v4(),
                stockItemId: item['item_id'] as String,
                godownId: 'godown_default',
                refVoucherId: transactionId,
                qty: item['qty'] as double,
                rate: item['rate'] as double,
                movementType: movementType,
                createdAt: date,
              );
              await txn.insert('stock_movements', movement.toMap());
            }
          }

          logs.add('Imported double-entry voucher $invoiceNo of type $mappedType');
        }
      }
    });

    return TallyImportResult(
      partiesImported: partiesImported,
      itemsImported: itemsImported,
      salesImported: salesImported,
      purchasesImported: purchasesImported,
      logs: logs,
    );
  }
}

