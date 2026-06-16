import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/services/tally_import_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Tally XML Import Service Tests', () {
    late DbHelper dbHelper;

    setUp(() async {
      dbHelper = DbHelper();
      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      final path = '$databasePath/godown_management.db';
      await deleteDatabase(path);
    });

    test('Full Tally XML Parse and Database Import Lifecycle', () async {
      const tallyXml = '''
<ENVELOPE>
  <HEADER>
    <TALLYREQUEST>Import Data</TALLYREQUEST>
  </HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <!-- Ledger Masters -->
        <TALLYMESSAGE>
          <LEDGER NAME="Sri Balaji Agro" RESERVEDNAME="">
            <PARENT>Sundry Creditors</PARENT>
            <ADDRESS>Warangal, Telangana</ADDRESS>
            <GSTIN>36AAAAA1111A1Z1</GSTIN>
            <LEDGERPHONE>9876543210</LEDGERPHONE>
          </LEDGER>
        </TALLYMESSAGE>
        <TALLYMESSAGE>
          <LEDGER NAME="Karthik Ganji" RESERVEDNAME="">
            <PARENT>Sundry Debtors</PARENT>
            <ADDRESS>Hyderabad, Telangana</ADDRESS>
            <PARTYGSTIN>36BBBBB2222B2Z2</PARTYGSTIN>
            <PHONE>8765432109</PHONE>
          </LEDGER>
        </TALLYMESSAGE>

        <!-- Stock Item Masters -->
        <TALLYMESSAGE>
          <STOCKITEM NAME="Super Hybrid Maize" RESERVEDNAME="">
            <BASEUNITS>BAG</BASEUNITS>
            <HSNCODE>12099190</HSNCODE>
            <GSTRATE>5.0</GSTRATE>
          </STOCKITEM>
        </TALLYMESSAGE>

        <!-- Transaction Vouchers (Purchase & Sale) -->
        <TALLYMESSAGE>
          <VOUCHER VCHTYPE="Purchase" VOUCHERNUMBER="PUR-TALLY-001">
            <DATE>20260601</DATE>
            <PARTYLEDGERNAME>Sri Balaji Agro</PARTYLEDGERNAME>
            <ALLINVENTORYENTRIES.LIST>
              <STOCKITEMNAME>Super Hybrid Maize</STOCKITEMNAME>
              <BILLEDQTY>100.0 BAG</BILLEDQTY>
              <RATE>100.0</RATE>
              <AMOUNT>-10000.0</AMOUNT>
              <BATCHNAME>BATCH-ABC-99</BATCHNAME>
            </ALLINVENTORYENTRIES.LIST>
          </VOUCHER>
        </TALLYMESSAGE>
        <TALLYMESSAGE>
          <VOUCHER VCHTYPE="Sales" VOUCHERNUMBER="SAL-TALLY-001">
            <DATE>20260610</DATE>
            <PARTYLEDGERNAME>Karthik Ganji</PARTYLEDGERNAME>
            <ALLINVENTORYENTRIES.LIST>
              <STOCKITEMNAME>Super Hybrid Maize</STOCKITEMNAME>
              <BILLEDQTY>25.0 BAG</BILLEDQTY>
              <RATE>100.0</RATE>
              <AMOUNT>-2500.0</AMOUNT>
              <BATCHNAME>BATCH-ABC-99</BATCHNAME>
            </ALLINVENTORYENTRIES.LIST>
          </VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      final result = await TallyImportService().importTallyXml(tallyXml);

      expect(result.partiesImported, 2);
      expect(result.itemsImported, 1);
      expect(result.purchasesImported, 1);
      expect(result.salesImported, 1);

      // Verify db state
      final db = await dbHelper.database;
      
      final parties = await db.query('parties');
      expect(parties.length, 2);
      final supplier = parties.firstWhere((p) => p['type'] == 'SUPPLIER');
      expect(supplier['name'], 'Sri Balaji Agro');
      expect(supplier['gstin'], '36AAAAA1111A1Z1');

      final items = await db.query('items');
      expect(items.length, 1);
      expect(items.first['name'], 'Super Hybrid Maize');

      final purchases = await db.query('purchases');
      expect(purchases.length, 1);
      expect(purchases.first['invoice_no'], 'PUR-TALLY-001');

      final sales = await db.query('sales');
      expect(sales.length, 1);
      expect(sales.first['invoice_no'], 'SAL-TALLY-001');
    });

    test('Tally XML Import Idempotency and Duplicate Guard', () async {
      const tallyXml = '''
<ENVELOPE>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE TALLYBUILDNO="100">
          <COMPANY NAME="Balaji Trading Co">
            <NAME>Balaji Trading Co</NAME>
          </COMPANY>
        </TALLYMESSAGE>
        <TALLYMESSAGE>
          <LEDGER NAME="Sri Balaji Agro">
            <PARENT>Sundry Creditors</PARENT>
          </LEDGER>
        </TALLYMESSAGE>
        <TALLYMESSAGE>
          <VOUCHER VCHTYPE="Purchase" VOUCHERNUMBER="PUR-IDEMP-001">
            <DATE>20260601</DATE>
            <PARTYLEDGERNAME>Sri Balaji Agro</PARTYLEDGERNAME>
            <ALLINVENTORYENTRIES.LIST>
              <STOCKITEMNAME>Super Hybrid Maize</STOCKITEMNAME>
              <BILLEDQTY>100.0 BAG</BILLEDQTY>
              <RATE>100.0</RATE>
              <AMOUNT>-10000.0</AMOUNT>
            </ALLINVENTORYENTRIES.LIST>
          </VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      // First import
      final result1 = await TallyImportService().importTallyXml(tallyXml);
      expect(result1.purchasesImported, 1);
      expect(result1.logs.any((l) => l.contains('Detected Tally Version: Tally Prime')), true);
      expect(result1.logs.any((l) => l.contains('Company detected: Balaji Trading Co')), true);

      // Second import (should skip voucher)
      final result2 = await TallyImportService().importTallyXml(tallyXml);
      expect(result2.purchasesImported, 0); // Idempotent!
      expect(result2.logs.any((l) => l.contains('Duplicate voucher skipped')), true);
    });

    test('Tally Build Version and Multi-Company Detection', () async {
      const multiCompanyXml = '''
<ENVELOPE>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE TALLYBUILDNO="72">
          <COMPANY NAME="Company Alpha"></COMPANY>
        </TALLYMESSAGE>
        <TALLYMESSAGE TALLYBUILDNO="72">
          <COMPANY NAME="Company Beta"></COMPANY>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      final result = await TallyImportService().importTallyXml(multiCompanyXml);
      expect(result.logs.any((l) => l.contains('Detected Tally Version: Tally 7.2')), true);
      expect(result.logs.any((l) => l.contains('Found multiple companies: Company Alpha, Company Beta')), true);
      expect(result.logs.any((l) => l.contains('Selected company for import: Company Alpha')), true);
    });
    test('StockIn Voucher Import and Nested GST Parsing', () async {
      const stockInXml = '''
<ENVELOPE>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE>
          <STOCKITEM NAME="Nested GST Item" RESERVEDNAME="">
            <PARENT>Agro Chemicals</PARENT>
            <BASEUNITS>BOX</BASEUNITS>
            <HSNCODE>3808</HSNCODE>
            <GSTDETAILS.LIST>
              <STATEGSTDETAILS.LIST>
                <RATEDETAILS.LIST>
                  <GSTRATE>18.00</GSTRATE>
                </RATEDETAILS.LIST>
              </STATEGSTDETAILS.LIST>
            </GSTDETAILS.LIST>
          </STOCKITEM>
        </TALLYMESSAGE>
        <TALLYMESSAGE>
          <VOUCHER VCHTYPE="StockIn" VOUCHERNUMBER="STK-IN-001">
            <DATE>20260605</DATE>
            <!-- Missing PARTYLEDGERNAME intentionally -->
            <ALLINVENTORYENTRIES.LIST>
              <STOCKITEMNAME>Nested GST Item</STOCKITEMNAME>
              <BILLEDQTY>50.0 BOX</BILLEDQTY>
              <RATE>200.0</RATE>
              <AMOUNT>-10000.0</AMOUNT>
              <BATCHNAME>BATCH-STK-11</BATCHNAME>
            </ALLINVENTORYENTRIES.LIST>
          </VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
''';

      final result = await TallyImportService().importTallyXml(stockInXml);
      expect(result.itemsImported, 1);
      expect(result.purchasesImported, 1); // StockIn should be parsed as purchase

      final db = await dbHelper.database;
      
      final items = await db.query('items');
      expect(items.length, 1);
      expect(items.first['gst_rate'], 18.0);
      expect(items.first['stock_group'], 'Agro Chemicals');

      final purchases = await db.query('purchases');
      expect(purchases.length, 1);
      expect(purchases.first['invoice_no'], 'STK-IN-001');

      final parties = await db.query('parties', where: 'id = ?', whereArgs: [purchases.first['party_id']]);
      expect(parties.first['name'], 'Stock Adjustment Supplier');

      final stockMovements = await db.query('stock_movements');
      expect(stockMovements.length, 1);
      expect(stockMovements.first['qty'], 50.0);
      expect(stockMovements.first['movement_type'], 'IN');
    });
  });
}
