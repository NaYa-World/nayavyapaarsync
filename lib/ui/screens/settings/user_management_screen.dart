import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/app_user.dart';
import '../../../providers/user_provider.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            tooltip: 'Add User',
            onPressed: () => _showUserDialog(context, ref, null),
          ),
        ],
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline_rounded,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No users added yet'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _showUserDialog(context, ref, null),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Add First User'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _UserCard(user: users[i]),
          );
        },
      ),
    );
  }

  void _showUserDialog(
      BuildContext context, WidgetRef ref, AppUser? existing) {
    showDialog(
      context: context,
      builder: (_) => _UserFormDialog(existing: existing, ref: ref),
    );
  }
}

// ─── Role badge color mapping ────────────────────────────────────────────────

Color _roleColor(String role) {
  switch (role) {
    case 'ADMIN':
      return Colors.red.shade700;
    case 'CA':
      return Colors.blue.shade700;
    case 'ACCOUNTANT':
      return Colors.green.shade700;
    case 'MANAGER':
      return Colors.orange.shade700;
    default:
      return Colors.grey;
  }
}

// ─── User Card ───────────────────────────────────────────────────────────────

class _UserCard extends ConsumerWidget {
  final AppUser user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _roleColor(user.role);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(user.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(
                user.roleLabel,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) =>
              _handleAction(context, ref, action),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'change_role',
              child: ListTile(
                leading: Icon(Icons.manage_accounts_rounded),
                title: Text('Change Role'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'change_pin',
              child: ListTile(
                leading: Icon(Icons.pin_rounded),
                title: Text('Change PIN'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'deactivate',
              child: ListTile(
                leading: Icon(Icons.person_off_rounded,
                    color: Colors.red),
                title: Text('Deactivate',
                    style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(
      BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'change_role':
        _showRoleDialog(context, ref);
        break;
      case 'change_pin':
        _showChangePinDialog(context, ref);
        break;
      case 'deactivate':
        _confirmDeactivate(context, ref);
        break;
    }
  }

  void _showRoleDialog(BuildContext context, WidgetRef ref) {
    String selectedRole = user.role;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Change Role — ${user.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppUser.roles.map((role) {
              final color = _roleColor(role);
              return ListTile(
                leading: Radio<String>(
                  value: role,
                  groupValue: selectedRole,
                  activeColor: color,
                  onChanged: (v) => setState(() => selectedRole = v!),
                ),
                title: Text(role),
                onTap: () => setState(() => selectedRole = role),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                ref
                    .read(userProvider.notifier)
                    .updateRole(user.id, selectedRole);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  void _showChangePinDialog(BuildContext context, WidgetRef ref) {
    final pinController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('New PIN — ${user.name}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: pinController,
            decoration: const InputDecoration(
              labelText: 'New 4–6 digit PIN',
              prefixIcon: Icon(Icons.pin_rounded),
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            validator: (v) {
              if (v == null || v.trim().length < 4) return 'Min 4 digits';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                ref
                    .read(userProvider.notifier)
                    .changePin(user.id, pinController.text.trim());
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN updated successfully')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDeactivate(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate User?'),
        content: Text(
            '${user.name} will no longer be able to log in. This can be reversed from the database.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(userProvider.notifier)
                  .deactivateUser(user.id);
              Navigator.pop(context);
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }
}

// ─── Add User Dialog ─────────────────────────────────────────────────────────

class _UserFormDialog extends StatefulWidget {
  final AppUser? existing;
  final WidgetRef ref;
  const _UserFormDialog({required this.existing, required this.ref});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _pin;
  String _selectedRole = 'ACCOUNTANT';
  bool _saving = false;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _pin = TextEditingController();
    _selectedRole = widget.existing?.role ?? 'ACCOUNTANT';
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.ref.read(userProvider.notifier).createUser(
          name: _name.text.trim(),
          plainPin: _pin.text.trim(),
          role: _selectedRole,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New User'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pin,
                decoration: InputDecoration(
                  labelText: 'PIN (4–6 digits) *',
                  prefixIcon: const Icon(Icons.pin_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePin
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () =>
                        setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
                keyboardType: TextInputType.number,
                obscureText: _obscurePin,
                maxLength: 6,
                validator: (v) {
                  if (v == null || v.trim().length < 4) {
                    return 'Minimum 4 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Role *',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                items: AppUser.roles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _roleColor(role),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(role),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedRole = v!),
              ),
              const SizedBox(height: 8),
              _RolePermissionHint(role: _selectedRole),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create User'),
        ),
      ],
    );
  }
}

// ─── Role Permission Hint widget ─────────────────────────────────────────────

class _RolePermissionHint extends StatelessWidget {
  final String role;
  const _RolePermissionHint({required this.role});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<String>> permissions = {
      'ADMIN': [
        'Full access to all features',
        'Lock/unlock financial years',
        'Manage users',
        'All voucher entry',
      ],
      'CA': [
        'Lock/unlock financial years',
        'All voucher entry',
        'View all reports',
      ],
      'ACCOUNTANT': [
        'All voucher entry (Sales, Purchase, Payment)',
        'View reports',
        'Cannot lock periods',
      ],
      'MANAGER': [
        'View-only access to reports',
        'Cannot create vouchers',
        'Cannot lock periods',
      ],
    };

    final perms = permissions[role] ?? [];
    final color = _roleColor(role);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Permissions:',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          const SizedBox(height: 4),
          ...perms.map((p) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 12, color: color),
                    const SizedBox(width: 4),
                    Expanded(
                        child: Text(p,
                            style: const TextStyle(fontSize: 11))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
