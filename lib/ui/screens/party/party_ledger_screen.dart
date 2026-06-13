import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../data/models/party.dart';
import '../../../providers/party_provider.dart';
import '../../widgets/party_balance_card.dart';
import 'party_statement_screen.dart';

class PartyLedgerScreen extends ConsumerStatefulWidget {
  const PartyLedgerScreen({super.key});

  @override
  ConsumerState<PartyLedgerScreen> createState() => _PartyLedgerScreenState();
}

class _PartyLedgerScreenState extends ConsumerState<PartyLedgerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

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

  void _showPartyDialog([PartyWithBalance? partyWithBal]) {
    showDialog(
      context: context,
      builder: (context) => PartyFormDialog(partyWithBal: partyWithBal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Party Ledger / ఖాతాల పుస్తకం'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Customers / కొనుగోలుదారులు'),
            Tab(text: 'Suppliers / అమ్మకందారులు'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: 'Add Party',
            onPressed: () => _showPartyDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search parties by name or phone...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
            ),
          ),

          // Tab Bar Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPartyList(ref.watch(customerProvider), theme),
                _buildPartyList(ref.watch(supplierProvider), theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartyList(List<PartyWithBalance> list, ThemeData theme) {
    final filtered = list.where((p) {
      final q = _searchQuery.toLowerCase();
      return p.party.name.toLowerCase().contains(q) ||
          p.party.phone.contains(q) ||
          (p.party.gstin != null && p.party.gstin!.toLowerCase().contains(q));
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No parties registered.' : 'No matching parties found.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final partyWithBal = filtered[index];
        final party = partyWithBal.party;

        return Stack(
          alignment: Alignment.centerRight,
          children: [
            PartyBalanceCard(
              party: party,
              balance: partyWithBal.outstandingBalance,
              balanceType: partyWithBal.balanceType,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PartyStatementScreen(party: party),
                  ),
                );
              },
            ),
            Positioned(
              right: 12,
              top: 6,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) async {
                  if (action == 'edit') {
                    _showPartyDialog(partyWithBal);
                  } else if (action == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Party'),
                        content: Text('Are you sure you want to delete "${party.name}"? It will be moved to the recycle bin.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await ref.read(partyProvider.notifier).deleteParty(party.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Party deleted successfully.')),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class PartyFormDialog extends ConsumerStatefulWidget {
  final PartyWithBalance? partyBal;
  final String? preselectedType;

  const PartyFormDialog({super.key, PartyWithBalance? partyWithBal, this.preselectedType}) : partyBal = partyWithBal;

  @override
  ConsumerState<PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends ConsumerState<PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstinController = TextEditingController();
  final _balanceController = TextEditingController(text: '0.0');

  String _type = 'CUSTOMER';
  String _balanceType = 'DR';

  @override
  void initState() {
    super.initState();
    if (widget.preselectedType != null) {
      _type = widget.preselectedType!;
      _balanceType = _type == 'CUSTOMER' ? 'DR' : 'CR';
    }
    if (widget.partyBal != null) {
      final p = widget.partyBal!.party;
      _nameController.text = p.name;
      _phoneController.text = p.phone;
      _addressController.text = p.address;
      _gstinController.text = p.gstin ?? '';
      _balanceController.text = p.openingBalance.toString();
      _type = p.type;
      _balanceType = p.balanceType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final party = Party(
      id: widget.partyBal?.party.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      type: _type,
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      gstin: _gstinController.text.trim().isEmpty ? null : _gstinController.text.trim(),
      openingBalance: double.tryParse(_balanceController.text.trim()) ?? 0.0,
      balanceType: _balanceType,
      createdAt: widget.partyBal?.party.createdAt ?? DateTime.now(),
      isDeleted: widget.partyBal?.party.isDeleted ?? false,
    );

    if (widget.partyBal != null) {
      await ref.read(partyProvider.notifier).editParty(party);
    } else {
      await ref.read(partyProvider.notifier).addParty(party);
    }

    if (mounted) {
      Navigator.pop(context, party);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.partyBal != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Account Details' : 'Register New Account'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Party Name / పేరు *'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Name is mandatory' : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Account Type / ఖాతా రకం'),
                items: const [
                  DropdownMenuItem(value: 'CUSTOMER', child: Text('CUSTOMER (కొనుగోలుదారు)')),
                  DropdownMenuItem(value: 'SUPPLIER', child: Text('SUPPLIER (అమ్మకందారు)')),
                ],
                onChanged: isEdit
                    ? null // Prevent altering type in edit mode to preserve double-entry sanity
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _type = val;
                            // Reset default balance types
                            _balanceType = _type == 'CUSTOMER' ? 'DR' : 'CR';
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number / ఫోన్ నంబర్ *'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Phone is mandatory' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address / చిరునామా *'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Address is mandatory' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _gstinController,
                decoration: const InputDecoration(labelText: 'GSTIN (Optional) / జి.ఎస్.టి.ఐ.ఎన్'),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Opening Balance (Rs) / ప్రారంభ నిల్వ'),
                enabled: !isEdit, // opening balance set only at registration
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter a valid opening balance' : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _balanceType,
                decoration: const InputDecoration(labelText: 'Balance Sign / నిల్వ గుర్తు'),
                items: const [
                  DropdownMenuItem(value: 'DR', child: Text('DR (Debit/Receivable)')),
                  DropdownMenuItem(value: 'CR', child: Text('CR (Credit/Payable)')),
                ],
                onChanged: isEdit
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _balanceType = val;
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
