import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
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

  /// Gets the backups folder ID under /VyapaarSync/backups/
  Future<String?> _getBackupsFolderId(drive.DriveApi driveApi) async {
    try {
      final godownAppId = await _findOrCreateFolder(driveApi, 'VyapaarSync', parentId: 'root');
      final backupsId = await _findOrCreateFolder(driveApi, 'backups', parentId: godownAppId);
      return backupsId;
    } catch (_) {
      return null;
    }
  }

  /// Uploads a file to Google Drive backups folder
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

  /// Lists all backup files in /VyapaarSync/backups/
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
