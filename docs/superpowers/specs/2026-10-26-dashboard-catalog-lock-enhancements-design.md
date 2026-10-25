# Design Specification: JOYCE POS Dashboard, Product Catalog Category, & Admin Lock Enhancements

**Date:** 2026-10-26  
**Status:** Draft (Pending Builder Review & User Approval)  
**Author:** Antigravity  

---

## 1. Intent & Context

JOYCE POS is a native Windows desktop offline-first POS designed for Philippine retail and sari-sari stores. Following the initial v1.0.1 implementation, this enhancement focuses on:
1. **Streamlining analytics:** Eliminating the separate Executive Admin Dashboard and consolidating all operational and financial insights into a single, cohesive, customizable **Store Overview** dashboard.
2. **Improving catalog UX:** Replacing free-form text input for product categories with a dynamic dropdown populated from existing categories, with an inline option to add new ones.
3. **Shift-based financial tracking:** Aligning all dashboard reports, charts, and summaries to **shift business dates** (`shifts.business_date`), fully integrating Store Expenses, Salary Payroll, Commissions, and LD Commissions, and respecting module disablement settings.
4. **Top employee earner tracking:** Highlighting the highest-earning employees by combining their salary, commission, and LD commission into a unified ranking.
5. **Personalized dashboard layout:** Giving store owners the ability to drag and reorder dashboard report sections via native reordering, with order saved across app restarts.
6. **Reliable terminal lock:** Pinning the Admin Lock button to a permanent, high-visibility position in the top bar.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- **Retire Admin Dashboard:** Remove `lib/ui/screens/admin_dashboard_screen.dart`, the `admin-dashboard` nav item in `kNavSpecs`, the route in `main.dart`, and default admin landing to `'dashboard'`.
- **Product Category Dropdown:** Provide a dropdown selection for product categories in the Add/Edit Product modal, allowing merchants to choose from existing categories or enter a new one.
- **Shift-Date Based Metrics:** Query all sales, COGS, expenses, salaries, commissions, and LD commissions by shift business date (`shifts.business_date`), falling back to calendar date only if no shift exists.
- **Comprehensive Financial Reports on Store Dashboard:**
  - Display dedicated summary cards and details for Store Expenses, Salary Payroll, Commissions, and LD Commissions.
  - Automatically omit any module and its numbers if disabled in Settings (`disabled_menus`).
  - Update Daily Revenue vs Net trend and KPI cards to factor in all enabled overheads.
- **Top Employee Earners:** Aggregate total compensation (`salary + commission + ld_commission`) per employee, display rankings in Store Overview, and omit if all three compensation modules are disabled.
- **Draggable Dashboard Sections:** Use Flutter's `ReorderableListView` to allow effortless drag-and-drop reordering of dashboard sections, persisting the layout in the database `settings` table.
- **Pinned Admin Lock Button:** Relocate the Lock action outside the scrollable top bar into a permanently visible, high-contrast button on the far right.

### Non-Goals
- Modifying POS checkout, receipt printing, or cash drawer FFI.
- Introducing multi-window support or web/mobile platforms.
- Adding third-party chart dependencies beyond existing `fl_chart`.

### Anti-Goals
- Introducing Flutter plugin symlinks that would break environments without Windows Developer Mode.
- Breaking existing unit tests or test coverage.

---

## 3. Approaches Considered & Trade-Offs

### Approach 1: Reorderable Card Flow with Native `ReorderableListView` (Selected)
- Wrap dashboard report sections in modular card widgets managed by a `ReorderableListView`.
- Provide subtle drag handles (`Icons.drag_indicator`) and smooth native reordering.
- Store the user's preferred card order as a JSON list in `settings` (`dashboard_card_order`).
- **Why chosen:** Native, 60fps performance on Windows desktop, zero risk of coordinate drift or hit-test failure, minimal new code.

### Approach 2: Custom Multi-Column Grid Drag-and-Drop (`Draggable` + `DragTarget`) (Rejected)
- Build a custom 2D grid allowing tiles to be dragged side-by-side or stacked.
- **Why rejected:** Significantly higher complexity, requires manual collision detection and slot calculation on window resize, prone to layout overflow bugs on desktop.

---

## 4. Detailed Design Specifications

### 4.1 Retirement of Admin Dashboard
- **Deleted file:** `lib/ui/screens/admin_dashboard_screen.dart`.
- **Navigation specs (`lib/ui/shell/app_shell.dart`):** Remove `NavItemSpec(id: 'admin-dashboard', ...)` from `kNavSpecs`. Group `Store Overview` directly under `Analytics & Control`.
- **Router (`lib/main.dart`):** Remove case `'admin-dashboard'`.
- **Application State (`lib/core/state/app_state.dart`):**
  - Update `loginWithPin`: If `user['role'] == 'admin'`, default `_activeTab = 'dashboard'`.
  - Remove `_adminSubTab` and `setAdminSubTab` methods.

### 4.2 Product Catalog Category Dropdown
- **Location:** `lib/ui/screens/products_screen.dart` (`_ProductFormModal`).
- **Behavior:**
  - Retrieve list of existing categories via `widget.appState.repo.listCategories()` and distinct categories from existing products.
  - Render a `DropdownButtonFormField<String>` displaying all unique categories.
  - Include a special dropdown item: `"+ Add New Category..."`.
  - When selected, display an inline `TextField` allowing the user to type a new category name.
  - Pre-select the existing product's category when editing.

