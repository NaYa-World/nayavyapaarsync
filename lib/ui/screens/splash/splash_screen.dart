import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/date_utils.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/sync_queue_service.dart';
import '../../../sync/manifest_manager.dart';
import '../../widgets/va_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _searchingBackups = false;
  Manifest? _manifestFound;
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
          final manifest = await ManifestManager().downloadManifest();
          if (manifest != null && (manifest.latestSnapshot != null || manifest.deviceRegistry.isNotEmpty)) {
            setState(() {
              _manifestFound = manifest;
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

  Future<void> _restoreBackup() async {
    setState(() {
      _searchingBackups = true;
      _showRestoreDialog = false;
    });

    try {
      final deviceId = ref.read(authProvider).deviceId;
      // Look up registered role in the manifest if they were registered, otherwise default to OWNER
      final registeredRole = _manifestFound?.deviceRegistry[deviceId]?.role ?? 'owner';

      final success = await SyncQueueService().restoreFromManifest(_manifestFound!, deviceId, registeredRole);
      if (success) {
        // Force reload db and settings
        await ref.read(settingsProvider.notifier).loadSettings();
        // Refresh app state
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database restored successfully!'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception('Download/apply failed');
      }
    } catch (e) {
      if (!mounted) return;
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
            if (_showRestoreDialog && _manifestFound != null)
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
                                  'Sync Data Found',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'We found existing sync data for your account. Restoring will download the latest database snapshot and replay incremental changes.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'VyapaarSync Cloud Backup',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              _manifestFound!.latestSnapshot != null
                                  ? 'Latest Snapshot: ${AppDateUtils.formatDate(DateTime.fromMillisecondsSinceEpoch(_manifestFound!.latestSnapshot!.generatedAt))}'
                                  : 'Incremental Change Logs Available',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Icon(Icons.settings_backup_restore_rounded, color: theme.colorScheme.primary),
                            onTap: _restoreBackup,
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
