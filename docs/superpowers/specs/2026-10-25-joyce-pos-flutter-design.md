# JOYCE POS (Flutter Windows) — Design Specification

## 1. Intent & Why

JOYCE POS v1.0.1 is an offline-first retail and sari-sari store Point-of-Sale system tailored for Philippine stores (currency: PHP `₱`). Previously built with React 18 + Tauri v2/Rust (`../Joy-Pos-Multiplatform`), this project rewrites JOYCE POS as a native **Windows desktop Flutter application** while preserving full feature parity, business rules, SQLite database compatibility, and the Black Gold / White Gold visual design system defined in [FLUTTER_HANDOFF.md](file:///c:/Users/picar/Desktop/My%20Dev%20ENV/Joyce-Pos-Flutter/FLUTTER_HANDOFF.md).

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **100% Feature & Rule Parity with JOYCE POS v1.0.1:**
  - POS checkout (cash-only, variant pack deductions, negative stock allowed, quick-tender chips, auto-print/receipt modal).
  - Transactions history & void workflow (restores stock, records permanent `voided_sales` snapshot, preserves original `sales` row with `status='voided'`).
  - Products catalog with multi-pack variants, barcode generation (`"2" + last9(epoch_ms) + rand(10..99)`), image resize/base64 (`<= 320px`, JPEG q=0.85), soft archive.
  - Inventory & Restock (`stock += qty`, last-cost overwrite when `unitCost > 0`, restock history).
  - Shift management (`SOD` / `EOD`), shift-gated operational tabs (`pos`, `expenses`, `commission`, `ld-commission`, `salary`), Z-Reading preview & thermal printing, and automatic EOD database snapshot backup.
  - Finance & Payroll modules: Store Expenses, Salary Payroll, Commissions (with custom commission types), LD (Load/Airtime) Commissions, and Employees roster.
  - Dual Dashboards: Store Overview (`dashboard`) and Executive Admin Dashboard (`admin_dashboard` with 11 tabs, period-over-period KPIs, trend & doughnut charts, leaderboards, activity feed, alerts, CSV/Excel exports).
  - Multi-branch SQLite database switching (`branches.json`), local + cloud backup folder (`storage_dir`), online backup/restore, database reset (`keepCatalog` option), global search (`Ctrl+K`), notification alerts bell, and PIN lock screen (`Administrator` + per-cashier PINs and tab permissions).
- **Drop-in SQLite Compatibility:** Maintain the exact table & column names, `PRAGMA journal_mode=WAL`, string timestamps (`YYYY-MM-DD HH:MM:SS`), and `REAL` money rounded via `r2(x) = (x * 100).roundToDouble() / 100` so existing `.db` files and backups work seamlessly.
- **Clean Git History:** Commit every logical change incrementally to git so the user can review and push manually.

### Non-Goals
- Web, iOS, macOS, Linux, or Android builds in this phase (Windows PC desktop only).
- Non-cash payment gateways, tax/VAT breakdowns, customer loyalty accounts, or cloud server databases.
- Webview kiosk key-blocking hacks (not applicable to native Flutter desktop).

### Anti-Goals (What Would Make This a Failure)
- **Over-engineering & Codegen Bloat:** Introducing heavy ORM code generation (`build_runner`, `drift`, `freezed`) that fights dynamic multi-branch SQLite file switching, `VACUUM INTO` backups, or the raw `COALESCE` shift-date SQL queries.
- **Breaking Shift-Date Attribution:** Filtering reports by wall-clock `created_at` instead of the shift's `business_date` (which breaks post-midnight sales belonging to an open shift).
- **Blocking Zero/Negative Stock Sales:** Preventing checkout when stock hits `0` (sari-sari stores frequently sell before encoding restocks).

## 3. Constraints
- **Target Platform:** Windows PC desktop (`1366×820` default window, `1024×640` minimum, maximized).
- **Offline-First Storage:** Local SQLite database via `sqlite3` + `sqlite3_flutter_libs`. Live `.db` files always reside in local app data (`%APPDATA%\com.joyce.pos`), never directly inside a cloud-synced folder (to prevent WAL corruption). `storage_dir` is used strictly as a snapshot/sync copy target.
- **Git Workflow:** Every milestone/change is committed to the local git repository; no remote push is performed automatically.

## 4. Approaches Considered

### Approach 1: Direct `sqlite3` + Plain Dart Service/Repository Layer + `ChangeNotifier` App State (Selected)
- **Description:** Use synchronous `sqlite3` FFI directly with the verbatim schema and SQL queries from `FLUTTER_HANDOFF.md`. Wrap all 60+ commands in a clean Dart repository/service layer (`PosDatabase` + domain services) and manage session/theme/branch/shift state via a central `AppState` (`ChangeNotifier`).
- **Pros:** Zero codegen (`build_runner`) overhead; 1:1 mapping with the original Rust SQL queries (`COALESCE` business-date queries, `VACUUM INTO`, SQLite Backup API for restore, live multi-branch connection swapping); fast compilation and minimal dependencies.
- **Cons:** SQL queries are string-based rather than compile-time checked, requiring unit tests for repository methods.

### Approach 2: `drift` ORM + `flutter_riverpod` + `freezed`
- **Description:** Model all 14 tables in Drift with generated DAOs and Freezed data classes.
- **Pros:** Compile-time SQL verification for simple queries.
- **Cons:** Heavy generated code; awkward handling of dynamic runtime branch database switching, `VACUUM INTO`, and complex `UNION ALL` / `COALESCE` reporting queries.

**Decision:** User selected **Approach 1**.

## 5. User Decisions vs. Builder Calls

### Decided by the User
1. **Target Platform:** Windows PC only for now.
2. **Database:** Offline SQLite, using Approach 1 (direct `sqlite3` + plain Dart repositories).
3. **Version Control:** Commit every change in git; user will push manually later.

### Builder Calls (Settled for Implementation)
To resolve the open items in `FLUTTER_HANDOFF.md` §12 and §9 without ambiguity:
1. **Expected-Cash Consistency (§12.1):** Apply the disabled-modules filter consistently in both `get_shift_status` / `end_day` and `build_z_reading` when computing `total_outflows` and `expected_cash`, so the screen EOD reconciliation and printed Z-Reading always match to the centavo.
2. **Three "Net" Labels (§12.2):** Keep all three calculations intact for parity (`net_profit = revenue - cogs - overheads`, `daily[].net = sales - overheads`, `Z-Reading net = gross_sales - enabled_outflows`) and label them explicitly in the UI ("Net Profit (After COGS)" vs. "Net Operating Cash Flow").
3. **PIN Compatibility (§4.6 & §12.3):** Store PINs in the existing `settings.admin_pin` and `cashiers.pin` columns in plaintext so existing `.db` backups restore and authenticate without breaking, while stripping `pin` from non-admin UI views and enforcing permission checks in the Dart service layer.
4. **Negative Stock (§12.4):** Keep negative stock allowed on sale (amber badge when `remaining <= 0`), matching sari-sari store workflow.
5. **Restock Cost (§12.6):** Keep last-cost overwrite (`if unitCost > 0`, update `products.cost`), with historical COGS preserved via `sale_items.cost_total`.
6. **Admin PIN Confirmation on Destructive Actions (§12.9):** Require Admin PIN verification modal when deleting finance records (`expenses`, `salaries`, `commissions`, `ld_commissions`) if the current user is not already logged in as Admin, and always require Admin PIN for `reset_db`.
7. **Windows Printing Transports (§9):**
   - Implement exact ESC/POS byte builders (`ReceiptBuilder`, `ZReadingBuilder`) returning `Uint8List` with ASCII sanitization (`₱` -> `P`).
   - Support **Network (`TCP host:9100`)** via `dart:io Socket`, **Serial/Bluetooth COM (`\\.\COMx`)** via Windows file/serial write, **Windows Spooler / USB** via PowerShell/Win32 raw printer spooling or USB device picker, plus an **in-app printable receipt preview modal** when `printer_conn` is `none` or `browser`.
8. **Storage Directory Path (§8):** Default local database directory to `%APPDATA%\com.joyce.pos` on Windows (matching the original Tauri app path) so existing local branches and databases on the machine are picked up automatically, with fallback to `getApplicationSupportDirectory()`.

## 6. Architecture & Directory Layout

```text
lib/
  main.dart                     # App entry, Windows window sizing, providers
  core/
    db/
      database_service.dart     # SQLite connection, init(), migrations, backup/restore/reset, branch switching
      branch_manager.dart       # branches.json management & EOD snapshot backups
    utils/
      money.dart                # r2(), formatPeso(), pesoShort()
      dates.dart                # active_business_date, business_now, date presets, pctChange()
      receipt_builder.dart      # Pure Dart ESC/POS receipt & Z-reading byte + text preview builders
      printer_service.dart      # TCP 9100, COM port, Windows Raw Spooler transport
      csv_exporter.dart         # CSV export + save file dialog helper
    theme/
      app_theme.dart            # Black Gold (dark) & White Gold (light) ThemeData + JoyceColors extension
    state/
      app_state.dart            # ChangeNotifier holding currentUser, settings, shiftStatus, branchInfo, alerts, nav tab
  data/
    pos_repository.dart         # Complete 60+ command surface (products, sales, shifts, finance, employees, auth, dashboards, system)
  ui/
    widgets/                    # Shared design system: JoyceModal, JoyceCard, RangeBar, Pagination, ReceiptPreview, Toast
    shell/
      pin_lock_screen.dart      # Animated gold-dust PIN keypad + password mode lock screen
      app_shell.dart            # Collapsible sidebar, top bar, Ctrl+K global search, alerts popover, SOD/EOD modals
    screens/
      pos_screen.dart           # Product grid, barcode search, variant modal, cart, quick tender, checkout receipt modal
      transactions_screen.dart  # Sales & Voided history tabs, expandable items, reprint, void modal
      products_screen.dart      # Catalog table/grid, add/edit modal, barcode generator, image resize, variants editor
      inventory_screen.dart     # Stock health, low-stock filter, restock modal, restock history table
      finance_screen.dart       # Shared reusable CRUD screen for Expenses, Salaries, Commissions, LD Commissions
      employees_screen.dart     # Employee roster CRUD with default payout rates
      store_overview_screen.dart# Store Overview KPIs, daily chart, top products, low stock, inline CRUD module
      admin_dashboard_screen.dart # 11-tab Executive Dashboard (Overview/P&L, Sales, Products, Finance tabs, Shifts, Audit, Reports)
      settings_screen.dart      # Theme, Store & Receipt preview, Printer, Security, Cashiers, Modules, Branches, Backup/Reset, Audit
test/
  pos_repository_test.dart      # Unit tests for sale deduction, variants, negative stock, void restore, SOD/EOD math, receipt bytes
```

## 7. What's Left to the Builder
- Exact Flutter widget composition and responsive flex ratios matching `../Joy-Pos-Multiplatform/src/styles.css` and JSX screens.
- Minimal dependencies in `pubspec.yaml` (`sqlite3`, `sqlite3_flutter_libs`, `path_provider`, `path`, `file_picker`, `image`, `lucide_icons_flutter` or standard Material/custom icons, `fl_chart`, `intl`).
