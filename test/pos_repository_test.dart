import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';

void main() {
  late Directory tempDir;
  late DatabaseService dbService;
  late BranchManager branchMgr;
  late PosRepository repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('joyce_repo_');
    dbService = DatabaseService();
    branchMgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    repo = PosRepository(dbService: dbService, branchManager: branchMgr);
  });

  tearDown(() {
    dbService.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('variant sale deducts pack units (allowing negative stock) and void restores stock', () {
    final prodId = repo.saveProduct({
      'name': 'Cola',
      'price': 15.0,
      'cost': 10.0,
      'stock': 5,
      'variants': [
        {'name': '6-Pack', 'qty': 6, 'price': 85.0},
      ],
    });
    final product = repo.listProducts().firstWhere((p) => p['id'] == prodId);
    final variantId = (product['variants'] as List).first['id'] as int;

    repo.startDay(businessDate: '2026-10-25', openedBy: 'Admin', openingCash: 500);
    final sale = repo.createSale(
      items: [
        {'product_id': prodId, 'variant_id': variantId, 'quantity': 2},
      ],
      paid: 200,
    );

    expect(sale['receipt_no'], 'JP-20261025-0001');
    expect(sale['total'], 170.0);
    expect(sale['change_amt'], 30.0);

    // 5 - (6 * 2) = -7 base units
    final afterSale = repo.listProducts().firstWhere((p) => p['id'] == prodId);
    expect(afterSale['stock'], -7);

    // Void restores +12 -> +5
    repo.voidSale(id: sale['id'] as int, reason: 'Customer changed mind', voidedBy: 'Admin');
    final afterVoid = repo.listProducts().firstWhere((p) => p['id'] == prodId);
    expect(afterVoid['stock'], 5);
  });

  test('shift attribution across midnight and disabled module outflow exclusion', () {
    repo.startDay(businessDate: '2026-10-25', openedBy: 'Admin', openingCash: 1000);
    final prodId = repo.saveProduct({'name': 'Bread', 'price': 50.0, 'cost': 30.0, 'stock': 20});
    repo.createSale(items: [{'product_id': prodId, 'quantity': 2}], paid: 100);
    repo.saveExpense({'category': 'Ice', 'description': 'Ice bags', 'amount': 40.0, 'date': '2026-10-25'});
    repo.saveSalary({'employee': 'Juan', 'amount': 200.0, 'date': '2026-10-25'});

    // Disable salary module
    repo.setSettings({'disabled_menus': '["salary"]'});

    final status = repo.getShiftStatus();
    final shift = status['shift'] as Map<String, dynamic>;
    // Expected cash = 1000 + 100 - 40 (salary 200 excluded because disabled) = 1060
    expect(shift['expected_cash'], 1060.0);

    final dash = repo.dashboard(from: '2026-10-25', to: '2026-10-25');
    expect(dash['revenue'], 100.0);
    expect(dash['cogs'], 60.0);
    expect(dash['gross_profit'], 40.0);
    expect(dash['overheads'], 40.0); // salary excluded
    expect(dash['net_profit'], 0.0);
  });

  test('post-midnight sale in open shift attributes to shift business_date and admin_dashboard math works', () {
    repo.startDay(businessDate: '2026-10-25', openedBy: 'Admin', openingCash: 300);
    final prodId = repo.saveProduct({'name': 'Coffee', 'price': 25.0, 'cost': 12.0, 'stock': 10});
    final sale = repo.createSale(items: [{'product_id': prodId, 'quantity': 2}], paid: 50);
    // Simulate wall-clock timestamp after midnight while shift is still 2026-10-25
    dbService.db.execute(
      "UPDATE sales SET created_at = '2026-10-26 00:45:00' WHERE id = ?",
      [sale['id']],
    );

    final sales25 = repo.listSales(from: '2026-10-25', to: '2026-10-25');
    expect(sales25.length, 1);
    expect(sales25.first['business_date'], '2026-10-25');

    final adminDash = repo.adminDashboard(from: '2026-10-25', to: '2026-10-25');
    expect(adminDash['revenue'], 50.0);
    expect(adminDash['cogs'], 24.0);
    expect(adminDash['gross_profit'], 26.0);
  });
}
