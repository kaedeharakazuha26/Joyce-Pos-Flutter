import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';

void main() {
  late Directory tempDir;
  late DatabaseService dbService;
  late BranchManager branchMgr;
  late PosRepository repo;
  late AppState appState;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('joyce_state_');
    dbService = DatabaseService();
    branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    repo = PosRepository(dbService: dbService, branchManager: branchMgr);
    appState = AppState(repo: repo);
  });

  tearDown(() {
    dbService.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('loginWithPin sets default landing tab and shift gating blocks POS when shift is closed', () {
    final err = appState.loginWithPin('0000');
    expect(err, isNull);
    expect(appState.currentUser?['role'], 'admin');
    expect(appState.activeTab, 'admin-dashboard');
    expect(appState.isShiftOpen, false);

    // Navigating to shift-gated tab while closed returns false (triggers SOD modal)
    final allowed = appState.navigateToTab('pos');
    expect(allowed, false);
    expect(appState.activeTab, 'admin-dashboard');

    appState.openShift(openingCash: 500, notes: 'Morning float');
    expect(appState.isShiftOpen, true);

    final allowedNow = appState.navigateToTab('pos');
    expect(allowedNow, true);
    expect(appState.activeTab, 'pos');
  });
}
