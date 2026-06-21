import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/security_provider.dart';
import 'ui/screens/auth/auth_screen.dart';
import 'ui/screens/auth/lock_screen.dart';
import 'ui/screens/dashboard/dashboard_screen.dart';
import 'ui/screens/settings/settings_screen.dart';
import 'ui/screens/splash/splash_screen.dart';

class VyapaarSyncApp extends ConsumerWidget {
  const VyapaarSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VyapaarSync',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Supports dark mode automatically
      debugShowCheckedModeBanner: false,
      home: const AppRootNavigator(),
    );
  }
}

class AppRootNavigator extends ConsumerStatefulWidget {
  const AppRootNavigator({super.key});

  @override
  ConsumerState<AppRootNavigator> createState() => _AppRootNavigatorState();
}

class _AppRootNavigatorState extends ConsumerState<AppRootNavigator> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ref.read(securityProvider.notifier).setLocked(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    final securityState = ref.watch(securityProvider);

    // 1. Show Splash Screen during initial boot & checks
    if (authState.isLoading) {
      return const SplashScreen();
    }

    // 2. Redirect to Auth Screen if not signed in
    if (authState.user == null) {
      return const AuthScreen();
    }

    // 3. Render Lock Screen overlay if security locks are active
    if (securityState.isAppLocked) {
      return const LockScreen();
    }

    // 4. Redirect to Settings Screen if firm name, phone or address are empty (First Launch Flow)
    if (settings == null || !settings.isValid) {
      return const SettingsScreen(isFirstLaunch: true);
    }

    // 5. Default landing is Dashboard
    return const DashboardScreen();
  }
}
