import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/csv_exporter.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/receipt_builder.dart';
import '../widgets/joyce_widgets.dart';

class SettingsScreen extends StatefulWidget {
  final AppState appState;

  const SettingsScreen({super.key, required this.appState});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _section = 'store'; // store | printer | security | cashiers | modules | branches | audit

  late TextEditingController _storeNameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _headerCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _networkAddrCtrl;
  late TextEditingController _serialPathCtrl;
  late TextEditingController _usbNameCtrl;

  String _paperWidth = '58';
  String _fontSize = 'normal';
  String _headerAlign = 'center';
  String _footerAlign = 'center';
  String _printerConn = 'none';
  bool _autoPrint = false;
  bool _cutPaper = true;
  bool _openDrawer = false;
  int _copies = 1;
  int _feedLines = 3;

  @override
  void initState() {
    super.initState();
    _loadFromSettings();
  }

  void _loadFromSettings() {
    final s = widget.appState.settings;
    _storeNameCtrl = TextEditingController(text: s['store_name'] ?? 'JOYCE POS');
    _addressCtrl = TextEditingController(text: s['store_address'] ?? '');
    _phoneCtrl = TextEditingController(text: s['store_phone'] ?? '');
    _headerCtrl = TextEditingController(text: s['receipt_header'] ?? '');
    _footerCtrl = TextEditingController(
      text: s['receipt_footer'] ?? 'Thank you! Come again.',
    );
    _networkAddrCtrl = TextEditingController(
      text: s['network_addr'] ?? '192.168.1.100:9100',
    );
    _serialPathCtrl = TextEditingController(text: s['serial_path'] ?? 'COM1');
    _usbNameCtrl = TextEditingController(text: s['usb_vid'] ?? '');

    _paperWidth = s['paper_width'] ?? '58';
    _fontSize = s['font_size'] ?? 'normal';
    _headerAlign = s['header_align'] ?? 'center';
    _footerAlign = s['footer_align'] ?? 'center';
    _printerConn = s['printer_conn'] ?? 'none';
    _autoPrint = s['auto_print'] == '1';
    _cutPaper = (s['cut_paper'] ?? '1') == '1';
    _openDrawer = s['open_drawer'] == '1';
    _copies = int.tryParse(s['copies'] ?? '1') ?? 1;
    _feedLines = int.tryParse(s['feed_lines'] ?? '3') ?? 3;
  }

  Map<String, String> _currentPreviewSettings() {
    return {
      ...widget.appState.settings,
      'store_name': _storeNameCtrl.text,
      'store_address': _addressCtrl.text,
      'store_phone': _phoneCtrl.text,
      'receipt_header': _headerCtrl.text,
      'receipt_footer': _footerCtrl.text,
      'paper_width': _paperWidth,
      'chars_per_line': _paperWidth == '80' ? '48' : '32',
      'font_size': _fontSize,
      'header_align': _headerAlign,
      'footer_align': _footerAlign,
      'printer_conn': _printerConn,
      'network_addr': _networkAddrCtrl.text,
      'serial_path': _serialPathCtrl.text,
      'usb_vid': _usbNameCtrl.text,
      'auto_print': _autoPrint ? '1' : '0',
      'cut_paper': _cutPaper ? '1' : '0',
      'open_drawer': _openDrawer ? '1' : '0',
      'copies': '$_copies',
      'feed_lines': '$_feedLines',
    };
  }

