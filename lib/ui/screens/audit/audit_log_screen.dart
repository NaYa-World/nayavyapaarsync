import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/database/db_helper.dart';

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  String _selectedAction = 'ALL'; // 'ALL', 'CREATE', 'EDIT', 'DELETE'
  String _selectedTable = 'ALL'; // 'ALL', 'items', 'parties', 'purchases', 'sales', 'payments', 'settings'

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() {
    setState(() {
      _logsFuture = _fetchAuditLogs();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchAuditLogs() async {
    final db = await DbHelper().database;
    String query = 'SELECT * FROM audit_logs';
    List<String> whereArgs = [];
    List<String> conditions = [];

    if (_selectedAction != 'ALL') {
      conditions.add('action = ?');
      whereArgs.add(_selectedAction);
    }

    if (_selectedTable != 'ALL') {
      conditions.add('table_name = ?');
      whereArgs.add(_selectedTable);
    }

    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }

    query += ' ORDER BY timestamp DESC';

    return await db.rawQuery(query, whereArgs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs / ఆడిట్ లాగ్స్'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter card
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedAction,
                      decoration: const InputDecoration(labelText: 'Action', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Actions')),
                        DropdownMenuItem(value: 'CREATE', child: Text('CREATE')),
                        DropdownMenuItem(value: 'EDIT', child: Text('EDIT')),
                        DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedAction = val;
                          });
                          _refreshLogs();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedTable,
                      decoration: const InputDecoration(labelText: 'Register', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Registers')),
                        DropdownMenuItem(value: 'items', child: Text('Items')),
                        DropdownMenuItem(value: 'parties', child: Text('Parties')),
                        DropdownMenuItem(value: 'purchases', child: Text('Purchases')),
                        DropdownMenuItem(value: 'sales', child: Text('Sales')),
                        DropdownMenuItem(value: 'payments', child: Text('Payments')),
                        DropdownMenuItem(value: 'settings', child: Text('Settings')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTable = val;
                          });
                          _refreshLogs();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Logs list
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _logsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final logs = snapshot.data ?? [];

                if (logs.isEmpty) {
                  return Center(
                    child: Text(
                      'No audit logs found.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final String action = log['action'] as String;
                    final DateTime time = DateTime.parse(log['timestamp'] as String);
                    
                    Color color = Colors.grey;
                    if (action == 'CREATE') color = Colors.green;
                    if (action == 'EDIT') color = Colors.blue;
                    if (action == 'DELETE') color = Colors.red;

                    return Card(
                      child: ExpansionTile(
                        leading: Chip(
                          label: Text(action, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                          backgroundColor: color,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        title: Text(
                          'Register: ${log['table_name']} (${log['record_id'].toString().substring(0, 8)}...)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Time: ${DateFormat('dd-MMM-yyyy HH:mm:ss').format(time)} | Device: ${log['device_id'].toString().substring(0, 8)}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _buildComparisonView(log, theme),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonView(Map<String, dynamic> log, ThemeData theme) {
    Map<String, dynamic> oldMap = {};
    Map<String, dynamic> newMap = {};

    try {
      if (log['old_values'] != null && (log['old_values'] as String).isNotEmpty) {
        oldMap = jsonDecode(log['old_values'] as String) as Map<String, dynamic>;
      }
      if (log['new_values'] != null && (log['new_values'] as String).isNotEmpty) {
        newMap = jsonDecode(log['new_values'] as String) as Map<String, dynamic>;
      }
    } catch (_) {}

    // Extract all unique keys
    final Set<String> keys = {...oldMap.keys, ...newMap.keys};
    final List<String> sortedKeys = keys.toList()..sort();

    if (sortedKeys.isEmpty) {
      return const Text('No data changes details to show.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic));
    }

    return Table(
      border: TableBorder.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.12), width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(1.2), // Key
        1: FlexColumnWidth(2.0), // Old
        2: FlexColumnWidth(2.0), // New
      },
      children: [
        // Table Header
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
          children: const [
            Padding(padding: EdgeInsets.all(6), child: Text('Field', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
            Padding(padding: EdgeInsets.all(6), child: Text('Old Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
            Padding(padding: EdgeInsets.all(6), child: Text('New Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
          ],
        ),
        // Table Data Rows
        ...sortedKeys.map((key) {
          final oldVal = oldMap[key]?.toString() ?? '-';
          final newVal = newMap[key]?.toString() ?? '-';
          final isChanged = oldVal != newVal;

          return TableRow(
            decoration: isChanged ? BoxDecoration(color: Colors.amber.withValues(alpha: 0.06)) : null,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: isChanged ? theme.colorScheme.secondary : null)),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(oldVal, style: TextStyle(fontSize: 9, decoration: isChanged ? TextDecoration.lineThrough : null, color: isChanged ? Colors.red.shade800 : null)),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(newVal, style: TextStyle(fontSize: 9, fontWeight: isChanged ? FontWeight.bold : null, color: isChanged ? Colors.green.shade800 : null)),
              ),
            ],
          );
        }),
      ],
    );
  }
}
