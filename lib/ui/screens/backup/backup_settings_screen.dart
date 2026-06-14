import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/date_utils.dart';
import '../../../providers/backup_provider.dart';
import '../../../services/backup_service.dart';
import '../../../services/tally_import_service.dart';
import 'cherry_pick_restore_screen.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  ConsumerState<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends ConsumerState<BackupSettingsScreen> {
  bool _isDownloading = false;

  Future<void> _triggerBackup() async {
    final success = await ref.read(backupProvider.notifier).runManualBackup();
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database backed up successfully to Google Drive!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup failed. Check internet connection.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startCherryPick(String fileId, String fileName) async {
    setState(() {
      _isDownloading = true;
    });

    try {
      final File? tempDbFile = await BackupService().downloadBackupForCherryPick(fileId);
      
      setState(() {
        _isDownloading = false;
      });

      if (tempDbFile != null && mounted) {
        // Navigate to CherryPickRestoreScreen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CherryPickRestoreScreen(
              backupDbFile: tempDbFile,
              backupName: fileName,
            ),
          ),
        );
      } else {
        throw Exception('Download failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download backup for restore: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _importTallyData() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isDownloading = true;
      });

      final file = File(result.files.single.path!);
      final xmlContent = await file.readAsString();

      final importResult = await TallyImportService().importTallyXml(xmlContent);

      setState(() {
        _isDownloading = false;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Import Successful!'),
            content: SingleChildScrollView(
              child: ListBody(
                children: [
                  Text('Parties Imported: ${importResult.partiesImported}'),
                  Text('Items Imported: ${importResult.itemsImported}'),
                  Text('Sales Invoices Imported: ${importResult.salesImported}'),
                  Text('Purchase Invoices Imported: ${importResult.purchasesImported}'),
                  const SizedBox(height: 12),
                  const Text('Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...importResult.logs.map((log) => Text('• $log', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import Tally data: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backupState = ref.watch(backupProvider);

    final String lastBackupStr = backupState.lastBackup != null
        ? DateFormat('dd-MMM-yyyy HH:mm').format(backupState.lastBackup!.timestamp)
        : 'Never';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backups / డేటా బ్యాకప్స్'),
      ),
      body: _isDownloading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Downloading backup file from Google Drive...', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Please wait, opening database in read-only mode...'),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.read(backupProvider.notifier).refreshRemoteBackups(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Sync status header card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                                foregroundColor: theme.colorScheme.primary,
                                radius: 24,
                                child: const Icon(Icons.cloud_upload_rounded),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Google Drive Backups', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 4),
                                    Text('Last Synced: $lastBackupStr', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (backupState.isLoading)
                            const CircularProgressIndicator()
                          else
                            ElevatedButton.icon(
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Backup Now / ఇప్పుడు బ్యాకప్ చేయి'),
                              onPressed: _triggerBackup,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Retention policy card
                  Card(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: theme.colorScheme.secondary.withValues(alpha: 0.1)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline_rounded, size: 18, color: Colors.blueGrey),
                              SizedBox(width: 8),
                              Text('Tiered Retention Policy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            '• Last 7 days: backups kept every 6 hours.\n'
                            '• Last 4 weeks: 1 backup per day kept.\n'
                            '• Last 6 months: 1 backup per week kept.\n'
                            '• Older backups are automatically cleaned up to save drive space.',
                            style: TextStyle(fontSize: 11, height: 1.5, color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Import Tally Data Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.teal.withValues(alpha: 0.12),
                                foregroundColor: Colors.teal,
                                radius: 24,
                                child: const Icon(Icons.import_export_rounded),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Import Tally XML Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    SizedBox(height: 4),
                                    Text('Import Ledgers, Stock, and Invoice vouchers from Tally.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.file_open_rounded),
                              label: const Text('Select Tally XML File / ఫైల్‌ను ఎంచుకోండి'),
                              onPressed: _importTallyData,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Backups List Title
                  Text(
                    'HISTORICAL BACKUPS ON GDRIVE (NEWEST FIRST)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (backupState.backups.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No backups found on Google Drive. Pull to refresh.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: backupState.backups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final backup = backupState.backups[index];
                        final String dateStr = AppDateUtils.formatDate(backup.createdTime);
                        final String timeStr = DateFormat('HH:mm').format(backup.createdTime);

                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
                              foregroundColor: theme.colorScheme.secondary,
                              child: const Icon(Icons.inventory_2_rounded, size: 18),
                            ),
                            title: Text(
                              '$dateStr $timeStr',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('Size: ${(backup.size / 1024 / 1024).toStringAsFixed(2)} MB'),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.settings_backup_restore_rounded, size: 14),
                              label: const Text('Cherry-pick', style: TextStyle(fontSize: 12)),
                              onPressed: () => _startCherryPick(backup.id, backup.name),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
