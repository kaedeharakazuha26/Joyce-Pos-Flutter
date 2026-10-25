import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';

class EmployeesScreen extends StatefulWidget {
  final AppState appState;

  const EmployeesScreen({super.key, required this.appState});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _employees = widget.appState.repo.listEmployees();
    });
  }

  void _openModal([Map<String, dynamic>? existing]) {
    final nameCtrl =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final posCtrl =
        TextEditingController(text: existing?['position']?.toString() ?? '');
    final salCtrl = TextEditingController(
      text: existing != null
          ? ((existing['salary'] as num?) ?? 0).toStringAsFixed(2)
          : '0',
    );
    final comCtrl = TextEditingController(
      text: existing != null
          ? ((existing['commission'] as num?) ?? 0).toStringAsFixed(2)
          : '0',
    );
    final ldCtrl = TextEditingController(
      text: existing != null
          ? ((existing['ld_commission'] as num?) ?? 0).toStringAsFixed(2)
          : '0',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Employee' : 'Edit Employee'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Full Name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: posCtrl,
                decoration: const InputDecoration(
                  labelText: 'Position / Role',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: salCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Default Salary Rate (₱)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: comCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default Comm (₱)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ldCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Default LD Comm (₱)',
                      ),
                    ),
                  ),
                ],
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
            label: 'Save Employee',
            icon: Icons.check,
            onPressed: () {
              try {
                widget.appState.repo.saveEmployee(
                  {
                    'id': existing?['id'],
                    'name': nameCtrl.text,
                    'position': posCtrl.text,
                    'salary': salCtrl.text,
                    'commission': comCtrl.text,
                    'ld_commission': ldCtrl.text,
                  },
                  actor: widget.appState.currentUserName,
                  role: widget.appState.currentUserRole,
                );
                Navigator.of(ctx).pop();
                _reload();
                showJoyceToast(context, 'Employee saved');
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
          title: 'Employees Roster',
          subtitle:
              '${_employees.length} active staff member(s) • Default rates prefill payroll & commission forms',
          actions: [
            JoyceButton(
              label: 'Add Employee',
              icon: Icons.person_add_outlined,
              onPressed: () => _openModal(),
            ),
          ],
        ),
        Expanded(
          child: JoyceCard(
            padding: const EdgeInsets.all(12),
            child: _employees.isEmpty
                ? const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No employees added yet',
                  )
                : ListView.separated(
                    itemCount: _employees.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final emp = _employees[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.accent.withValues(alpha: 0.2),
                          child: Text(
                            (emp['name'] as String)[0].toUpperCase(),
                            style: TextStyle(
                              color: c.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          emp['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Position: ${(emp['position'] as String).isEmpty ? "Staff" : emp['position']} • Salary: ${formatPeso(emp['salary'] as num)} • Comm: ${formatPeso(emp['commission'] as num)} • LD: ${formatPeso(emp['ld_commission'] as num)}',
                          style: TextStyle(color: c.muted, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _openModal(emp),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.archive_outlined,
                                size: 18,
                                color: c.bad,
                              ),
                              onPressed: () {
                                widget.appState.repo.deleteEmployee(
                                  emp['id'] as int,
                                  actor: widget.appState.currentUserName,
                                  role: widget.appState.currentUserRole,
                                );
                                _reload();
                                showJoyceToast(
                                  context,
                                  'Archived ${emp['name']}',
                                );
                              },
                            ),
                          ],
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
