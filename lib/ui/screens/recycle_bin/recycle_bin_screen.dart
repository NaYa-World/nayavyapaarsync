import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/database/db_helper.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/party_provider.dart';
import '../../../providers/transaction_provider.dart';

class RecycleBinItem {
  final String id;
  final String type; // 'ITEM', 'PARTY', 'PURCHASE', 'SALE', 'PAYMENT'
  final String title;
  final String subtitle;
  final DateTime deletedAt;

  RecycleBinItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
  });
}

class RecycleBinScreen extends ConsumerStatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  ConsumerState<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends ConsumerState<RecycleBinScreen> {
  late Future<List<RecycleBinItem>> _trashFuture;

  @override
  void initState() {
    super.initState();
    _refreshTrash();
  }

  void _refreshTrash() {
    setState(() {
      _trashFuture = _fetchTrashItems();
    });
  }

  Future<List<RecycleBinItem>> _fetchTrashItems() async {
    final db = await DbHelper().database;
    final List<RecycleBinItem> trash = [];

    // Query AuditLogs for recent DELETE operations to find deletion timestamps
    final List<Map<String, dynamic>> deleteLogs = await db.query(
      'audit_logs',
      where: "action = 'DELETE' AND timestamp >= ?",
      whereArgs: [DateTime.now().subtract(const Duration(days: 30)).toIso8601String()],
      orderBy: 'timestamp DESC',
    );

    // Helper map to avoid duplicates and store delete times
    final Map<String, DateTime> deleteTimes = {};
    for (final log in deleteLogs) {
      final String key = '${log['table_name']}_${log['record_id']}';
      if (!deleteTimes.containsKey(key)) {
        deleteTimes[key] = DateTime.parse(log['timestamp'] as String);
      }
    }

    // 1. Soft deleted Items
    final List<Map<String, dynamic>> items = await db.query('items', where: 'is_deleted = 1');
    for (final row in items) {
      final id = row['id'] as String;
      final deleteTime = deleteTimes['items_$id'] ?? DateTime.now();
      trash.add(RecycleBinItem(
        id: id,
        type: 'ITEM',
        title: 'Item: ${row['name']}',
        subtitle: 'HSN: ${row['hsn_code']} | Unit: ${row['primary_unit']}',
        deletedAt: deleteTime,
      ));
    }

    // 2. Soft deleted Parties
    final List<Map<String, dynamic>> parties = await db.query('parties', where: 'is_deleted = 1');
    for (final row in parties) {
      final id = row['id'] as String;
      final deleteTime = deleteTimes['parties_$id'] ?? DateTime.now();
      trash.add(RecycleBinItem(
        id: id,
        type: 'PARTY',
        title: '${row['type'] == 'CUSTOMER' ? 'Customer' : 'Supplier'}: ${row['name']}',
        subtitle: 'Phone: ${row['phone']} | Address: ${row['address']}',
        deletedAt: deleteTime,
      ));
    }

    // 3. Soft deleted Purchases
    final List<Map<String, dynamic>> purchases = await db.query('purchases', where: 'is_deleted = 1');
    for (final row in purchases) {
      final id = row['id'] as String;
      final deleteTime = deleteTimes['purchases_$id'] ?? DateTime.now();
      trash.add(RecycleBinItem(
        id: id,
        type: 'PURCHASE',
        title: 'Purchase Invoice: ${row['invoice_no']}',
        subtitle: 'Total: Rs ${row['grand_total']} | Date: ${row['date'].toString().substring(0, 10)}',
        deletedAt: deleteTime,
      ));
    }

    // 4. Soft deleted Sales
    final List<Map<String, dynamic>> sales = await db.query('sales', where: 'is_deleted = 1');
    for (final row in sales) {
      final id = row['id'] as String;
      final deleteTime = deleteTimes['sales_$id'] ?? DateTime.now();
      trash.add(RecycleBinItem(
        id: id,
        type: 'SALE',
        title: 'Sale Invoice: ${row['invoice_no']}',
        subtitle: 'Total: Rs ${row['grand_total']} | Date: ${row['date'].toString().substring(0, 10)}',
        deletedAt: deleteTime,
      ));
    }

    // 5. Soft deleted Payments
    final List<Map<String, dynamic>> payments = await db.query('payments', where: 'is_deleted = 1');
    for (final row in payments) {
      final id = row['id'] as String;
      final deleteTime = deleteTimes['payments_$id'] ?? DateTime.now();
      trash.add(RecycleBinItem(
        id: id,
        type: 'PAYMENT',
        title: 'Payment: Rs ${row['amount']} (${row['direction']})',
        subtitle: 'Mode: ${row['mode']} | Date: ${row['date'].toString().substring(0, 10)}',
        deletedAt: deleteTime,
      ));
    }

    // Sort newest deletions first
    trash.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return trash;
  }

