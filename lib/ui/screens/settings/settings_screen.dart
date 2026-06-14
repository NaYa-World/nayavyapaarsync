import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/settings.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../sync/sync_role_manager.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final bool isFirstLaunch;

  const SettingsScreen({super.key, this.isFirstLaunch = false});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firmNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstinController = TextEditingController();
  final _stateController = TextEditingController(text: 'Telangana');
  String _selectedRole = 'OWNER';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final settings = ref.read(settingsProvider);
    if (settings != null) {
      _firmNameController.text = settings.firmName;
      _phoneController.text = settings.phone;
      _addressController.text = settings.address;
      _gstinController.text = settings.gstin ?? '';
      _stateController.text = settings.state;
      setState(() {
        _selectedRole = settings.role;
      });
    }
  }

  @override
  void dispose() {
    _firmNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final String stateName = _stateController.text.trim();
      final String stateCode = stateName.toLowerCase() == 'telangana' ? '36' : '99'; // 36 is Telangana, 99 for other/inter-state

      final newSettings = Settings(
        firmName: _firmNameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
        gstin: _gstinController.text.trim().isEmpty ? null : _gstinController.text.trim(),
        state: stateName,
        stateCode: stateCode,
        role: _selectedRole,
      );

      // Save database settings
      await ref.read(settingsProvider.notifier).saveSettings(newSettings);

      // Persist active role in singleton
      await SyncRoleManager().setRoleManually(_selectedRole);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully!'), backgroundColor: Colors.green),
      );

      if (widget.isFirstLaunch) {
        // AppRootNavigator will automatically route to Dashboard on next rebuild
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstLaunch ? 'Setup Distributor Profile' : 'Business Settings'),
        automaticallyImplyLeading: !widget.isFirstLaunch,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isFirstLaunch) ...[
                Text(
                  'Welcome to VyapaarSync!',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please fill out your business profile. These details will appear on tax invoices and generated PDFs.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ],

              // Google Account section
              Text(
                'GOOGLE BACKUP ACCOUNT',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_done_rounded, color: Colors.green),
                  title: Text(authUser?.displayName ?? 'Google User'),
                  subtitle: Text(authUser?.email ?? 'Not signed in'),
                  trailing: widget.isFirstLaunch
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.logout_rounded, color: Colors.red),
                          tooltip: 'Log Out',
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Log Out'),
                                content: const Text('Are you sure you want to log out and exit?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log Out')),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref.read(authProvider.notifier).signOut();
                            }
                          },
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Firm profile fields
              Text(
                'FIRM DETAILS',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Device Role / పరికరం పాత్ర *',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'OWNER', child: Text('Owner (యజమాని)')),
                  DropdownMenuItem(value: 'ACCOUNTANT', child: Text('Accountant (అకౌంటెంట్)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedRole = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _firmNameController,
                decoration: const InputDecoration(
                  labelText: 'Firm Name / వ్యాపార పేరు *',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Firm Name is mandatory' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number / ఫోన్ నంబర్ *',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Phone number is mandatory' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address / చిరునామా *',
                  prefixIcon: Icon(Icons.location_on_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Address is mandatory' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gstinController,
                decoration: const InputDecoration(
                  labelText: 'GSTIN (Optional) / జి.ఎస్.టి.ఐ.ఎన్',
                  prefixIcon: Icon(Icons.receipt_long_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _stateController,
                decoration: const InputDecoration(
                  labelText: 'State / రాష్ట్రము *',
                  prefixIcon: Icon(Icons.map_rounded),
                  suffixText: '(Code: 36 for Telangana)',
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'State is mandatory' : null,
              ),
              const SizedBox(height: 32),

              // Save button
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _saveSettings,
                  child: Text(widget.isFirstLaunch ? 'Save & Start App' : 'Save Details'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
