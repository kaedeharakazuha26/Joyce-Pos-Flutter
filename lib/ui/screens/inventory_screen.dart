import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';

class InventoryScreen extends StatefulWidget {
  final AppState appState;

  const InventoryScreen({super.key, required this.appState});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _view = 'stock'; // 'stock' | 'history'
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _restocks = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _products = widget.appState.repo.listProducts();
      _restocks = widget.appState.repo.listRestocks();
    });
  }

  void _openRestockModal(Map<String, dynamic> product) {
    final qtyCtrl = TextEditingController(text: '10');
    final costCtrl = TextEditingController(
      text: ((product['cost'] as num?) ?? 0).toStringAsFixed(2),
    );
    final noteCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restock — ${product['name']}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity Added (Base Units) *',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'New Unit Cost (₱, >0 updates product cost)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Supplier / Delivery Note',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          JoyceButton(
            label: 'Confirm Restock',
            icon: Icons.add_box_outlined,
            onPressed: () {
              try {
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                widget.appState.repo.restock(
                  productId: product['id'] as int,
                  qty: qty,
                  unitCost: cost,
                  note: noteCtrl.text.trim(),
                  actor: widget.appState.currentUserName,
                  role: widget.appState.currentUserRole,
                );
                Navigator.of(ctx).pop();
                _reload();
                widget.appState.refreshAll();
                showJoyceToast(
                  context,
                  'Restocked +$qty ${product['name']}',
                );
              } catch (e) {
                showJoyceToast(
                  context,
                  e.toString().replaceFirst('Exception: ', ''),
                  isError: true,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Stock & Restock',
          subtitle:
              'Monitor stock health and record incoming inventory deliveries',
          actions: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'stock',
                  label: Text('Stock Levels (${_products.length})'),
                ),
                ButtonSegment(
                  value: 'history',
                  label: Text('Restock History (${_restocks.length})'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ],
        ),
        Expanded(
          child: JoyceCard(
            padding: const EdgeInsets.all(12),
            child: _view == 'stock'
                ? ListView.separated(
                    itemCount: _products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final p = _products[i];
                      final stock = (p['stock'] as num).toInt();
                      final low = (p['low_stock'] as num?)?.toInt() ?? 5;
                      final isOut = stock <= 0;
                      final isLow = stock > 0 && stock <= low;
                      return ListTile(
                        title: Text(
                          p['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Category: ${(p['category'] as String).isEmpty ? "General" : p['category']} • Unit Cost: ${formatPeso(p['cost'] as num)} • Low Alert: ≤$low',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: (isOut
                                        ? c.bad
                                        : (isLow ? c.warn : c.ok))
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isOut
                                    ? 'OUT ($stock)'
                                    : (isLow
                                        ? 'LOW ($stock)'
                                        : 'HEALTHY ($stock)'),
                                style: TextStyle(
                                  color: isOut
                                      ? c.bad
                                      : (isLow ? c.warn : c.ok),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            JoyceButton(
                              label: 'Restock',
                              icon: Icons.add,
                              compact: true,
                              onPressed: () => _openRestockModal(p),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : _restocks.isEmpty
                    ? const EmptyState(
                        icon: Icons.history,
                        title: 'No restock entries yet',
                      )
                    : ListView.separated(
                        itemCount: _restocks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = _restocks[i];
                          return ListTile(
                            title: Text(
                              '+${r['qty']} ${r['product_name']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${r['created_at']} • Note: ${(r['note'] as String).isEmpty ? "—" : r['note']}',
                              style: TextStyle(color: c.muted, fontSize: 12),
                            ),
                            trailing: Text(
                              'Unit Cost: ${formatPeso((r['unit_cost'] as num?) ?? 0)}',
                              style: TextStyle(
                                color: c.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}