### 4.3 Shift-Based Store Overview & Finance Overheads
- **Shift Date Attribution:**
  - All SQL queries in `PosRepository.dashboard()` and `_computeCoreMetrics()` must resolve date via:
    `COALESCE((SELECT business_date FROM shifts WHERE id = x.shift_id), x.date) BETWEEN ? AND ?`.
  - This ensures that transactions entered during a midnight-crossing shift are attributed to that shift's business date.
- **Module Enablement Filtering (`disabled_menus`):**
  - `expenses`: If disabled, store expenses = 0, excluded from overheads and net profit, expense breakdown card omitted.
  - `salary`: If disabled, salaries = 0, excluded from overheads, salary breakdown omitted.
  - `commission`: If disabled, commissions = 0, excluded from overheads, commission breakdown omitted.
  - `ld-commission`: If disabled, LD commissions = 0, excluded from overheads, LD commission breakdown omitted.
- **Overheads & Net Formulas:**
  - `Gross Profit = Revenue - COGS`.
  - `Total Overheads = Expenses + Salaries + Commissions + LD Commissions` (only enabled modules).
  - `Net Profit = Gross Profit - Total Overheads`.
  - `Net Operating Cash Flow = Revenue - Total Overheads`.
  - Daily trend chart renders lines for `Daily Revenue` and `Daily Net`.

### 4.4 Top Employee Earners Card
- **Calculation (`PosRepository._computeTopEmployees`):**
  - Gathers all payouts in the selected date range:
    - Salaries (if `salary` enabled)
    - Commissions (if `commission` enabled)
    - LD Commissions (if `ld-commission` enabled)
  - Aggregates by employee name: `total = salary + commission + ld_commission`.
  - Sorts descending by `total`.
- **UI Card in Store Overview:**
  - Title: `Top Employee Earners`.
  - Displays avatar/badge, employee name, individual breakdowns (e.g. `Salary: ₱X • Comm: ₱Y • LD: ₱Z`), and total payout.
  - If all three modules are disabled in Settings, the card is completely hidden from the dashboard.

### 4.5 Draggable Dashboard Sections Architecture
- **Cards Definitions:**
  1. `kpis`: KPI metrics grid (Revenue, Gross Profit, Overheads, Net Profit, Inventory Valuation).
  2. `daily_trend`: Line chart of Daily Revenue vs Net.
  3. `finance_breakdown`: Summary tiles and category totals for Store Expenses, Salary, Commissions, and LD Commissions (only enabled modules).
  4. `top_employees`: Top Employee Earners (omitted if all compensation modules are disabled).
  5. `top_products`: Top Products by Revenue.
  6. `variant_sales`: Variant & Pack Sales breakdown.
  7. `stock_alerts`: Low & Out-of-Stock alert list.
  8. `shift_history`: Recent shifts list with cash float, drawer over/short, and notes (relocated from admin dashboard).
- **CSV Data Exports:**
  - Preserved in Store Overview header alongside the date range picker: 1-click export for Daily P&L and Product Sales CSVs.
- **Reordering UI:**
  - The dashboard body uses a `ReorderableListView` (with `buildDefaultDragHandles: false`).
  - Each card header includes a drag handle (`ReorderableDragStartListener(index: ..., child: Icon(Icons.drag_indicator))`) in the upper-right corner.
  - On reorder: updates state and calls `widget.appState.saveDashboardCardOrder(newOrder)`.
  - Persistent storage: stored as JSON list in SQLite `settings` table (`key: 'dashboard_card_order'`).

### 4.6 Shift History & Reconciliation Access
- Shift history is accessible directly via the draggable `shift_history` card on the Store Overview, and also opens via clicking the shift badge in the top bar.
- Cash shortage alerts deep-link directly to the shift history section.

### 4.7 Access Control & Role Permissions
- **Store Overview Visibility:** Store Overview (`dashboard`) remains viewable by both Administrators and Cashiers (with cashier permission).
- **Settings-Driven Masking:** Any financial, payroll, commission, or employee earner card is completely omitted and excluded from calculations if the merchant disables that module in Settings (`disabled_menus`). If a module is enabled, it displays transparently on the dashboard.

### 4.6 Header Admin Lock Button
- **Location:** `lib/ui/shell/app_shell.dart` top bar.
- **Fix & Positioning:**
  - Extract the Lock action completely out of any horizontally scrollable container.
  - Position it on the fixed right side of the header:
    - Label: `Lock Terminal` or `Admin Lock` with `Icons.lock_outline`.
    - Distinct styling (gold accent border or warning subtle highlight) with explicit tooltip `"Lock terminal and return to PIN screen"`.
  - Immediate execution: Invokes `appState.logout()`, immediately transitioning the UI back to `PinLockScreen`.

---

## 5. What's Left to the Builder
- Exact card spacing and padding constants.
- Visual micro-styling of the drag handle icon and hover states.
- Minor string representations in tooltips and empty states.
