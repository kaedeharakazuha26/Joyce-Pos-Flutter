import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/barcode_scanner_service.dart';
import '../../core/utils/money.dart';
import '../widgets/joyce_widgets.dart';
import 'sod_eod_modals.dart';

class NavItemSpec {
  final String id;
  final String label;
  final IconData icon;
  final String group;
  final bool adminOnly;

  const NavItemSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.adminOnly = false,
  });
}

const List<NavItemSpec> kNavSpecs = [
  // 1. Analytics & Control
  NavItemSpec(
    id: 'dashboard',
    label: 'Store Overview',
    icon: Icons.dashboard_outlined,
    group: 'Analytics & Control',
  ),
  // 2. Operations
  NavItemSpec(
    id: 'pos',
    label: 'Point of Sale',
    icon: Icons.point_of_sale_outlined,
    group: 'Operations',
  ),
  NavItemSpec(
    id: 'transactions',
    label: 'Transactions',
    icon: Icons.receipt_long_outlined,
    group: 'Operations',
  ),
  // 3. Inventory & Catalog
  NavItemSpec(
    id: 'products',
    label: 'Products Catalog',
    icon: Icons.inventory_2_outlined,
    group: 'Inventory & Catalog',
  ),
  NavItemSpec(
    id: 'inventory',
    label: 'Stock & Restock',
    icon: Icons.warehouse_outlined,
    group: 'Inventory & Catalog',
  ),
  // 4. Finance & Payroll
  NavItemSpec(
    id: 'expenses',
    label: 'Store Expenses',
    icon: Icons.money_off_csred_outlined,
    group: 'Finance & Payroll',
  ),
  NavItemSpec(
    id: 'salary',
    label: 'Salary Payroll',
    icon: Icons.account_balance_wallet_outlined,
    group: 'Finance & Payroll',
  ),
  NavItemSpec(
    id: 'commission',
    label: 'Commissions',
    icon: Icons.workspace_premium_outlined,
    group: 'Finance & Payroll',
  ),
  NavItemSpec(
    id: 'ld-commission',
    label: 'LD Commissions',
    icon: Icons.phone_android_outlined,
    group: 'Finance & Payroll',
  ),
  // 5. Administration
  NavItemSpec(
    id: 'employees',
    label: 'Employees',
    icon: Icons.badge_outlined,
    group: 'Administration',
  ),
  NavItemSpec(
    id: 'settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    group: 'Administration',
  ),
];

class AppShell extends StatefulWidget {
  final AppState appState;
  final Widget Function(String activeTab) screenBuilder;

