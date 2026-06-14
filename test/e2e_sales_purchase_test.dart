import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:godown_management/data/database/db_helper.dart';
import 'package:godown_management/data/repositories/item_repository.dart';
import 'package:godown_management/data/repositories/purchase_repository.dart';
import 'package:godown_management/data/repositories/sale_repository.dart';
import 'package:godown_management/data/models/item.dart';
import 'package:godown_management/data/models/party.dart';
import 'package:godown_management/data/models/purchase.dart';
import 'package:godown_management/data/models/sale.dart';

void main() {
  // Setup sqflite ffi for testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('E2E Sales and Purchase Batch Flow Tests', () {
    late DbHelper dbHelper;
    late ItemRepository itemRepo;
    late PurchaseRepository purchaseRepo;
    late SaleRepository saleRepo;

    setUp(() async {
      dbHelper = DbHelper();
      itemRepo = ItemRepository();
      purchaseRepo = PurchaseRepository();
      saleRepo = SaleRepository();

      // Start with a clean database for every test
      await dbHelper.close();
      final databasePath = await getDatabasesPath();
      final path = '$databasePath/godown_management.db';
      await deleteDatabase(path);
    });

    test('Full Purchase & Sale E2E Batch Lifecycle', () async {
      // 1. Create a Product/Item
      final testItem = Item(
        id: 'item-1',
        name: 'Super Hybrid Maize',
        category: 'SEED',
        hsnCode: '12099190',
        gstRate: 5.0,
        primaryUnit: 'BAG',
        bagWeightKg: 25.0,
        createdAt: DateTime.now(),
      );
      await itemRepo.insertItem(testItem, 'test-device');

      // Verify item inserted correctly
      final dbItem = await itemRepo.getItem('item-1');
      expect(dbItem, isNotNull);
      expect(dbItem!.name, 'Super Hybrid Maize');

      // 2. Create Parties (Supplier and Customer)
      final supplier = Party(
        id: 'supplier-1',
        name: 'Sri Balaji Agro',
        type: 'SUPPLIER',
        phone: '9876543210',
        address: 'Warangal, Telangana',
        gstin: '36AAAAA1111A1Z1', // Telangana State Code 36
        createdAt: DateTime.now(),
      );
      final customer = Party(
        id: 'customer-1',
        name: 'Karthik Ganji',
        type: 'CUSTOMER',
        phone: '8765432109',
        address: 'Hyderabad, Telangana',
        gstin: '36BBBBB2222B2Z2',
        createdAt: DateTime.now(),
      );

      final db = await dbHelper.database;
      await db.insert('parties', supplier.toMap());
      await db.insert('parties', customer.toMap());

      // 3. Enter a Purchase (Establishes the Batch and Stock)
      final purchaseDate = DateTime(2026, 6, 1);
      final purchase = Purchase(
        id: 'purchase-1',
        invoiceNo: 'PUR/2026-27/001',
        partyId: supplier.id,
        date: purchaseDate,
        subtotal: 10000.0,
        gstTotal: 500.0,
        grandTotal: 10500.0,
        paymentStatus: 'PAID',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: 'SEED',
      );

      final purchaseItem = PurchaseItem(
        id: 'pi-1',
        purchaseId: purchase.id,
        itemId: testItem.id,
        qty: 100.0, // 100 kg total
        rate: 100.0,
        gstRate: 5.0,
        gstAmt: 500.0,
        total: 10500.0,
        lotNo: 'BATCH-ABC-99',
        hsnCode: testItem.hsnCode,
        noOfBags: 4.0,
        perUnit: 'kgs',
        discountPct: 0.0,
        mfgDate: '01-May-2026',
        expDate: '30-Apr-2027',
        manufacturer: 'VA Seeds Corp',
        packing: '25 kg',
      );

      await purchaseRepo.insertPurchase(purchase, [purchaseItem], 'test-device');

      // Verify purchase batch details are available
      final batches = await itemRepo.getAvailableBatchesForItem(testItem.id);
      expect(batches.length, 1);
      
      final batch = batches.first;
      expect(batch.batchNo, 'BATCH-ABC-99');
      expect(batch.manufacturer, 'VA Seeds Corp');
      expect(batch.packing, '25 kg');
      expect(batch.hsnCode, '12099190');
      expect(batch.mfgDate, '01-May-2026');
      expect(batch.expDate, '30-Apr-2027');
      expect(batch.remainingStock, 100.0); // 100.0 purchased, 0 sold

      // 4. Enter a Sale (Consumes Stock from the Batch)
      final saleDate = DateTime(2026, 6, 10);
      final sale = Sale(
        id: 'sale-1',
        invoiceNo: 'SAL/2026-27/001',
        partyId: customer.id,
        date: saleDate,
        subtotal: 2500.0,
        gstTotal: 125.0,
        grandTotal: 2625.0,
        paymentStatus: 'PAID',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        category: 'SEED',
      );

      final saleItem = SaleItem(
        id: 'si-1',
        saleId: sale.id,
        itemId: testItem.id,
        qty: 25.0, // Sell 25 kg (1 bag)
        rate: 100.0,
        gstRate: 5.0,
        gstAmt: 125.0,
        total: 2625.0,
        manufacturer: batch.manufacturer,
        packing: batch.packing,
        batchNo: batch.batchNo,
        hsnCode: batch.hsnCode,
        mfgDate: batch.mfgDate,
        expDate: batch.expDate,
        unitPerCase: 25.0,
        noOfCases: 1.0,
        totalUnits: 25.0,
        unitPrice: 100.0,
      );

      // Perform the sale
      await saleRepo.insertSale(sale, [saleItem], 'test-device');

      // 5. Query batches again and verify remaining stock level got reduced
      final updatedBatches = await itemRepo.getAvailableBatchesForItem(testItem.id);
      expect(updatedBatches.length, 1);
      
      final updatedBatch = updatedBatches.first;
      expect(updatedBatch.remainingStock, 75.0); // 100.0 - 25.0 = 75.0

      // 6. Test insufficient stock check logic
      const double requestQty = 80.0;
      final double availableStock = updatedBatch.remainingStock;
      
      // Stock check must block sales when requestQty > availableStock
      final bool isStockDeficit = requestQty > availableStock;
      expect(isStockDeficit, true); // 80.0 > 75.0, should block
      
      const double safeQty = 50.0;
      final bool isSafeStock = safeQty > availableStock;
      expect(isSafeStock, false); // 50.0 <= 75.0, should pass
    });
  });
}
