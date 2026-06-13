import 'package:sqflite/sqflite.dart';
import '../models/backup_meta.dart';
import '../models/sync_queue.dart';
import '../database/db_helper.dart';

class BackupRepository {
  final DbHelper _dbHelper = DbHelper();

  /// Fetches all backup metadata records (newest first)
  Future<List<BackupMeta>> getBackupMetas() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'backup_metas',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => BackupMeta.fromMap(maps[i]));
  }

  /// Inserts a new backup metadata record
  Future<void> insertBackupMeta(BackupMeta meta) async {
    final db = await _dbHelper.database;
    await db.insert(
      'backup_metas',
      meta.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Fetches all sync queue items that are pending sync
  Future<List<SyncQueueItem>> getPendingSyncQueue() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sync_queue',
      where: "status = 'PENDING'",
      orderBy: 'created_at ASC',
    );
    return List.generate(maps.length, (i) => SyncQueueItem.fromMap(maps[i]));
  }

  /// Updates the status of a sync queue item (e.g. 'DONE', 'FAILED')
  Future<void> updateSyncQueueStatus(String id, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'sync_queue',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Clear successfully synced entries from sync queue to keep it clean
  Future<void> clearSyncedQueue() async {
    final db = await _dbHelper.database;
    await db.delete(
      'sync_queue',
      where: "status = 'DONE'",
    );
  }

  /// Check if there are any unsynced changes in the queue
  Future<bool> hasUnsyncedChanges() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> res = await db.rawQuery(
      "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'PENDING'"
    );
    if (res.isEmpty) return false;
    final int count = res.first['count'] as int;
    return count > 0;
  }
}
