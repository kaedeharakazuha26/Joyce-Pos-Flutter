# Dashboard, Product Catalog Category, & Admin Lock Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the executive admin dashboard, add category dropdown selection in the product catalog, group all Store Overview reports by shift date with comprehensive finance overheads & top employee earners, make dashboard cards reorderable via drag-and-drop with persistence, and fix the pinned header Admin Lock button.

**Architecture:** Extend `PosRepository` to provide shift-attributed financial metrics, top employee combined earnings, and card order storage in SQLite `settings`; simplify `AppState` and `AppShell` navigation to retire `admin-dashboard` and pin the Admin Lock button; update `ProductsScreen` with dynamic category dropdown; re-architect `StoreOverviewScreen` around Flutter's `ReorderableListView` with modular cards.

**Tech Stack:** Flutter desktop (Windows), SQLite FFI (`winsqlite3.dll`), `fl_chart`, pure-Dart state and repositories.

**Spec:** `docs/superpowers/specs/2026-10-26-dashboard-catalog-lock-enhancements-design.md`

## Global Constraints
- Target platform: Windows PC desktop only (`flutter run -d windows` / `flutter build windows`).
- No Flutter plugin symlinks: rely strictly on pure-Dart/FFI packages (`sqlite3`, `win32`, `ffi`).
- Philippine Peso formatting: `formatPeso(...)` with ASCII fallback in thermal printing if needed.
- Shift date attribution: all financial aggregation must use `shifts.business_date` (falling back to calendar date only if no shift exists).
- Settings-driven masking: all financial, payroll, and earner reports must be cleanly omitted if marked disabled in `disabled_menus`.

## Review Focus
1. **Empty / No Active Shift Date Attribution:** A sale or expense recorded outside any shift must fall back to `date(created_at)` rather than throwing null errors or disappearing from range queries.
2. **All Payroll Modules Disabled:** When `salary`, `commission`, and `ld-commission` are all disabled in Settings, the `top_employees` card and query must not crash and must hide cleanly from Store Overview.
3. **Product Category Dropdown with No Existing Categories:** If the store has 0 products and 0 categories, selecting `+ Add New Category...` must work seamlessly and allow typing the first category name.
4. **Reorderable Card State Corrupted in DB:** If the saved `dashboard_card_order` in `settings` contains missing or extra keys, it must self-heal to include all valid cards without throwing `StateError`.
5. **Admin Lock Trigger:** Clicking the top-right Admin Lock button must instantly call `logout()`, clearing the active user and immediately displaying `PinLockScreen`.

---

### Task 1: PosRepository Shift-Based Metrics, Overheads Breakdown, Top Earners & Card Order Persistence

**Files:**
- Modify: `lib/data/pos_repository.dart`
- Test: `test/pos_repository_test.dart`

**Interfaces:**
- Consumes: `_db.select`, `getDisabledMenus`, `activeBusinessDate`, `shifts` table
- Produces:
  - `PosRepository.dashboard({required String from, required String to}) -> Map<String, dynamic>` (augmented with `finance_summary`, `shift_history`, and shift-date attribution)
  - `PosRepository.getDashboardCardOrder() -> List<String>`
  - `PosRepository.saveDashboardCardOrder(List<String> order) -> void`

- [ ] **Step 1: Write the failing tests**

