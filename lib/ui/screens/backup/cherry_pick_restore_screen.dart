import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../../data/models/item.dart';
import '../../../data/models/party.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';

class CherryPickRestoreScreen extends ConsumerStatefulWidget {
  final File backupDbFile;
  final String backupName;

  const CherryPickRestoreScreen({
    super.key,
    required this.backupDbFile,
    required this.backupName,
  });

  @override
  ConsumerState<CherryPickRestoreScreen> createState() => _CherryPickRestoreScreenState();
}

class _CherryPickRestoreScreenState extends ConsumerState<CherryPickRestoreScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Database? _backupDb;
  bool _isLoading = true;

  final List<CompareItem> _compareItems = [];
  final List<CompareParty> _compareParties = [];

  final Set<String> _selectedItemIds = {};
  final Set<String> _selectedPartyIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeComparison();
  }

  Future<void> _initializeComparison() async {
    try {
      // 1. Open the backup DB read-only
      _backupDb = await openDatabase(widget.backupDbFile.path, readOnly: true);

      // 2. Fetch current items and parties
      final currentItems = ref.read(itemProvider).value ?? [];
      final currentParties = ref.read(partyProvider).value ?? [];

      // 3. Query backup items
      final List<Map<String, dynamic>> backupItemMaps = await _backupDb!.query('items');
      final List<Item> backupItems = backupItemMaps.map((m) => Item.fromMap(m)).toList();

      for (final backupItem in backupItems) {
        // Find matching item in current DB
        final match = currentItems.where((e) => e.item.id == backupItem.id);
        
        final bool exists = match.isNotEmpty;
        final bool hasDifferences = exists && 
            (match.first.item.name != backupItem.name || 
             match.first.item.gstRate != backupItem.gstRate || 
             match.first.item.lowStockThreshold != backupItem.lowStockThreshold ||
             match.first.item.isDeleted != backupItem.isDeleted);

        _compareItems.add(CompareItem(
          item: backupItem,
          existsInCurrent: exists,
          hasDifferences: hasDifferences,
          currentRecord: exists ? match.first.item : null,
        ));
      }

      // 4. Query backup parties
      final List<Map<String, dynamic>> backupPartyMaps = await _backupDb!.query('parties');
      final List<Party> backupParties = backupPartyMaps.map((m) => Party.fromMap(m)).toList();

      for (final backupParty in backupParties) {
        final match = currentParties.where((e) => e.party.id == backupParty.id);

        final bool exists = match.isNotEmpty;
        final bool hasDifferences = exists &&
            (match.first.party.name != backupParty.name ||
             match.first.party.phone != backupParty.phone ||
             match.first.party.address != backupParty.address ||
             match.first.party.isDeleted != backupParty.isDeleted);

        _compareParties.add(CompareParty(
          party: backupParty,
          existsInCurrent: exists,
          hasDifferences: hasDifferences,
          currentRecord: exists ? match.first.party : null,
        ));
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load backup: ${e.toString()}'), backgroundColor: Colors.red),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _closeBackupDb();
    super.dispose();
  }

  Future<void> _closeBackupDb() async {
    final db = _backupDb;
    if (db != null) {
      await db.close();
      _backupDb = null;
    }
    // Delete local temp file
    if (await widget.backupDbFile.exists()) {
      await widget.backupDbFile.delete();
    }
  }

  Future<void> _performRestore() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final itemRepo = ref.read(itemRepositoryProvider);
      final partyRepo = ref.read(partyRepositoryProvider);

      // Restore selected items
      int restoredItemsCount = 0;
      for (final comp in _compareItems) {
        if (_selectedItemIds.contains(comp.item.id)) {
          // If it exists in current, update; else insert
          if (comp.existsInCurrent) {
            await itemRepo.updateItem(comp.item, 'cherry-pick-restore');
          } else {
            await itemRepo.insertItem(comp.item, 'cherry-pick-restore');
          }
          restoredItemsCount++;
        }
      }

      // Restore selected parties
      int restoredPartiesCount = 0;
      for (final comp in _compareParties) {
        if (_selectedPartyIds.contains(comp.party.id)) {
          if (comp.existsInCurrent) {
            await partyRepo.updateParty(comp.party, 'cherry-pick-restore');
          } else {
            await partyRepo.insertParty(comp.party, 'cherry-pick-restore');
          }
          restoredPartiesCount++;
        }
      }

      // Refresh Riverpod state
      ref.read(itemProvider.notifier).loadItems();
      ref.read(partyProvider.notifier).loadParties();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restored $restoredItemsCount items and $restoredPartiesCount parties successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restore failed: ${e.toString()}'), backgroundColor: Colors.red),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cherry-pick Restore'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Items / సరుకులు'),
            Tab(text: 'Parties / ఖాతాదారులు'),
          ],
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: (_selectedItemIds.isEmpty && _selectedPartyIds.isEmpty)
                  ? null
                  : _performRestore,
              child: const Text(
                'RESTORE',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildItemsComparisonList(theme),
                _buildPartiesComparisonList(theme),
              ],
            ),
    );
  }

  Widget _buildItemsComparisonList(ThemeData theme) {
    if (_compareItems.isEmpty) {
      return const Center(child: Text('No items found in this backup.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _compareItems.length,
      itemBuilder: (context, index) {
        final comp = _compareItems[index];
        final item = comp.item;
        final isSelected = _selectedItemIds.contains(item.id);

        Color statusColor = Colors.green;
        String statusText = 'New (Missing in Current)';
        if (comp.existsInCurrent) {
          if (comp.hasDifferences) {
            statusColor = Colors.orange.shade800;
            statusText = 'Modified (Has differences)';
          } else {
            statusColor = Colors.grey;
            statusText = 'Identical (No changes)';
          }
        }

        return Card(
          child: CheckboxListTile(
            value: isSelected,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedItemIds.add(item.id);
                } else {
                  _selectedItemIds.remove(item.id);
                }
              });
            },
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Category: ${item.category} | HSN: ${item.hsnCode}'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartiesComparisonList(ThemeData theme) {
    if (_compareParties.isEmpty) {
      return const Center(child: Text('No parties found in this backup.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _compareParties.length,
      itemBuilder: (context, index) {
        final comp = _compareParties[index];
        final party = comp.party;
        final isSelected = _selectedPartyIds.contains(party.id);

        Color statusColor = Colors.green;
        String statusText = 'New (Missing in Current)';
        if (comp.existsInCurrent) {
          if (comp.hasDifferences) {
            statusColor = Colors.orange.shade800;
            statusText = 'Modified (Has differences)';
          } else {
            statusColor = Colors.grey;
            statusText = 'Identical (No changes)';
          }
        }

        return Card(
          child: CheckboxListTile(
            value: isSelected,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedPartyIds.add(party.id);
                } else {
                  _selectedPartyIds.remove(party.id);
                }
              });
            },
            title: Text(party.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Type: ${party.type} | Phone: ${party.phone}'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CompareItem {
  final Item item;
  final bool existsInCurrent;
  final bool hasDifferences;
  final Item? currentRecord;

  CompareItem({
    required this.item,
    required this.existsInCurrent,
    required this.hasDifferences,
    this.currentRecord,
  });
}

class CompareParty {
  final Party party;
  final bool existsInCurrent;
  final bool hasDifferences;
  final Party? currentRecord;

  CompareParty({
    required this.party,
    required this.existsInCurrent,
    required this.hasDifferences,
    this.currentRecord,
  });
}
