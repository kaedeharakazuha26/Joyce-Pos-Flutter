import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../data/pos_repository.dart';
import '../widgets/joyce_widgets.dart';

class StoreOverviewScreen extends StatefulWidget {
  final AppState appState;

  const StoreOverviewScreen({super.key, required this.appState});

  @override
  State<StoreOverviewScreen> createState() => _StoreOverviewScreenState();
}

class _StoreOverviewScreenState extends State<StoreOverviewScreen> {
  late String _from;
  late String _to;
  String _preset = 'this_month';
  late Map<String, dynamic> _data;
  late List<String> _cardOrder;

  @override
  void initState() {
    super.initState();
    final bDate = widget.appState.repo.activeBusinessDate();
    final r = resolveDatePreset('this_month', bDate);
    _from = r.from;
    _to = r.to;
    _cardOrder = widget.appState.repo.getDashboardCardOrder();
    _reload();
  }

  void _reload() {
    setState(() {
      _data = widget.appState.repo.dashboard(from: _from, to: _to);
    });
  }

  void _exportPnl() {
    final daily = (_data['daily'] as List? ?? const []);
    if (daily.isEmpty) {
      showJoyceToast(context, 'No daily trend data to export', isError: true);
      return;
    }
    CsvExporter.exportCsvDialog(
      defaultFileName: 'store_overview_pnl_${_from}_$_to.csv',
      headers: [
        'Date',
        'Sales (PHP)',
        'Orders',
        'COGS (PHP)',
        'Gross Profit (PHP)',
        'Expenses (PHP)',
        'Salaries (PHP)',
        'Commissions (PHP)',
        'LD Commissions (PHP)',
        'Overheads (PHP)',
        'Net Cash Flow (PHP)',
      ],
      rows: daily
          .map((d) => [
                d['date'],
                d['sales'],
                d['orders'],
                d['cogs'],
                d['gross_profit'],
                d['expenses'],
                d['salaries'],
                d['commissions'],
                d['ld_commissions'],
                d['overheads'],
                d['net'],
              ])
          .toList(),
    );
  }

