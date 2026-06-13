import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/indian_format.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/gdrive_service.dart';
import '../../screens/settings/settings_screen.dart';
import '../../widgets/va_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _searchingBackups = false;
  List<GDriveFileMeta> _backupsFound = [];
  bool _showRestoreDialog = false;

  @override
  void initState() {
    super.initState();
    _checkForBackups();
  }

  Future<void> _checkForBackups() async {
    // Wait for auth provider to load
    await Future.delayed(const Duration(milliseconds: 800));
    final auth = ref.read(authProvider);

    if (auth.user != null) {
      final settings = ref.read(settingsProvider);
      // Only check GDrive backups if settings are not initialized yet (Clean Install)
      if (settings == null || !settings.isValid) {
        setState(() {
          _searchingBackups = true;
        });

        try {
          final backups = await GDriveService().listBackups();
          if (backups.isNotEmpty) {
            setState(() {
              _backupsFound = backups;
              _showRestoreDialog = true;
              _searchingBackups = false;
            });
            return;
          }
        } catch (_) {
          // If network check fails, ignore and proceed
        }

        setState(() {
          _searchingBackups = false;
        });
      }
    }
  }

  Future<void> _restoreBackup(GDriveFileMeta backup) async {
    setState(() {
      _searchingBackups = true;
      _showRestoreDialog = false;
    });

    try {
      final String dbDir = await getDatabasesPath();
      final String dbPath = p.join(dbDir, 'godown_management.db');
      final File tempFile = File(dbPath);

      final success = await GDriveService().downloadBackup(backup.id, tempFile);
      if (success) {
        // Force reload db and settings
        ref.read(settingsProvider.notifier).loadSettings();
        // Refresh app state
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database restored successfully!'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception('Download failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore backup: ${e.toString()}'), backgroundColor: Colors.red),
      );
      setState(() {
        _showRestoreDialog = true;
        _searchingBackups = false;
      });
    }
  }

  void _skipRestore() {
    setState(() {
      _showRestoreDialog = false;
    });
    // This will trigger AppRootNavigator to redirect to SettingsScreen
    ref.read(settingsProvider.notifier).loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary.withOpacity(0.9),
              theme.colorScheme.primary,
              theme.colorScheme.primaryContainer,
            ],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // VA logo
                  const VALogo(size: 100),
                  const SizedBox(height: 24),
                  const Text(
                    'విత్తన & ఎరువుల గోదాం',
                    style: TextStyle(
                      fontFamily: 'Telugu',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Seed & Fertiliser Godown',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (_searchingBackups) ...[
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Checking for backups...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ] else ...[
                    const CircularProgressIndicator(color: Colors.white30),
                  ],
                ],
              ),
            ),

            // Restore Dialog Overlay
            if (_showRestoreDialog)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.backup_rounded, color: theme.colorScheme.primary, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Backups Found on Google Drive',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'We found existing backups for your account. Select a backup to restore your data, or skip to start fresh.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _backupsFound.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final backup = _backupsFound[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    AppDateUtils.formatDate(backup.createdTime),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    'Size: ${(backup.size / 1024 / 1024).toStringAsFixed(2)} MB',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Icon(Icons.settings_backup_restore_rounded, color: theme.colorScheme.primary),
                                  onTap: () => _restoreBackup(backup),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _skipRestore,
                                child: const Text('Skip & Start Fresh'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
