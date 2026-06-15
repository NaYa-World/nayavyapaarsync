import 'dart:io';
import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'auth_service.dart';


class GDriveFileMeta {
  final String id;
  final String name;
  final int size;
  final DateTime createdTime;

  GDriveFileMeta({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
  });
}

class GDriveService {
  static final GDriveService _instance = GDriveService._internal();
  factory GDriveService() => _instance;
  GDriveService._internal();

  final AuthService _authService = AuthService();

  /// Gets the Drive API instance using authenticated client
  Future<drive.DriveApi?> _getDriveApi() async {
    final client = await _authService.getAuthenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  /// Finds or creates a folder by name under a given parent
  Future<String> _findOrCreateFolder(drive.DriveApi driveApi, String folderName, {String parentId = 'root'}) async {
    final String query = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and '$parentId' in parents and trashed = false";
    
    final drive.FileList fileList = await driveApi.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      return fileList.files!.first.id!;
    }

    // Create the folder
    final drive.File folderMetadata = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];

    final drive.File createdFolder = await driveApi.files.create(folderMetadata);
    return createdFolder.id!;
  }

  /// Gets the root VyapaarSync folder ID
  Future<String?> _getVyapaarSyncFolderId(drive.DriveApi driveApi) async {
    try {
      return await _findOrCreateFolder(driveApi, 'VyapaarSync', parentId: 'root');
    } catch (_) {
      return null;
    }
  }

  /// Gets the VyapaarSync/snapshots folder ID
  Future<String?> _getSnapshotsFolderId(drive.DriveApi driveApi) async {
    try {
      final rootId = await _getVyapaarSyncFolderId(driveApi);
      if (rootId == null) return null;
      return await _findOrCreateFolder(driveApi, 'snapshots', parentId: rootId);
    } catch (_) {
      return null;
    }
  }

  /// Gets the VyapaarSync/logs folder ID
  Future<String?> _getLogsFolderId(drive.DriveApi driveApi) async {
    try {
      final rootId = await _getVyapaarSyncFolderId(driveApi);
      if (rootId == null) return null;
      return await _findOrCreateFolder(driveApi, 'logs', parentId: rootId);
    } catch (_) {
      return null;
    }
  }

  /// Gets the backups folder ID under /VyapaarSync/backups/ (Legacy backup folder)
  Future<String?> _getBackupsFolderId(drive.DriveApi driveApi) async {
    try {
      final godownAppId = await _findOrCreateFolder(driveApi, 'VyapaarSync', parentId: 'root');
      final backupsId = await _findOrCreateFolder(driveApi, 'backups', parentId: godownAppId);
      return backupsId;
    } catch (_) {
      return null;
    }
  }

  /// Uploads or overwrites manifest.json in root VyapaarSync folder
  Future<bool> uploadManifest(String jsonContent) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    final rootFolderId = await _getVyapaarSyncFolderId(driveApi);
    if (rootFolderId == null) return false;

    try {
      // Check if manifest.json already exists
      final String query = "name = 'manifest.json' and '$rootFolderId' in parents and trashed = false";
      final drive.FileList fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id)',
      );

      final bytes = utf8.encode(jsonContent);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Overwrite existing file
        final fileId = fileList.files!.first.id!;
        await driveApi.files.update(
          drive.File(),
          fileId,
          uploadMedia: media,
        );
        return true;
      } else {
        // Create new file
        final drive.File fileMetadata = drive.File()
          ..name = 'manifest.json'
          ..parents = [rootFolderId];
        await driveApi.files.create(fileMetadata, uploadMedia: media);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  /// Downloads manifest.json content from root VyapaarSync folder
  Future<String?> downloadManifest() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    final rootFolderId = await _getVyapaarSyncFolderId(driveApi);
    if (rootFolderId == null) return null;

    try {
      final String query = "name = 'manifest.json' and '$rootFolderId' in parents and trashed = false";
      final drive.FileList fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return null; // manifest doesn't exist
      }

      final fileId = fileList.files!.first.id!;
      final drive.Media response = (await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      )) as drive.Media;

      final List<int> bytes = [];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Uploads a sync log to the VyapaarSync/logs/ folder
  Future<String?> uploadLog(String fileName, String jsonContent) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    final logsFolderId = await _getLogsFolderId(driveApi);
    if (logsFolderId == null) return null;

    try {
      final bytes = utf8.encode(jsonContent);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      final drive.File fileMetadata = drive.File()
        ..name = fileName
        ..parents = [logsFolderId];

      final drive.File uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      return uploadedFile.id;
    } catch (_) {
      return null;
    }
  }

  /// Lists all log files in VyapaarSync/logs/
  Future<List<GDriveFileMeta>> listLogs() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return [];

    final logsFolderId = await _getLogsFolderId(driveApi);
    if (logsFolderId == null) return [];

    try {
      final String query = "'$logsFolderId' in parents and name contains 'sync_log_' and trashed = false";
      final drive.FileList fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'name asc',
        $fields: 'files(id, name, size, createdTime)',
      );

      if (fileList.files == null) return [];

      return fileList.files!
          .map((f) => GDriveFileMeta(
                id: f.id!,
                name: f.name!,
                size: f.size != null ? int.parse(f.size!) : 0,
                createdTime: f.createdTime ?? DateTime.now(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Downloads a log file content by file ID
  Future<String?> downloadLog(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    try {
      final drive.Media response = (await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      )) as drive.Media;

      final List<int> bytes = [];
      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Uploads a snapshot database file to VyapaarSync/snapshots/
  Future<String?> uploadSnapshot(File dbFile, String fileName) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    final snapshotsFolderId = await _getSnapshotsFolderId(driveApi);
    if (snapshotsFolderId == null) return null;

    try {
      final drive.File fileMetadata = drive.File()
        ..name = fileName
        ..parents = [snapshotsFolderId];

      final media = drive.Media(
        dbFile.openRead(),
        dbFile.lengthSync(),
      );

      final drive.File uploadedFile = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      return uploadedFile.id;
    } catch (_) {
      return null;
    }
  }

  /// Lists all snapshots in VyapaarSync/snapshots/
  Future<List<GDriveFileMeta>> listSnapshots() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return [];

    final snapshotsFolderId = await _getSnapshotsFolderId(driveApi);
    if (snapshotsFolderId == null) return [];

    try {
      final String query = "'$snapshotsFolderId' in parents and name contains 'godown_snapshot_' and trashed = false";
      final drive.FileList fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'name desc',
        $fields: 'files(id, name, size, createdTime)',
      );

      if (fileList.files == null) return [];

      return fileList.files!
          .map((f) => GDriveFileMeta(
                id: f.id!,
                name: f.name!,
                size: f.size != null ? int.parse(f.size!) : 0,
                createdTime: f.createdTime ?? DateTime.now(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Downloads a snapshot file to a destination file
  Future<bool> downloadSnapshot(String fileId, File destinationFile) async {
    return downloadBackup(fileId, destinationFile);
  }

  /// Uploads a file to Google Drive backups folder (Legacy backups)
  Future<String?> uploadBackup(File dbFile, String fileName) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return null;

    final backupsFolderId = await _getBackupsFolderId(driveApi);
    if (backupsFolderId == null) return null;

    final drive.File fileMetadata = drive.File()
      ..name = fileName
      ..parents = [backupsFolderId];

    final media = drive.Media(
      dbFile.openRead(),
      dbFile.lengthSync(),
    );

    final drive.File uploadedFile = await driveApi.files.create(
      fileMetadata,
      uploadMedia: media,
    );

    return uploadedFile.id;
  }

  /// Lists all backup files in /VyapaarSync/backups/ (Legacy backups)
  Future<List<GDriveFileMeta>> listBackups() async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return [];

    final backupsFolderId = await _getBackupsFolderId(driveApi);
    if (backupsFolderId == null) return [];

    final String query = "'$backupsFolderId' in parents and name contains 'godown_backup_' and trashed = false";

    final drive.FileList fileList = await driveApi.files.list(
      q: query,
      spaces: 'drive',
      orderBy: 'name desc', // sorts lexicographically, which matches date order due to formatting
      $fields: 'files(id, name, size, createdTime)',
    );

    if (fileList.files == null) return [];

    return fileList.files!
        .map((f) => GDriveFileMeta(
              id: f.id!,
              name: f.name!,
              size: f.size != null ? int.parse(f.size!) : 0,
              createdTime: f.createdTime ?? DateTime.now(),
            ))
        .toList();
  }

  /// Downloads a backup file from Google Drive to a local destination file
  Future<bool> downloadBackup(String fileId, File destinationFile) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    try {
      final drive.Media response = (await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      )) as drive.Media;

      // Delete destination file if exists
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }

      // Write bytes to file
      final IOSink sink = destinationFile.openWrite();
      await response.stream.pipe(sink);
      await sink.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes a file on Google Drive
  Future<bool> deleteFile(String fileId) async {
    final driveApi = await _getDriveApi();
    if (driveApi == null) return false;

    try {
      await driveApi.files.delete(fileId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