In `test/pos_repository_test.dart`, add a test suite verifying:
1. `dashboard()` returns shift-attributed revenue, overheads, `finance_summary` (expenses, salaries, commissions, ld_commissions), `top_employees`, and `shift_history`.
2. Disabling `salary`, `commission`, and `ld-commission` in `disabled_menus` zeroes their totals and excludes them from `top_employees`.
3. `getDashboardCardOrder()` returns the default 8 cards, and `saveDashboardCardOrder()` persists and updates the order.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/pos_repository_test.dart`
Expected: FAIL (missing methods or properties)

- [ ] **Step 3: Implement PosRepository updates**

In `lib/data/pos_repository.dart`:
1. Ensure all `_db.select` queries in `_computeCoreMetrics`, `dashboard()`, and `_computeTopEmployees` use:
   `COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), t.date) BETWEEN ? AND ?` (or `date(t.created_at)` for sales).
2. Add `finance_summary` in `dashboard()` returning:
   ```dart
   'finance_summary': {
     'expenses': {'enabled': isModuleEnabled('expenses', disabled), 'total': expenses, 'count': expCount},
     'salaries': {'enabled': isModuleEnabled('salary', disabled), 'total': salaries, 'count': salCount},
     'commissions': {'enabled': isModuleEnabled('commission', disabled), 'total': commissions, 'count': comCount},
     'ld_commissions': {'enabled': isModuleEnabled('ld-commission', disabled), 'total': ldCommissions, 'count': ldCount},
   }
   ```
3. Add `shift_history` in `dashboard()` returning `listShifts(limit: 30)`.
4. Implement `getDashboardCardOrder()`:
   Reads `dashboard_card_order` from `settings` table, parses JSON or comma-separated list, self-heals against default list:
   `['kpis', 'daily_trend', 'finance_breakdown', 'top_employees', 'top_products', 'variant_sales', 'stock_alerts', 'shift_history']`.
5. Implement `saveDashboardCardOrder(List<String> order)`:
   Writes JSON encoded list to `settings(key, value)` with key `'dashboard_card_order'`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/pos_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/pos_repository.dart test/pos_repository_test.dart
git commit -m "feat: add shift-attributed finance metrics, top earners, and card order persistence"
```

---

### Task 2: AppState & AppShell Cleanup (Retire Admin Dashboard & Pin Header Admin Lock Button)

**Files:**
- Delete: `lib/ui/screens/admin_dashboard_screen.dart`
- Modify: `lib/core/state/app_state.dart`
- Modify: `lib/ui/shell/app_shell.dart`
- Modify: `lib/main.dart`
- Test: `test/app_state_test.dart`
- Test: `test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `AppState.logout()`, `AppState.repo.saveDashboardCardOrder`
- Produces:
  - Cleaned `kNavSpecs` without `admin-dashboard`
  - Admin login defaulting to `dashboard`
  - Fixed, pinned Admin Lock button in top bar header

- [ ] **Step 1: Write the failing tests**

In `test/app_state_test.dart` and `test/widget_smoke_test.dart`:
1. Verify `appState.loginWithPin('0000')` sets `activeTab` to `'dashboard'`.
2. Verify `kNavSpecs` contains only 1 item in `Analytics & Control` (`Store Overview`).
3. Verify the pinned Admin Lock button is present in `AppShell` and clicking it invokes `appState.logout()`, locking the terminal.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_state_test.dart test/widget_smoke_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement retirement of Admin Dashboard & Pinned Lock Button**

1. Delete `lib/ui/screens/admin_dashboard_screen.dart`.
2. In `lib/core/state/app_state.dart`:
   - Remove `_adminSubTab` and `setAdminSubTab`.
   - In `loginWithPin`: If `user['role'] == 'admin'`, set `_activeTab = 'dashboard'`.
   - Remove `'admin-dashboard'` from permission checks.
3. In `lib/main.dart`:
   - Remove import and `case 'admin-dashboard':` from `screenBuilder`.
4. In `lib/ui/shell/app_shell.dart`:
   - Remove `admin-dashboard` spec from `kNavSpecs`.
   - Move the Lock button outside the `SingleChildScrollView` of the top bar into a pinned right action:
     ```dart
     // Pinned Admin Lock Button
     IconButton(
       tooltip: 'Lock Terminal (Admin Lock)',
       icon: Icon(Icons.lock_outline, color: c.accent, size: 20),
       onPressed: appState.logout,
     )
     ```
   - Also retain the user display badge (`Text('${appState.currentUserName}')`) clearly in the top bar.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/app_state_test.dart test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git rm lib/ui/screens/admin_dashboard_screen.dart
git add lib/core/state/app_state.dart lib/ui/shell/app_shell.dart lib/main.dart test/app_state_test.dart test/widget_smoke_test.dart
git commit -m "feat: retire admin dashboard and pin header Admin Lock button"
```

---

### Task 3: Product Catalog Category Dropdown with Inline Creation

