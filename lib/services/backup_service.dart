import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'gdrive_service.dart';
import '../data/repositories/backup_repository.dart';
import '../data/models/backup_meta.dart';
import '../data/database/db_helper.dart';
import '../core/utils/encryption_helper.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final GDriveService _gdriveService = GDriveService();
  final BackupRepository _backupRepository = BackupRepository();

  /// Performs a backup of the current SQLite database to Google Drive
  Future<BackupMeta?> performBackup(String deviceId) async {
    final String dbPath = join(await getDatabasesPath(), 'godown_management.db');
    final File dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      return null;
    }

    final String tempBackupPath = join(await getDatabasesPath(), 'godown_backup_temp.db');
    final File tempBackupFile = File(tempBackupPath);
    if (await tempBackupFile.exists()) {
      await tempBackupFile.delete();
    }

    final DateTime now = DateTime.now();
    final String timestampStr = DateFormat('yyyy-MM-dd_HH-mm').format(now);
    final String fileName = 'godown_backup_$timestampStr.db';

    String? gdriveFileId;
    String status = 'FAILED';

    final String tempEncBackupPath = join(await getDatabasesPath(), 'godown_backup_temp_enc.db');
    final File tempEncBackupFile = File(tempEncBackupPath);

    try {
      final db = await DbHelper().database;
      try {
        // Safe database backup utilizing SQLite's atomic VACUUM INTO to avoid dirty reads during active transactions
        await db.execute("VACUUM INTO '$tempBackupPath'");
      } catch (_) {
        // Fallback to copying live database file if VACUUM INTO is not supported or fails
        await dbFile.copy(tempBackupPath);
      }

      // Encrypt the temp backup file
      if (await tempEncBackupFile.exists()) {
        await tempEncBackupFile.delete();
      }
      await EncryptionHelper.encryptFile(tempBackupFile, tempEncBackupFile);

      // Perform the upload using the encrypted database snapshot
      gdriveFileId = await _gdriveService.uploadBackup(tempEncBackupFile, fileName);
      if (gdriveFileId != null) {
        status = 'SUCCESS';
      }
    } catch (_) {
      status = 'FAILED';
    } finally {
      if (await tempBackupFile.exists()) {
        await tempBackupFile.delete();
      }
      if (await tempEncBackupFile.exists()) {
        await tempEncBackupFile.delete();
      }
    }

    final backupMeta = BackupMeta(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: now,
      gdriveFileId: gdriveFileId ?? 'FAILED',
      fileSize: await dbFile.length(),
      status: status,
      deviceId: deviceId,
    );

    // Save metadata locally
    await _backupRepository.insertBackupMeta(backupMeta);

    if (status == 'SUCCESS') {
      // Run retention policy maintenance
      await enforceRetentionPolicy();
    }

    return backupMeta;
  }

  /// Cleans up older backup files on GDrive based on the tiered retention policy
  Future<void> enforceRetentionPolicy() async {
    try {
      final List<GDriveFileMeta> backups = await _gdriveService.listBackups();
      final DateTime now = DateTime.now();

      final List<String> filesToDelete = [];

      // Group backups by time categories:
      // 1. Last 7 days: Keep all (every 6 hours)
      // 2. Last 4 weeks (days 8-28): Keep 1 per day
      // 3. Last 6 months (days 29-180): Keep 1 per week
      // 4. Older than 6 months: Delete

      final Map<String, GDriveFileMeta> dailyKeeps = {}; // key: YYYY-MM-DD
      final Map<String, GDriveFileMeta> weeklyKeeps = {}; // key: YYYY-WW (year-week)

      for (final backup in backups) {
        final age = now.difference(backup.createdTime);

        if (age.inDays <= 7) {
          // Keep everything in the last 7 days
          continue;
        } else if (age.inDays <= 28) {
          // Keep 1 per day
          final String dateKey = DateFormat('yyyy-MM-dd').format(backup.createdTime);
          if (!dailyKeeps.containsKey(dateKey)) {
            dailyKeeps[dateKey] = backup;
          } else {
            // Keep the newest of that day, delete others
            final currentKeep = dailyKeeps[dateKey]!;
            if (backup.createdTime.isAfter(currentKeep.createdTime)) {
              filesToDelete.add(currentKeep.id);
              dailyKeeps[dateKey] = backup;
            } else {
              filesToDelete.add(backup.id);
            }
          }
        } else if (age.inDays <= 180) {
          // Keep 1 per week
          // Calculate year-week key
          final String weekKey = '${backup.createdTime.year}-${_getWeekNumber(backup.createdTime)}';
          if (!weeklyKeeps.containsKey(weekKey)) {
            weeklyKeeps[weekKey] = backup;
          } else {
            // Keep the newest of that week, delete others
            final currentKeep = weeklyKeeps[weekKey]!;
            if (backup.createdTime.isAfter(currentKeep.createdTime)) {
              filesToDelete.add(currentKeep.id);
              weeklyKeeps[weekKey] = backup;
            } else {
              filesToDelete.add(backup.id);
            }
          }
        } else {
          // Older than 6 months -> Delete
          filesToDelete.add(backup.id);
        }
      }

      // Perform deletions on Google Drive
      for (final fileId in filesToDelete) {
        await _gdriveService.deleteFile(fileId);
      }
    } catch (_) {
      // Fail silently for retention checks so it doesn't block backup completion
    }
  }

  /// Helper to calculate the ISO week number of a date
  int _getWeekNumber(DateTime date) {
    final int dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  /// Opens a downloaded backup database in read-only mode for comparison
  Future<Database> openBackupReadOnly(String tempDbPath) async {
    return await openDatabase(
      tempDbPath,
      readOnly: true,
    );
  }

  /// Downloads a specific backup file to a local path for read-only cherry-picking
  Future<File?> downloadBackupForCherryPick(String gdriveFileId) async {
    try {
      final String tempDir = await getDatabasesPath();
      final String tempEncPath = join(tempDir, 'temp_restore_enc_${DateTime.now().millisecondsSinceEpoch}.db');
      final File tempEncFile = File(tempEncPath);

      final bool success = await _gdriveService.downloadBackup(gdriveFileId, tempEncFile);
      if (success) {
        final String tempDecPath = join(tempDir, 'temp_restore_${DateTime.now().millisecondsSinceEpoch}.db');
        final File tempDecFile = File(tempDecPath);
        await EncryptionHelper.decryptFile(tempEncFile, tempDecFile);
        if (await tempEncFile.exists()) {
          await tempEncFile.delete();
        }
        return tempDecFile;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
