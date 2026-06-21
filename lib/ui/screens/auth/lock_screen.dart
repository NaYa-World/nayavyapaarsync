import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/app_user.dart';
import '../../../providers/security_provider.dart';
import '../../../providers/user_provider.dart';
import '../../widgets/va_logo.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _usePin = false;
  AppUser? _selectedUser;
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Auto-trigger biometric authentication after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerBiometrics();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _triggerBiometrics() async {
    final success = await ref.read(securityProvider.notifier).authenticate();
    if (!success && mounted) {
      setState(() {
        _usePin = true; // Auto fallback if biometrics are cancelled/unavailable
      });
    }
  }

  Future<void> _unlockWithPin() async {
    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a user profile.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final pin = _pinController.text.trim();
    final authenticatedUser = await ref.read(userProvider.notifier).authenticate(_selectedUser!.id, pin);

    if (authenticatedUser != null) {
      ref.read(securityProvider.notifier).forceUnlock();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid PIN! Access Denied.'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usersState = ref.watch(userProvider);
    final securityState = ref.watch(securityProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: VALogo(size: 80)),
              const SizedBox(height: 16),
              Text(
                'Naya Vyapaar',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 36),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Application Locked',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please verify your credentials to continue sync operations.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!_usePin && securityState.isBiometricEnabled) ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.fingerprint_rounded, size: 28),
                          label: const Text('Unlock with Biometrics'),
                          onPressed: _triggerBiometrics,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _usePin = true;
                            });
                          },
                          child: const Text('Use Secure PIN Fallback'),
                        ),
                      ] else ...[
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              usersState.when(
                                loading: () => const Center(child: CircularProgressIndicator()),
                                error: (err, _) => Text('Error loading profiles: $err', style: const TextStyle(color: Colors.red)),
                                data: (users) {
                                  if (_selectedUser == null && users.isNotEmpty) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      setState(() {
                                        _selectedUser = users.first;
                                      });
                                    });
                                  }
                                  return DropdownButtonFormField<String>(
                                    value: _selectedUser?.id,
                                    decoration: const InputDecoration(
                                      labelText: 'Select Profile',
                                      prefixIcon: Icon(Icons.person_rounded),
                                    ),
                                    items: users.map((u) {
                                      return DropdownMenuItem(
                                        value: u.id,
                                        child: Text('${u.name} (${u.role})'),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      setState(() {
                                        _selectedUser = users.firstWhere((u) => u.id == val);
                                      });
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _pinController,
                                obscureText: true,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Enter 4-Digit PIN',
                                  prefixIcon: Icon(Icons.pin_rounded),
                                  counterText: '',
                                ),
                                validator: (val) {
                                  if (val == null || val.length != 4) {
                                    return 'Must be 4 digits';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _unlockWithPin,
                                child: const Text('Verify & Unlock'),
                              ),
                              if (securityState.isBiometricEnabled) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _usePin = false;
                                    });
                                  },
                                  child: const Text('Scan Fingerprint / Face ID'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
