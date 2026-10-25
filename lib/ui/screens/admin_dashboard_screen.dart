import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  final AppState appState;

  const AdminDashboardScreen({super.key, required this.appState});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late String _from;
  late String _to;
  String _preset = 'this_month';
  late String _subTab;
  late Map<String, dynamic> _data;

  static const List<({String id, String label})> _tabs = [
    (id: 'overview', label: 'Overview & P&L'),
    (id: 'sales', label: 'Sales'),
    (id: 'products', label: 'Products & Margin'),
    (id: 'expenses', label: 'Expenses'),
    (id: 'salaries', label: 'Salaries'),
    (id: 'commissions', label: 'Commissions'),
    (id: 'ld-commissions', label: 'LD Commissions'),
    (id: 'employees', label: 'Employee Leaderboard'),
    (id: 'shifts', label: 'Shifts History'),
    (id: 'audit', label: 'Audit & Activity'),
    (id: 'reports', label: 'Exports & Reports'),
  ];

  @override
  void initState() {
    super.initState();
    final bDate = widget.appState.repo.activeBusinessDate();
    final r = resolveDatePreset('this_month', bDate);
    _from = r.from;
    _to = r.to;
    _subTab = widget.appState.adminSubTab;
    _reload();
  }

  void _reload() {
    setState(() {
      _data = widget.appState.repo.adminDashboard(from: _from, to: _to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final disabled = widget.appState.repo.getDisabledMenus();
    final visibleTabs = _tabs.where((t) {
      if (t.id == 'expenses' && disabled.contains('expenses')) return false;
      if (t.id == 'salaries' && disabled.contains('salary')) return false;
      if (t.id == 'commissions' && disabled.contains('commission')) return false;
      if (t.id == 'ld-commissions' && disabled.contains('ld-commission')) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Executive Admin Dashboard',
          subtitle:
              'Today: ${formatPeso((_data['today']?['revenue'] as num?) ?? 0)} (${_data['today']?['orders'] ?? 0} orders) • MTD: ${formatPeso((_data['mtd']?['revenue'] as num?) ?? 0)}',
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
        const SizedBox(height: 10),
        // Sub-tab bar
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final t in visibleTabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(t.label, style: const TextStyle(fontSize: 12)),
                    selected: _subTab == t.id,
                    selectedColor: c.accent.withValues(alpha: 0.25),
                    onSelected: (_) => setState(() => _subTab = t.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildSubTabContent(context)),
      ],
    );
  }

  Widget _buildSubTabContent(BuildContext context) {
    final c = context.joyce;
    final prev = (_data['previous_period'] as Map<String, dynamic>? ?? const {});
    switch (_subTab) {
      case 'overview':
        final daily = (_data['daily'] as List? ?? const []);
        final revDelta = pctChange(
          (_data['revenue'] as num?) ?? 0,
          (prev['revenue'] as num?) ?? 0,
        );
        final gpDelta = pctChange(
          (_data['gross_profit'] as num?) ?? 0,
          (prev['gross_profit'] as num?) ?? 0,
        );
        final netDelta = pctChange(
          (_data['net_profit'] as num?) ?? 0,
          (prev['net_profit'] as num?) ?? 0,
        );
        final cogs = ((_data['cogs'] as num?) ?? 0).toDouble();
        final exp = ((_data['expenses'] as num?) ?? 0).toDouble();
        final sal = ((_data['salaries'] as num?) ?? 0).toDouble();
        final com = ((_data['commissions'] as num?) ?? 0).toDouble() +
            ((_data['ld_commissions'] as num?) ?? 0).toDouble();

        return ListView(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DeltaKpiCard(
                  label: 'Gross Revenue',
                  value: formatPeso((_data['revenue'] as num?) ?? 0),
                  deltaText:
                      '${revDelta.pct >= 0 ? "+" : ""}${revDelta.pct}% vs prev period',
                  isPositive: revDelta.pct >= 0,
                ),
                _DeltaKpiCard(
                  label: 'Gross Profit (After COGS)',
                  value: formatPeso((_data['gross_profit'] as num?) ?? 0),
                  deltaText:
                      '${gpDelta.pct >= 0 ? "+" : ""}${gpDelta.pct}% • Margin ${_data['gross_margin']}%',
                  isPositive: gpDelta.pct >= 0,
                ),
                _DeltaKpiCard(
                  label: 'Net Profit (After COGS)',
                  value: formatPeso((_data['net_profit'] as num?) ?? 0),
                  deltaText:
                      '${netDelta.pct >= 0 ? "+" : ""}${netDelta.pct}% • Net Margin ${_data['net_margin']}%',
                  isPositive: ((_data['net_profit'] as num?) ?? 0) >= 0,
                ),
                _DeltaKpiCard(
                  label: 'Average Ticket',
                  value: formatPeso((_data['avg_ticket'] as num?) ?? 0),
                  deltaText:
                      '${_data['orders'] ?? 0} orders • Void Rate ${_data['void_rate']}%',
                  isPositive: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // P&L Statement Card
                Expanded(
                  flex: 3,
                  child: JoyceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profit & Loss (P&L) Statement',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _PnlLine('Gross Sales Revenue', _data['revenue'],
                            isBold: true),
                        _PnlLine(
                            'Less: Cost of Goods Sold (COGS)', -cogs,
                            color: c.bad),
                        const Divider(),
                        _PnlLine('= Gross Profit', _data['gross_profit'],
                            isBold: true, color: c.ok),
                        _PnlLine('Less: Store Expenses', -exp),
                        _PnlLine('Less: Salary Payroll', -sal),
                        _PnlLine('Less: Commissions & LD', -com),
                        const Divider(),
                        _PnlLine(
                          '= Net Profit (After COGS & Overheads)',
                          _data['net_profit'],
                          isBold: true,
                          color: ((_data['net_profit'] as num?) ?? 0) < 0
                              ? c.bad
                              : c.accent,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Cost & Outflow Breakdown Doughnut Chart
                Expanded(
                  flex: 2,
                  child: JoyceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cost & Outflow Breakdown',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 190,
                          child: (cogs + exp + sal + com) <= 0
                              ? const EmptyState(title: 'No outflows in period')
                              : PieChart(
                                  PieChartData(
                                    centerSpaceRadius: 38,
                                    sections: [
                                      if (cogs > 0)
                                        PieChartSectionData(
                                          value: cogs,
                                          title: 'COGS',
                                          color: c.info,
                                          radius: 44,
                                          titleStyle: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (exp > 0)
                                        PieChartSectionData(
                                          value: exp,
                                          title: 'Exp',
                                          color: c.bad,
                                          radius: 44,
                                          titleStyle: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (sal > 0)
                                        PieChartSectionData(
                                          value: sal,
                                          title: 'Salary',
                                          color: c.warn,
                                          radius: 44,
                                          titleStyle: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                      if (com > 0)
                                        PieChartSectionData(
                                          value: com,
                                          title: 'Comm',
                                          color: c.purple,
                                          radius: 44,
                                          titleStyle: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Daily Trend Table
            JoyceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Performance Breakdown (${daily.length} day(s))',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final d in daily.reversed.take(14))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${d['date']} (${d['orders']} orders)',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Sales: ${formatPeso(d['sales'] as num)} • COGS: ${formatPeso(d['cogs'] as num)} • Overheads: ${formatPeso(d['overheads'] as num)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Net (After COGS): ${formatPeso(d['net_after_cogs'] as num)}',
                            style: TextStyle(
                              color: (d['net_after_cogs'] as num) < 0
                                  ? c.bad
                                  : c.ok,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Cash Net (No COGS): ${formatPeso(d['net'] as num)}',
                            style: TextStyle(color: c.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );

      case 'sales':
        final sales = (_data['recent_sales'] as List? ?? const []);
        return _SimpleListCard(
          title: 'Recent Sales in Period',
          items: sales,
          itemBuilder: (s) => ListTile(
            title: Text(
              '${s['receipt_no']} (${s['status']})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Date: ${s['created_at']} • Business Date: ${s['business_date']}'),
            trailing: Text(
              formatPeso(s['total'] as num),
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w800),
            ),
          ),
        );

      case 'products':
        final catalog = (_data['catalog_performance'] as List? ?? const []);
        return _SimpleListCard(
          title: 'Catalog Performance & Margin Analysis',
          items: catalog,
          itemBuilder: (p) => ListTile(
            title: Text(
              '${p['name']} (${(p['category'] as String).isEmpty ? "General" : p['category']})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Sold: ${p['units_sold']} units • Stock: ${p['stock']} • Margin: ${p['margin_pct']}%',
            ),
            trailing: Text(
              'Rev: ${formatPeso(p['revenue'] as num)} | GP: ${formatPeso(p['gross_profit'] as num)}',
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
            ),
          ),
        );

      case 'expenses':
        final list = widget.appState.repo.listExpenses(from: _from, to: _to);
        return _SimpleListCard(
          title: 'Expenses Ledger (${list.length})',
          items: list,
          itemBuilder: (e) => ListTile(
            title: Text('${e['category']} — ${e['description']}'),
            subtitle: Text('Business Date: ${e['business_date']}'),
            trailing: Text(formatPeso(e['amount'] as num)),
          ),
        );

      case 'salaries':
        final list = widget.appState.repo.listSalaries(from: _from, to: _to);
        return _SimpleListCard(
          title: 'Salaries Ledger (${list.length})',
          items: list,
          itemBuilder: (s) => ListTile(
            title: Text('${s['employee']} (${s['period']})'),
            subtitle: Text('Business Date: ${s['business_date']} • ${s['note']}'),
            trailing: Text(formatPeso(s['amount'] as num)),
          ),
        );

      case 'commissions':
        final list = widget.appState.repo.listCommissions(from: _from, to: _to);
        return _SimpleListCard(
          title: 'Commissions Ledger (${list.length})',
          items: list,
          itemBuilder: (cm) => ListTile(
            title: Text('${cm['employee_name']} (${cm['type']})'),
            subtitle: Text('Business Date: ${cm['business_date']}'),
            trailing: Text(formatPeso(cm['amount'] as num)),
          ),
        );

      case 'ld-commissions':
        final list =
            widget.appState.repo.listLdCommissions(from: _from, to: _to);
        return _SimpleListCard(
          title: 'LD Commissions Ledger (${list.length})',
          items: list,
          itemBuilder: (l) => ListTile(
            title: Text('${l['employee_name']} (Qty: ${l['quantity']})'),
            subtitle: Text('Business Date: ${l['business_date']}'),
            trailing: Text(formatPeso(l['amount'] as num)),
          ),
        );

      case 'employees':
        final topEmp = (_data['top_employees'] as List? ?? const []);
        return _SimpleListCard(
          title: 'Highest Income per Employee Leaderboard',
          items: topEmp,
          itemBuilder: (e) => ListTile(
            title: Text(
              e['employee'].toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Salary: ${formatPeso(e['salary'] as num)} • Comm: ${formatPeso(e['commission'] as num)} • LD: ${formatPeso(e['ld_commission'] as num)}',
            ),
            trailing: Text(
              formatPeso(e['total'] as num),
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w800),
            ),
          ),
        );

      case 'shifts':
        final shifts = (_data['shift_history'] as List? ?? const []);
        return _SimpleListCard(
          title: 'Shifts History (${shifts.length})',
          items: shifts,
          itemBuilder: (sh) {
            final expCash = ((sh['expected_cash'] as num?) ?? 0).toDouble();
            final clsCash = ((sh['closing_cash'] as num?) ?? 0).toDouble();
            final variance = r2(clsCash - expCash);
            return ListTile(
              title: Text(
                'Shift #${sh['id']} — ${sh['business_date']} (${(sh['status'] ?? '').toString().toUpperCase()})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Opened by ${sh['opened_by']} • Expected: ${formatPeso(expCash)} • Counted: ${formatPeso(clsCash)}',
              ),
              trailing: Text(
                sh['status'] == 'open'
                    ? 'OPEN'
                    : 'Variance: ${formatPeso(variance)}',
                style: TextStyle(
                  color: variance < -0.01 ? c.bad : c.ok,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        );

      case 'audit':
        final logs = (_data['recent_activity'] as List? ?? const []);
        return _SimpleListCard(
          title: 'Audit & Activity Feed (${logs.length})',
          items: logs,
          itemBuilder: (l) => ListTile(
            title: Text(
              '[${l['action']}] ${l['summary']}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text('${l['timestamp']} • Actor: ${l['actor']} (${l['role']})'),
          ),
        );

      case 'reports':
        final daily = (_data['daily'] as List? ?? const []);
        final catalog = (_data['catalog_performance'] as List? ?? const []);
        return JoyceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CSV Reports & Data Exports ($_from to $_to)',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  JoyceButton(
                    label: 'Export Daily P&L Summary CSV',
                    icon: Icons.table_view_outlined,
                    onPressed: () async {
                      final path = await CsvExporter.exportCsvDialog(
                        defaultFileName: 'joyce_daily_pnl_${_from}_$_to.csv',
                        headers: [
                          'Date',
                          'Orders',
                          'Revenue',
                          'COGS',
                          'Gross Profit',
                          'Expenses',
                          'Salaries',
                          'Commissions',
                          'LD Commissions',
                          'Overheads',
                          'Net Profit (After COGS)',
                          'Net Operating (No COGS)',
                        ],
                        rows: daily
                            .map((d) => [
                                  d['date'],
                                  d['orders'],
                                  d['revenue'],
                                  d['cogs'],
                                  d['gross_profit'],
                                  d['expenses'],
                                  d['salaries'],
                                  d['commissions'],
                                  d['ld_commissions'],
                                  d['overheads'],
                                  d['net_after_cogs'],
                                  d['net'],
                                ])
                            .toList(),
                      );
                      if (path != null && context.mounted) {
                        showJoyceToast(context, 'Saved P&L CSV to $path');
                      }
                    },
                  ),
                  JoyceButton(
                    label: 'Export Product Performance CSV',
                    icon: Icons.inventory_outlined,
                    outline: true,
                    onPressed: () async {
                      final path = await CsvExporter.exportCsvDialog(
                        defaultFileName: 'joyce_products_${_from}_$_to.csv',
                        headers: [
                          'ID',
                          'Name',
                          'Category',
                          'Stock',
                          'Price',
                          'Cost',
                          'Units Sold',
                          'Revenue',
                          'COGS',
                          'Gross Profit',
                          'Margin %',
                        ],
                        rows: catalog
                            .map((p) => [
                                  p['id'],
                                  p['name'],
                                  p['category'],
                                  p['stock'],
                                  p['price'],
                                  p['cost'],
                                  p['units_sold'],
                                  p['revenue'],
                                  p['cogs'],
                                  p['gross_profit'],
                                  p['margin_pct'],
                                ])
                            .toList(),
                      );
                      if (path != null && context.mounted) {
                        showJoyceToast(context, 'Saved Products CSV to $path');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

class _DeltaKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String deltaText;
  final bool isPositive;

  const _DeltaKpiCard({
    required this.label,
    required this.value,
    required this.deltaText,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return SizedBox(
      width: 245,
      child: JoyceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: c.accent,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              deltaText,
              style: TextStyle(
                color: isPositive ? c.ok : c.bad,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PnlLine extends StatelessWidget {
  final String label;
  final dynamic amount;
  final bool isBold;
  final Color? color;

  const _PnlLine(
    this.label,
    this.amount, {
    this.isBold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isBold ? c.text : c.muted,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            formatPeso((amount as num?) ?? 0),
            style: TextStyle(
              color: color ?? c.text,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleListCard extends StatelessWidget {
  final String title;
  final List<dynamic> items;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  const _SimpleListCard({
    required this.title,
    required this.items,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(title: 'No records in selected range')
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) =>
                        itemBuilder(items[i] as Map<String, dynamic>),
                  ),
          ),
        ],
      ),
    );
  }
}
