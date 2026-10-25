import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
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

  @override
  void initState() {
    super.initState();
    final bDate = widget.appState.repo.activeBusinessDate();
    final r = resolveDatePreset('this_month', bDate);
    _from = r.from;
    _to = r.to;
    _reload();
  }

  void _reload() {
    setState(() {
      _data = widget.appState.repo.dashboard(from: _from, to: _to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final daily = (_data['daily'] as List? ?? const []);
    final top = (_data['top'] as List? ?? const []);
    final lowStock = (_data['low_stock'] as List? ?? const []);
    final variantSales = (_data['variant_sales'] as List? ?? const []);

    return ListView(
      children: [
        PageHeader(
          title: 'Store Overview',
          subtitle: 'Operational KPIs, daily performance, and stock alerts',
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
        // KPI Grid
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
              sub: 'Margin: ${_data['gross_margin'] ?? 0}% • COGS: ${formatPeso((_data['cogs'] as num?) ?? 0)}',
              color: c.ok,
            ),
            _KpiTile(
              label: 'Total Overheads',
              value: formatPeso((_data['overheads'] as num?) ?? 0),
              sub: 'Enabled finance modules',
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
              sub: 'Cost: ${formatPeso((_data['inventory_cost'] as num?) ?? 0)} • Potential: ${formatPeso((_data['potential_profit'] as num?) ?? 0)}',
              color: c.info,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Daily Sales & Net Trend Chart
        JoyceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daily Revenue vs Net Operating Cash Flow',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
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
                                    ((daily[i]['sales'] as num?) ?? 0)
                                        .toDouble(),
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
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Products
            Expanded(
              child: JoyceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Products by Revenue',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
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
              ),
            ),
            const SizedBox(width: 16),
            // Low Stock Alerts
            Expanded(
              child: JoyceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Low / Out-of-Stock Items (${lowStock.length})',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
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
                              color: (item['stock'] as num) <= 0
                                  ? c.bad
                                  : c.warn,
                              fontWeight: FontWeight.w700,
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
        // Variant-Level Sales Viewer
        JoyceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Variant & Pack Sales Breakdown',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
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
