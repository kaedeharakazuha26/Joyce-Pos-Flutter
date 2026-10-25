# JOYCE POS (Flutter Windows) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete native Windows Flutter port of JOYCE POS v1.0.1 with 100% SQLite schema/backup compatibility, shift-attributed accounting, ESC/POS thermal printing, and Black Gold / White Gold themes.

**Architecture:** Synchronous `sqlite3` FFI database and multi-branch manager wrapped by a plain Dart repository (`PosRepository`) implementing all 60+ backend commands, consumed by a central `AppState` (`ChangeNotifier`) and modular Flutter desktop screens.

**Tech Stack:** Flutter 3.47+ (Windows desktop), `sqlite3`, `sqlite3_flutter_libs`, `path_provider`, `path`, `file_picker`, `image`, `fl_chart`, `intl`.

**Spec:** `docs/superpowers/specs/2026-10-25-joyce-pos-flutter-design.md` and `FLUTTER_HANDOFF.md`

## Global Constraints

- Target platform: Windows desktop (`1366×820` default window, `1024×640` minimum).
- SQLite engine: `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=OFF`, idempotent `init()` on startup, branch switch, and restore.
- Timestamps: local-time strings `YYYY-MM-DD HH:MM:SS`; dates: `YYYY-MM-DD`. Never store epoch integers.
- Money: `REAL` (double) rounded via `r2(x) = (x * 100).roundToDouble() / 100` on all outputs.
- Business date attribution: all report date filters use `COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), <fallback>)`.
- Commit every task's changes to git (`git commit`), no `git push`.

## Review Focus

1. **Post-midnight sale in an open shift:** A sale recorded at `2026-10-26 00:45:00` while a shift with `business_date = '2026-10-25'` is open must appear under `2026-10-25` in `list_sales`, `dashboard`, and `admin_dashboard`, and use `JP-20261025-XXXX` receipt numbering.
2. **Variant pack sale & void stock round-trip:** Selling 2 packs of a 6-pack variant deducts `12` base units from `products.stock` (allowing negative stock) and snapshots `cost_total = product.cost * 12`; voiding that sale restores `+12` base units and keeps the row in `sales` with `status='voided'`.
3. **Disabled module outflow consistency:** When `expenses` or `salary` is in `settings.disabled_menus`, both `get_shift_status`/`end_day` and `build_z_reading` omit that module's total from `total_outflows`, `expected_cash`, and `net_profit`.
4. **Corrupt or missing `branches.json` recovery:** If `branches.json` is missing or invalid JSON on startup, `BranchManager` regenerates the default `main` branch (`joyce_pos.db`) and saves it without crashing.
5. **Non-ASCII characters & `₱` on thermal printer:** `ReceiptBuilder` and `ZReadingBuilder` replace `₱` with `P` and non-ASCII bytes with `?`, ensuring line width `w` (`32` or `48`) never overflows or garbles ESC/POS output.

---

### Task 1: Flutter Windows Scaffold, Core Utilities (`money.dart`, `dates.dart`), and Theme System

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/core/utils/money.dart`
- Create: `lib/core/utils/dates.dart`
- Create: `lib/core/theme/app_theme.dart`
- Test: `test/core_utils_test.dart`

**Interfaces:**
- Produces:
  - `double r2(num v)`
  - `String formatPeso(num v, {bool showSign = true})`
  - `String pesoShort(num v)`
  - `String formatDate(DateTime dt)` (`YYYY-MM-DD`)
  - `String formatDateTime(DateTime dt)` (`YYYY-MM-DD HH:MM:SS`)
  - `String businessNow(String activeBusinessDate, [DateTime? now])`
  - `({String from, String to}) resolveDatePreset(String preset, String anchorBusinessDate)` (`today`, `yesterday`, `this_week`, `last_week`, `this_month`, `last_month`, `this_quarter`, `this_year`)
  - `({double pct, bool isNew}) pctChange(num cur, num prev)`
  - `AppTheme.dark()` (Black Gold `#0a0b10` / `#d4af37`) and `AppTheme.light()` (White Gold `#faf9f5` / `#b88a28`) with `JoyceColors` `ThemeExtension`.

