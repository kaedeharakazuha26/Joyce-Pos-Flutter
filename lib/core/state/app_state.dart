import 'package:flutter/material.dart';
import '../../data/pos_repository.dart';
import '../utils/printer_service.dart';
import '../utils/receipt_builder.dart';

class AppState extends ChangeNotifier {
  final PosRepository repo;
  final PrinterService printerService;

  Map<String, dynamic>? _currentUser;
  String _activeTab = 'pos';
  bool _sidebarCollapsed = false;
  Map<String, String> _settings = {};
  Map<String, dynamic> _shiftStatus = {'is_open': false, 'shift': null};
  Map<String, dynamic> _branchInfo = {};
  List<Map<String, dynamic>> _alerts = [];
  final Set<String> _dismissedAlertIds = {};
  String _deepLinkFilter = '';
  String _adminSubTab = 'overview';
  int _branchGeneration = 0;

  static const Set<String> shiftGatedTabs = {
    'pos',
    'expenses',
    'commission',
    'ld-commission',
    'salary',
  };

  AppState({
    required this.repo,
    PrinterService? printerService,
  }) : printerService = printerService ?? PrinterService() {
    refreshAll();
  }

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?['role'] == 'admin';
  String get currentUserName =>
      (_currentUser?['name'] as String?) ?? 'Administrator';
  String get currentUserRole => (_currentUser?['role'] as String?) ?? 'admin';

  String get activeTab => _activeTab;
  bool get sidebarCollapsed => _sidebarCollapsed;
  Map<String, String> get settings => _settings;
  Map<String, dynamic> get shiftStatus => _shiftStatus;
  bool get isShiftOpen => _shiftStatus['is_open'] == true;
  Map<String, dynamic>? get activeShift =>
      _shiftStatus['shift'] as Map<String, dynamic>?;
  Map<String, dynamic> get branchInfo => _branchInfo;
  String get activeBranchName {
    final branches = (_branchInfo['branches'] as List? ?? const []);
    final activeId = _branchInfo['active_branch'];
    for (final b in branches) {
      if (b is Map && b['id'] == activeId) {
        return (b['name'] ?? 'Main Store').toString();
      }
    }
    return 'Main Store';
  }

  String get deepLinkFilter => _deepLinkFilter;
  String get adminSubTab => _adminSubTab;
  int get branchGeneration => _branchGeneration;

  ThemeMode get themeMode =>
      (_settings['theme'] == 'light') ? ThemeMode.light : ThemeMode.dark;

  List<Map<String, dynamic>> get activeAlerts => _alerts
      .where((a) => !_dismissedAlertIds.contains(a['id']?.toString() ?? ''))
      .toList();

  void refreshAll() {
    _settings = repo.getSettings();
    _shiftStatus = repo.getShiftStatus();
    _branchInfo = repo.branchManager.getBranchInfo();
    _alerts = repo.computeAlerts();
    notifyListeners();
  }

  String? loginWithPin(String pin) {
    try {
      final user = repo.verifyPin(pin);
      _currentUser = user;
      refreshAll();
      final disabled = repo.getDisabledMenus();
      if (user['role'] == 'admin') {
        _activeTab = disabled.contains('admin-dashboard')
            ? 'dashboard'
            : 'admin-dashboard';
      } else {
        final perms = (user['permissions'] as List? ?? const ['pos'])
            .map((e) => e.toString())
            .toList();
        _activeTab = perms.contains('pos') ? 'pos' : perms.first;
      }
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  void logout() {
    _currentUser = null;
    _deepLinkFilter = '';
    notifyListeners();
  }

  void toggleSidebar() {
    _sidebarCollapsed = !_sidebarCollapsed;
    notifyListeners();
  }

  void toggleTheme() {
    final next = (_settings['theme'] == 'light') ? 'dark' : 'light';
    _settings = repo.setSettings(
      {'theme': next},
      actor: currentUserName,
      role: currentUserRole,
    );
    notifyListeners();
  }

  bool canAccessTab(String tabId) {
    if (_currentUser == null) return false;
    final disabled = repo.getDisabledMenus();
    if (disabled.contains(tabId.toLowerCase())) return false;
    if (isAdmin) return true;
    if (tabId == 'admin-dashboard') return false;
    final perms = (_currentUser?['permissions'] as List? ?? const [])
        .map((e) => e.toString())
        .toSet();
    return perms.contains('*') || perms.contains(tabId);
  }

  /// Returns false if navigation is blocked by a closed shift (caller should open SOD modal).
  bool navigateToTab(
    String tabId, {
    String filter = '',
    String? adminSub,
  }) {
    if (shiftGatedTabs.contains(tabId) && !isShiftOpen) {
      return false;
    }
    _activeTab = tabId;
    _deepLinkFilter = filter;
    if (adminSub != null && adminSub.isNotEmpty) {
      _adminSubTab = adminSub;
    }
    notifyListeners();
    return true;
  }

  void clearDeepLinkFilter() {
    if (_deepLinkFilter.isNotEmpty) {
      _deepLinkFilter = '';
      notifyListeners();
    }
  }

  void setAdminSubTab(String subTab) {
    _adminSubTab = subTab;
    notifyListeners();
  }

  void dismissAlert(String alertId) {
    _dismissedAlertIds.add(alertId);
    notifyListeners();
  }

  void openShift({
    String? businessDate,
    required double openingCash,
    String notes = '',
  }) {
    _shiftStatus = repo.startDay(
      businessDate: businessDate,
      openedBy: currentUserName,
      openingCash: openingCash,
      notes: notes,
    );
    _alerts = repo.computeAlerts();
    notifyListeners();
  }

  Map<String, dynamic> closeShift({
    required double closingCash,
    String notes = '',
  }) {
    final res = repo.endDay(
      closingCash: closingCash,
      closedBy: currentUserName,
      notes: notes,
    );
    _shiftStatus = repo.getShiftStatus();
    _branchInfo = repo.branchManager.getBranchInfo();
    _alerts = repo.computeAlerts();
    notifyListeners();
    return res;
  }

  void switchBranch(String branchId) {
    _branchInfo = repo.branchManager.switchBranch(branchId);
    _branchGeneration++;
    _dismissedAlertIds.clear();
    refreshAll();
  }

  void createBranch(String name) {
    _branchInfo = repo.branchManager.createBranch(name);
    _branchGeneration++;
    _dismissedAlertIds.clear();
    refreshAll();
  }

  void deleteBranch(String branchId) {
    _branchInfo = repo.branchManager.deleteBranch(branchId);
    _branchGeneration++;
    refreshAll();
  }

  Future<void> printSaleReceipt(Map<String, dynamic> sale) async {
    final bytes = ReceiptBuilder.buildReceiptBytes(sale, _settings);
    await printerService.sendBytes(bytes, _settings);
  }

  Future<void> printZReading({
    int? shiftId,
    double? closingCash,
    String? closingNotes,
  }) async {
    final zData = repo.getZReadingData(
      shiftId: shiftId,
      closingCash: closingCash,
      closingNotes: closingNotes,
      closedBy: currentUserName,
    );
    final bytes = ReceiptBuilder.buildZReadingBytes(
      zData,
      _settings,
      repo.getDisabledMenus(),
    );
    await printerService.sendBytes(bytes, _settings);
  }
}
