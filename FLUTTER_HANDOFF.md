# JOYCE POS → Flutter Rewrite Handoff

Source app: **JOYCE POS v1.0.1** (React 18 + Vite UI, Tauri v2/Rust backend, SQLite WAL). Offline-first POS for Philippine sari-sari/retail stores. Currency is PHP (₱).

This document is the contract for a feature-parity Flutter port. Every behavior below was read from source. Source locations are given so you can verify.

| Concern | Source of truth |
|---|---|
| Schema + migrations + branch manager | `src-tauri/src/db.rs` |
| Command (API) surface | `src/api.js`, `src-tauri/src/cmds/*.rs` |
| Sales / void | `cmds/sales.rs` |
| Shifts (SOD/EOD) | `cmds/shifts.rs` |
| Auth / cashiers | `cmds/auth.rs` |
| Products / restock | `cmds/products.rs` |
| Expenses / salaries / commissions / LD | `cmds/finance.rs` |
| Employees | `cmds/employees.rs` |
| Dashboards, activity feed | `cmds/dashboard.rs` |
| Settings, backup, branches, search | `cmds/system.rs` |
| ESC/POS + transports | `printer.rs`, `cmds/printing.rs` |
| Theme tokens | `src/styles.css` |
| Nav, gating, shell | `src/App.jsx` |
| Formatting/date helpers | `src/utils.js` |

---

## 1. Product scope

Single-terminal, fully offline desktop POS (Win/Linux/macOS). **Target Flutter platforms:** Windows, Linux, macOS first. The window is 1366×820 (min 1024×640), maximized, so it is a desktop/tablet-landscape layout. Android tablet is optional (printer transport differs, see §9).

Modules: POS, Transactions (+void), Products (+variants), Inventory/Restock, Expenses, Salary, Commissions, LD Commissions, Employees, Store Overview dashboard, Admin Dashboard (executive analytics + reports), Settings (printer, receipt layout, security, cashiers, branches, backup, theme, module toggles), PIN lock screen, SOD/EOD shift flow, global search, notifications.

---

## 2. Architecture for Flutter

The Tauri design is "thin UI over a command layer". Preserve that boundary. Implement the Rust commands as a Dart **repository/service layer**, UI calls only that layer.

Recommended stack (suggestions, not extracted from source):

| Need | Package |
|---|---|
| SQLite | `drift` with `sqlite3_flutter_libs` (+ `sqlite3` for desktop). `VACUUM INTO` and WAL need real SQLite, so avoid web. |
| State | `flutter_riverpod` (replaces `SettingsCtx` React context + hooks) |
| Routing | `go_router` or a simple `IndexedStack` driven by tab id (the app is tab-based, not URL-based) |
| Charts | `fl_chart` (app draws custom SVG trend + doughnut charts) |
| Icons | `lucide_icons` (UI uses lucide) |
| Fonts | Outfit (UI), JetBrains Mono (numbers/receipt) via `google_fonts` or bundled assets |
| File dialogs | `file_picker` (backup/restore/storage dir/export) |
| Printing | `esc_pos_utils_plus` (byte builder) + transport (§9) |
| Paths | `path_provider` (`getApplicationSupportDirectory`) |
| CSV/Excel export | `csv`, `excel` |
| Images | `image` (resize product photos) + `image_picker`/`file_picker` |

Layers:

```
lib/
  core/        db/ (drift tables, init, migrations), branch_manager.dart, audit.dart, money.dart, dates.dart, theme/
  data/        repositories: sales, shifts, products, finance, employees, auth, settings, system, dashboard, printing
  domain/      models (freezed/plain), receipt_builder.dart, zreading_builder.dart
  features/    pos, transactions, products, inventory, expenses, salary, commission, ld_commission,
               employees, store_overview, admin, settings, lock, shell
  ui/          design system (Modal, Field, Toast, Pagination, RangeBar, Receipt preview, PageHeader, Empty)
```

---

## 3. Database (port verbatim)

Engine: SQLite, `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=OFF` (no FK constraints exist; integrity is enforced in code). `init()` is idempotent and re-run on every start, branch switch and after restore. Keep that: use `CREATE TABLE IF NOT EXISTS`, try-and-ignore `ALTER TABLE ADD COLUMN`, `INSERT OR IGNORE` seeds.

Timestamps are local-time strings `YYYY-MM-DD HH:MM:SS`. Dates are `YYYY-MM-DD`. Do **not** store epoch ints; all SQL uses `date(created_at)` and string `BETWEEN`.

