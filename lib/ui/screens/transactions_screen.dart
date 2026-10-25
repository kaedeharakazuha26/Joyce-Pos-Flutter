import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';

class TransactionsScreen extends StatefulWidget {
  final AppState appState;

  const TransactionsScreen({super.key, required this.appState});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late String _from;
  late String _to;
  String _preset = 'today';
  String _activeTab = 'sales'; // 'sales' | 'voided'
  int _page = 1;

  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _voided = [];

  @override
  void initState() {
    super.initState();
    final bDate = widget.appState.repo.activeBusinessDate();
    _from = bDate;
    _to = bDate;
    if (widget.appState.deepLinkFilter == 'voided') {
      _activeTab = 'voided';
      widget.appState.clearDeepLinkFilter();
    }
    _reload();
  }

  void _reload() {
    setState(() {
      _sales = widget.appState.repo.listSales(from: _from, to: _to);
      _voided = widget.appState.repo.listVoided(from: _from, to: _to);
      _page = 1;
    });
  }

  void _promptVoidSale(Map<String, dynamic> sale) {
    final reasonCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Void Sale ${sale['receipt_no']}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voiding restores all sold units back to inventory and excludes this sale from revenue.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Void Reason (e.g., Wrong item / Customer cancelled)',
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
            label: 'Confirm Void',
            danger: true,
            icon: Icons.cancel_outlined,
            onPressed: () {
              try {
                widget.appState.repo.voidSale(
                  id: sale['id'] as int,
                  reason: reasonCtrl.text.trim(),
                  voidedBy: widget.appState.currentUserName,
                );
                Navigator.of(ctx).pop();
                _reload();
                widget.appState.refreshAll();
                showJoyceToast(context, 'Sale ${sale['receipt_no']} voided');
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
    final completedSales =
        _sales.where((s) => s['status'] == 'completed').toList();
    final completedSum = r2(
      completedSales.fold<double>(
        0.0,
        (acc, s) => acc + ((s['total'] as num?)?.toDouble() ?? 0.0),
      ),
    );

    final activeList = _activeTab == 'sales' ? _sales : _voided;
    const pageSize = 20;
    final paged = activeList.skip((_page - 1) * pageSize).take(pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Transactions',
          subtitle:
              '${completedSales.length} completed sale(s) • Total: ${formatPeso(completedSum)}',
          actions: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'sales',
                  label: Text('Sales (${_sales.length})'),
                ),
                ButtonSegment(
                  value: 'voided',
                  label: Text('Voided History (${_voided.length})'),
                ),
              ],
              selected: {_activeTab},
              onSelectionChanged: (s) => setState(() {
                _activeTab = s.first;
                _page = 1;
              }),
            ),
          ],
        ),
        RangeBar(
          from: _from,
          to: _to,
          selectedPreset: _preset,
          activeBusinessDate: widget.appState.repo.activeBusinessDate(),
          onChanged: (f, t, p) {
            _from = f;
            _to = t;
            _preset = p;
            _reload();
          },
        ),
        const SizedBox(height: 14),
        Expanded(
          child: JoyceCard(
            padding: const EdgeInsets.all(12),
            child: paged.isEmpty
                ? const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions in selected date range',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: paged.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final row = paged[i];
                            final items = (row['items'] as List? ?? const []);
                            final isVoided =
                                _activeTab == 'voided' || row['status'] == 'voided';
                            return ExpansionTile(
                              title: Row(
                                children: [
                                  Text(
                                    (row['receipt_no'] ?? '').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isVoided ? c.bad : c.ok)
                                          .withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isVoided ? 'VOIDED' : 'COMPLETED',
                                      style: TextStyle(
                                        color: isVoided ? c.bad : c.ok,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    formatPeso((row['total'] as num?) ?? 0),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: isVoided ? c.muted : c.accent,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                _activeTab == 'sales'
                                    ? 'Date: ${row['created_at']} • Business Date: ${row['business_date']}'
                                    : 'Sold: ${row['sold_at']} • Voided: ${row['voided_at']} by ${row['voided_by']} • Reason: ${row['reason']}',
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      for (final item in items)
                                        if (item is Map)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 3,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  '${item['quantity']}× ${item['name']}${(item['variant_name'] ?? '').toString().isNotEmpty ? " (${item['variant_name']})" : ""} @ ${formatPeso((item['unit_price'] as num?) ?? 0)}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                Text(
                                                  formatPeso(
                                                    (item['subtotal'] as num?) ??
                                                        0,
                                                  ),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      if (_activeTab == 'sales') ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            JoyceButton(
                                              label: 'Reprint Receipt',
                                              icon: Icons.print_outlined,
                                              compact: true,
                                              outline: true,
                                              onPressed: () async {
                                                try {
                                                  await widget.appState
                                                      .printSaleReceipt(row);
                                                  if (context.mounted) {
                                                    showJoyceToast(
                                                      context,
                                                      'Reprinted ${row['receipt_no']}',
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    showJoyceToast(
                                                      context,
                                                      e
                                                          .toString()
                                                          .replaceFirst(
                                                            'Exception: ',
                                                            '',
                                                          ),
                                                      isError: true,
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                            if (row['status'] ==
                                                'completed') ...[
                                              const SizedBox(width: 8),
                                              JoyceButton(
                                                label: 'Void Sale',
                                                icon: Icons.cancel_outlined,
                                                compact: true,
                                                danger: true,
                                                onPressed: () =>
                                                    _promptVoidSale(row),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      PaginationBar(
                        currentPage: _page,
                        totalItems: activeList.length,
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
