import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'sync/sync_role_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SyncRoleManager().initAtBoot();
  runApp(
    const ProviderScope(
      child: VyapaarSyncApp(),
    ),
  );
}
