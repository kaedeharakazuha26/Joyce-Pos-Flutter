import 'package:flutter/material.dart';
import 'core/db/branch_manager.dart';
import 'core/db/database_service.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'data/pos_repository.dart';
import 'ui/screens/admin_dashboard_screen.dart';
import 'ui/screens/employees_screen.dart';
import 'ui/screens/finance_screen.dart';
import 'ui/screens/inventory_screen.dart';
import 'ui/screens/pos_screen.dart';
import 'ui/screens/products_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/store_overview_screen.dart';
import 'ui/screens/transactions_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/pin_lock_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dbService = DatabaseService();
  final branchManager = BranchManager(dbService: dbService);
  final repo = PosRepository(
    dbService: dbService,
    branchManager: branchManager,
  );
  final appState = AppState(repo: repo);
  runApp(JoycePosApp(appState: appState));
}

class JoycePosApp extends StatelessWidget {
  final AppState appState;

  const JoycePosApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'JOYCE POS',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: appState.themeMode,
          home: appState.isLoggedIn
              ? AppShell(
                  appState: appState,
                  screenBuilder: (tabId) => _buildScreen(tabId),
                )
              : PinLockScreen(appState: appState),
        );
      },
    );
  }

  Widget _buildScreen(String tabId) {
    switch (tabId) {
      case 'admin-dashboard':
        return AdminDashboardScreen(appState: appState);
      case 'dashboard':
        return StoreOverviewScreen(appState: appState);
      case 'pos':
        return PosScreen(appState: appState);
      case 'transactions':
        return TransactionsScreen(appState: appState);
      case 'products':
        return ProductsScreen(appState: appState);
      case 'inventory':
        return InventoryScreen(appState: appState);
      case 'expenses':
        return FinanceScreen(
          appState: appState,
          moduleType: FinanceModuleType.expenses,
        );
      case 'salary':
        return FinanceScreen(
          appState: appState,
          moduleType: FinanceModuleType.salary,
        );
      case 'commission':
        return FinanceScreen(
          appState: appState,
          moduleType: FinanceModuleType.commission,
        );
      case 'ld-commission':
        return FinanceScreen(
          appState: appState,
          moduleType: FinanceModuleType.ldCommission,
        );
      case 'employees':
        return EmployeesScreen(appState: appState);
      case 'settings':
        return SettingsScreen(appState: appState);
      default:
        return PosScreen(appState: appState);
    }
  }
}