  Future<void> _restore(RecycleBinItem item) async {
    final db = await DbHelper().database;
    String tableName = '';
    
    switch (item.type) {
      case 'ITEM':
        tableName = 'items';
        break;
      case 'PARTY':
        tableName = 'parties';
        break;
      case 'PURCHASE':
        tableName = 'purchases';
        break;
      case 'SALE':
        tableName = 'sales';
        break;
      case 'PAYMENT':
        tableName = 'payments';
        break;
    }

    await db.transaction((txn) async {
      await txn.update(
        tableName,
        {'is_deleted': 0},
        where: 'id = ?',
        whereArgs: [item.id],
      );
      
      // Also log restore to sync queue and audit log
      // We will refresh our Riverpod providers to update their cache
    });

    // Refresh Riverpod caches
    ref.read(itemProvider.notifier).loadItems();
    ref.read(partyProvider.notifier).loadParties();
    ref.read(transactionProvider.notifier).loadAllTransactions();

    _refreshTrash();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${item.title}" restored successfully!'), backgroundColor: Colors.green),
    );
  }

  Future<void> _purge(RecycleBinItem item) async {
    final db = await DbHelper().database;
    String tableName = '';
    String itemsTableName = '';
    String foreignKey = '';
    
    switch (item.type) {
      case 'ITEM':
        tableName = 'items';
        break;
      case 'PARTY':
        tableName = 'parties';
        break;
      case 'PURCHASE':
        tableName = 'purchases';
        itemsTableName = 'purchase_items';
        foreignKey = 'purchase_id';
        break;
      case 'SALE':
        tableName = 'sales';
        itemsTableName = 'sale_items';
        foreignKey = 'sale_id';
        break;
      case 'PAYMENT':
        tableName = 'payments';
        break;
    }

    await db.transaction((txn) async {
      // If purchase or sale, first delete associated items
      if (itemsTableName.isNotEmpty) {
        await txn.delete(
          itemsTableName,
          where: '$foreignKey = ?',
          whereArgs: [item.id],
        );
      }
      
      // Delete primary record
      await txn.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    });

    _refreshTrash();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Record permanently deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin / రీసైకిల్ బిన్'),
      ),
      body: FutureBuilder<List<RecycleBinItem>>(
        future: _trashFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading trash: ${snapshot.error}'));
          }

          final list = snapshot.data ?? [];

          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'Recycle bin is empty.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'Deleted items are kept here for 30 days before being permanently purged.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final dateStr = DateFormat('dd-MMM-yyyy HH:mm').format(item.deletedAt);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.errorContainer.withOpacity(0.5),
                        foregroundColor: theme.colorScheme.error,
                        child: const Icon(Icons.delete_rounded),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(item.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('Deleted: $dateStr', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.settings_backup_restore_rounded, color: Colors.green),
                            tooltip: 'Restore',
                            onPressed: () => _restore(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                            tooltip: 'Delete Permanently',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Permanently'),
                                  content: Text('Are you sure you want to permanently delete "${item.title}"? This action CANNOT be undone.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete Forever')),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await _purge(item);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