  const AppShell({
    super.key,
    required this.appState,
    required this.screenBuilder,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void Function()? _unsubGlobalScanner;

  @override
  void initState() {
    super.initState();
    BarcodeScannerService.instance.init();
    _unsubGlobalScanner = BarcodeScannerService.instance.subscribe((barcode) {
      if (!mounted) return;
      if (widget.appState.activeTab != 'pos' && widget.appState.activeTab != 'products') {
        if (widget.appState.isShiftOpen) {
          widget.appState.navigateToTab('pos');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            BarcodeScannerService.instance.dispatch(barcode);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _unsubGlobalScanner?.call();
    super.dispose();
  }

  Future<void> _handleNavTap(String tabId, {String filter = ''}) async {
    final allowed = widget.appState.navigateToTab(tabId, filter: filter);
    if (!allowed && mounted) {
      final opened = await showSodModal(context, widget.appState);
      if (opened) {
        widget.appState.navigateToTab(tabId, filter: filter);
      }
    }
  }

  void _handleAlertClick(Map<String, dynamic> alert) {
    final target = (alert['target_tab'] ?? 'dashboard').toString();
    final filter = (alert['filter'] ?? '').toString();
    if (target == 'shifts' && filter == 'open_sod') {
      showSodModal(context, widget.appState);
      return;
    }
    const mapToOp = {
      'sales': 'transactions',
      'products': 'products',
      'expenses': 'expenses',
      'salaries': 'salary',
      'commissions': 'commission',
      'ld-commissions': 'ld-commission',
      'employees': 'employees',
      'shifts': 'dashboard',
    };
    final dest = mapToOp[target] ?? 'dashboard';
    _handleNavTap(dest, filter: filter);
  }

  void _openGlobalSearchDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _GlobalSearchModal(
        appState: widget.appState,
        onNavigate: (tab, {filter = ''}) {
          Navigator.of(ctx).pop();
          _handleNavTap(tab, filter: filter);
        },
      ),
    );
  }

  void _openBranchModal() {
    if (!widget.appState.isAdmin) return;
    final nameCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final info = widget.appState.branchInfo;
          final branches = (info['branches'] as List? ?? const []);
          final activeId = info['active_branch'];
          return AlertDialog(
            title: const Text('Store Branches'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final b in branches)
                    if (b is Map)
                      ListTile(
                        leading: Icon(
                          b['id'] == activeId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: ctx.joyce.accent,
                        ),
                        title: Text((b['name'] ?? '').toString()),
                        subtitle: Text((b['file'] ?? '').toString()),
                        onTap: () {
                          widget.appState.switchBranch(b['id'].toString());
                          Navigator.of(ctx).pop();
                          showJoyceToast(
                            context,
                            'Switched to ${b['name']}',
                          );
                        },
                      ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'New Branch Name',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      JoyceButton(
                        label: 'Add Branch',
                        icon: Icons.add,
                        onPressed: () {
                          if (nameCtrl.text.trim().isEmpty) return;
                          widget.appState.createBranch(nameCtrl.text.trim());
                          Navigator.of(ctx).pop();
                          showJoyceToast(
                            context,
                            'Created & switched to new branch',
                          );
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
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final appState = widget.appState;
    final collapsed = appState.sidebarCollapsed;
    final visibleSpecs =
        kNavSpecs.where((s) => appState.canAccessTab(s.id)).toList();

    final groups = <String, List<NavItemSpec>>{};
    for (final spec in visibleSpecs) {
      groups.putIfAbsent(spec.group, () => []).add(spec);
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openGlobalSearchDialog,
      },
      child: Scaffold(
          backgroundColor: c.bg,
          body: Row(
            children: [
              // Left Sidebar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: collapsed ? 72 : 248,
                decoration: BoxDecoration(
                  color: c.bg2,
                  border: Border(right: BorderSide(color: c.borderSubtle)),
                ),
                child: Column(
                  children: [
                    // Brand header
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: c.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: c.buttonGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.point_of_sale,
                              color: c.btnText,
                              size: 20,
                            ),
                          ),
                          if (!collapsed) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appState.settings['store_name'] ??
                                        'JOYCE POS',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    appState.activeBranchName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: c.accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Nav Groups
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        children: [
                          for (final entry in groups.entries) ...[
                            if (!collapsed)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 10,
                                  top: 10,
                                  bottom: 6,
                                ),
                                child: Text(
                                  entry.key.toUpperCase(),
                                  style: TextStyle(
                                    color: c.muted,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            for (final item in entry.value)
                              _SidebarNavTile(
                                spec: item,
                                selected: appState.activeTab == item.id,
                                collapsed: collapsed,
                                isLockedByShift: AppState.shiftGatedTabs
                                        .contains(item.id) &&
                                    !appState.isShiftOpen,
                                onTap: () => _handleNavTap(item.id),
                              ),
                          ],
                        ],
                      ),
                    ),
                    // Collapse toggle
                    Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                              Border(top: BorderSide(color: c.borderSubtle)),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            collapsed
                                ? Icons.keyboard_double_arrow_right
                                : Icons.keyboard_double_arrow_left,
                            color: c.muted,
                          ),
                          title: collapsed
                              ? null
                              : Text(
                                  'Collapse Sidebar',
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: c.muted, fontSize: 12),
                                ),
                          onTap: appState.toggleSidebar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Right Main Content Area
              Expanded(
                child: Column(
                  children: [
                    // Top Bar
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: c.bg2,
                        border: Border(
                          bottom: BorderSide(color: c.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Global Search Button (Ctrl+K)
                          Flexible(
                            child: InkWell(
                              onTap: _openGlobalSearchDialog,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 260),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: c.input,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: c.borderSubtle),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search,
                                        size: 17, color: c.muted),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Search (Ctrl+K)...',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: c.muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Shift Status / SOD / EOD Button
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        if (appState.isShiftOpen) {
                                          showEodModal(context, appState);
                                        } else {
                                          showSodModal(context, appState);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: appState.isShiftOpen
                                              ? c.ok.withValues(alpha: 0.14)
                                              : c.warn.withValues(alpha: 0.14),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: appState.isShiftOpen
                                                ? c.ok
                                                : c.warn,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              appState.isShiftOpen
                                                  ? Icons.check_circle
                                                  : Icons.warning_amber_rounded,
                                              size: 15,
                                              color: appState.isShiftOpen
                                                  ? c.ok
                                                  : c.warn,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              appState.isShiftOpen
                                                  ? 'Shift Open (${appState.activeShift?['business_date']}) • End Day'
                                                  : 'Shift Closed • Start Day (SOD)',
                                              style: TextStyle(
                                                color: c.text,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Branch Switcher (only admin can edit/switch branch; disabled for cashier)
                                    Tooltip(
                                      message: appState.isAdmin
                                          ? 'Switch or manage branches'
                                          : 'Branch management is restricted to Administrator',
                                      child: OutlinedButton.icon(
                                        onPressed: appState.isAdmin
                                            ? _openBranchModal
                                            : null,
                                        icon: Icon(
                                          Icons.storefront_outlined,
                                          size: 16,
                                          color: appState.isAdmin
                                              ? c.accent
                                              : c.muted,
                                        ),
                                        label: Text(
                                          appState.activeBranchName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: appState.isAdmin
                                                ? null
                                                : c.muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Alerts Bell
                                    PopupMenuButton<Map<String, dynamic>>(
                                      tooltip: 'Alerts & Notifications',
                                      icon: Badge(
                                        isLabelVisible:
                                            appState.activeAlerts.isNotEmpty,
                                        label: Text(
                                            '${appState.activeAlerts.length}'),
                                        child: Icon(
                                          Icons.notifications_outlined,
                                          color: c.text,
                                        ),
                                      ),
                                      onSelected: _handleAlertClick,
                                      itemBuilder: (ctx) {
                                        final list = appState.activeAlerts;
                                        if (list.isEmpty) {
                                          return [
                                            const PopupMenuItem(
                                              enabled: false,
                                              child: Text('No active alerts'),
                                            ),
                                          ];
                                        }
                                        return list.map((a) {
                                          final sev = a['severity'] ?? 'info';
                                          final sevColor = sev == 'bad'
                                              ? c.bad
                                              : (sev == 'warn'
                                                  ? c.warn
                                                  : c.info);
                                          return PopupMenuItem<
                                              Map<String, dynamic>>(
                                            value: a,
                                            child: SizedBox(
                                              width: 300,
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.circle,
                                                    size: 10,
                                                    color: sevColor,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          (a['title'] ?? '')
                                                              .toString(),
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        Text(
                                                          (a['description'] ??
                                                                  '')
                                                              .toString(),
                                                          style: TextStyle(
                                                            color: c.muted,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.close,
                                                      size: 14,
                                                    ),
                                                    onPressed: () {
                                                      appState.dismissAlert(
                                                        a['id'].toString(),
                                                      );
                                                      Navigator.of(ctx).pop();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList();
                                      },
                                    ),
                                    // Theme Toggle
                                    IconButton(
                                      tooltip: 'Switch Theme',
                                      onPressed: appState.toggleTheme,
                                      icon: Icon(
                                        appState.themeMode == ThemeMode.dark
                                            ? Icons.light_mode_outlined
                                            : Icons.dark_mode_outlined,
                                        color: c.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.input,
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border:
                                            Border.all(color: c.borderSubtle),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.person_outline,
                                              size: 14, color: c.accent),
                                          const SizedBox(width: 5),
                                          Text(
                                            appState.currentUserName,
                                            style: TextStyle(
                                              color: c.text,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Pinned Admin Lock Button
                          IconButton(
                            tooltip: 'Lock Terminal (Admin Lock)',
                            style: IconButton.styleFrom(
                              backgroundColor: c.bad.withValues(alpha: 0.12),
                              side: BorderSide(
                                  color: c.bad.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.all(8),
                            ),
                            icon: Icon(Icons.lock_outline,
                                color: c.bad, size: 18),
                            onPressed: appState.logout,
                          ),
                        ],
                      ),
                    ),
                    // Active Screen Body
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey(
                          '${appState.branchGeneration}-${appState.activeTab}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: widget.screenBuilder(appState.activeTab),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

class _SidebarNavTile extends StatelessWidget {
  final NavItemSpec spec;
  final bool selected;
  final bool collapsed;
  final bool isLockedByShift;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.spec,
    required this.selected,
    required this.collapsed,
    required this.isLockedByShift,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? c.accent.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? c.accent : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  spec.icon,
                  size: 19,
                  color: selected ? c.accent : c.muted,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      spec.label,
                      style: TextStyle(
                        color: selected ? c.text : c.muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (isLockedByShift)
                    Icon(
                      Icons.lock_clock_outlined,
                      size: 14,
                      color: c.warn,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchModal extends StatefulWidget {
  final AppState appState;
  final void Function(String tab, {String filter}) onNavigate;

  const _GlobalSearchModal({
    required this.appState,
    required this.onNavigate,
  });

  @override
  State<_GlobalSearchModal> createState() => _GlobalSearchModalState();
}

class _GlobalSearchModalState extends State<_GlobalSearchModal> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  Map<String, List<Map<String, dynamic>>> _results = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _results = widget.appState.repo.globalSearch(q);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final products = _results['products'] ?? [];
    final sales = _results['sales'] ?? [];
    final expenses = _results['expenses'] ?? [];
    final employees = _results['employees'] ?? [];

    return AlertDialog(
      title: TextField(
        controller: _ctrl,
        autofocus: true,
        onChanged: _onQueryChanged,
        decoration: const InputDecoration(
          hintText: 'Search products, receipts, expenses, employees...',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      content: SizedBox(
        width: 560,
        height: 400,
        child: _ctrl.text.trim().isEmpty
            ? const EmptyState(
                icon: Icons.manage_search,
                title: 'Type to search across all store records',
              )
            : ListView(
                children: [
                  if (products.isNotEmpty) ...[
                    Text(
                      'PRODUCTS',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final p in products)
                      ListTile(
                        dense: true,
                        title: Text(p['name'].toString()),
                        subtitle: Text(
                          'Stock: ${p['stock']} • ${formatPeso(p['price'] as num)}',
                        ),
                        onTap: () => widget.onNavigate('products'),
                      ),
                  ],
                  if (sales.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'SALES',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final s in sales)
                      ListTile(
                        dense: true,
                        title: Text(s['receipt_no'].toString()),
                        subtitle: Text(
                          '${s['created_at']} • ${formatPeso(s['total'] as num)} (${s['status']})',
                        ),
                        onTap: () => widget.onNavigate('transactions'),
                      ),
                  ],
                  if (expenses.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'EXPENSES',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final e in expenses)
                      ListTile(
                        dense: true,
                        title: Text('${e['category']} — ${e['description']}'),
                        subtitle: Text(
                          '${e['date']} • ${formatPeso(e['amount'] as num)}',
                        ),
                        onTap: () => widget.onNavigate('expenses'),
                      ),
                  ],
                  if (employees.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'EMPLOYEES',
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    for (final emp in employees)
                      ListTile(
                        dense: true,
                        title: Text(emp['name'].toString()),
                        subtitle: Text(emp['position'].toString()),
                        onTap: () => widget.onNavigate('employees'),
                      ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