  void _saveStoreAndPrinterSettings() {
    widget.appState.repo.setSettings(
      _currentPreviewSettings(),
      actor: widget.appState.currentUserName,
      role: widget.appState.currentUserRole,
    );
    widget.appState.refreshAll();
    showJoyceToast(context, 'Settings saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    const sections = [
      (id: 'store', label: 'Store & Receipt', icon: Icons.receipt_outlined),
      (id: 'printer', label: 'Printer Setup', icon: Icons.print_outlined),
      (id: 'security', label: 'Security & PIN', icon: Icons.security_outlined),
      (id: 'cashiers', label: 'Cashier Accounts', icon: Icons.people_outline),
      (id: 'modules', label: 'Module Toggles', icon: Icons.tune_outlined),
      (id: 'branches', label: 'Branches & Backups', icon: Icons.storage_outlined),
      (id: 'audit', label: 'Audit Logs', icon: Icons.history_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'System Settings',
          subtitle:
              'Configure store layout, thermal printing, permissions, multi-branch storage, and backups',
          actions: [
            JoyceButton(
              label: widget.appState.themeMode == ThemeMode.dark
                  ? 'Switch to White Gold (Light)'
                  : 'Switch to Black Gold (Dark)',
              icon: Icons.brightness_6_outlined,
              outline: true,
              onPressed: widget.appState.toggleTheme,
            ),
          ],
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in sections)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(s.icon, size: 15),
                    label: Text(s.label, style: const TextStyle(fontSize: 12)),
                    selected: _section == s.id,
                    selectedColor: c.accent.withValues(alpha: 0.25),
                    onSelected: (_) => setState(() => _section = s.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(child: _buildSectionBody(context)),
      ],
    );
  }

