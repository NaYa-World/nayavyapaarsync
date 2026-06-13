import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/utils/indian_format.dart';
import '../../../data/models/item.dart';
import '../../../providers/item_provider.dart';
import '../../widgets/unit_display.dart';
import 'stock_movement_screen.dart';

class StockRegisterScreen extends ConsumerStatefulWidget {
  const StockRegisterScreen({super.key});

  @override
  ConsumerState<StockRegisterScreen> createState() => _StockRegisterScreenState();
}

class _StockRegisterScreenState extends ConsumerState<StockRegisterScreen> {
  String _searchQuery = '';

  void _showItemDialog([ItemWithStock? itemWithStock]) {
    showDialog(
      context: context,
      builder: (context) => ItemFormDialog(itemWithStock: itemWithStock),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsState = ref.watch(itemProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Register / సరుకు నిల్వలు'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add New Item',
            onPressed: () => _showItemDialog(),
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
                hintText: 'Search items by name or HSN...',
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

          // Items List
          Expanded(
            child: itemsState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: ${err.toString()}')),
              data: (items) {
                final filtered = items.where((i) {
                  final q = _searchQuery.toLowerCase();
                  return i.item.name.toLowerCase().contains(q) ||
                      i.item.hsnCode.contains(q) ||
                      i.item.category.toLowerCase().contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No items in inventory.' : 'No matching items found.',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final itemWithStock = filtered[index];
                    final item = itemWithStock.item;
                    final isLowStock = itemWithStock.currentStock <= item.lowStockThreshold;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StockMovementScreen(item: item),
                            ),
                          );
                        },
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isLowStock)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LOW STOCK',
                                  style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Category: ${item.category} | HSN: ${item.hsnCode} | GST: ${item.gstRate.toInt()}%',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8)),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Stock quantity and weight equivalent
                            UnitDisplay(
                              qty: itemWithStock.currentStock,
                              unit: item.primaryUnit,
                              bagWeightKg: item.bagWeightKg,
                              boxWeightKg: item.boxWeightKg,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              primaryStyle: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isLowStock ? Colors.red : theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Quick Action Options
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  _showItemDialog(itemWithStock);
                                } else if (action == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Item'),
                                      content: Text('Are you sure you want to delete "${item.name}"? It will be moved to the recycle bin.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await ref.read(itemProvider.notifier).deleteItem(item.id);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Item deleted successfully.')),
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
                          ],
                        ),
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
}

class ItemFormDialog extends ConsumerStatefulWidget {
  final ItemWithStock? itemWithStock;
  final String? preselectedCategory;

  const ItemFormDialog({super.key, this.itemWithStock, this.preselectedCategory});

  @override
  ConsumerState<ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends ConsumerState<ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hsnController = TextEditingController();
  final _thresholdController = TextEditingController(text: '10.0');
  final _weightController = TextEditingController();
  
  String _category = 'SEED';
  double _gstRate = 0.0;
  String _unit = 'BAG';
  bool _isBrandedSeed = false;

  @override
  void initState() {
    super.initState();
    if (widget.itemWithStock != null) {
      final item = widget.itemWithStock!.item;
      _nameController.text = item.name;
      _hsnController.text = item.hsnCode;
      _thresholdController.text = item.lowStockThreshold.toString();
      _category = item.category;
      _gstRate = item.gstRate;
      _unit = item.primaryUnit;
      
      final double? weight = _unit == 'BAG' ? item.bagWeightKg : item.boxWeightKg;
      _weightController.text = weight != null ? weight.toString() : '';
      
      if (_category == 'SEED' && _gstRate == 5.0) {
        _isBrandedSeed = true;
      }
    } else if (widget.preselectedCategory != null) {
      _category = widget.preselectedCategory!;
      if (_category == 'SEED') {
        _gstRate = 0.0;
      } else {
        _gstRate = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hsnController.dispose();
    _thresholdController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _onCategoryChanged(String? val) {
    if (val == null) return;
    setState(() {
      _category = val;
      // Recalculate default GST rate
      if (_category == 'FERTILISER') {
        _gstRate = 0.0;
      } else {
        _gstRate = _isBrandedSeed ? 5.0 : 0.0;
      }
    });
  }

  void _onBrandedChanged(bool? val) {
    if (val == null) return;
    setState(() {
      _isBrandedSeed = val;
      if (_category == 'SEED') {
        _gstRate = _isBrandedSeed ? 5.0 : 0.0;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final double? weight = double.tryParse(_weightController.text.trim());

    final item = Item(
      id: widget.itemWithStock?.item.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      category: _category,
      hsnCode: _hsnController.text.trim(),
      gstRate: _gstRate,
      primaryUnit: _unit,
      bagWeightKg: _unit == 'BAG' ? weight : null,
      boxWeightKg: _unit == 'BOX' ? weight : null,
      lowStockThreshold: double.tryParse(_thresholdController.text.trim()) ?? 10.0,
      createdAt: widget.itemWithStock?.item.createdAt ?? DateTime.now(),
      isDeleted: widget.itemWithStock?.item.isDeleted ?? false,
    );

    if (widget.itemWithStock != null) {
      await ref.read(itemProvider.notifier).editItem(item);
    } else {
      await ref.read(itemProvider.notifier).addItem(item);
    }

    if (mounted) {
      Navigator.pop(context, item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.itemWithStock != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Item Details' : 'Add New Item'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name / సరుకు పేరు *'),
                validator: (val) => val == null || val.trim().isEmpty ? 'Name is mandatory' : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category / విభాగం'),
                items: const [
                  DropdownMenuItem(value: 'SEED', child: Text('SEED (విత్తనాలు)')),
                  DropdownMenuItem(value: 'FERTILISER', child: Text('FERTILISER (ఎరువులు)')),
                ],
                onChanged: widget.preselectedCategory != null ? null : _onCategoryChanged,
              ),
              const SizedBox(height: 12),

              if (_category == 'SEED') ...[
                CheckboxListTile(
                  title: const Text('Is Branded Seed?'),
                  subtitle: const Text('Branded seeds attract 5% GST, unbranded are 0% (exempt).'),
                  value: _isBrandedSeed,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: _onBrandedChanged,
                ),
                const SizedBox(height: 12),
              ],

              DropdownButtonFormField<double>(
                value: _gstRate,
                decoration: const InputDecoration(labelText: 'GST Rate (%)'),
                items: const [
                  DropdownMenuItem(value: 0.0, child: Text('0% (Exempt)')),
                  DropdownMenuItem(value: 5.0, child: Text('5%')),
                  DropdownMenuItem(value: 12.0, child: Text('12%')),
                  DropdownMenuItem(value: 18.0, child: Text('18%')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _gstRate = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _hsnController,
                decoration: const InputDecoration(labelText: 'HSN Code / హెచ్.ఎస్.ఎన్ కోడ్ *'),
                validator: (val) => val == null || val.trim().isEmpty ? 'HSN Code is mandatory' : null,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _unit,
                decoration: const InputDecoration(labelText: 'Primary Unit / కొలమానం'),
                items: const [
                  DropdownMenuItem(value: 'BAG', child: Text('BAG (సంచి)')),
                  DropdownMenuItem(value: 'BOX', child: Text('BOX (పెట్టె)')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _unit = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _unit == 'BAG' ? 'Bag Weight (kg) / సంచి బరువు' : 'Box Weight (kg) / పెట్టె బరువు',
                  helperText: 'Optional. Used to compute total kg equivalent stock.',
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _thresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Low Stock Alarm Threshold'),
                validator: (val) => val == null || double.tryParse(val) == null ? 'Enter a valid threshold number' : null,
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