  Widget _cardHeader(String title, String cardId, JoyceColors c) {
    final idx = _cardOrder.indexOf(cardId);
    return Row(
      children: [
        if (title.isNotEmpty)
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          )
        else
          const Spacer(),
        if (idx >= 0)
          ReorderableDragStartListener(
            index: idx,
            child: Tooltip(
              message: 'Drag to reorder card',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(Icons.drag_indicator, color: c.muted, size: 20),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKpisCard(JoyceColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cardHeader('Key Performance Indicators', 'kpis', c),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _KpiTile(
              label: 'Gross Revenue',
              value: formatPeso((_data['revenue'] as num?) ?? 0),
              sub: '${_data['orders'] ?? 0} completed orders',
              color: c.accent,
            ),
            _KpiTile(
              label: 'Gross Profit (After COGS)',
              value: formatPeso((_data['gross_profit'] as num?) ?? 0),
              sub:
                  'Margin: ${_data['gross_margin'] ?? 0}% • COGS: ${formatPeso((_data['cogs'] as num?) ?? 0)}',
              color: c.ok,
            ),
            _KpiTile(
              label: 'Total Overheads',
              value: formatPeso((_data['overheads'] as num?) ?? 0),
              sub: 'Active & enabled finance modules',
              color: c.warn,
            ),
            _KpiTile(
              label: 'Net Profit (After COGS)',
              value: formatPeso((_data['net_profit'] as num?) ?? 0),
              sub: 'Net Margin: ${_data['net_margin'] ?? 0}%',
              color: ((_data['net_profit'] as num?) ?? 0) < 0 ? c.bad : c.ok,
            ),
            _KpiTile(
              label: 'Inventory Valuation',
              value: formatPeso((_data['inventory_retail'] as num?) ?? 0),
              sub:
                  'Cost: ${formatPeso((_data['inventory_cost'] as num?) ?? 0)} • Potential: ${formatPeso((_data['potential_profit'] as num?) ?? 0)}',
              color: c.info,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyTrendCard(JoyceColors c, List daily) {
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Daily Revenue vs Net Operating Cash Flow', 'daily_trend', c),
          const SizedBox(height: 14),
          SizedBox(
            height: 220,
            child: daily.isEmpty
                ? const EmptyState(title: 'No daily trend data')
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < daily.length; i++)
                              FlSpot(
                                i.toDouble(),
                                ((daily[i]['sales'] as num?) ?? 0).toDouble(),
                              ),
                          ],
                          isCurved: true,
                          color: c.accent,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                        ),
                        LineChartBarData(
                          spots: [
                            for (int i = 0; i < daily.length; i++)
                              FlSpot(
                                i.toDouble(),
                                ((daily[i]['net'] as num?) ?? 0).toDouble(),
                              ),
                          ],
                          isCurved: true,
                          color: c.ok,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceBreakdownCard(
      JoyceColors c, Map<String, dynamic> finance) {
    final exp = (finance['expenses'] as Map<String, dynamic>?) ??
        {'enabled': false, 'total': 0.0, 'count': 0};
    final sal = (finance['salaries'] as Map<String, dynamic>?) ??
        {'enabled': false, 'total': 0.0, 'count': 0};
    final com = (finance['commissions'] as Map<String, dynamic>?) ??
        {'enabled': false, 'total': 0.0, 'count': 0};
    final ld = (finance['ld_commissions'] as Map<String, dynamic>?) ??
        {'enabled': false, 'total': 0.0, 'count': 0};

    final anyEnabled = exp['enabled'] == true ||
        sal['enabled'] == true ||
        com['enabled'] == true ||
        ld['enabled'] == true;
    if (!anyEnabled) return const SizedBox.shrink();

    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Finance & Overheads Breakdown', 'finance_breakdown', c),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (exp['enabled'] == true)
                _FinanceTile(
                  title: 'Store Expenses',
                  amount: (exp['total'] as num?) ?? 0,
                  count: (exp['count'] as int?) ?? 0,
                  icon: Icons.money_off_csred_outlined,
                  color: c.warn,
                  onTap: () => widget.appState.navigateToTab('expenses'),
                ),
              if (sal['enabled'] == true)
                _FinanceTile(
                  title: 'Salary Payroll',
                  amount: (sal['total'] as num?) ?? 0,
                  count: (sal['count'] as int?) ?? 0,
                  icon: Icons.account_balance_wallet_outlined,
                  color: c.info,
                  onTap: () => widget.appState.navigateToTab('salary'),
                ),
              if (com['enabled'] == true)
                _FinanceTile(
                  title: 'Commissions',
                  amount: (com['total'] as num?) ?? 0,
                  count: (com['count'] as int?) ?? 0,
                  icon: Icons.workspace_premium_outlined,
                  color: c.accent,
                  onTap: () => widget.appState.navigateToTab('commission'),
                ),
              if (ld['enabled'] == true)
                _FinanceTile(
                  title: 'LD Commissions',
                  amount: (ld['total'] as num?) ?? 0,
                  count: (ld['count'] as int?) ?? 0,
                  icon: Icons.phone_android_outlined,
                  color: c.ok,
                  onTap: () => widget.appState.navigateToTab('ld-commission'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopEmployeesCard(
      JoyceColors c, List<Map<String, dynamic>> topEmployees) {
    if (topEmployees.isEmpty) return const SizedBox.shrink();

    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
              'Top Employee Earners (Combined Salary & Commissions)',
              'top_employees',
              c),
          const SizedBox(height: 12),
          for (final emp in topEmployees)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: c.accent.withValues(alpha: 0.15),
                child: Text(
                  (emp['employee']?.toString().isNotEmpty ?? false)
                      ? emp['employee'].toString().substring(0, 1).toUpperCase()
                      : 'E',
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
              title: Text(
                emp['employee'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Salary: ${formatPeso(emp['salary'] as num)} • Comm: ${formatPeso(emp['commission'] as num)} • LD: ${formatPeso(emp['ld_commission'] as num)}',
                style: TextStyle(color: c.muted, fontSize: 11),
              ),
              trailing: Text(
                formatPeso(emp['total'] as num),
                style: TextStyle(
                  color: c.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(JoyceColors c, List top) {
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Top Products by Revenue', 'top_products', c),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const EmptyState(title: 'No sales recorded yet')
          else
            for (final p in top)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  p['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${p['units_sold']} base units sold • Gross Profit: ${formatPeso(p['gross_profit'] as num)}',
                ),
                trailing: Text(
                  formatPeso(p['revenue'] as num),
                  style: TextStyle(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildVariantSalesCard(JoyceColors c, List variantSales) {
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Variant & Pack Sales Breakdown', 'variant_sales', c),
          const SizedBox(height: 10),
          if (variantSales.isEmpty)
            const EmptyState(title: 'No variant sales in period')
          else
            for (final v in variantSales.take(15))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${v['name']} ${(v['variant_name'] as String).isEmpty ? "(Single / Base Unit)" : "(${v['variant_name']} — ${v['units_per']} units)"}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Packs Sold: ${v['packs_sold']} • Total Base Units: ${v['base_units_sold']} • Gross Profit: ${formatPeso(v['gross_profit'] as num)}',
                ),
                trailing: Text(
                  formatPeso(v['revenue'] as num),
                  style: TextStyle(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildStockAlertsCard(JoyceColors c, List lowStock) {
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
              'Low / Out-of-Stock Items (${lowStock.length})', 'stock_alerts', c),
          const SizedBox(height: 10),
          if (lowStock.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'All active products have healthy stock',
            )
          else
            for (final item in lowStock)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item['name'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Threshold: ≤${item['low_stock']} • Price: ${formatPeso(item['price'] as num)}',
                ),
                trailing: Text(
                  '${item['stock']} in stock',
                  style: TextStyle(
                    color: (item['stock'] as num) <= 0 ? c.bad : c.warn,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildShiftHistoryCard(
      JoyceColors c, List<Map<String, dynamic>> shifts) {
    return JoyceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('Recent Shifts & Cash Drawer Reconciliation',
              'shift_history', c),
          const SizedBox(height: 12),
          if (shifts.isEmpty)
            const EmptyState(title: 'No shift history recorded')
          else
            for (final s in shifts.take(10))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s['status'] == 'open'
                      ? Icons.timelapse
                      : Icons.check_circle_outline,
                  color: s['status'] == 'open' ? c.warn : c.ok,
                  size: 20,
                ),
                title: Text(
                  'Shift #${s['id']} — ${s['business_date']} (${s['status'].toString().toUpperCase()})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Float: ${formatPeso(s['opening_cash'] as num)} • Opened: ${s['opened_by']} • Closed: ${s['closed_by'] ?? 'In progress'}'
                  '${(s['shortage'] as num?) != null && (s['shortage'] as num) != 0 ? " • Short/Over: ${formatPeso(s['shortage'] as num)}" : ""}',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
                trailing: s['shortage'] != null && (s['shortage'] as num) != 0
                    ? Chip(
                        backgroundColor: c.bad.withValues(alpha: 0.15),
                        label: Text(
                          formatPeso(s['shortage'] as num),
                          style: TextStyle(
                              color: c.bad,
                              fontWeight: FontWeight.bold,
                              fontSize: 11),
                        ),
                      )
                    : null,
              ),
        ],
      ),
    );
  }

  Widget _buildCardById(String cardId, JoyceColors c) {
    final daily = (_data['daily'] as List? ?? const []);
    final top = (_data['top'] as List? ?? const []);
    final lowStock = (_data['low_stock'] as List? ?? const []);
    final variantSales = (_data['variant_sales'] as List? ?? const []);
    final finance = (_data['finance_summary'] as Map<String, dynamic>?) ?? {};
    final topEmployees = ((_data['top_employees'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final shifts = ((_data['shift_history'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();

    switch (cardId) {
      case 'kpis':
        return _buildKpisCard(c);
      case 'daily_trend':
        return _buildDailyTrendCard(c, daily);
      case 'finance_breakdown':
        return _buildFinanceBreakdownCard(c, finance);
      case 'top_employees':
        return _buildTopEmployeesCard(c, topEmployees);
      case 'top_products':
        return _buildTopProductsCard(c, top);
      case 'variant_sales':
        return _buildVariantSalesCard(c, variantSales);
      case 'stock_alerts':
        return _buildStockAlertsCard(c, lowStock);
      case 'shift_history':
        return _buildShiftHistoryCard(c, shifts);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;

    return ReorderableListView(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 30),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Store Overview',
            subtitle:
                'Operational KPIs, daily performance, finance reports, and stock alerts',
            actions: [
              IconButton(
                tooltip: 'Export Daily P&L CSV',
                icon: Icon(Icons.download, color: c.accent, size: 20),
                onPressed: _exportPnl,
              ),
              IconButton(
                tooltip: 'Reset Card Layout',
                icon: Icon(Icons.restart_alt, color: c.muted, size: 20),
                onPressed: () {
                  setState(() {
                    _cardOrder = List<String>.from(
                        PosRepository.kDefaultDashboardCardOrder);
                  });
                  widget.appState.repo.saveDashboardCardOrder(_cardOrder);
                },
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
          const SizedBox(height: 16),
        ],
      ),
      // ignore: deprecated_member_use
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (newIndex > oldIndex) {
            newIndex -= 1;
          }
          final item = _cardOrder.removeAt(oldIndex);
          _cardOrder.insert(newIndex, item);
        });
        widget.appState.repo.saveDashboardCardOrder(_cardOrder);
      },
      children: [
        for (final cardId in _cardOrder)
          KeyedSubtree(
            key: ValueKey(cardId),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildCardById(cardId, c),
            ),
          ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
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
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: c.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _FinanceTile extends StatelessWidget {
  final String title;
  final num amount;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FinanceTile({
    required this.title,
    required this.amount,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.input,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 11, color: c.muted),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatPeso(amount),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$count entries in period',
              style: TextStyle(color: c.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