- [ ] **Step 1: Scaffold Flutter Windows project and configure `pubspec.yaml`**

Run `flutter create --platforms=windows .` (preserving existing docs/handoff) and configure `pubspec.yaml` with `sqlite3`, `sqlite3_flutter_libs`, `path_provider`, `path`, `file_picker`, `image`, `fl_chart`, `intl`.

- [ ] **Step 2: Write failing unit tests in `test/core_utils_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/utils/money.dart';
import 'package:joyce_pos_flutter/core/utils/dates.dart';

void main() {
  test('r2 and peso formatting match handoff spec', () {
    expect(r2(10.555), 10.56);
    expect(formatPeso(1234.5), '₱1,234.50');
    expect(pesoShort(1500000), '₱1.50M');
    expect(pesoShort(25400), '₱25.4k');
  });

  test('date presets anchor to active business date and Monday week start', () {
    final w = resolveDatePreset('this_week', '2026-10-25'); // Sunday
    expect(w.from, '2026-10-19');
    expect(w.to, '2026-10-25');
    final delta = pctChange(150, 0);
    expect(delta.pct, 100);
    expect(delta.isNew, true);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/core_utils_test.dart`
Expected: FAIL (missing files).

- [ ] **Step 4: Implement `lib/core/utils/money.dart`, `lib/core/utils/dates.dart`, and `lib/core/theme/app_theme.dart`**

Implement exact rounding, PHP currency formatting, active-business-date presets, and the Black Gold / White Gold color tokens from `FLUTTER_HANDOFF.md` §6 & §10.

- [ ] **Step 5: Run test to verify it passes and commit**

Run: `flutter test test/core_utils_test.dart`
Expected: PASS. Commit with `git commit -m "feat: scaffold Windows Flutter app with core money, date, and theme utilities"`.

---

### Task 2: SQLite Database Service, Schema Init, Multi-Branch Manager & Backups

**Files:**
- Create: `lib/core/db/database_service.dart`
- Create: `lib/core/db/branch_manager.dart`
- Test: `test/db_branch_test.dart`

**Interfaces:**
- Consumes: `lib/core/utils/dates.dart`, `lib/core/utils/money.dart`
- Produces:
  - `class DatabaseService`:
    - `Database get db`
    - `void openPath(String dbPath)` (sets `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=OFF`, runs idempotent `init()`)
    - `void init()` (creates all 14 tables, 9 indexes, seeds `commission_types` and `admin_pin='0000'`, runs safe `ALTER TABLE` migrations)
    - `void logAudit({String actor, String role, required String action, required String entityType, String entityId, required String summary, Map<String, dynamic>? details})`
    - `void backupDb(String targetPath)` (`VACUUM INTO`)
    - `void restoreDb(String sourcePath)` (validates `products`, `sales`, `settings` tables exist, restores into live DB, re-runs `init()`, logs `RESTORE`)
    - `void resetDb(String pin, bool keepCatalog)` (verifies `admin_pin`, wipes transactional tables, and if `!keepCatalog` wipes `products`, `variants`, `employees`, `cashiers`; preserves `audit_logs` and `settings`)
  - `class BranchManager`:
    - `Map<String, dynamic> getBranchInfo()`
    - `Map<String, dynamic> createBranch(String name)`
    - `Map<String, dynamic> switchBranch(String branchId)`
    - `Map<String, dynamic> deleteBranch(String branchId)` (refuses if `id == 'main'` or only 1 branch left)
    - `Map<String, dynamic> setStorageDir(String dir)`
    - `Map<String, dynamic> performEodSnapshot(String tag)` (`EOD_<bizDate>`, `SYNC_<date>_<HHMMSS>`, `INIT_<date>`)