```sql
CREATE TABLE IF NOT EXISTS products(
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
  barcode TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '',
  price REAL NOT NULL DEFAULT 0,        -- price of 1 base unit
  cost REAL NOT NULL DEFAULT 0,         -- cost of 1 base unit
  stock INTEGER NOT NULL DEFAULT 0,     -- base units
  low_stock INTEGER NOT NULL DEFAULT 5,
  image TEXT NOT NULL DEFAULT '',       -- data:image/jpeg;base64,... (max edge 320px, q=0.85)
  active INTEGER NOT NULL DEFAULT 1,    -- soft delete
  created_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS variants(    -- a "pack": qty base units for price
  id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL,
  name TEXT NOT NULL, qty INTEGER NOT NULL, price REAL NOT NULL);

CREATE TABLE IF NOT EXISTS sales(
  id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_no TEXT NOT NULL,
  total REAL NOT NULL DEFAULT 0, paid REAL NOT NULL DEFAULT 0, change_amt REAL NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'completed',          -- 'completed' | 'voided'
  created_at TEXT NOT NULL, voided_at TEXT, void_reason TEXT,
  voided_by TEXT NOT NULL DEFAULT '', shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS sale_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL,
  variant_id INTEGER, name TEXT NOT NULL, variant_name TEXT NOT NULL DEFAULT '',
  units_per INTEGER NOT NULL DEFAULT 1, unit_price REAL NOT NULL, quantity INTEGER NOT NULL,
  subtotal REAL NOT NULL, cost_total REAL NOT NULL DEFAULT 0);   -- snapshot of name/price/cost at sale time

CREATE TABLE IF NOT EXISTS voided_sales(   -- permanent snapshot
  id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, receipt_no TEXT NOT NULL,
  total REAL NOT NULL, reason TEXT NOT NULL DEFAULT '', items_json TEXT NOT NULL,
  sold_at TEXT NOT NULL, voided_at TEXT NOT NULL, voided_by TEXT NOT NULL DEFAULT '',
  shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS restocks(
  id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, product_name TEXT NOT NULL,
  qty INTEGER NOT NULL, unit_cost REAL NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL, shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS expenses(
  id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '', amount REAL NOT NULL, date TEXT NOT NULL, shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS salaries(
  id INTEGER PRIMARY KEY AUTOINCREMENT, employee TEXT NOT NULL, amount REAL NOT NULL,
  period TEXT NOT NULL DEFAULT '', date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS employees(
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, position TEXT NOT NULL DEFAULT '',
  commission REAL NOT NULL DEFAULT 0,      -- default flat amount
  ld_commission REAL NOT NULL DEFAULT 0,   -- default flat amount
  salary REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS commission_types(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE);
INSERT OR IGNORE INTO commission_types(name) VALUES('Sales'),('Bonus'),('Referral');

CREATE TABLE IF NOT EXISTS commissions(
  id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, employee_id INTEGER,
  employee_name TEXT NOT NULL, type TEXT NOT NULL DEFAULT '', amount REAL NOT NULL, shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS ld_commissions(   -- LD = electronic load / airtime
  id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, employee_id INTEGER,
  employee_name TEXT NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, amount REAL NOT NULL, shift_id INTEGER DEFAULT NULL);

CREATE TABLE IF NOT EXISTS cashiers(
  id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, pin TEXT NOT NULL UNIQUE,
  permissions TEXT NOT NULL,   -- JSON array of tab ids
  created_at TEXT NOT NULL);

CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);   -- all values are strings

CREATE TABLE IF NOT EXISTS shifts(
  id INTEGER PRIMARY KEY AUTOINCREMENT, business_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open',
  opened_by TEXT NOT NULL DEFAULT '', opened_at TEXT NOT NULL, opening_cash REAL NOT NULL DEFAULT 0,
  closed_by TEXT NOT NULL DEFAULT '', closed_at TEXT, closing_cash REAL NOT NULL DEFAULT 0,
  expected_cash REAL NOT NULL DEFAULT 0, cash_sales REAL NOT NULL DEFAULT 0,
  expenses REAL NOT NULL DEFAULT 0, salaries REAL NOT NULL DEFAULT 0,
  commissions REAL NOT NULL DEFAULT 0, ld_commissions REAL NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT '');

CREATE TABLE IF NOT EXISTS audit_logs(
  id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL,
  actor TEXT NOT NULL DEFAULT 'Administrator', role TEXT NOT NULL DEFAULT 'admin',
  action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL, details_json TEXT NOT NULL DEFAULT '{}');

CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_items_sale ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_variants_product ON variants(product_id);
CREATE INDEX IF NOT EXISTS idx_shifts_status ON shifts(status);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date);
CREATE INDEX IF NOT EXISTS idx_salaries_date ON salaries(date);
CREATE INDEX IF NOT EXISTS idx_commissions_date ON commissions(date);
CREATE INDEX IF NOT EXISTS idx_ld_commissions_date ON ld_commissions(date);

INSERT OR IGNORE INTO settings(key,value) VALUES('admin_pin','0000');
```

Migrations in source are best-effort `ALTER TABLE ... ADD COLUMN` (ignored on failure). If you need to import legacy `.db` backups from the Tauri app, keep identical table/column names and run the same ALTERs, so old backups restore cleanly.

> **Money is `REAL` (double) in the source.** All outputs are rounded with `r2(x) = (x*100).round()/100`. For Flutter, either keep REAL + `r2` for compatibility, or move to integer centavos (better) and convert at the import boundary. Recommend centavos for new data, but only if you do not need drop-in compatibility with old `.db` files.

---

## 4. Core rules and invariants (must match)

