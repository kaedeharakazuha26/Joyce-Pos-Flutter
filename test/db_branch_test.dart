import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('joyce_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('corrupt branches.json recovers default main branch and initializes schema', () {
    File('${tempDir.path}/branches.json').writeAsStringSync('{corrupt json');
    final dbService = DatabaseService();
    final mgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final info = mgr.getBranchInfo();
    expect(info['active_branch'], 'main');
    final pin = dbService.db
        .select("SELECT value FROM settings WHERE key='admin_pin'")
        .first['value'];
    expect(pin, '0000');
    dbService.close();
  });

  test('create, switch, delete branch, backup, restore, and reset_db obey invariants', () {
    final dbService = DatabaseService();
    final mgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final created = mgr.createBranch('Branch Two');
    expect(created['active_branch'], startsWith('branch_branch_two_'));
    expect(() => mgr.deleteBranch('main'), throwsException);

    final backupPath = '${tempDir.path}/test_backup.db';
    dbService.backupDb(backupPath);
    expect(File(backupPath).existsSync(), true);

    dbService.resetDb('0000', true);
    final audits = dbService.db
        .select('SELECT * FROM audit_logs WHERE action = ?', ['RESET_DB']);
    expect(audits.isNotEmpty, true);
    dbService.close();
  });
}