**Files:**
- Modify: `lib/ui/screens/products_screen.dart`
- Test: `test/operations_screens_test.dart`

**Interfaces:**
- Consumes: `PosRepository.listCategories()`, `products` catalog
- Produces: `_ProductFormModal` with dynamic category dropdown and inline custom category entry

- [ ] **Step 1: Write the failing tests**

In `test/operations_screens_test.dart`:
1. Add test opening the Add Product modal and verifying category selection renders existing categories as dropdown items plus `+ Add New Category...`.
2. Selecting `+ Add New Category...` exposes text entry and saves product with the new category.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/operations_screens_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement category dropdown in ProductsScreen**

In `lib/ui/screens/products_screen.dart`:
1. In `_ProductFormModal`:
   - Fetch unique categories: `repo.listCategories()` unioned with distinct categories from current product list.
   - Maintain state: `String? _selectedCategory` and `bool _isAddingNewCategory`.
   - If editing an existing product whose category is in the list, pre-select it. If not in the list, include it in the dropdown options.
   - Render `DropdownButtonFormField<String>`:
     - Items: all existing categories + `DropdownMenuItem(value: '__NEW__', child: Text('+ Add New Category...', style: TextStyle(color: c.accent, fontWeight: FontWeight.bold)))`.
     - When `'__NEW__'` is selected: display an inline `TextFormField` for new category name.
   - On save: validate that category is not empty.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/operations_screens_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/products_screen.dart test/operations_screens_test.dart
git commit -m "feat: add category dropdown with inline creation to product catalog"
```

---

### Task 4: Store Overview Draggable Card Flow, Top Employee Earners & Finance Overheads

**Files:**
- Modify: `lib/ui/screens/store_overview_screen.dart`
- Test: `test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `PosRepository.dashboard()`, `PosRepository.getDashboardCardOrder()`, `PosRepository.saveDashboardCardOrder()`
- Produces: Reorderable dashboard with 8 modular cards, top employee earners, and finance overheads

- [ ] **Step 1: Write the failing tests**

In `test/widget_smoke_test.dart`:
1. Verify `StoreOverviewScreen` renders `ReorderableListView`.
2. Verify `Top Employee Earners` card displays staff names and earnings.
3. Verify `Finance Overheads` card renders breakdown when enabled and hides when disabled.
4. Verify reordering updates card order and calls `saveDashboardCardOrder`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement StoreOverviewScreen reorderable card system**

In `lib/ui/screens/store_overview_screen.dart`:
1. Load `_cardOrder = widget.appState.repo.getDashboardCardOrder()`.
2. Implement 8 modular card builders with drag handles:
   - `_buildKpisCard(c)`
   - `_buildDailyTrendCard(c, daily)`
   - `_buildFinanceBreakdownCard(c, financeSummary)` (omits disabled modules; hides if all disabled)
   - `_buildTopEmployeesCard(c, topEmployees)` (omits if all payroll modules disabled)
   - `_buildTopProductsCard(c, top)`
   - `_buildVariantSalesCard(c, variantSales)`
   - `_buildStockAlertsCard(c, lowStock)`
   - `_buildShiftHistoryCard(c, shiftHistory)`
3. Wrap cards in a `ReorderableListView`:
   - `buildDefaultDragHandles: false`
   - Each card header includes `ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator, color: c.muted))`
   - `onReorder: (oldIndex, newIndex) => setState(...)` and save order via `repo.saveDashboardCardOrder(_cardOrder)`.
4. Add 1-click CSV Export button in screen header / RangeBar.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test; flutter analyze`
Expected: PASS (all tests pass, 0 analyzer issues)

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/store_overview_screen.dart test/widget_smoke_test.dart
git commit -m "feat: implement draggable store overview dashboard with top earners and finance overheads"
```

---

### Task 5: Final Review & End-to-End Verification

**Files:**
- Entire repository

- [ ] **Step 1: Run full verification suite**
  Run: `flutter test; flutter analyze`
  Expected: 0 failures, 0 issues.
- [ ] **Step 2: Review git status and git log**
  Confirm all changes are cleanly committed to local git with descriptive messages.