- [ ] **Step 1: Write failing tests in `test/db_branch_test.dart`**

```dart
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
    tempDir.deleteSync(recursive: true);
  });

  test('corrupt branches.json recovers default main branch and initializes schema', () {
    File('${tempDir.path}/branches.json').writeAsStringSync('{corrupt json');
    final dbService = DatabaseService();
    final mgr = BranchManager(appDataDir: tempDir.path, dbService: dbService);
    final info = mgr.getBranchInfo();
    expect(info['active_branch'], 'main');
    final pin = dbService.db.select("SELECT value FROM settings WHERE key='admin_pin'").first['value'];
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
    final audits = dbService.db.select('SELECT * FROM audit_logs WHERE action = ?', ['RESET_DB']);
    expect(audits.isNotEmpty, true);
    dbService.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/db_branch_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `DatabaseService` and `BranchManager`**

Implement `lib/core/db/database_service.dart` and `lib/core/db/branch_manager.dart` matching `FLUTTER_HANDOFF.md` §3 and §8.

- [ ] **Step 4: Run test to verify it passes and commit**

Run: `flutter test test/db_branch_test.dart`
Expected: PASS. Commit with `git commit -m "feat: add SQLite database service, schema init, backup/restore, and branch manager"`.

---

### Task 3: Core Repository (`PosRepository`) — Products, Sales, Void, Shifts, Finance, Auth & Dashboards

**Files:**
- Create: `lib/data/pos_repository.dart`
- Test: `test/pos_repository_test.dart`

**Interfaces:**
- Consumes: `DatabaseService`, `BranchManager`, `money.dart`, `dates.dart`
- Produces `class PosRepository` with synchronous/async methods for all 60+ commands in `FLUTTER_HANDOFF.md` §4, §5, §6:
  - Auth & Settings: `verifyPin(String pin)`, `changeAdminPin(String oldPin, String newPin)`, `listCashiers()`, `saveCashier(Map data)`, `deleteCashier(int id)`, `getSettings()`, `setSettings(Map<String, String> values)`, `getDisabledMenus()`
  - Shifts: `getShiftStatus()`, `startDay({String? businessDate, required String openedBy, double openingCash = 0, String notes = ''})`, `endDay({required double closingCash, required String closedBy, String notes = ''})`, `listShifts({int limit = 30})`, `updateShiftNotes(int id, String notes)`
  - Products & Inventory: `listProducts()`, `saveProduct(Map data)`, `deleteProduct(int id)`, `restock({required int productId, required int qty, double unitCost = 0, String note = ''})`, `listRestocks()`
  - Sales & Voids: `createSale({required List<Map<String, dynamic>> items, required double paid})`, `listSales({required String from, required String to, String status = ''})`, `voidSale({required int id, required String reason, required String voidedBy})`, `listVoided({required String from, required String to})`
  - Finance & Employees: `listExpenses`, `saveExpense`, `deleteExpense`, `listSalaries`, `saveSalary`, `deleteSalary`, `listCommissionTypes`, `addCommissionType`, `listCommissions`, `saveCommission`, `deleteCommission`, `listLdCommissions`, `saveLdCommission`, `deleteLdCommission`, `listEmployees`, `saveEmployee`, `deleteEmployee`
  - Analytics & Search: `dashboard({required String from, required String to})`, `adminDashboard({required String from, required String to})`, `listAuditLogs({required String from, required String to, int limit = 200})`, `globalSearch(String query)`

- [ ] **Step 1: Write failing business-rule tests in `test/pos_repository_test.dart`**

```dart
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
    tempDir.deleteSync(recursive: true);
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pos_repository_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `lib/data/pos_repository.dart`**

Implement all 60+ repository commands with exact SQL queries, `COALESCE` shift-date attribution, `NOT EXISTS` synthesized audit feed, dashboard/admin_dashboard aggregations, alerts generation, and disabled-module filtering.