  Widget _buildSectionBody(BuildContext context) {
    final c = context.joyce;
    switch (_section) {
      case 'store':
        final previewSale = {
          'receipt_no': 'JP-20261025-0001',
          'created_at': '2026-10-25 14:30:00',
          'status': 'completed',
          'total': 185.0,
          'paid': 200.0,
          'change_amt': 15.0,
          'items': [
            {
              'name': 'San Miguel Pale',
              'variant_name': '6-Pack',
              'quantity': 1,
              'unit_price': 150.0,
              'subtotal': 150.0,
            },
            {
              'name': 'lucky Me Pancit Canton',
              'variant_name': '',
              'quantity': 2,
              'unit_price': 17.5,
              'subtotal': 35.0,
            },
          ],
        };
        final previewCfg = _currentPreviewSettings();
        final previewText =
            ReceiptBuilder.buildReceiptText(previewSale, previewCfg);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: JoyceCard(
                child: ListView(
                  children: [
                    TextField(
                      controller: _storeNameCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Store Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _addressCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Store Address'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Contact Phone'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _headerCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Receipt Header Note'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _footerCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration:
                          const InputDecoration(labelText: 'Receipt Footer Note'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _paperWidth,
                            decoration:
                                const InputDecoration(labelText: 'Paper Width'),
                            items: const [
                              DropdownMenuItem(
                                value: '58',
                                child: Text('58 mm (32 cols)'),
                              ),
                              DropdownMenuItem(
                                value: '80',
                                child: Text('80 mm (48 cols)'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _paperWidth = v ?? '58'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _headerAlign,
                            decoration: const InputDecoration(
                              labelText: 'Header Alignment',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'left',
                                child: Text('Left'),
                              ),
                              DropdownMenuItem(
                                value: 'center',
                                child: Text('Center'),
                              ),
                              DropdownMenuItem(
                                value: 'right',
                                child: Text('Right'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _headerAlign = v ?? 'center'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    JoyceButton(
                      label: 'Save Store & Receipt Layout',
                      icon: Icons.save_outlined,
                      onPressed: _saveStoreAndPrinterSettings,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: JoyceCard(
                child: Column(
                  children: [
                    Text(
                      'Live Thermal Receipt Preview',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ReceiptPreviewWidget(
                          receiptText: previewText,
                          columns: _paperWidth == '80' ? 48 : 32,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case 'printer':
        return JoyceCard(
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _printerConn,
                decoration:
                    const InputDecoration(labelText: 'Printer Connection Mode'),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('None / Screen Preview Only'),
                  ),
                  DropdownMenuItem(
                    value: 'network',
                    child: Text('Network LAN (TCP Raw Port 9100)'),
                  ),
                  DropdownMenuItem(
                    value: 'serial',
                    child: Text('Serial / Bluetooth Virtual COM Port'),
                  ),
                  DropdownMenuItem(
                    value: 'usb',
                    child: Text('Windows Installed USB / Spooler Printer'),
                  ),
                ],
                onChanged: (v) => setState(() => _printerConn = v ?? 'none'),
              ),
              const SizedBox(height: 12),
              if (_printerConn == 'network')
                TextField(
                  controller: _networkAddrCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Network Address (host:port, default 9100)',
                  ),
                ),
              if (_printerConn == 'serial' || _printerConn == 'bluetooth')
                TextField(
                  controller: _serialPathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'COM Port (e.g., COM1, COM3)',
                  ),
                ),
              if (_printerConn == 'usb')
                TextField(
                  controller: _usbNameCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'Windows Printer Name (blank = Default Windows Printer)',
                  ),
                ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Auto-print receipt after every sale'),
                value: _autoPrint,
                onChanged: (v) => setState(() => _autoPrint = v),
              ),
              SwitchListTile(
                title: const Text('Send paper cut command (GS V 66 0)'),
                value: _cutPaper,
                onChanged: (v) => setState(() => _cutPaper = v),
              ),
              SwitchListTile(
                title: const Text('Pulse cash drawer kick (ESC p)'),
                value: _openDrawer,
                onChanged: (v) => setState(() => _openDrawer = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  JoyceButton(
                    label: 'Save Printer Settings',
                    icon: Icons.save_outlined,
                    onPressed: _saveStoreAndPrinterSettings,
                  ),
                  const SizedBox(width: 12),
                  JoyceButton(
                    label: 'Test Print',
                    icon: Icons.print_outlined,
                    outline: true,
                    onPressed: () async {
                      try {
                        await widget.appState.printerService
                            .printTestPage(_currentPreviewSettings());
                        if (context.mounted) {
                          showJoyceToast(context, 'Test print sent');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showJoyceToast(
                            context,
                            e.toString().replaceFirst('Exception: ', ''),
                            isError: true,
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        );

      case 'security':
        final oldCtrl = TextEditingController();
        final newCtrl = TextEditingController();
        return JoyceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Change Administrator PIN (minimum 4 digits)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    TextField(
                      controller: oldCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Admin PIN',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Admin PIN (min 4 digits)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    JoyceButton(
                      label: 'Update Admin PIN',
                      icon: Icons.lock_reset,
                      onPressed: () {
                        try {
                          widget.appState.repo.changeAdminPin(
                            oldCtrl.text,
                            newCtrl.text,
                            actor: widget.appState.currentUserName,
                            role: widget.appState.currentUserRole,
                          );
                          widget.appState.refreshAll();
                          showJoyceToast(context, 'Admin PIN updated');
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
              ),
            ],
          ),
        );

      case 'cashiers':
        final cashiers = widget.appState.repo.listCashiers();
        return JoyceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cashier Accounts & Tab Permissions (${cashiers.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  JoyceButton(
                    label: 'Add Cashier',
                    icon: Icons.person_add_outlined,
                    onPressed: () => _openCashierModal(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: cashiers.isEmpty
                    ? const EmptyState(title: 'No cashier accounts created yet')
                    : ListView.separated(
                        itemCount: cashiers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final cs = cashiers[i];
                          final perms =
                              (cs['permissions_list'] as List? ?? const [])
                                  .join(', ');
                          return ListTile(
                            title: Text(
                              cs['name'].toString(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text('Allowed Tabs: $perms'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: () => _openCashierModal(cs),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: c.bad,
                                  ),
                                  onPressed: () {
                                    widget.appState.repo
                                        .deleteCashier(cs['id'] as int);
                                    setState(() {});
                                    showJoyceToast(
                                      context,
                                      'Deleted cashier ${cs['name']}',
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );

      case 'modules':
        final disabled = widget.appState.repo.getDisabledMenus();
        const toggleableModules = [
          (id: 'expenses', label: 'Store Expenses'),
          (id: 'salary', label: 'Salary Payroll'),
          (id: 'commission', label: 'Commissions'),
          (id: 'ld-commission', label: 'LD Commissions'),
          (id: 'employees', label: 'Employees Roster'),
        ];
        return JoyceCard(
          child: ListView(
            children: [
              const Text(
                'Enable or Disable Optional Store Modules',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Disabled modules are hidden from navigation and excluded from P&L overheads, EOD expected drawer cash, and Z-Reading reports.',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              for (final m in toggleableModules)
                SwitchListTile(
                  title: Text(m.label),
                  value: !disabled.contains(m.id),
                  onChanged: (enabled) {
                    final raw =
                        widget.appState.settings['disabled_menus'] ?? '[]';
                    final current = <String>{};
                    try {
                      for (final x in (jsonDecode(raw) as List)) {
                        current.add(x.toString());
                      }
                    } catch (_) {}
                    if (enabled) {
                      current.remove(m.id);
                    } else {
                      current.add(m.id);
                    }
                    widget.appState.repo.setSettings({
                      'disabled_menus': jsonEncode(current.toList()),
                    });
                    widget.appState.refreshAll();
                    setState(() {});
                  },
                ),
            ],
          ),
        );

      case 'branches':
        final info = widget.appState.branchInfo;
        final branches = (info['branches'] as List? ?? const []);
        return JoyceCard(
          child: ListView(
            children: [
              const Text(
                'Multi-Branch & Database Backups',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Active DB: ${info['active_db_path'] ?? ''}\nCloud/Backup Sync Folder: ${(info['storage_dir'] ?? '').toString().isEmpty ? "Not configured (using local AppData)" : info['storage_dir']}\nLast Snapshot: ${info['last_backup_at'] ?? 'Never'}',
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  JoyceButton(
                    label: 'Set Backup / Cloud Sync Folder',
                    icon: Icons.folder_open_outlined,
                    outline: true,
                    onPressed: () async {
                      final dir = await CsvExporter.pickFolder();
                      if (dir == null) return;
                      widget.appState.repo.branchManager.setStorageDir(dir);
                      widget.appState.refreshAll();
                      setState(() {});
                      if (context.mounted) {
                        showJoyceToast(context, 'Sync folder set to $dir');
                      }
                    },
                  ),
                  JoyceButton(
                    label: 'Manual Sync Snapshot Now',
                    icon: Icons.cloud_upload_outlined,
                    outline: true,
                    onPressed: () {
                      final nowTag =
                          'SYNC_${todayDateString()}_${DateTime.now().millisecondsSinceEpoch}';
                      final res = widget.appState.repo.branchManager
                          .performEodSnapshot(nowTag);
                      widget.appState.refreshAll();
                      setState(() {});
                      if (res['ok'] == true) {
                        showJoyceToast(
                          context,
                          'Snapshot saved to ${res['path']}',
                        );
                      }
                    },
                  ),
                  JoyceButton(
                    label: 'Export Backup (.db)',
                    icon: Icons.save_alt,
                    onPressed: () async {
                      final path = await CsvExporter.pickSaveFile(
                        defaultFileName: 'joyce_pos_backup_${todayDateString()}.db',
                        filter: 'SQLite Database (*.db)|*.db',
                      );
                      if (path == null) return;
                      widget.appState.repo.dbService.backupDb(path);
                      if (context.mounted) {
                        showJoyceToast(context, 'Backup saved to $path');
                      }
                    },
                  ),
                  JoyceButton(
                    label: 'Restore Backup (.db)',
                    icon: Icons.restore_page_outlined,
                    outline: true,
                    onPressed: () async {
                      final path = await CsvExporter.pickOpenFile(
                        filter: 'SQLite Database (*.db)|*.db',
                      );
                      if (path == null) return;
                      try {
                        widget.appState.repo.dbService.restoreDb(path);
                        widget.appState.refreshAll();
                        setState(() {});
                        if (context.mounted) {
                          showJoyceToast(
                            context,
                            'Database restored successfully',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showJoyceToast(
                            context,
                            e.toString().replaceFirst('Exception: ', ''),
                            isError: true,
                          );
                        }
                      }
                    },
                  ),
                  JoyceButton(
                    label: 'Reset Database',
                    icon: Icons.delete_forever_outlined,
                    danger: true,
                    onPressed: _promptResetDb,
                  ),
                ],
              ),
              const Divider(height: 28),
              const Text(
                'Configured Branches',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final b in branches)
                if (b is Map)
                  ListTile(
                    title: Text(b['name'].toString()),
                    subtitle: Text('${b['id']} • ${b['file']}'),
                    trailing: b['id'] == 'main'
                        ? const Chip(label: Text('Primary'))
                        : IconButton(
                            icon: Icon(Icons.delete_outline, color: c.bad),
                            onPressed: () {
                              try {
                                widget.appState
                                    .deleteBranch(b['id'].toString());
                                setState(() {});
                              } catch (e) {
                                showJoyceToast(
                                  context,
                                  e.toString().replaceFirst('Exception: ', ''),
                                  isError: true,
                                );
                              }
                            },
                          ),
                  ),
            ],
          ),
        );

      case 'audit':
        final bDate = widget.appState.repo.activeBusinessDate();
        final logs = widget.appState.repo.listAuditLogs(
          from: '2020-01-01',
          to: bDate,
          limit: 200,
        );
        return JoyceCard(
          child: ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final l = logs[i];
              return ListTile(
                dense: true,
                title: Text(
                  '[${l['action']}] ${l['summary']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${l['timestamp']} • ${l['actor']} (${l['role']})',
                  style: TextStyle(color: c.muted, fontSize: 11),
                ),
              );
            },
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  void _openCashierModal([Map<String, dynamic>? existing]) {
    final nameCtrl =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final pinCtrl =
        TextEditingController(text: existing?['pin']?.toString() ?? '');
    final perms = <String>{
      ...((existing?['permissions_list'] as List?)?.map((e) => e.toString()) ??
          const ['pos', 'transactions']),
    };
    const allTabs = [
      'dashboard',
      'pos',
      'transactions',
      'products',
      'inventory',
      'expenses',
      'salary',
      'commission',
      'ld-commission',
      'employees',
      'settings',
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(existing == null ? 'Add Cashier' : 'Edit Cashier'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Cashier Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Login PIN (min 4 digits) *',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in allTabs)
                      FilterChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        selected: perms.contains(t),
                        onSelected: (sel) {
                          setModalState(() {
                            if (sel) {
                              perms.add(t);
                            } else if (perms.length > 1) {
                              perms.remove(t);
                            }
                          });
                        },
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
              label: 'Save Cashier',
              onPressed: () {
                try {
                  widget.appState.repo.saveCashier({
                    'id': existing?['id'],
                    'name': nameCtrl.text,
                    'pin': pinCtrl.text,
                    'permissions_list': perms.toList(),
                  });
                  Navigator.of(ctx).pop();
                  setState(() {});
                  showJoyceToast(context, 'Cashier saved');
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
      ),
    );
  }

  void _promptResetDb() {
    final pinCtrl = TextEditingController();
    bool keepCatalog = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Reset Database'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: keepCatalog,
                  title: const Text(
                    'Keep Products, Variants, Employees & Cashiers',
                  ),
                  onChanged: (v) =>
                      setModalState(() => keepCatalog = v ?? true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Admin PIN *',
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
              label: 'Confirm Reset',
              danger: true,
              onPressed: () {
                try {
                  widget.appState.repo.dbService.resetDb(
                    pinCtrl.text,
                    keepCatalog,
                    actor: widget.appState.currentUserName,
                    role: widget.appState.currentUserRole,
                  );
                  Navigator.of(ctx).pop();
                  widget.appState.refreshAll();
                  setState(() {});
                  showJoyceToast(context, 'Database reset complete');
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
      ),
    );
  }
}
