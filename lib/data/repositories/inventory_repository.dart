import '../database/db_helper.dart';
import '../models/godown.dart';
import '../models/batch.dart';
import '../models/stock_movement.dart';

class InventoryRepository {
  final DbHelper _dbHelper = DbHelper();

  // ─── Godowns ───────────────────────────────────────────────────────────────

  Future<void> createGodown(Godown godown) async {
    final db = await _dbHelper.database;
    await db.insert('godowns', godown.toMap());
  }

  Future<List<Godown>> getGodowns(String companyId, {bool activeOnly = true}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'godowns',
      where: activeOnly ? 'company_id = ? AND is_active = 1' : 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'name ASC',
    );
    return rows.map(Godown.fromMap).toList();
  }

  // ─── Batches ───────────────────────────────────────────────────────────────

  Future<void> createBatch(Batch batch) async {
    final db = await _dbHelper.database;
    await db.insert('batches', batch.toMap());
  }

  Future<List<Batch>> getBatches(String stockItemId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'batches',
      where: 'stock_item_id = ?',
      whereArgs: [stockItemId],
      orderBy: 'expiry_date ASC',
    );
    return rows.map(Batch.fromMap).toList();
  }

  // ─── Stock Movements ───────────────────────────────────────────────────────

  Future<void> insertStockMovement(StockMovement movement) async {
    final db = await _dbHelper.database;
    await db.insert('stock_movements', movement.toMap());
  }

  Future<List<StockMovement>> getStockMovements(String stockItemId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      where: 'stock_item_id = ?',
      whereArgs: [stockItemId],
      orderBy: 'created_at ASC',
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<List<StockMovement>> getVoucherStockMovements(String voucherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      where: 'ref_voucher_id = ?',
      whereArgs: [voucherId],
    );
    return rows.map(StockMovement.fromMap).toList();
  }
}