- [ ] **Step 4: Run test to verify it passes and commit**

Run: `flutter test test/pos_repository_test.dart`
Expected: PASS. Commit with `git commit -m "feat: implement PosRepository with full business rules, shift attribution, and dashboard math"`.

---

### Task 4: ESC/POS Thermal Receipt & Z-Reading Builders + Windows Printer Service

**Files:**
- Create: `lib/core/utils/receipt_builder.dart`
- Create: `lib/core/utils/printer_service.dart`
- Test: `test/receipt_builder_test.dart`

**Interfaces:**
- Consumes: `money.dart`
- Produces:
  - `class ReceiptBuilder`:
    - `static String sanitizeAscii(String input)` (`₱` -> `P`, non-ASCII -> `?`)
    - `static String twoColumn(String left, String right, int width)`
    - `static String buildReceiptText(Map<String, dynamic> sale, Map<String, String> settings)`
    - `static Uint8List buildReceiptBytes(Map<String, dynamic> sale, Map<String, String> settings)`
    - `static String buildZReadingText(Map<String, dynamic> zData, Map<String, String> settings, Set<String> disabledModules)`
    - `static Uint8List buildZReadingBytes(Map<String, dynamic> zData, Map<String, String> settings, Set<String> disabledModules)`
  - `class PrinterService`:
    - `Future<void> sendBytes(Uint8List bytes, Map<String, String> settings)` (supports `network` TCP default 9100, `serial`/`bluetooth` `\\.\COMx`, and `usb` / Windows raw printer spooler)
    - `Future<List<Map<String, dynamic>>> listAvailablePrinters()`

