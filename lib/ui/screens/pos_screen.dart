import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/barcode_scanner_service.dart';
import '../../core/utils/money.dart';
import '../../core/utils/receipt_builder.dart';
import '../widgets/joyce_widgets.dart';

class _CartLine {
  final int productId;
  final int? variantId;
  final String name;
  final String variantName;
  final int unitsPer;
  final double unitPrice;
  int quantity = 1;

  _CartLine({
    required this.productId,
    this.variantId,
    required this.name,
    this.variantName = '',
    this.unitsPer = 1,
    required this.unitPrice,
  });

  String get key => '$productId-${variantId ?? 0}';
  double get subtotal => r2(unitPrice * quantity);
}

class PosScreen extends StatefulWidget {
  final AppState appState;

  const PosScreen({super.key, required this.appState});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _paidCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  void Function()? _unsubScanner;

  List<Map<String, dynamic>> _products = [];
  String _selectedCategory = 'All';
  final List<_CartLine> _cart = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _unsubScanner =
        BarcodeScannerService.instance.subscribe(_handleBarcodeScanned);
  }

  @override
  void dispose() {
    _unsubScanner?.call();
    _searchCtrl.dispose();
    _paidCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _loadProducts() {
    setState(() {
      _products = widget.appState.repo.listProducts();
    });
  }

  int _remainingStockFor(int productId, int baseStock) {
    int usedUnits = 0;
    for (final line in _cart) {
      if (line.productId == productId) {
        usedUnits += line.unitsPer * line.quantity;
      }
    }
    return baseStock - usedUnits;
  }

  List<String> get _categories {
    final set = <String>{'All'};
    for (final p in _products) {
      final cat = (p['category'] as String? ?? '').trim();
      if (cat.isNotEmpty) set.add(cat);
    }
    return set.toList();
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      if (_selectedCategory != 'All' &&
          (p['category'] as String? ?? '').trim() != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      final name = (p['name'] as String? ?? '').toLowerCase();
      final bc = (p['barcode'] as String? ?? '').toLowerCase();
      final cat = (p['category'] as String? ?? '').toLowerCase();
      return name.contains(q) || bc.contains(q) || cat.contains(q);
    }).toList();
  }

  void _handleBarcodeScanned(String rawBarcode, {bool isSearchSubmit = false}) {
    final q = rawBarcode.trim().toLowerCase();
    if (q.isEmpty) return;

    // 1. Exact barcode match
    Map<String, dynamic>? match;
    for (final p in _products) {
      final bc = (p['barcode'] as String? ?? '').trim().toLowerCase();
      if (bc.isNotEmpty && bc == q) {
        match = p;
        break;
      }
    }

    // 2. Barcode match stripping non-alphanumeric (e.g. spaces/dashes)
    if (match == null) {
      final cleanQ = q.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      if (cleanQ.isNotEmpty) {
        for (final p in _products) {
          final bc = (p['barcode'] as String? ?? '')
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
              .toLowerCase();
          if (bc.isNotEmpty && bc == cleanQ) {
            match = p;
            break;
          }
        }
      }
    }

    // 3. Exact name match
    if (match == null) {
      for (final p in _products) {
        if ((p['name'] as String? ?? '').trim().toLowerCase() == q) {
          match = p;
          break;
        }
      }
    }

    // 4. Sole filtered result if manually typed into search
    if (match == null && isSearchSubmit) {
      final filtered = _products.where((p) {
        final name = (p['name'] as String? ?? '').toLowerCase();
        final bc = (p['barcode'] as String? ?? '').toLowerCase();
        return name.contains(q) || bc.contains(q);
      }).toList();
      if (filtered.length == 1) {
        match = filtered.first;
      }
    }

    if (match != null) {
      _onProductTap(match);
      _searchCtrl.clear();
      setState(() {});
      if (_searchFocus.canRequestFocus) {
        _searchFocus.requestFocus();
      }
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added "${match['name']}" to cart (${formatPeso(match['price'] as num)})',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() {
        _searchCtrl.text = rawBarcode.trim();
      });
      if (_searchFocus.canRequestFocus) {
        _searchFocus.requestFocus();
      }
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode "$rawBarcode" not found in store catalog.'),
          action: SnackBarAction(
            label: 'Clear',
            onPressed: () {
              _searchCtrl.clear();
              setState(() {});
            },
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleSearchEnter(String rawQuery) {
    _handleBarcodeScanned(rawQuery, isSearchSubmit: true);
  }

  void _onProductTap(Map<String, dynamic> product) {
    final variants = (product['variants'] as List? ?? const []);
    if (variants.isEmpty) {
      _addToCart(
        productId: product['id'] as int,
        name: product['name'] as String,
        unitPrice: (product['price'] as num).toDouble(),
      );
    } else {
      _showVariantPicker(product);
    }
  }

  void _addToCart({
    required int productId,
    int? variantId,
    required String name,
    String variantName = '',
    int unitsPer = 1,
    required double unitPrice,
  }) {
    final key = '$productId-${variantId ?? 0}';
    setState(() {
      final idx = _cart.indexWhere((c) => c.key == key);
      if (idx >= 0) {
        _cart[idx].quantity++;
      } else {
        _cart.add(
          _CartLine(
            productId: productId,
            variantId: variantId,
            name: name,
            variantName: variantName,
            unitsPer: unitsPer,
            unitPrice: unitPrice,
          ),
        );
      }
    });
  }

  void _showVariantPicker(Map<String, dynamic> product) {
    final variants = (product['variants'] as List).cast<Map<String, dynamic>>();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.joyce;
        return AlertDialog(
          title: Text('Select Option — ${product['name']}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: c.borderSubtle),
                  ),
                  title: const Text('1 pc (regular)'),
                  subtitle: const Text('Uses 1 from stock'),
                  trailing: Text(
                    formatPeso(product['price'] as num),
                    style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _addToCart(
                      productId: product['id'] as int,
                      name: product['name'] as String,
                      unitPrice: (product['price'] as num).toDouble(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                for (final v in variants) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: c.borderSubtle),
                    ),
                    title: Text(v['name'].toString()),
                    subtitle: Text('Uses ${v['qty']} from stock'),
                    trailing: Text(
                      formatPeso(v['price'] as num),
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _addToCart(
                        productId: product['id'] as int,
                        variantId: v['id'] as int,
                        name: product['name'] as String,
                        variantName: v['name'].toString(),
                        unitsPer: (v['qty'] as num).toInt(),
                        unitPrice: (v['price'] as num).toDouble(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  double get _cartTotal {
    double sum = 0.0;
    for (final line in _cart) {
      sum += line.subtotal;
    }
    return r2(sum);
  }

  double get _effectivePaid {
    final txt = _paidCtrl.text.trim();
    if (txt.isEmpty) return _cartTotal;
    return r2(double.tryParse(txt) ?? 0);
  }

  List<double> get _quickTenderOptions {
    final total = _cartTotal;
    if (total <= 0) return [];
    final candidates = <double>[total, 20, 50, 100, 200, 500, 1000];
    final unique = <double>[];
    for (final c in candidates) {
      if (c + 1e-9 >= total && !unique.any((u) => (u - c).abs() < 0.01)) {
        unique.add(c);
      }
    }
    return unique.take(5).toList();
  }

  Future<void> _completeCheckout() async {
    if (_cart.isEmpty) return;
    final total = _cartTotal;
    final paid = _effectivePaid;
    if (paid + 1e-9 < total) return;

    try {
      final payload = _cart
          .map((c) => {
                'product_id': c.productId,
                'variant_id': c.variantId,
                'quantity': c.quantity,
              })
          .toList();

      final sale = widget.appState.repo.createSale(
        items: payload,
        paid: paid,
        actor: widget.appState.currentUserName,
        role: widget.appState.currentUserRole,
      );

      setState(() {
        _cart.clear();
        _paidCtrl.clear();
      });
      _loadProducts();
      widget.appState.refreshAll();

      if (widget.appState.settings['auto_print'] == '1') {
        try {
          await widget.appState.printSaleReceipt(sale);
        } catch (_) {}
      }

      if (mounted) {
        _showSaleCompletedModal(sale);
      }
    } catch (e) {
      if (mounted) {
        showJoyceToast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  void _showSaleCompletedModal(Map<String, dynamic> sale) {
    final text = ReceiptBuilder.buildReceiptText(
      sale,
      widget.appState.settings,
    );
    final cols = ReceiptBuilder.resolveWidth(widget.appState.settings);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = ctx.joyce;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: c.ok),
              const SizedBox(width: 8),
              Text('Sale Completed (${sale['receipt_no']})'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('Total', style: TextStyle(color: c.muted)),
                          Text(
                            formatPeso(sale['total'] as num),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text('Change Due', style: TextStyle(color: c.muted)),
                          Text(
                            formatPeso(sale['change_amt'] as num),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.ok,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ReceiptPreviewWidget(receiptText: text, columns: cols),
                ],
              ),
            ),
          ),
          actions: [
            JoyceButton(
              label: 'Print Receipt',
              icon: Icons.print_outlined,
              outline: true,
              onPressed: () async {
                try {
                  await widget.appState.printSaleReceipt(sale);
                  if (ctx.mounted) {
                    showJoyceToast(ctx, 'Receipt sent to printer');
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    showJoyceToast(
                      ctx,
                      e.toString().replaceFirst('Exception: ', ''),
                      isError: true,
                    );
                  }
                }
              },
            ),
            JoyceButton(
              label: 'New Sale',
              icon: Icons.add_shopping_cart,
              onPressed: () {
                Navigator.of(ctx).pop();
                _searchFocus.requestFocus();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final filtered = _filteredProducts;
    final total = _cartTotal;
    final paid = _effectivePaid;
    final change = r2(paid - total);
    final canCharge = _cart.isNotEmpty && paid + 1e-9 >= total;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left: Product Catalog Grid
        Expanded(
          flex: 7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search & Barcode input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _handleSearchEnter,
                      decoration: InputDecoration(
                        hintText:
                            'Scan barcode or search product name (Press Enter to auto-select)...',
                        prefixIcon: const Icon(Icons.qr_code_scanner, size: 18),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Category Chips
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final cat in _categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat, style: const TextStyle(fontSize: 12)),
                          selected: _selectedCategory == cat,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = cat),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Product Grid
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No matching products found',
                        subtitle:
                            'Add products in Products Catalog or clear your search filter.',
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 195,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          final pid = p['id'] as int;
                          final baseStock = (p['stock'] as num).toInt();
                          final remaining = _remainingStockFor(pid, baseStock);
                          final variants = (p['variants'] as List? ?? const []);
                          final imgStr = (p['image'] as String? ?? '');

                          return JoyceCard(
                            padding: const EdgeInsets.all(12),
                            onTap: () => _onProductTap(p),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Image or Placeholder + Options badge
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: c.bg2,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: _buildProductThumb(imgStr, c),
                                      ),
                                      if (variants.isNotEmpty)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.accent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${variants.length + 1} options',
                                              style: TextStyle(
                                                color: c.btnText,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p['name'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        formatPeso(p['price'] as num),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.accent,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '$remaining in stock',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color:
                                              remaining <= 0 ? c.warn : c.muted,
                                          fontWeight: remaining <= 0
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Right: Current Order Cart & Tender Panel
        SizedBox(
          width: 390,
          child: JoyceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Current Order (${_cart.length})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (_cart.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => setState(() => _cart.clear()),
                        icon: Icon(Icons.delete_sweep_outlined,
                            size: 16, color: c.bad),
                        label: Text(
                          'Clear All',
                          style: TextStyle(color: c.bad, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const Divider(),
                // Cart Lines
                Expanded(
                  child: _cart.isEmpty
                      ? const EmptyState(
                          icon: Icons.shopping_basket_outlined,
                          title: 'Cart is empty',
                          subtitle: 'Tap a product or scan a barcode to add items.',
                        )
                      : ListView.separated(
                          itemCount: _cart.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 12),
                          itemBuilder: (ctx, i) {
                            final line = _cart[i];
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.variantName.isNotEmpty
                                            ? '${line.name} (${line.variantName})'
                                            : line.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${formatPeso(line.unitPrice)} each',
                                        style: TextStyle(
                                          color: c.muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      line.quantity--;
                                      if (line.quantity <= 0) {
                                        _cart.removeAt(i);
                                      }
                                    });
                                  },
                                ),
                                Text(
                                  '${line.quantity}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() => line.quantity++);
                                  },
                                ),
                                SizedBox(
                                  width: 78,
                                  child: Text(
                                    formatPeso(line.subtotal),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
                const Divider(),
                // Total, Cash Received, Quick Tender Chips, Change, Charge Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL',
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      formatPeso(total),
                      style: TextStyle(
                        color: c.accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _paidCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Cash Received (blank = Exact ${formatPeso(total)})',
                    prefixIcon: const Icon(Icons.payments_outlined, size: 18),
                  ),
                ),
                if (_quickTenderOptions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final amt in _quickTenderOptions)
                        ActionChip(
                          label: Text(
                            (amt - total).abs() < 0.01
                                ? 'Exact'
                                : formatPeso(amt),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            setState(() {
                              _paidCtrl.text = amt.toStringAsFixed(2);
                            });
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Change', style: TextStyle(color: c.muted)),
                    Text(
                      formatPeso(change),
                      style: TextStyle(
                        color: change < 0 ? c.bad : c.ok,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                JoyceButton(
                  label: 'Charge ${formatPeso(total)}',
                  icon: Icons.check_circle_outline,
                  onPressed: canCharge ? _completeCheckout : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductThumb(String imageDataUrl, JoyceColors c) {
    if (imageDataUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageDataUrl.indexOf(',');
        if (commaIdx > 0) {
          final bytes = base64Decode(imageDataUrl.substring(commaIdx + 1));
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(bytes, fit: BoxFit.cover),
          );
        }
      } catch (_) {}
    }
    return Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: 32,
        color: c.muted.withValues(alpha: 0.45),
      ),
    );
  }
}
