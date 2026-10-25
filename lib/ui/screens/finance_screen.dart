import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';

enum FinanceModuleType {
  expenses,
  salary,
  commission,
  ldCommission,
}

class FinanceScreen extends StatefulWidget {
  final AppState appState;
  final FinanceModuleType moduleType;

  const FinanceScreen({
    super.key,
    required this.appState,
    required this.moduleType,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late String _from;
  late String _to;
  String _preset = 'this_month';
  int _page = 1;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    final bDate = widget.appState.repo.activeBusinessDate();
    _from = '${bDate.substring(0, 7)}-01';
    _to = bDate;
    _reload();
  }

  String get _title {
    switch (widget.moduleType) {
      case FinanceModuleType.expenses:
        return 'Store Expenses';
      case FinanceModuleType.salary:
        return 'Salary Payroll';
      case FinanceModuleType.commission:
        return 'Commissions';
      case FinanceModuleType.ldCommission:
        return 'LD Commissions';
    }
  }

  void _reload() {
    final repo = widget.appState.repo;
    setState(() {
      switch (widget.moduleType) {
        case FinanceModuleType.expenses:
          _rows = repo.listExpenses(from: _from, to: _to);
          break;
        case FinanceModuleType.salary:
          _rows = repo.listSalaries(from: _from, to: _to);
          break;
        case FinanceModuleType.commission:
          _rows = repo.listCommissions(from: _from, to: _to);
          break;
        case FinanceModuleType.ldCommission:
          _rows = repo.listLdCommissions(from: _from, to: _to);
          break;
      }
      _page = 1;
    });
  }

  void _openEditModal([Map<String, dynamic>? existing]) {
    final repo = widget.appState.repo;
    final employees = repo.listEmployees();
    final commTypes = repo.listCommissionTypes();
    final bDate = repo.activeBusinessDate();

    final dateCtrl = TextEditingController(
      text: existing?['date']?.toString() ?? bDate,
    );
    final amountCtrl = TextEditingController(
      text: existing != null
          ? ((existing['amount'] as num?) ?? 0).toStringAsFixed(2)
          : '',
    );
    final categoryCtrl = TextEditingController(
      text: existing?['category']?.toString() ?? 'General',
    );
    final descCtrl = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );
    final empCtrl = TextEditingController(
      text: (existing?['employee'] ?? existing?['employee_name'] ?? '')
          .toString(),
    );
    final periodCtrl = TextEditingController(
      text: existing?['period']?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(
      text: existing?['note']?.toString() ?? '',
    );
    final typeCtrl = TextEditingController(
      text: existing?['type']?.toString() ??
          (commTypes.isNotEmpty ? commTypes.first : 'Sales'),
    );
    final qtyCtrl = TextEditingController(
      text: '${existing?['quantity'] ?? 1}',
    );
    int? selectedEmpId = existing?['employee_id'] as int?;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return AlertDialog(
            title: Text(
              '${existing == null ? "Add" : "Edit"} $_title Record',
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.moduleType != FinanceModuleType.expenses &&
                        employees.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: employees.any((e) => e['id'] == selectedEmpId)
                            ? selectedEmpId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Select Employee Roster (Prefills Default)',
                        ),
                        items: [
                          for (final e in employees)
                            DropdownMenuItem<int>(
                              value: e['id'] as int,
                              child: Text('${e['name']} (${e['position']})'),
                            ),
                        ],
                        onChanged: (empId) {
                          final emp = employees.firstWhere(
                            (e) => e['id'] == empId,
                          );
                          setModalState(() {
                            selectedEmpId = empId;
                            empCtrl.text = emp['name'].toString();
                            if (widget.moduleType == FinanceModuleType.salary &&
                                (emp['salary'] as num) > 0) {
                              amountCtrl.text =
                                  (emp['salary'] as num).toStringAsFixed(2);
                            } else if (widget.moduleType ==
                                    FinanceModuleType.commission &&
                                (emp['commission'] as num) > 0) {
                              amountCtrl.text =
                                  (emp['commission'] as num).toStringAsFixed(2);
                            } else if (widget.moduleType ==
                                    FinanceModuleType.ldCommission &&
                                (emp['ld_commission'] as num) > 0) {
                              final qty =
                                  int.tryParse(qtyCtrl.text.trim()) ?? 1;
                              amountCtrl.text = ((emp['ld_commission'] as num) *
                                      qty)
                                  .toStringAsFixed(2);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.moduleType == FinanceModuleType.expenses) ...[
                      TextField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Category (e.g., Utilities, Supplies, Ice)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: empCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Employee Name *',
                        ),
                      ),
                    ],
                    if (widget.moduleType == FinanceModuleType.salary) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: periodCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Pay Period (e.g., Oct 1–15)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Note',
                        ),
                      ),
                    ],
                    if (widget.moduleType == FinanceModuleType.commission) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: typeCtrl,
                        decoration: InputDecoration(
                          labelText:
                              'Commission Type (${commTypes.join(", ")})',
                        ),
                      ),
                    ],
                    if (widget.moduleType ==
                        FinanceModuleType.ldCommission) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'LD Quantity',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount (₱) *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: dateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Date (YYYY-MM-DD)',
                            ),
                          ),
                        ),
                      ],
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
                label: 'Save',
                icon: Icons.check,
                onPressed: () {
                  try {
                    final actor = widget.appState.currentUserName;
                    final role = widget.appState.currentUserRole;
                    switch (widget.moduleType) {
                      case FinanceModuleType.expenses:
                        repo.saveExpense(
                          {
                            'id': existing?['id'],
                            'category': categoryCtrl.text,
                            'description': descCtrl.text,
                            'amount': amountCtrl.text,
                            'date': dateCtrl.text,
                          },
                          actor: actor,
                          role: role,
                        );
                        break;
                      case FinanceModuleType.salary:
                        repo.saveSalary(
                          {
                            'id': existing?['id'],
                            'employee': empCtrl.text,
                            'period': periodCtrl.text,
                            'note': noteCtrl.text,
                            'amount': amountCtrl.text,
                            'date': dateCtrl.text,
                          },
                          actor: actor,
                          role: role,
                        );
                        break;
                      case FinanceModuleType.commission:
                        repo.saveCommission(
                          {
                            'id': existing?['id'],
                            'employee_id': selectedEmpId,
                            'employee_name': empCtrl.text,
                            'type': typeCtrl.text,
                            'amount': amountCtrl.text,
                            'date': dateCtrl.text,
                          },
                          actor: actor,
                          role: role,
                        );
                        break;
                      case FinanceModuleType.ldCommission:
                        repo.saveLdCommission(
                          {
                            'id': existing?['id'],
                            'employee_id': selectedEmpId,
                            'employee_name': empCtrl.text,
                            'quantity': qtyCtrl.text,
                            'amount': amountCtrl.text,
                            'date': dateCtrl.text,
                          },
                          actor: actor,
                          role: role,
                        );
                        break;
                    }
                    Navigator.of(ctx).pop();
                    _reload();
                    widget.appState.refreshAll();
                    showJoyceToast(context, 'Saved record');
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

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final authorized = await confirmAdminPinIfRequired(
      context,
      repo: widget.appState.repo,
      isAlreadyAdmin: widget.appState.isAdmin,
    );
    if (!authorized) return;

    final id = row['id'] as int;
    final repo = widget.appState.repo;
    final actor = widget.appState.currentUserName;
    final role = widget.appState.currentUserRole;

    switch (widget.moduleType) {
      case FinanceModuleType.expenses:
        repo.deleteExpense(id, actor: actor, role: role);
        break;
      case FinanceModuleType.salary:
        repo.deleteSalary(id, actor: actor, role: role);
        break;
      case FinanceModuleType.commission:
        repo.deleteCommission(id, actor: actor, role: role);
        break;
      case FinanceModuleType.ldCommission:
        repo.deleteLdCommission(id, actor: actor, role: role);
        break;
    }
    _reload();
    widget.appState.refreshAll();
    if (mounted) {
      showJoyceToast(context, 'Deleted record #$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final total = r2(
      _rows.fold<double>(
        0.0,
        (acc, r) => acc + ((r['amount'] as num?)?.toDouble() ?? 0.0),
      ),
    );
    const pageSize = 20;
    final paged = _rows.skip((_page - 1) * pageSize).take(pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: _title,
          subtitle:
              '${_rows.length} record(s) in period • Total: ${formatPeso(total)}',
          actions: [
            JoyceButton(
              label: 'Export CSV',
              icon: Icons.download_outlined,
              outline: true,
              onPressed: () async {
                final path = await CsvExporter.exportCsvDialog(
                  defaultFileName:
                      '${_title.toLowerCase().replaceAll(" ", "_")}_${_from}_$_to.csv',
                  headers: ['ID', 'Business Date', 'Label', 'Details', 'Amount'],
                  rows: _rows
                      .map((r) => [
                            r['id'],
                            r['business_date'] ?? r['date'],
                            r['category'] ??
                                r['employee'] ??
                                r['employee_name'] ??
                                '',
                            r['description'] ??
                                r['period'] ??
                                r['type'] ??
                                'Qty: ${r['quantity'] ?? 1}',
                            r['amount'],
                          ])
                      .toList(),
                );
                if (path != null && context.mounted) {
                  showJoyceToast(context, 'Exported CSV to $path');
                }
              },
            ),
            JoyceButton(
              label: 'Add Entry',
              icon: Icons.add,
              onPressed: () => _openEditModal(),
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
                ? EmptyState(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'No $_title records in selected date range',
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: paged.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final r = paged[i];
                            String titleText;
                            String subText;
                            switch (widget.moduleType) {
                              case FinanceModuleType.expenses:
                                titleText = '${r['category']}';
                                subText =
                                    '${r['business_date']} • ${(r['description'] as String).isEmpty ? "No description" : r['description']}';
                                break;
                              case FinanceModuleType.salary:
                                titleText = '${r['employee']}';
                                subText =
                                    '${r['business_date']} • Period: ${(r['period'] as String).isEmpty ? "—" : r['period']} • ${r['note']}';
                                break;
                              case FinanceModuleType.commission:
                                titleText =
                                    '${r['employee_name']} (${r['type']})';
                                subText = 'Business Date: ${r['business_date']}';
                                break;
                              case FinanceModuleType.ldCommission:
                                titleText = '${r['employee_name']}';
                                subText =
                                    'Business Date: ${r['business_date']} • Quantity: ${r['quantity']}';
                                break;
                            }

                            return ListTile(
                              title: Text(
                                titleText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                subText,
                                style: TextStyle(color: c.muted, fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    formatPeso(r['amount'] as num),
                                    style: TextStyle(
                                      color: c.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    onPressed: () => _openEditModal(r),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: c.bad,
                                    ),
                                    onPressed: () => _deleteRow(r),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      PaginationBar(
                        currentPage: _page,
                        totalItems: _rows.length,
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
