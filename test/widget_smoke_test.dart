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

    expect(find.textContaining('Admin Dashboard'), findsWidgets);

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });
}
