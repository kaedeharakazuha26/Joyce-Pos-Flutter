import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/money.dart';
import '../../core/utils/receipt_builder.dart';
import '../widgets/joyce_widgets.dart';

Future<bool> showSodModal(BuildContext context, AppState appState) async {
  final dateCtrl = TextEditingController(text: todayDateString());
  final cashCtrl = TextEditingController(text: '0');
  final notesCtrl = TextEditingController();
  String? error;

  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.joyce;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.wb_sunny_outlined, color: c.accent),
              const SizedBox(width: 10),
              const Text('Start of Day (SOD)'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open a new business shift to unlock POS and finance modules.',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Business Date (YYYY-MM-DD)',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cashCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Opening Cash Float (₱)',
                    prefixIcon: Icon(Icons.payments_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Shift Notes (optional)',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: TextStyle(color: c.bad, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            JoyceButton(
              label: 'Open Shift',
              icon: Icons.play_arrow,
              onPressed: () {
                try {
                  final opening = double.tryParse(cashCtrl.text.trim()) ?? 0.0;
                  appState.openShift(
                    businessDate: dateCtrl.text.trim(),
                    openingCash: opening,
                    notes: notesCtrl.text.trim(),
                  );
                  Navigator.of(ctx).pop(true);
                } catch (e) {
                  setState(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
            ),
          ],
        );
      },
    ),
  );
  return res == true;
}

Future<void> showEodModal(BuildContext context, AppState appState) async {
  final shift = appState.activeShift;
  if (shift == null) return;

  final expected = r2((shift['expected_cash'] as num?) ?? 0);
  final closingCtrl = TextEditingController(text: expected.toStringAsFixed(2));
  final notesCtrl = TextEditingController(text: (shift['notes'] ?? '').toString());
  String activeView = 'reconciliation'; // 'reconciliation' | 'receipt'
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.joyce;
        final counted = r2(double.tryParse(closingCtrl.text.trim()) ?? 0);
        final variance = r2(counted - expected);
        final zData = appState.repo.getZReadingData(
          shiftId: shift['id'] as int?,
          closingCash: counted,
          closingNotes: notesCtrl.text,
          closedBy: appState.currentUserName,
        );
        final zText = ReceiptBuilder.buildZReadingText(
          zData,
          appState.settings,
          appState.repo.getDisabledMenus(),
        );

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.nights_stay_outlined, color: c.accent),
                  const SizedBox(width: 10),
                  Text('End of Day (EOD) — Shift #${shift['id']}'),
                ],
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'reconciliation',
                    label: Text('Reconciliation'),
                  ),
                  ButtonSegment(
                    value: 'receipt',
                    label: Text('Z-Reading Preview'),
                  ),
                ],
                selected: {activeView},
                onSelectionChanged: (s) => setState(() => activeView = s.first),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: activeView == 'receipt'
                  ? Center(
                      child: ReceiptPreviewWidget(
                        receiptText: zText,
                        columns: ReceiptBuilder.resolveWidth(appState.settings),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SummaryRow(
                          label: 'Business Date',
                          value: (shift['business_date'] ?? '').toString(),
                        ),
                        _SummaryRow(
                          label: 'Opening Float',
                          value: formatPeso((shift['opening_cash'] as num?) ?? 0),
                        ),
                        _SummaryRow(
                          label: '+ Gross Cash Sales (${shift['orders_count'] ?? 0} orders)',
                          value: formatPeso((shift['cash_sales'] as num?) ?? 0),
                          valueColor: c.ok,
                        ),
                        _SummaryRow(
                          label: '- Total Drawer Outflows',
                          value: '-${formatPeso((shift['total_outflows'] as num?) ?? 0)}',
                          valueColor: c.bad,
                        ),
                        const Divider(height: 20),
                        _SummaryRow(
                          label: 'Expected Cash in Drawer',
                          value: formatPeso(expected),
                          isBold: true,
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: closingCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Actual Cash Counted (₱)',
                            prefixIcon: Icon(Icons.calculate_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.bg2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: variance.abs() < 0.01
                                  ? c.ok
                                  : (variance > 0 ? c.info : c.bad),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Drawer Variance',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                variance.abs() < 0.01
                                    ? '₱0.00 (Balanced)'
                                    : (variance > 0
                                        ? '+${formatPeso(variance)} (Overage)'
                                        : '${formatPeso(variance)} (Shortage)'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: variance.abs() < 0.01
                                      ? c.ok
                                      : (variance > 0 ? c.info : c.bad),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtrl,
                          maxLines: 2,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Closing Notes',
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(error!, style: TextStyle(color: c.bad, fontSize: 12)),
                        ],
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
              label: 'Print Z-Reading',
              icon: Icons.print_outlined,
              outline: true,
              onPressed: () async {
                try {
                  await appState.printZReading(
                    shiftId: shift['id'] as int?,
                    closingCash: counted,
                    closingNotes: notesCtrl.text,
                  );
                  if (ctx.mounted) {
                    showJoyceToast(ctx, 'Z-Reading sent to printer');
                  }
                } catch (e) {
                  setState(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
            ),
            JoyceButton(
              label: 'Close Shift & Backup',
              icon: Icons.check_circle_outline,
              onPressed: () {
                try {
                  final summary = appState.closeShift(
                    closingCash: counted,
                    notes: notesCtrl.text,
                  );
                  Navigator.of(ctx).pop();
                  final backup = summary['eod_backup'] as Map<String, dynamic>?;
                  if (backup?['ok'] == true) {
                    showJoyceToast(
                      context,
                      'Shift closed & EOD backup saved',
                    );
                  } else {
                    showJoyceToast(
                      context,
                      'Shift closed (Backup warning: ${backup?['error'] ?? 'none'})',
                    );
                  }
                } catch (e) {
                  setState(() => error = e.toString().replaceFirst('Exception: ', ''));
                }
              },
            ),
          ],
        );
      },
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
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
            value,
            style: TextStyle(
              color: valueColor ?? c.text,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: isBold ? 15 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
