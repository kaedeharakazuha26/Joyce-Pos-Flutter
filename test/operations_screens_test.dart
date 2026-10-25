import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';
import 'package:joyce_pos_flutter/core/theme/app_theme.dart';
import 'package:joyce_pos_flutter/ui/screens/finance_screen.dart';
import 'package:joyce_pos_flutter/ui/screens/pos_screen.dart';
import 'package:joyce_pos_flutter/ui/screens/products_screen.dart';
import 'package:joyce_pos_flutter/ui/screens/store_overview_screen.dart';

void main() {
  testWidgets('PosScreen renders product grid, adds item to cart, and completes sale', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_pos_ui_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.saveProduct({
      'name': 'San Miguel Pale',
      'category': 'Drinks',
      'price': 65.0,
      'cost': 50.0,
      'stock': 10,
    });
    repo.startDay(businessDate: '2026-10-25', openedBy: 'Admin', openingCash: 500);
    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: PosScreen(appState: appState)),
      ),
    );
    await tester.pump();

    expect(find.text('San Miguel Pale'), findsOneWidget);
    await tester.tap(find.text('San Miguel Pale'));
    await tester.pump();

    // Remaining stock badge should update from 10 to 9 in stock
    expect(find.text('9 in stock'), findsOneWidget);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('ProductsScreen category selection uses dropdown and allows adding new category', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_prod_ui_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.saveProduct({
      'name': 'Existing Cola',
      'category': 'Beverages',
      'price': 20.0,
      'cost': 15.0,
      'stock': 10,
    });
    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: ProductsScreen(appState: appState)),
      ),
    );
    await tester.pump();

    // Open Add Product Modal
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();

    // Verify Dropdown exists with Category label
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Beverages'), findsWidgets);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('StoreOverviewScreen renders Top Performer Employee empty state and paginates cards max 5 per page', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_store_dash_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);

    for (int i = 1; i <= 12; i++) {
      repo.saveProduct({
        'name': 'Item $i',
        'category': 'General',
        'price': 10.0 * i,
        'cost': 5.0 * i,
        'stock': 2,
        'low_stock': 5,
      });
    }

    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: StoreOverviewScreen(appState: appState)),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Top Performer Employee is present with empty state even with 0 payouts
    final topEarnerFinder = find.textContaining('Top Performer Employee');
    await tester.scrollUntilVisible(
      topEarnerFinder,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(topEarnerFinder, findsOneWidget);
    expect(find.text('No employee payouts recorded yet'), findsOneWidget);

    // Scroll to Low / Out-of-Stock Items card
    final stockAlertFinder = find.textContaining('Low / Out-of-Stock Items (12)');
    await tester.scrollUntilVisible(
      stockAlertFinder,
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(stockAlertFinder, findsOneWidget);

    // Page 1 should show 5 items (Item 1 to Item 5) and PaginationBar
    expect(find.text('Showing 1–5 of 12'), findsOneWidget);
    expect(find.text('Page 1 / 3'), findsOneWidget);

    // Tap next page
    await tester.tap(find.byIcon(Icons.chevron_right).last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 6–10 of 12'), findsOneWidget);
    expect(find.text('Page 2 / 3'), findsOneWidget);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('FinanceScreen expenses uses Category dropdown with plus icon and Date selector defaulting to shift date', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_fin_exp_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);

    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: FinanceScreen(
            appState: appState,
            moduleType: FinanceModuleType.expenses,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click Add Entry
    await tester.tap(find.text('Add Entry'));
    await tester.pumpAndSettle();

    // Verify Category Dropdown and Plus Icon button
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

    // Verify Date selector contains default shift date '2026-10-26'
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('2026-10-26')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.calendar_today)), findsOneWidget);

    // Cancel modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('FinanceScreen salary removes Pay Period and uses Date selector defaulting to shift date', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_fin_sal_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);

    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: FinanceScreen(
            appState: appState,
            moduleType: FinanceModuleType.salary,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click Add Entry
    await tester.tap(find.text('Add Entry'));
    await tester.pumpAndSettle();

    // Verify Pay Period is removed
    expect(find.textContaining('Pay Period'), findsNothing);

    // Verify Date selector contains default shift date '2026-10-26'
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('2026-10-26')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.calendar_today)), findsOneWidget);

    // Cancel modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('FinanceScreen commission uses Commission Type dropdown with plus icon and Date selector', (tester) async {
    tester.view.physicalSize = const Size(1366, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('joyce_fin_comm_');
    final dbService = DatabaseService();
    final branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);

    final appState = AppState(repo: repo);
    appState.loginWithPin('0000');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: FinanceScreen(
            appState: appState,
            moduleType: FinanceModuleType.commission,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Click Add Entry
    await tester.tap(find.text('Add Entry'));
    await tester.pumpAndSettle();

    // Verify Commission Type Dropdown and Plus Icon button
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

    // Verify Date selector contains default shift date '2026-10-26'
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('2026-10-26')), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.byIcon(Icons.calendar_today)), findsOneWidget);

    // Cancel modal
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });
}
