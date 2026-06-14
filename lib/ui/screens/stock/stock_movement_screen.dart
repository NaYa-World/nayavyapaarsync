import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/item.dart';
import '../../../data/repositories/item_repository.dart';
import '../../../providers/item_provider.dart';
import '../../widgets/unit_display.dart';
// We could push to view invoices if we want, but simple details suffice.

class StockMovementScreen extends ConsumerStatefulWidget {
  final Item item;

  const StockMovementScreen({super.key, required this.item});

  @override
  ConsumerState<StockMovementScreen> createState() => _StockMovementScreenState();
}

class _StockMovementScreenState extends ConsumerState<StockMovementScreen> {
  late Future<List<StockMovement>> _movementFuture;

  @override
  void initState() {
    super.initState();
    _refreshMovements();
  }

  void _refreshMovements() {
    setState(() {
      _movementFuture = ref.read(itemRepositoryProvider).getItemMovementHistory(widget.item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshMovements,
          ),
        ],
      ),
      body: FutureBuilder<List<StockMovement>>(
        future: _movementFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error loading history: ${snapshot.error.toString()}'));
          }

          final movements = snapshot.data ?? [];

          if (movements.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  Text(
                    'No stock movements recorded.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            );
          }

          // Outstanding stock heading
          final double currentStock = movements.first.runningStock;

          return Column(
            children: [
              // Header Summary Card
              Card(
                margin: const EdgeInsets.all(16),
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                        foregroundColor: theme.colorScheme.primary,
                        radius: 28,
                        child: const Icon(Icons.inventory_rounded, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Stock on Hand',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            UnitDisplay(
                              qty: currentStock,
                              unit: widget.item.primaryUnit,
                              bagWeightKg: widget.item.bagWeightKg,
                              boxWeightKg: widget.item.boxWeightKg,
                              primaryStyle: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Ledger List Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'STOCK MOVEMENT HISTORY (NEWEST FIRST)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ),

              // Movements Timeline List
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final mv = movements[index];
                    final isPurchase = mv.type == 'PURCHASE';
                    final color = isPurchase ? Colors.green : Colors.orange.shade800;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Icon indicator
                            CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.1),
                              foregroundColor: color,
                              radius: 18,
                              child: Icon(
                                isPurchase ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mv.partyName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${mv.invoiceNo} | ${DateFormat('dd-MMM-yyyy').format(mv.date)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  Text(
                                    'Rate: ${IndianFormatUtils.formatCurrency(mv.rate)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quantities
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Flow Quantity
                                Text(
                                  '${isPurchase ? '+' : ''}${IndianFormatUtils.formatNumber(mv.qty)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Running Stock
                                Text(
                                  'Bal: ${IndianFormatUtils.formatNumber(mv.runningStock)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
