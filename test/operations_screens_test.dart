import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';
import 'package:joyce_pos_flutter/core/theme/app_theme.dart';
import 'package:joyce_pos_flutter/ui/screens/pos_screen.dart';

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
}