- [ ] **Step 1: Write failing tests in `test/receipt_builder_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/core/utils/receipt_builder.dart';

void main() {
  test('ReceiptBuilder sanitizes ₱ to P, enforces column width, and emits ESC/POS cut/drawer bytes', () {
    final settings = {
      'store_name': 'JOYCE POS ₱',
      'paper_width': '58',
      'chars_per_line': '32',
      'cut_paper': '1',
      'open_drawer': '1',
      'copies': '1',
    };
    final sale = {
      'receipt_no': 'JP-20261025-0001',
      'created_at': '2026-10-25 14:30:00',
      'status': 'completed',
      'total': 170.0,
      'paid': 200.0,
      'change_amt': 30.0,
      'items': [
        {
          'name': 'Cola',
          'variant_name': '6-Pack',
          'quantity': 2,
          'unit_price': 85.0,
          'subtotal': 170.0,
        }
      ],
    };

    final text = ReceiptBuilder.buildReceiptText(sale, settings);
    expect(text.contains('₱'), false);
    expect(text.contains('JOYCE POS P'), true);
    for (final line in text.split('\n')) {
      expect(line.length <= 32, true, reason: 'Line exceeded 32 chars: "$line"');
    }

    final bytes = ReceiptBuilder.buildReceiptBytes(sale, settings);
    // Starts with ESC @ (0x1B, 0x40)
    expect(bytes[0], 0x1B);
    expect(bytes[1], 0x40);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/receipt_builder_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `ReceiptBuilder` and `PrinterService`**

Implement `lib/core/utils/receipt_builder.dart` and `lib/core/utils/printer_service.dart` per `FLUTTER_HANDOFF.md` §9.

- [ ] **Step 4: Run test to verify it passes and commit**

Run: `flutter test test/receipt_builder_test.dart`
Expected: PASS. Commit with `git commit -m "feat: add ESC/POS receipt and Z-reading byte/preview builders and Windows printer transports"`.

---

### Task 5: Central AppState, Shared UI Primitives, PIN Lock Screen & Main Shell (with SOD/EOD Modals)

**Files:**
- Create: `lib/core/state/app_state.dart`
- Create: `lib/core/utils/csv_exporter.dart`
- Create: `lib/ui/widgets/joyce_widgets.dart`
- Create: `lib/ui/shell/pin_lock_screen.dart`
- Create: `lib/ui/shell/sod_eod_modals.dart`
- Create: `lib/ui/shell/app_shell.dart`

**Interfaces:**
- Consumes: `PosRepository`, `ReceiptBuilder`, `PrinterService`, `AppTheme`
- Produces:
  - `class AppState extends ChangeNotifier`: manages `currentUser`, `activeTab`, `sidebarCollapsed`, `themeMode`, `settings`, `shiftStatus`, `branchInfo`, `alerts`, `dismissedAlertIds`, `deepLinkFilter`, login/logout, shift gating (`pos`, `expenses`, `commission`, `ld-commission`, `salary` require open shift), and toast notifications.
  - Shared UI primitives in `joyce_widgets.dart`: `JoyceCard`, `JoyceButton`, `JoyceModal`, `RangeBar`, `PaginationBar`, `ReceiptPreviewWidget`, `EmptyState`, `AdminPinConfirmDialog`.
  - `PinLockScreen`: Gold-dust animated particle canvas, touch PIN keypad + password input toggle, shift/branch badges, theme toggle.
  - `SodModal` & `EodModal` (with reconciliation view + thermal Z-Reading preview + print button).
  - `AppShell`: Collapsible grouped sidebar, top bar with `Ctrl+K` debounced global search dialog, alerts bell popover with deep-linking, quick-actions menu, branch switcher modal, user menu.

- [ ] **Step 1: Implement `AppState`, `csv_exporter.dart`, and `joyce_widgets.dart`**

Build the central state controller and shared UI design system components matching the Black Gold / White Gold theme tokens.

- [ ] **Step 2: Implement `PinLockScreen`, `SodModal`/`EodModal`, and `AppShell`**

Implement the lock screen with custom particle `CustomPainter`, shift modals, and main navigation shell.

- [ ] **Step 3: Run `flutter analyze` and commit**

Run: `flutter analyze`
Expected: No errors. Commit with `git commit -m "feat: add AppState, shared UI widgets, PinLockScreen, SOD/EOD modals, and AppShell"`.

---

### Task 6: Operations & Catalog Screens (POS, Transactions, Products, Inventory)

**Files:**
- Create: `lib/ui/screens/pos_screen.dart`
- Create: `lib/ui/screens/transactions_screen.dart`
- Create: `lib/ui/screens/products_screen.dart`
- Create: `lib/ui/screens/inventory_screen.dart`

**Interfaces:**
- Consumes: `AppState`, `PosRepository`, `ReceiptBuilder`, `PrinterService`, `joyce_widgets.dart`
- Produces:
  - `PosScreen`: Left product grid with barcode/name search (Enter auto-selects exact barcode -> exact name -> sole result), category chips, stock badges (`remaining = stock - cart units`, amber when `<= 0`), `"N options"` tag & variant picker modal; Right cart panel with steppers, quick-tender chips (`[total, 20, 50, 100, 200, 500, 1000]` `>= total`), change calculation, checkout completion modal with receipt preview & auto-print.
  - `TransactionsScreen`: `RangeBar`, Sales vs Voided tabs, expandable item rows, Reprint button, Void sale modal with reason & actor attribution.
  - `ProductsScreen`: Search/filter (`out_of_stock`, `low_stock` deep-link support), Add/Edit modal with barcode generator (`"2" + last9(epoch_ms) + rand(10..99)`), image picker + resize (`<= 320px`, JPEG q=0.85 base64 data URI), dynamic variants editor, soft archive confirmation.
  - `InventoryScreen`: Stock health table, low-stock highlights, Restock modal (`qty`, `unitCost`, `note`), and Restock history table (last 300).

- [ ] **Step 1: Implement `PosScreen` and `TransactionsScreen`**

Build the full checkout flow, variant picker, quick-tender chips, receipt modal, and transactions/void history.

- [ ] **Step 2: Implement `ProductsScreen` and `InventoryScreen`**

Build the product catalog CRUD with image resizing (`package:image`), barcode generation, variant rows editor, and inventory restock module.

- [ ] **Step 3: Run `flutter analyze` and commit**

Run: `flutter analyze`
Expected: No errors. Commit with `git commit -m "feat: implement POS checkout, Transactions/Void, Products catalog, and Inventory screens"`.

---

### Task 7: Finance, Payroll, Employees, Dashboards (Store Overview & Admin Dashboard) & Settings

**Files:**
- Create: `lib/ui/screens/finance_screen.dart`
- Create: `lib/ui/screens/employees_screen.dart`
- Create: `lib/ui/screens/store_overview_screen.dart`
- Create: `lib/ui/screens/admin_dashboard_screen.dart`
- Create: `lib/ui/screens/settings_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `AppState`, `PosRepository`, `joyce_widgets.dart`, `csv_exporter.dart`, `fl_chart`
- Produces:
  - `FinanceScreen`: Reusable CRUD screen configured for `expenses`, `salary`, `commission` (with employee default prefill + extensible commission types), and `ld-commission` (with `quantity` field), protected by Admin PIN confirmation on delete for non-admins.
  - `EmployeesScreen`: Roster CRUD with default `commission`, `ld_commission`, and `salary` rates.
  - `StoreOverviewScreen`: KPI tiles, daily revenue/profit trend chart (`fl_chart`), top products, low stock alerts, variant sales table, inventory report, and inline CRUD module.
  - `AdminDashboardScreen`: 11-tab executive analytics (`overview/P&L`, `sales`, `products`, `expenses`, `salaries`, `commissions`, `ld-commissions`, `employees`, `shifts`, `audit`, `reports`) with period-over-period delta badges, trend + cost breakdown doughnut charts, leaderboards, activity feed, and CSV export.
  - `SettingsScreen`: Theme toggle, Store & Receipt live preview, Printer configuration & test print, Security (Admin PIN), Cashier accounts & permissions matrix, Module toggles (`disabled_menus`), Multi-branch & Cloud/Storage directory sync, Backup/Restore, Reset DB (with Admin PIN), and Audit Log viewer.
  - `main.dart`: Wires `AppState`, `DatabaseService`, `BranchManager`, `PosRepository`, `PinLockScreen`, and `AppShell`.

