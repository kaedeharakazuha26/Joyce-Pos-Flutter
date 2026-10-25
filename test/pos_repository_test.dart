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

  test('dashboard includes finance_summary, top_employees combining salary/comm/ld, and shift_history', () {
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);
    repo.saveExpense({'category': 'Rent', 'description': 'Monthly', 'amount': 150.0, 'date': '2026-10-26'});
    repo.saveSalary({'employee': 'Alice', 'amount': 300.0, 'date': '2026-10-26'});
    repo.saveCommission({'employee_name': 'Alice', 'type': 'sales', 'amount': 120.0, 'date': '2026-10-26'});
    repo.saveLdCommission({'employee_name': 'Alice', 'amount': 80.0, 'date': '2026-10-26'});
    repo.saveSalary({'employee': 'Bob', 'amount': 250.0, 'date': '2026-10-26'});

    final dash = repo.dashboard(from: '2026-10-26', to: '2026-10-26');
    final finance = dash['finance_summary'] as Map<String, dynamic>;
    expect(finance['expenses']['total'], 150.0);
    expect(finance['salaries']['total'], 550.0);
    expect(finance['commissions']['total'], 120.0);
    expect(finance['ld_commissions']['total'], 80.0);

    final topEarners = (dash['top_employees'] as List).cast<Map<String, dynamic>>();
    expect(topEarners.isNotEmpty, isTrue);
    // Alice = 300 + 120 + 80 = 500 total
    final alice = topEarners.firstWhere((e) => e['employee'] == 'Alice');
    expect(alice['salary'], 300.0);
    expect(alice['commission'], 120.0);
    expect(alice['ld_commission'], 80.0);
    expect(alice['total'], 500.0);

    final shifts = (dash['shift_history'] as List).cast<Map<String, dynamic>>();
    expect(shifts.isNotEmpty, isTrue);
    expect(shifts.first['business_date'], '2026-10-26');
  });

  test('disabling salary/commission/ld-commission masks them and empties top_employees', () {
    repo.startDay(businessDate: '2026-10-26', openedBy: 'Admin', openingCash: 500);
    repo.saveSalary({'employee': 'Alice', 'amount': 300.0, 'date': '2026-10-26'});
    repo.saveCommission({'employee_name': 'Alice', 'type': 'sales', 'amount': 120.0, 'date': '2026-10-26'});
    repo.saveLdCommission({'employee_name': 'Alice', 'amount': 80.0, 'date': '2026-10-26'});

    repo.setSettings({'disabled_menus': '["salary", "commission", "ld-commission"]'});
    final dash = repo.dashboard(from: '2026-10-26', to: '2026-10-26');
    final finance = dash['finance_summary'] as Map<String, dynamic>;
    expect(finance['salaries']['enabled'], isFalse);
    expect(finance['salaries']['total'], 0.0);
    expect(finance['commissions']['enabled'], isFalse);
    expect(finance['ld_commissions']['enabled'], isFalse);

    final topEarners = (dash['top_employees'] as List).cast<Map<String, dynamic>>();
    expect(topEarners.isEmpty, isTrue);
  });

  test('getDashboardCardOrder returns defaults and saveDashboardCardOrder persists custom order', () {
    final defaults = repo.getDashboardCardOrder();
    expect(defaults, containsAll(['kpis', 'daily_trend', 'finance_breakdown', 'top_employees', 'top_products', 'variant_sales', 'stock_alerts', 'shift_history']));

    final customOrder = ['shift_history', 'kpis', 'finance_breakdown'];
    repo.saveDashboardCardOrder(customOrder);
    final reloaded = repo.getDashboardCardOrder();
    expect(reloaded.first, 'shift_history');
    expect(reloaded[1], 'kpis');
    expect(reloaded[2], 'finance_breakdown');
    // Self-heals remaining missing defaults
    expect(reloaded.length, defaults.length);
  });
}
