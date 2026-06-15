import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/company.dart';
import '../../../data/models/financial_year.dart';
import '../../../providers/company_provider.dart';

class CompanyListScreen extends ConsumerStatefulWidget {
  const CompanyListScreen({super.key});

  @override
  ConsumerState<CompanyListScreen> createState() => _CompanyListScreenState();
}

class _CompanyListScreenState extends ConsumerState<CompanyListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Companies & Financial Years'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.business_rounded), text: 'Companies'),
            Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Financial Years'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CompaniesTab(),
          _FinancialYearsTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Tab 1 — Companies
// ═══════════════════════════════════════════════════

class _CompaniesTab extends ConsumerWidget {
  const _CompaniesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companyProvider);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (companies) => companies.isEmpty
          ? _buildEmpty(context, ref)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: companies.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _CompanyCard(company: companies[i]),
            ),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No companies added yet'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showCompanyDialog(context, ref, null),
            icon: const Icon(Icons.add),
            label: const Text('Add Company'),
          ),
        ],
      ),
    );
  }
}

class _CompanyCard extends ConsumerWidget {
  final Company company;
  const _CompanyCard({required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          child: Text(company.name[0].toUpperCase()),
        ),
        title: Text(company.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(company.gstin ?? 'No GSTIN • ${company.state}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _showCompanyDialog(context, ref, company),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              onPressed: () => _confirmDelete(context, ref, company),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Company c) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Company?'),
        content: Text('Remove "${c.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref.read(companyProvider.notifier).deleteCompany(c.id);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

void _showCompanyDialog(
    BuildContext context, WidgetRef ref, Company? existing) {
  showDialog(
    context: context,
    builder: (_) => _CompanyFormDialog(existing: existing, ref: ref),
  );
}

class _CompanyFormDialog extends StatefulWidget {
  final Company? existing;
  final WidgetRef ref;
  const _CompanyFormDialog({required this.existing, required this.ref});

  @override
  State<_CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyFormDialogState extends State<_CompanyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _gstin;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _gstin = TextEditingController(text: widget.existing?.gstin ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _address = TextEditingController(text: widget.existing?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _gstin.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final company = Company(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      gstin: _gstin.text.trim().isEmpty ? null : _gstin.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    await widget.ref.read(companyProvider.notifier).saveCompany(company);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Company' : 'Edit Company'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Company Name *',
                    prefixIcon: Icon(Icons.business_rounded)),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gstin,
                decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    prefixIcon: Icon(Icons.receipt_long_rounded)),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_rounded)),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_rounded)),
                maxLines: 2,
              ),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// Tab 2 — Financial Years
// ═══════════════════════════════════════════════════

class _FinancialYearsTab extends ConsumerWidget {
  const _FinancialYearsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesState = ref.watch(companyProvider);
    final fyState = ref.watch(financialYearProvider);

    return companiesState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (companies) {
        if (companies.isEmpty) {
          return const Center(
            child: Text('Add a company first to manage financial years.'),
          );
        }

        // Use first company by default (future: company switcher)
        final company = companies.first;

        // Load FYs for this company if not loaded yet
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(financialYearProvider.notifier)
              .loadForCompany(company.id);
        });

        return fyState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (fys) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        company.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          _showAddFYDialog(context, ref, company.id),
                      icon: const Icon(Icons.add),
                      label: const Text('Add FY'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: fys.isEmpty
                    ? const Center(child: Text('No financial years added.'))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: fys.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) =>
                            _FYCard(fy: fys[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddFYDialog(
      BuildContext context, WidgetRef ref, String companyId) {
    showDialog(
      context: context,
      builder: (_) => _FYFormDialog(companyId: companyId, ref: ref),
    );
  }
}

class _FYCard extends ConsumerWidget {
  final FinancialYear fy;
  const _FYCard({required this.fy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd-MMM-yyyy');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: fy.isLocked
              ? Colors.red.withValues(alpha: 0.12)
              : Colors.green.withValues(alpha: 0.12),
          foregroundColor: fy.isLocked ? Colors.red : Colors.green,
          child: Icon(
              fy.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded),
        ),
        title: Text(fy.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${fmt.format(fy.startDate)} → ${fmt.format(fy.endDate)}'),
        trailing: fy.isLocked
            ? TextButton.icon(
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: const Text('Unlock'),
                onPressed: () => _toggleLock(context, ref),
              )
            : TextButton.icon(
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: const Text('Lock'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => _toggleLock(context, ref),
              ),
      ),
    );
  }

  void _toggleLock(BuildContext context, WidgetRef ref) {
    final action = fy.isLocked ? 'unlock' : 'lock';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${fy.isLocked ? 'Unlock' : 'Lock'} Period?'),
        content: Text(
            'Are you sure you want to $action "${fy.label}"?\n\n'
            '${fy.isLocked ? 'This will allow new entries in this period.' : 'No new vouchers can be added to this period.'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: fy.isLocked ? Colors.green : Colors.red),
            onPressed: () {
              if (fy.isLocked) {
                ref.read(financialYearProvider.notifier).unlockFY(fy.id);
              } else {
                ref
                    .read(financialYearProvider.notifier)
                    .lockFY(fy.id, 'local_admin');
              }
              Navigator.pop(context);
            },
            child: Text(fy.isLocked ? 'Unlock' : 'Lock'),
          ),
        ],
      ),
    );
  }
}

class _FYFormDialog extends StatefulWidget {
  final String companyId;
  final WidgetRef ref;
  const _FYFormDialog({required this.companyId, required this.ref});

  @override
  State<_FYFormDialog> createState() => _FYFormDialogState();
}

class _FYFormDialogState extends State<_FYFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _startDate;
  late final TextEditingController _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final fyStart = now.month >= 4
        ? DateTime(now.year, 4, 1)
        : DateTime(now.year - 1, 4, 1);
    final fyEnd = DateTime(fyStart.year + 1, 3, 31);
    final fyYear1 = fyStart.year.toString().substring(2);
    final fyYear2 = fyEnd.year.toString().substring(2);
    _label = TextEditingController(text: 'FY $fyYear1-$fyYear2');
    _startDate = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(fyStart));
    _endDate =
        TextEditingController(text: DateFormat('yyyy-MM-dd').format(fyEnd));
  }

  @override
  void dispose() {
    _label.dispose();
    _startDate.dispose();
    _endDate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final fy = FinancialYear(
      id: const Uuid().v4(),
      companyId: widget.companyId,
      label: _label.text.trim(),
      startDate: DateTime.parse(_startDate.text.trim()),
      endDate: DateTime.parse(_endDate.text.trim()),
    );
    await widget.ref
        .read(financialYearProvider.notifier)
        .saveFinancialYear(fy);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Financial Year'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label *'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _startDate,
                decoration:
                    const InputDecoration(labelText: 'Start Date (yyyy-MM-dd) *'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  try {
                    DateTime.parse(v.trim());
                    return null;
                  } catch (_) {
                    return 'Invalid date';
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _endDate,
                decoration:
                    const InputDecoration(labelText: 'End Date (yyyy-MM-dd) *'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  try {
                    DateTime.parse(v.trim());
                    return null;
                  } catch (_) {
                    return 'Invalid date';
                  }
                },
              ),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}