- [ ] **Step 1: Implement `FinanceScreen` and `EmployeesScreen`**

Build the 4 finance modules (`expenses`, `salary`, `commission`, `ld-commission`) and `EmployeesScreen`.

- [ ] **Step 2: Implement `StoreOverviewScreen`, `AdminDashboardScreen`, and `SettingsScreen`, and wire `lib/main.dart`**

Build both dashboards with `fl_chart` charts, CSV exports, deep-link handling, the complete Settings screen, and connect all screens in `AppShell` and `main.dart`.

- [ ] **Step 3: Write integration smoke test in `test/widget_smoke_test.dart` and run full test suite + Windows build verification**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:joyce_pos_flutter/main.dart';
import 'package:joyce_pos_flutter/core/db/database_service.dart';
import 'package:joyce_pos_flutter/core/db/branch_manager.dart';
import 'package:joyce_pos_flutter/data/pos_repository.dart';
import 'package:joyce_pos_flutter/core/state/app_state.dart';

void main() {
  testWidgets('App launches into PinLockScreen and unlocks with default admin PIN 0000', (tester) async {
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

    dbService.close();
    tempDir.deleteSync(recursive: true);
  });
}
```

- [ ] **Step 4: Run all tests and `flutter analyze` and commit**

Run: `flutter test` and `flutter analyze`
Expected: All tests PASS and 0 analyzer errors. Commit with `git commit -m "feat: complete finance, dashboards, settings screens, and full app integration"`.