### 4.1 "Business date" and shift attribution
- A **shift** = one business day (SOD → EOD). Only one `status='open'` shift may exist.
- Every transactional record (sale, expense, salary, commission, LD commission, restock, void) is stamped with `shift_id` of the open shift at creation (null if none).
- **All reporting date filters use the shift's business_date, not the wall clock**, so sales after midnight still belong to the shift:
  `COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), <fallback>)`
  Fallbacks: sales `date(created_at)`, expenses/salaries/commissions/ld `date` column, restocks `date(created_at)`, voided `date(voided_at)` (plus a join via the original sale's shift).
- `active_business_date` = open shift's `business_date`, else today.
- `business_now` = `<active_business_date> <HH:MM:SS now>` (used for void and restock timestamps and sale `created_at`).
- Default record `date` when client sends empty = `active_business_date`.

### 4.2 Inventory units
- `products.stock` is in **base units**. A variant sells `qty` base units for `price`.
- Deduct: `stock -= variant.qty(units_per) × quantity`. Base-unit sale uses `units_per=1`.
- **Selling at 0 or negative stock is allowed** (no check; stock may go negative). POS UI shows "N in stock" in amber when remaining ≤ 0 but does not block.
- POS UI computes `remaining = stock − Σ(cart qty × (variant.qty or 1))` across all lines of that product.
- Void restores exactly `units_per × quantity` per item.
- `cost_total = product.cost × units` captured at sale time (COGS source).

### 4.3 Sale creation (`create_sale(items[], paid)`) — single DB transaction
1. Reject empty cart: `"Cart is empty"`.
2. Resolve shift: `(shift_id, biz_date)` of open shift, else `(null, today)`.
3. Receipt number: `JP-{biz_date without dashes}-{count+1 zero-padded 4}` where count = `COUNT(*) FROM sales WHERE date(created_at)=biz_date` (counts voided too). Example `JP-20260125-0007`.
4. `created_at = "{biz_date} {now HH:MM:SS}"`.
5. Insert sale shell (total/paid/change = 0), then for each item `{product_id, variant_id?, quantity}`:
   - `quantity <= 0` → `"Invalid quantity"`; product must exist.
   - If `variant_id`: load `(name, qty, price)` where `variant.product_id = product_id`; else `variant_name=''`, `units_per=1`, `unit_price = product.price`.
   - Deduct stock, insert `sale_items` with `subtotal = unit_price × qty`, `cost_total = cost × units`.
6. `total = r2(Σ subtotal)`. If `paid + 1e-9 < total` → `"Payment is less than the total"` (rollback). Else `change_amt = r2(paid − total)`.
7. Audit `SALE` (actor `Cashier`, role `cashier`, entity `sale`, entity_id = receipt_no).
8. Return sale + `items[]`.
- Client: `paid = Number(paidInput || total)` (blank = exact). Server trusts client prices only via DB lookup; the client sends only ids/qty.
- **Only cash exists.** No card/e-wallet/discount/tax/partial payment/customer. `cash_sales == gross sales`.

### 4.4 Void (`void_sale(id, reason, voided_by)`) — transaction
- Only `status='completed'`, else `"This sale is already voided"`.
- Restore stock; `ts = business_now`; `who = voided_by or "Administrator"`.
- Update sale: `status='voided'`, `voided_at`, `void_reason`, `voided_by`.
- Insert `voided_sales` snapshot (`items_json` = JSON of sale_items; `shift_id` = **active shift id if open, else the sale's original shift**).
- Audit `VOID` (role `admin`). UI sends `currentUser.name`, or "Administrator"/"Staff".
- The sale row is **never deleted**; reports count it under `voided_*`, excluded from revenue by `status='completed'`.

### 4.5 Shifts
- **`start_day(business_date, opened_by, opening_cash, notes)`**: error `"A business day shift is already open. Please end the current day first."` if one open. Blank date → today. Audit `SHIFT_OPEN`.
- **`get_shift_status`** returns `{is_open:true, shift:{…live totals}}` or `{is_open:false, last_shift}`.
  - Live totals for open shift: `cash_sales = gross_sales = SUM(total) completed sales WHERE shift_id=? OR (shift_id IS NULL AND created_at >= opened_at)`; `expenses/salaries/commissions/ld_commissions = SUM(amount)` by `shift_id`; `orders_count`; `sold_items = GROUP BY name, variant_name → {name, variant_name, quantity, amount} ORDER BY amount DESC`; `total_outflows = expenses+salaries+commissions+ld`; **`expected_cash = opening_cash + cash_sales − total_outflows`**.
- **`end_day(closing_cash, closed_by, notes)`**: recompute same totals, `variance = r2(closing − expected)`, update shift to `status='closed'` with all snapshot columns (`notes` overwritten only if non-empty), audit `SHIFT_CLOSE`, then **auto EOD snapshot backup** (§8). Returns the summary + `eod_backup` result (failure does not fail EOD; returns `{ok:false,error}`).
- `list_shifts(limit=30)`, `update_shift_notes(id, notes)` (audit `UPDATE`).
- **Gating:** tabs `pos, expenses, commission, ld-commission, salary` are blocked unless a shift is open. Navigating to one while closed opens the SOD modal instead.
- EOD modal has two views: `reconciliation` and thermal `receipt` preview; it can print the Z-Reading.

### 4.6 Auth
- `verify_pin(pin)`: trim; empty → `"Please enter a PIN"`. Equals `settings.admin_pin` → `{id:0, name:"Administrator", role:"admin", permissions:["*"]}`. Else lookup `cashiers.pin` → `{id, name, role:"cashier", permissions:[…]}` (fallback perms `["pos","transactions"]`). Else `"Incorrect PIN. Please try again."`
- `change_admin_pin(old, new)`: `new.length >= 4` ("New PIN must be at least 4 digits"), old must match ("Current admin PIN is incorrect"). Audit `SECURITY`.
- `save_cashier`: name required; pin ≥ 4 chars; ≠ admin pin; unique among cashiers ("Another cashier is already using this PIN"); permissions default `["pos","transactions"]`. UI forces ≥1 permission. Audit CREATE/UPDATE/DELETE.
- Session lives in `sessionStorage` (cleared on app close). Flutter: keep in memory/riverpod only; do not persist.
- **Security gaps in source you should NOT copy blindly:** PINs are stored and compared in plaintext and `list_cashiers` returns `pin`; the default admin PIN is `0000`; there is no lockout/rate-limit; client-side-only permission enforcement (nav filtering). Recommended in Flutter: hash with salt, force PIN change on first launch, add attempt throttling, enforce permission checks in the repository layer. This is a deliberate improvement; flag it to the stakeholder because it changes backup compatibility (`pin` column semantics).

### 4.7 Permissions & module toggles
- Permission ids (cashier sidebar tabs): `dashboard, pos, transactions, products, inventory, expenses, salary, commission, ld-commission, employees, settings`.
- Admin sees everything except tabs in `settings.disabled_menus`. `admin-dashboard` is admin-only. Cashier sees only tabs in `permissions` and not disabled.
- `settings.disabled_menus` = JSON array of ids. **Disabled modules are excluded everywhere** (KPI tiles, P&L, charts, leaderboards, ledgers, CSV/Excel exports, thermal Z-reading). Accepted aliases: salary/`salaries`, commission/`commissions`, `ld-commission`/`ld_commission`, `expenses`. Note: the Z-Reading net formula omits disabled modules *and* they are omitted from the drawer outflows too, but `end_day`/`get_shift_status` expected cash does **not** (see §12).
- On admin unlock, default landing tab: `admin-dashboard` (unless disabled → `dashboard`). Cashiers land on `pos`.

### 4.8 Audit log
`log_audit(actor, role, action, entity_type, entity_id, summary, details)` writes `audit_logs`; blank actor→"Administrator", blank role→"admin". Never fails the parent operation (result ignored, but it's in the same tx where applicable).
Actions seen: `SALE, VOID, RESTOCK, CREATE, UPDATE, DELETE, ARCHIVE, SHIFT_OPEN, SHIFT_CLOSE, SECURITY, BACKUP, RESTORE, RESET_DB, EOD_BACKUP`.
`save_*` commands accept optional `actor` / `actor_role` fields in the payload for attribution; delete commands hard-code `Administrator/admin`. In Flutter pass `currentUser` everywhere (improvement).
**Activity feed** (`list_audit_logs`, `limit` default 200; admin dashboard uses 60) = UNION of `audit_logs` plus synthesized rows from sales/voids/restocks/expenses/salaries/commissions/ld/shifts that have **no matching audit row** (legacy data back-fill), filtered by business-date range, ordered by timestamp desc. Replicate with the exact `NOT EXISTS` pattern from `dashboard.rs:149-305`.

---

## 5. Command / repository surface (all 60+ commands)

Name → arguments → returns. Errors are plain strings; show via toast. Implement each as an async Dart method.

**Products:** `list_products()` → active products each with `variants[]` ordered by `qty`, name NOCASE · `save_product(product)` → id (upserts + replaces variants; see below) · `delete_product(id)` soft (`active=0`, audit `ARCHIVE`) · `restock(productId, qty, unitCost, note)` · `list_restocks()` last 300.

`save_product`: name required; price/cost ≥ 0 ("Price and cost cannot be negative"). On **update**, `stock` is written only if payload has integer `stock`; otherwise untouched. Variants are **deleted and re-inserted** each save; skipped unless `qty>0` and name non-empty. Transaction + audit with before/after.
`restock`: `qty>0`; `stock += qty`; if `unitCost>0` overwrite `products.cost` (**last-cost, not average cost**); insert `restocks` with `business_now` and `shift_id`; audit `RESTOCK`.

**Sales:** `create_sale(items, paid)` · `list_sales(from,to,status='')` (limit 1000, id desc, includes `items[]` and computed `business_date`) · `void_sale(id, reason, voidedBy)` · `list_voided(from,to)` (items parsed from `items_json`).

**Finance:** `list/save/delete` for `expenses`, `salaries`, `commissions`, `ld_commissions`; `list_commission_types()`, `add_commission_type(name)` (INSERT OR IGNORE).
Validation: expense `amount>0`, category blank→"General"; salary needs employee + `amount>0`; commission needs `employee_name`, `type` (ld: none), `amount>0`; LD `quantity = max(1, int)`. Lists are ordered `business_date DESC, id DESC`. On **edit** the `shift_id` is *not* changed; on create it is the active shift. Salary `period` is a free-text label.
UI says deletions require Admin PIN (README); the backend does not check. Re-verify in `DashboardCrudModule.jsx` before building the PIN prompt.

**Employees:** `list_employees()` active only · `save_employee(employee)` (name required) · `delete_employee(id)` soft archive. Employee `commission`/`ld_commission`/`salary` are prefill defaults for the payout forms.

**Dashboards:** `dashboard(from,to)` (Store Overview) · `admin_dashboard(from,to)` (Executive) — see §6.

**Shifts:** `get_shift_status`, `start_day`, `end_day`, `list_shifts(limit)`, `update_shift_notes`.

**Settings:** `get_settings()` → map<string,string> · `set_settings(values)` upsert each key.

**Auth:** `verify_pin`, `change_admin_pin`, `list_cashiers` (adds `permissions_list`), `save_cashier`, `delete_cashier`.

**Printing:** `print_receipt(saleId)`, `print_z_reading(shiftId?, closingCash?, closingNotes?, closedBy?)`, `print_test()`, `list_usb_devices()`.

**System/DB:** `backup_db(path)`, `restore_db(path)`, `reset_db(pin, keepCatalog)`, `save_text_file(path, content)`, `sync_to_gdrive()`, `get_branch_info`, `switch_branch(id)`, `create_branch(name)`, `delete_branch(id)`, `set_storage_dir(dir)`, `list_audit_logs(from,to,limit)`, `global_search(query)`.

---

## 6. Dashboard math

Revenue/COGS use `status='completed'` sales whose shift-business-date is in range.

```
revenue        = SUM(sales.total)
orders         = COUNT(sales)
cogs           = SUM(sale_items.cost_total)
gross_profit   = revenue − cogs
overheads      = expenses + salaries + commissions + ld_commissions      (each by business-date range)
net_profit     = gross_profit − overheads
gross_margin % = gross/revenue·100            net_margin % = net/revenue·100        (0 if revenue=0)
avg_ticket     = revenue/orders
void_rate %    = voided/(revenue+voided)·100
inventory_cost = SUM(stock·cost) active       inventory_retail = SUM(stock·price)   potential_profit = retail − cost
```
All rounded with `r2`. NOTE: Store Overview `dashboard()` returns the same core plus `daily[]`, `top[]` (top 8 by revenue grouped by product), `top_employees[]`, `inventory_report[]`, `variant_sales[]`, `low_stock[]` (≤10). `admin_dashboard()` additionally returns:

- `previous_period` (same length window immediately before `from`: `span_days = (to−from)+1`; `prev_to = from−1d`; `prev_from = prev_to−(span−1)d`) with all KPIs + `daily[]`.
- `today` (active business date) and `mtd` (1st of that month → active business date): revenue, orders, net, `records_created`.
- `counts`: products_active/healthy/low/out, employees_active, cashiers_count, open_shifts_count, completed/voided sales, per-module record counts, `total_records`.
- `hourly[]` (`strftime('%H', created_at)` → count, revenue), `categories[]` (revenue, units, gross_profit; blank category → "General"), `product_performance[]` (with margin_pct), `catalog_performance[]` (includes 0-sale products; margin falls back to `(price−cost)/price`), `variant_sales[]`, `low_stock_items[]`, `expense_categories[]`, `shift_history[]` (≤100), `top_employees[]` (≤15, union of salary/commission/ld per employee name), `daily[]` (adds `cogs`, `gross_profit`, `net_after_cogs`, `net`; note `net` here = sales − overheads **without** COGS), `recent_sales[]` (25 with items), `recent_activity[]` (60), `alerts[]`.

Two different "net" definitions exist: **Dashboard `net_profit` = revenue − COGS − overheads**, while `daily[].net` = sales − overheads (no COGS) and the Z-Reading net = gross sales − overheads (no COGS). Keep all three as-is for parity, and label them clearly in the UI.

**Alerts** (shape `{id, severity: bad|warn|info, title, description, timestamp, target_tab, filter}`):
| id | when | severity | target_tab / filter |
|---|---|---|---|
| alert-out-of-stock | out-of-stock count>0 (`stock<=0`) | bad | products / out_of_stock |
| alert-low-stock | `0<stock<=low_stock` count>0 | warn | products / low_stock |
| alert-shift-closed | no open shift | info | shifts / open_sod |
| alert-high-void-rate | void_rate ≥ 5 and voided count>0 | warn | sales / voided |
| alert-negative-net | net<0 and (revenue>0 or overheads>0) | bad | overview / negative_net |
| alert-shift-shortage | any closed shift in range with `closing−expected < −0.01` | bad | shifts / shortage |

App refreshes alerts using range `monthStart()`→today, on login/branch switch. Users can dismiss alerts (ids stored in session only). Bell icon shows undismissed count. Clicking navigates via `navigateToAdminReport(reportTab, filters)` (deep link with `ts` to retrigger); non-admins are mapped to operational tabs: sales→transactions, products→products, expenses→expenses, salaries→salary, commissions→commission, ld-commissions→ld-commission, employees→employees, else dashboard.

### Date presets (`utils.js`)
today, yesterday, this_week (Monday start), last_week, this_month, last_month, this_quarter, this_year. All are anchored to the **active business date**, not the wall clock. `toDate('YYYY-MM-DD')` parses at 12:00 local to dodge DST. `pctChange(cur, prev)`: if prev≈0 → pct = (cur≈0 ? 0 : 100), `isNew` when cur≠0. Currency: `₱` + `en-PH` grouping with 2 decimals; `pesoShort`: ≥1,000,000 → `₱x.xxM`; ≥10,000 → `₱x.xk`.

---

## 7. Screens (UI inventory)

Shell (`App.jsx`, 1857 lines): collapsible left sidebar (state persisted `joyce-sidebar-collapsed`), grouped nav, responsive drawer on narrow widths, top bar with **global search (Ctrl/Cmd+K, 220 ms debounce)**, notification bell + popover, quick-actions menu (SOD/EOD, add items), user menu (logout), branch switcher with "add branch" modal, theme toggle, shift status badge, Page error boundary with "Reload Section".

Sidebar groups & order:
1. Analytics & Control: Admin Dashboard (admin only), Store Overview
2. Operations: POS, Transactions
3. Inventory & Catalog: Products Catalog, Stock & Restock
4. Finance & Payroll: Store Expenses, Salary Payroll, Commissions, LD Commissions
5. Administration: Employees, Settings

| Screen | Behavior |
|---|---|
| **Lock (PinLock)** | Gold-dust particle canvas that reacts to cursor, floating 3D orbs and rotating dashed rings, branch + shift badges ("Shift Open/Closed"), two modes: touch keypad with PIN dots and keyboard password field with show/hide, admin hint, theme toggle. Errors from `verify_pin` shown inline. |
| **POS** | Left: search (autofocus; Enter selects exact barcode → exact name → sole result, then clears), category chips (`All` + distinct categories), product grid (image or placeholder, name, price, "N in stock", "N options" tag when variants exist = `variants+1`). Tap: no variants → add; variants → picker modal listing `1 pc (regular)` (qty 1, base price) + variants with "uses N from stock". Right: cart (key = `productId-variantId|0`; steppers; qty→0 removes line), clear-all, total, "Cash received" number, quick-tender chips = unique of `[total,20,50,100,200,500,1000]` ≥ total, first 5 ("Exact" for total), change (red if negative), Charge button disabled if empty or paid<total. After checkout: modal with total, change, receipt preview, "Print receipt", "New sale"; if `auto_print=="1"` print automatically. Print falls back to OS print dialog when `printer_conn` is none/browser. |
| **Transactions** | RangeBar (from/to, presets, defaults to active business date). Tabs: Sales (n) / Voided history (n). Expandable rows with items (qty× name, variant badge, unit price, subtotal). Actions: reprint, **Void** (modal with reason; records `voidedBy`). Subtitle: completed count + sum. |
| **Products** | Search by name/category/barcode; add/edit modal: name, barcode (+ **Generate**: `"2"+last9(ms epoch)+rand(10..99)`), category, price, cost, stock, low_stock (default 5), photo (pick/camera; reject >5 MB; resize so max edge 320 px; JPEG q 0.85 → data URL), variants editor (name, qty, price rows). Delete = soft archive with confirm "Past sales stay in history". Honors `?filter=out_of_stock|low_stock` from alerts. |
| **Inventory** | Product list with stock health, low-stock highlight, restock modal (qty, unit cost, note), restock history table (date/product/qty/cost/note). |
| **Expenses / Salary / Commissions / LD** | CRUD tables with RangeBar, shift-date column, shift-gated. Commission forms pick employee (prefill default amount) + type (extensible via `add_commission_type`); LD has quantity. |
| **Employees** | Roster: name, position, default commission, default LD commission, salary; soft delete. |
| **Store Overview (Dashboard)** | KPI tiles, trend charts, top products, low stock, `DashboardCrudModule` (records & CRUD with variant-level sales viewer and inventory performance). |
| **Admin Dashboard** | Tabs: overview/P&L, sales, products, expenses, salaries, commissions, ld-commissions, employees, shifts, audit, reports. KPI grid with period-over-period deltas, trend + doughnut (cost breakdown) charts, comprehensive P&L, leaderboards ("Highest Income per employee"), payroll/audit tables, CSV/Excel export, deep-link intents. |
| **Settings** | Sections: Theme · Store & receipt layout (live preview) · Printer · Security (change admin PIN, min 4 digits) · Cashier accounts & permissions · Module toggles (`disabled_menus`) · Branches & storage dir & Google-Drive/cloud sync · Backup/Restore · Reset DB (PIN) · Audit log. |
| **SOD / EOD modals** | SOD: business date (default today), opening cash (default 0), notes. EOD: closing cash, notes, reconciliation vs thermal-receipt preview, print Z-Reading. |

Kiosk protection (`main.jsx`): block context menu and devtools shortcuts (F12, Ctrl+Shift+I/J/C, Ctrl+U). **Not needed in Flutter** (no webview), skip.

---

## 8. Settings keys, branches, backups

### Settings (key → default; all strings)
`theme` dark|light · `store_name` ("JOYCE POS") · `store_address` · `store_phone` · `receipt_header` · `receipt_footer` ("Thank you! Come again.") · `paper_width` "58"|"80" · `chars_per_line` (32 for 58 mm, 48 for 80 mm) · `font_size` normal|large · `header_align` / `footer_align` left|center|right (default center) · `printer_conn` none|usb|bluetooth|serial|network|browser · `usb_vid` / `usb_pid` (hex, no `0x`) · `serial_path` · `network_addr` (host or host:port; default port 9100) · `auto_print` "0"|"1" · `copies` 1–5 · `feed_lines` (default 3) · `cut_paper` "1"|"0" (default 1) · `open_drawer` "0"|"1" · `disabled_menus` JSON array · `admin_pin`.

### Multi-branch
- `branches.json` in the app-data dir: `{active_branch, storage_dir, last_backup_at, last_backup_path, branches:[{id,name,file,created_at}]}`. Default branch: `{id:"main", name:"Main Store", file:"joyce_pos.db"}`. Corrupt/missing file → regenerate default and re-save.
- Each branch is its own SQLite file in the app-data dir. Settings (including PIN and theme) are **per-branch DB**.
- `create_branch(name)`: `id = branch_{slug(name)}_{last4 of epoch secs}`, `file = joyce_pos_{id}.db`; **becomes active immediately**; opens new DB and runs `init`.
- `delete_branch`: refuse if only one left, or id=="main"; if active was deleted, switch to first remaining. The `.db` file is **not** deleted from disk.
- `switch_branch` swaps the live connection with no restart; UI bumps a `branchKey` to remount all pages and reloads settings/shift/alerts.
- **Live DB always stays in local app-data**, never in a cloud-synced folder (WAL corruption). `storage_dir` (e.g. Google Drive folder) is only a backup target. If a branch file exists only in `storage_dir`, copy it to local once.
- App-data locations (Tauri id `com.joyce.pos`): Win `%APPDATA%\com.joyce.pos\`, Linux `~/.local/share/com.joyce.pos/`, macOS `~/Library/Application Support/com.joyce.pos/`. Flutter's `getApplicationSupportDirectory()` yields a different path, so offer a one-time "import from legacy folder".

### Backup / restore / reset / EOD snapshot
- Backup: `VACUUM INTO path` (delete target first); audit `BACKUP`.
- Restore: open source read-only; require tables `products, sales, settings` all present else `"Not a valid JOYCE POS backup"`; SQLite online-backup into the live connection (100 pages/step); re-run `init`; audit `RESTORE`.
- Reset (`reset_db(pin, keepCatalog)`): PIN must equal admin pin; transaction deletes sales, sale_items, voided_sales, restocks, expenses, salaries, commissions, ld_commissions, shifts; if `!keepCatalog` also products, variants, employees, cashiers. Audit rows are **kept**; settings kept. Does not reset AUTOINCREMENT counters.
- **EOD snapshot** (`perform_eod_snapshot`): target = `storage_dir` if valid else app-data; dir `EOD_Backups/`; file `joyce_pos_{branchId}_{safeTag}.db` where tag is `EOD_{bizDate}` (EOD), `SYNC_{date}_{HHMMSS}` (manual), `INIT_{date}` (on setting storage dir); safeTag replaces non `[A-Za-z0-9_-]` with `_`. Write `VACUUM INTO` to `.tmp_…` then **rename atomically**. If cloud dir configured, also copy over `<storage_dir>/<branch.file>` as the "latest" file. Update `last_backup_at/path` in `branches.json`. Audit `EOD_BACKUP`.
- `get_branch_info` returns `{active_branch, storage_dir, default_dir, active_db_path, last_backup_at, last_backup_path, branches}`.
- `global_search(q)`: `LIKE %q%` across products (name/category/barcode, 12), sales (receipt/status/void_reason, 12), expenses (10), salaries (10), commissions (10), ld_commissions (10), employees (10), shifts (8). Empty q returns empty arrays.

---

## 9. Printing (highest-risk area)

### Receipt bytes (`build_receipt`)
Width `w = chars_per_line` (fallback 48 if paper 80 else 32). ASCII-only: any non-ASCII → `?`, `₱` → `P` (thermal firmware lacks ₱). `two(left,right,w)` = left truncated to `w−len(right)−1`, padded with spaces, right-aligned, newline.

Sequence: `ESC @` init → align(header_align) `ESC a n` → bold on `ESC E 1` → size `GS ! (large?0x11:0x01)` → store_name → size reset `GS ! 0`, bold off → address, phone, receipt_header (non-empty only) → left → `-`×w → `Receipt: …`, `Date: …`, `*** VOIDED ***` if voided → rule → each item `"{qty}x {name}[ (variant)]"` ↔ subtotal, plus `"   @ {unit_price}"` if qty>1 → rule → bold `TOTAL` → `Cash`, `Change` → rule → align(footer_align) footer → `ESC d feed_lines` → if `cut_paper=="1"`: `GS V 66 0` → if `open_drawer=="1"`: `ESC p 0 25 250`. Money format `%.2f` (no ₱ sign, no thousands separators).
`copies` (1–5) repeats the whole byte buffer.

### Z-Reading (`build_z_reading`)
Header (centered, bold, store name at `GS ! 1`, address, phone, `*** END OF DAY / Z-READING ***`) → `=` rule → `Shift ID : #n`, `Date`, `Opened At`, `Opened By`, `Closed By` → `-` rule → bold `PRODUCTS SOLD (QTY x AMOUNT):` → rows `"{name}[ (variant)] x {qty}"` ↔ amount (or `No products sold in shift.`) → `=` →
```
TOTAL GROSS SALES            gross       (bold)
- Store Expenses            -x           if expenses enabled
- Salaries Paid             -x           if salary enabled
- LD Comm Paid              -x           if ld enabled
- Commissions Paid          -x           if commission enabled
-----
= NET OPERATING PROFIT       net         (bold)   net = gross − enabled outflows
=====
Opening Float / + Cash Sales / - Total Outflows (enabled only)
Expected in Drawer  = opening + cash_sales − enabled outflows      (bold)
Actual Cash Counted = closing_cash if > 0 else expected
Variance: "0.00 (Balanced)" if |v|<0.01, "+x (Overage)", "x (Shortage)"
[Notes: …]
=====
(centered) signature lines: Cashier Signature / Manager Signature, "Printed: <now>"
```
then feed/cut/drawer as above. `print_z_reading` picks shift by id, else open shift, else most recent; totals recomputed from DB; `cash_sales = gross_sales`.

### Transports (`send`)
`printer_conn`: `usb` (VID/PID hex → find first bulk-OUT endpoint → claim interface w/ auto-detach → chunked `write_bulk` 5 s timeout), `bluetooth|serial` (open path and write; on Windows prefix `COMx` with `\\.\`), `network` (TCP, 4 s connect timeout, default port 9100), otherwise error `"No printer configured. Set one up in Settings > Printer."`. `browser`/`none` in POS means "use OS print dialog" (UI-level, not in Rust).
`list_usb_devices` heuristics: skip VID 0x1d6b and hub class 9; include if printer class 7, or name matches printer keywords (printer, pos, thermal, receipt, esc, xprinter, rongta, epson, citizen, star, bixolon, zywell, gprinter, 58, 80), or has bulk-OUT and isn't audio/HID/video/wireless class; exclude names containing camera/audio/bluetooth/touch/fingerprint/keyboard/mouse/receiver/hub. Returns `{vid, pid (4-hex), name, is_printer}`.

### Flutter options and risk
- **Network (TCP 9100):** `dart:io` `Socket`. Easy, cross-platform. Build first.
- **Serial/Bluetooth-COM:** `flutter_libserialport` (desktop). Reproduces the path model.
- **USB on desktop:** no first-class Flutter plugin. Options: FFI to `libusb` (mirrors `rusb`, needs Zadig/WinUSB on Windows and a udev rule on Linux, see README), or write raw to the OS spooler (Windows: `winspool` via `win32`/FFI `WritePrinter` with `RAW` datatype; Linux/mac: `lp -o raw`). **Spooler RAW is the more user-friendly approach**, but it changes the setup UX (pick printer by name instead of VID/PID). Decide this with the user before building.
- **Android:** `usb_serial` / `flutter_blue_plus`, entirely different permission model.
- Keep `ReceiptBuilder`/`ZReadingBuilder` as pure Dart functions returning `Uint8List` and cover them with golden-byte unit tests copied from the layout above. Hardware code is untestable otherwise. If using `esc_pos_utils_plus`, still verify output bytes match (especially `GS ! 0x11` large font, and the cut command `GS V 66 0`).
- Add a **screen receipt preview widget** (monospace, `w` columns) mirroring the same builder, as the UI shows a live preview in settings and after sale.

---

## 10. Design system / theme

Two themes, switched instantly (persisted in `settings.theme` **and** local `joyce-theme`; default dark). Fonts: **Outfit** (UI), **JetBrains Mono**. Base radius 14.

| Token | Black Gold (dark) | White Gold (light) |
|---|---|---|
| bg | `#0a0b10` | `#faf9f5` |
| bg-2 | `#12131b` | `#ffffff` |
| card-solid | `#161823` | `#ffffff` |
| card | `rgba(212,175,55,.04)` | `#ffffff` |
| border | `rgba(212,175,55,.22)` | `rgba(184,138,40,.22)` |
| border-subtle | `rgba(255,255,255,.08)` | `rgba(184,138,40,.12)` |
| text | `#f7f6f0` | `#1b1914` |
| muted | `#a4a093` | `#6e695d` |
| input | `#11121c` | `#f5f3eb` |
| accent | `#d4af37` | `#b88a28` |
| accent-hover | `#e8c65a` | `#9e731b` |
| accent-2 | `#f2d98d` | `#caa03e` |
| accent-deep | `#997519` | `#7a540a` |
| gradient (buttons) | 135° `#f7d468 → #d4af37 50% → #9e7518` | 135° `#d8b24e → #b88a28 60% → #8c6312` |
| btn-text | `#120e03` | `#ffffff` |
| shadow | `0 14px 45px rgba(0,0,0,.65)` | `0 10px 30px rgba(184,138,40,.10)` |
| accent shadow | `0 6px 20px rgba(212,175,55,.35)` | `0 6px 18px rgba(184,138,40,.28)` |
| app radial 1 / 2 | `rgba(212,175,55,.13)` / `rgba(247,212,104,.06)` | `rgba(184,138,40,.09)` / `rgba(216,178,78,.05)` |

Semantic (both): ok `#2fcf8a`, warn `#d4af37`, bad `#ff5470`, info `#38bdf8`, purple `#a855f7`.
Build as two `ThemeData` + a `ThemeExtension<JoyceColors>` for gradients/glows. The app background has soft radial gold glows; cards use a subtle gradient (`grad-card`). `src/styles.css` (77 KB) holds all component rules. Read it for spacing/typography before building widgets.
Shared primitives (`ui.jsx`): `Modal`, `Field`, `Toast` provider (`toast(msg, "err"?)`), `Pagination`, `PageHeader`, `RangeBar`, `Empty`, `Receipt` preview.

---

## 11. Suggested build order

1. `core/db`: schema + `init` + migrations; branch manager; `r2`, date helpers; unit tests for receipt numbering.
2. Repositories mirroring §5 with the exact SQL/validation, then **port the business-rule tests first** (sale deduction w/ variants, 0-stock sale, void restore, SOD/EOD math, business-date attribution across midnight, Z-reading net with disabled modules, previous-period window).
3. Theme + shell + lock screen + permission gating.
4. POS → Transactions/void → Products → Inventory.
5. SOD/EOD + shift gating + Z-reading preview.
6. Expenses/Salary/Commission/LD/Employees.
7. Store Overview → Admin Dashboard (largest UI: ~25 files / ~300 KB JSX; port tab by tab, it is mostly tables, KPI cards and 2 chart types).
8. Settings, branches, backup/restore/EOD snapshot, search, notifications.
9. Printing transports + hardware verification on real 58 mm and 80 mm printers.
10. Packaging per platform + legacy-DB import.

---

## 12. Known quirks / decisions for you to make

1. **Expected-cash inconsistency:** `end_day`/`get_shift_status` include *all* outflows regardless of disabled modules, while the printed Z-Reading excludes disabled ones, so the screen and receipt can show different "Expected in Drawer". Pick one rule (recommend: the printed rule, applied everywhere).
2. **Three "net" numbers** (see §6). Parity vs. clarity.
3. **Plaintext PINs** and default `0000` (§4.6).
4. **Stock can go negative** by design; confirm that's wanted.
5. **Receipt numbering counts voids and uses the wall-clock count per business date**, so it can collide only if rows are deleted (reset DB). Fine, but don't make it depend on `MAX(id)`.
6. **`restock` overwrites cost** (no weighted average); COGS for earlier sales is safe since cost is snapshotted per sale item.
7. `list_sales` is capped at 1000 rows; `list_restocks` at 300; audit feed at its `limit`. Flutter list views should paginate (UI has a `Pagination` component).
8. `delete_branch` leaves the DB file orphaned on disk.
9. Admin-PIN-for-delete is described in README but not enforced in the Rust layer (verify UI in `DashboardCrudModule.jsx`).
10. Not verified by this handoff: the inside of the large React files (`Dashboard.jsx` 52 KB, `DashboardCrudModule.jsx` 53 KB, `Settings.jsx` 50 KB, `AdminCharts.jsx` 41 KB, `AdminSalesInventoryTables.jsx` 46 KB, `useAdminController.js` 46 KB, `adminUtils.js` CSV/Excel exporters, `PinLock.jsx` animation details). Backend contracts and rules above are complete; UI layout for those screens must be taken from the JSX/CSS directly.
11. No tests exist in the repo, so there is no executable spec to port. The tests in step 2 are net-new.
