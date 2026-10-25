import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/main.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';

void main() {
  testWidgets('App launches into PinLockScreen and unlocks with default admin PIN 0000', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_ui_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    final appState = AppState(repo: repo);

    await tester.pumpWidget(JoycePosApp(appState: appState));
    await tester.pump();

    expect(find.textContaining('JOYCE POS'), findsWidgets);
    final unlocked = appState.loginWithPin('0000');
    expect(unlocked, isNull); // null error = success
    expect(appState.currentUser?['role'], 'admin');
    await tester.pump();

    expect(find.textContaining('Store Overview'), findsWidgets);
    expect(find.textContaining('Admin Dashboard'), findsNothing);

    // Verify pinned Admin Lock button exists and locks back to PinLockScreen
    final lockBtn = find.byTooltip('Lock Terminal (Admin Lock)');
    expect(lockBtn, findsOneWidget);
    await tester.tap(lockBtn);
    await tester.pump();

    expect(appState.isLoggedIn, false);
    expect(find.textContaining('Enter your Cashier or Administrator PIN'), findsOneWidget);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('StoreOverviewScreen renders ReorderableListView with finance overheads and top employee earners', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_overview_ui_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 1000);
    repo.saveExpense({'category': 'Electricity', 'description': 'Monthly bill', 'amount': 250.0, 'date': '2026-10-26'});
    repo.saveSalary({'employee': 'Maria Santos', 'amount': 450.0, 'date': '2026-10-26'});
    repo.saveCommission({'employee_name': 'Maria Santos', 'type': 'sales', 'amount': 150.0, 'date': '2026-10-26'});
    repo.saveLdCommission({'employee_name': 'Maria Santos', 'amount': 100.0, 'date': '2026-10-26'});

    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(JoycePosApp(appState: appState));
    await tester.pumpAndSettle();

    // Verify ReorderableListView is present
    expect(find.byType(ReorderableListView), findsOneWidget);

    // Verify CSV export actions for both Daily P&L and Product Sales
    expect(find.byTooltip('Export Daily P&L CSV'), findsOneWidget);
    expect(find.byTooltip('Export Product Sales CSV'), findsOneWidget);

    final dashData = repo.dashboard(from: '2026-10-01', to: '2026-10-31');
    expect((dashData['top_employees'] as List).isNotEmpty, isTrue);

    // Scroll to Finance Overheads Breakdown
    final financeFinder = find.textContaining('Finance & Overheads Breakdown');
    await tester.scrollUntilVisible(
      financeFinder,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(financeFinder, findsOneWidget);
    expect(find.textContaining('Store Expenses'), findsWidgets);

    // Scroll to Top Performer Employee
    final topEarnersFinder = find.textContaining('Top Performer Employee');
    await tester.scrollUntilVisible(
      topEarnersFinder,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    // Verify Top Performer Employee card displays Maria Santos
    expect(topEarnersFinder, findsOneWidget);
    expect(find.textContaining('Maria Santos'), findsOneWidget);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });
}
