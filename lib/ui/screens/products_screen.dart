import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../../core/utils/money.dart';
import '../../data/pos_repository.dart';
import '../widgets/joyce_widgets.dart';

class ProductsScreen extends StatefulWidget {
  final AppState appState;

  const ProductsScreen({super.key, required this.appState});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _stockFilter = 'all'; // 'all' | 'low_stock' | 'out_of_stock'
  List<Map<String, dynamic>> _products = [];
  int _page = 1;

  @override
  void initState() {
    super.initState();
    final dl = widget.appState.deepLinkFilter;
    if (dl == 'low_stock' || dl == 'out_of_stock') {
      _stockFilter = dl;
      widget.appState.clearDeepLinkFilter();
    }
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _products = widget.appState.repo.listProducts();
      _page = 1;
    });
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      final stock = (p['stock'] as num).toInt();
      final low = (p['low_stock'] as num?)?.toInt() ?? 5;
      if (_stockFilter == 'out_of_stock' && stock > 0) return false;
      if (_stockFilter == 'low_stock' && (stock <= 0 || stock > low)) {
        return false;
      }
      if (q.isEmpty) return true;
      return (p['name'] as String).toLowerCase().contains(q) ||
          (p['category'] as String).toLowerCase().contains(q) ||
          (p['barcode'] as String).toLowerCase().contains(q);
    }).toList();
  }

  void _openProductModal([Map<String, dynamic>? existing]) {
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final barcodeCtrl = TextEditingController(text: existing?['barcode']?.toString() ?? '');
    final existingCat = (existing?['category']?.toString() ?? '').trim();

    final categoriesSet = <String>{};
    try {
      for (final cat in widget.appState.repo.listCategories()) {
        final name = cat.trim();
        if (name.isNotEmpty) categoriesSet.add(name);
      }
    } catch (_) {}
    for (final p in _products) {
      final name = (p['category'] ?? '').toString().trim();
      if (name.isNotEmpty) categoriesSet.add(name);
    }
    if (existingCat.isNotEmpty) {
      categoriesSet.add(existingCat);
    }
    final categoryList = categoriesSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    bool isAddingNewCategory = categoryList.isEmpty;
    String? selectedCategory = existingCat.isNotEmpty
        ? existingCat
        : (categoryList.isNotEmpty ? categoryList.first : null);
    final newCatCtrl = TextEditingController();

    final priceCtrl = TextEditingController(
      text: existing != null ? (existing['price'] as num).toStringAsFixed(2) : '0',
    );
    final costCtrl = TextEditingController(
      text: existing != null ? (existing['cost'] as num).toStringAsFixed(2) : '0',
    );
    final stockCtrl = TextEditingController(
      text: existing != null ? '${existing['stock']}' : '0',
    );
    final lowCtrl = TextEditingController(
      text: existing != null ? '${existing['low_stock'] ?? 5}' : '5',
    );
    String imageDataUrl = existing?['image']?.toString() ?? '';

    final variants = <Map<String, TextEditingController>>[];
    if (existing != null && existing['variants'] is List) {
      for (final v in (existing['variants'] as List)) {
        if (v is Map) {
          variants.add({
            'name': TextEditingController(text: v['name']?.toString() ?? ''),
            'qty': TextEditingController(text: '${v['qty'] ?? 1}'),
            'price': TextEditingController(
              text: ((v['price'] as num?) ?? 0).toStringAsFixed(2),
            ),
          });
        }
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final c = ctx.joyce;
          return AlertDialog(
            title: Text(existing == null ? 'Add Product' : 'Edit Product'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Product Name *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: isAddingNewCategory ? '__NEW__' : selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                            ),
                            items: [
                              for (final cat in categoryList)
                                DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat, overflow: TextOverflow.ellipsis),
                                ),
                              DropdownMenuItem(
                                value: '__NEW__',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_circle_outline, size: 15, color: c.accent),
                                    const SizedBox(width: 6),
                                    Text('+ Add New...', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              setModalState(() {
                                if (val == '__NEW__') {
                                  isAddingNewCategory = true;
                                } else {
                                  isAddingNewCategory = false;
                                  selectedCategory = val;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (isAddingNewCategory) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: newCatCtrl,
                        decoration: const InputDecoration(
                          labelText: 'New Category Name *',
                          hintText: 'Enter new category name',
                          prefixIcon: Icon(Icons.new_label_outlined, size: 16),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: barcodeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Barcode',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        JoyceButton(
                          label: 'Generate',
                          icon: Icons.autorenew,
                          outline: true,
                          onPressed: () {
                            setModalState(() {
                              barcodeCtrl.text = PosRepository.generateBarcode();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Selling Price (₱)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Base Cost (₱)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Stock (Base Units)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: lowCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Low Stock Alert Level',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Image picker
                    Row(
                      children: [
                        JoyceButton(
                          label: imageDataUrl.isEmpty
                              ? 'Pick Product Photo'
                              : 'Change Photo',
                          icon: Icons.image_outlined,
                          outline: true,
                          compact: true,
                          onPressed: () async {
                            final path = await CsvExporter.pickOpenFile(
                              filter:
                                  'Images (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp',
                            );
                            if (path == null) return;
                            final file = File(path);
                            if (file.lengthSync() > 5 * 1024 * 1024) {
                              if (ctx.mounted) {
                                showJoyceToast(
                                  ctx,
                                  'Image must be 5 MB or smaller',
                                  isError: true,
                                );
                              }
                              return;
                            }
                            final rawBytes = file.readAsBytesSync();
                            final decoded = img.decodeImage(rawBytes);
                            if (decoded == null) return;
                            img.Image resized = decoded;
                            if (decoded.width > 320 || decoded.height > 320) {
                              resized = decoded.width >= decoded.height
                                  ? img.copyResize(decoded, width: 320)
                                  : img.copyResize(decoded, height: 320);
                            }
                            final jpg = img.encodeJpg(resized, quality: 85);
                            setModalState(() {
                              imageDataUrl =
                                  'data:image/jpeg;base64,${base64Encode(jpg)}';
                            });
                          },
                        ),
                        if (imageDataUrl.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                setModalState(() => imageDataUrl = ''),
                            child: Text(
                              'Remove Photo',
                              style: TextStyle(color: c.bad),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Pack Variants (Multi-unit pricing)',
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              variants.add({
                                'name': TextEditingController(),
                                'qty': TextEditingController(text: '6'),
                                'price': TextEditingController(text: '0'),
                              });
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Variant'),
                        ),
                      ],
                    ),
                    for (int idx = 0; idx < variants.length; idx++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: variants[idx]['name'],
                                decoration: const InputDecoration(
                                  labelText: 'Pack Name (e.g. 6-Pack)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: variants[idx]['qty'],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Units',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: variants[idx]['price'],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Pack Price',
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: c.bad),
                              onPressed: () =>
                                  setModalState(() => variants.removeAt(idx)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              JoyceButton(
                label: 'Save Product',
                icon: Icons.check,
                onPressed: () {
                  final finalCategory = isAddingNewCategory
                      ? newCatCtrl.text.trim()
                      : (selectedCategory ?? '').trim();
                  if (finalCategory.isEmpty) {
                    showJoyceToast(context, 'Category is required',
                        isError: true);
                    return;
                  }
                  try {
                    widget.appState.repo.saveProduct(
                      {
                        'id': existing?['id'],
                        'name': nameCtrl.text,
                        'barcode': barcodeCtrl.text,
                        'category': finalCategory,
                        'price': priceCtrl.text,
                        'cost': costCtrl.text,
                        'stock': stockCtrl.text,
                        'low_stock': lowCtrl.text,
                        'image': imageDataUrl,
                        'variants': variants
                            .map((v) => {
                                  'name': v['name']!.text,
                                  'qty': v['qty']!.text,
                                  'price': v['price']!.text,
                                })
                            .toList(),
                      },
                      actor: widget.appState.currentUserName,
                      role: widget.appState.currentUserRole,
                    );
                    Navigator.of(ctx).pop();
                    _reload();
                    widget.appState.refreshAll();
                    showJoyceToast(context, 'Product saved');
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
          );
        },
      ),
    );
  }

  void _confirmArchive(Map<String, dynamic> prod) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Archive ${prod['name']}?'),
        content: const Text(
          'This removes the product from active POS catalog. Past sales stay in history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          JoyceButton(
            label: 'Archive',
            danger: true,
            onPressed: () {
              widget.appState.repo.deleteProduct(
                prod['id'] as int,
                actor: widget.appState.currentUserName,
                role: widget.appState.currentUserRole,
              );
              Navigator.of(ctx).pop();
              _reload();
              widget.appState.refreshAll();
              showJoyceToast(context, 'Archived ${prod['name']}');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final list = _filtered;
    const pageSize = 20;
    final paged = list.skip((_page - 1) * pageSize).take(pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Products Catalog',
          subtitle: '${_products.length} active product(s) in catalog',
          actions: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'low_stock', label: Text('Low Stock')),
                ButtonSegment(
                  value: 'out_of_stock',
                  label: Text('Out of Stock'),
                ),
              ],
              selected: {_stockFilter},
              onSelectionChanged: (s) => setState(() {
                _stockFilter = s.first;
                _page = 1;
              }),
            ),
            JoyceButton(
              label: 'Add Product',
              icon: Icons.add,
              onPressed: () => _openProductModal(),
            ),
          ],
        ),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() => _page = 1),
          decoration: const InputDecoration(
            hintText: 'Search by product name, category, or barcode...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: JoyceCard(
            padding: const EdgeInsets.all(12),
            child: paged.isEmpty
                ? const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products match your filter',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: paged.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final p = paged[i];
                            final stock = (p['stock'] as num).toInt();
                            final low = (p['low_stock'] as num?)?.toInt() ?? 5;
                            final variants =
                                (p['variants'] as List? ?? const []);
                            return ListTile(
                              title: Row(
                                children: [
                                  Text(
                                    p['name'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if ((p['category'] as String)
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Chip(
                                      label: Text(
                                        p['category'].toString(),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                'Barcode: ${(p['barcode'] as String).isEmpty ? "—" : p['barcode']} • Cost: ${formatPeso(p['cost'] as num)} • Variants: ${variants.length}',
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
                                      color: (stock <= 0
                                              ? c.bad
                                              : (stock <= low ? c.warn : c.ok))
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$stock in stock',
                                      style: TextStyle(
                                        color: stock <= 0
                                            ? c.bad
                                            : (stock <= low ? c.warn : c.ok),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(
                                    formatPeso(p['price'] as num),
                                    style: TextStyle(
                                      color: c.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () => _openProductModal(p),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.archive_outlined,
                                      size: 18,
                                      color: c.bad,
                                    ),
                                    onPressed: () => _confirmArchive(p),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      PaginationBar(
                        currentPage: _page,
                        totalItems: list.length,
                        pageSize: pageSize,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
