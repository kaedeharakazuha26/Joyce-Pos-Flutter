# Joyce POS 🛒

A fast, offline-first Point of Sale (POS) and Store Management system built with **Flutter Desktop (Windows)** and pure **SQLite3 FFI**. Designed specifically for retail stores, convenience shops, and small businesses requiring reliable shift reconciliation, thermal receipt printing, and comprehensive overhead tracking.

---

## 🚀 Key Features & Capabilities

### 1. 💳 Point of Sale (POS)
* **High-Speed Checkout:** Fast product lookup by barcode scanner or real-time text search.
* **Variant & Multi-Pack Sales:** Sell items as individual units or bundled packs (e.g., *Single Can*, *6-Pack*, *Case of 24*); stock is automatically deducted in base units.
* **Multiple Payment Methods:** Supports Cash, GCash, Maya, and Bank Transfer with instant change calculation.
* **Discounts & Price Overrides:** Item-level discounts or custom pricing with permission validation.
* **Voiding & Corrections:** Order cancellation and item removal logged in the audit trail.
* **Receipt Printing:** Built-in ESC/POS printer driver supporting 58mm and 80mm thermal paper, USB and network connections, and automatic paper cutting.

### 2. 📊 Store Overview Dashboard
* **Draggable & Reorderable Cards:** Customize your dashboard view by dragging cards into your preferred order (persisted automatically with a one-click reset button).
* **Core Business KPIs:** Live metrics for Gross Revenue, Orders, Cost of Goods Sold (COGS), Gross Profit, Overheads, and Net Operating Cash Flow.
* **Shift-Date Financial Metrics:** Financial data is anchored to physical business shifts rather than plain calendar days.
* **Top Performer Employee:** Combines salary, standard commissions, and LD commissions into a single ranked leaderboard.
* **Daily Trend Graph:** Interactive visual chart comparing daily revenue against net cash flow.
* **Paginated Reports (Max 5 per page):**
  * *Top Products by Revenue*
  * *Variant & Pack Breakdown*
  * *Low / Out-of-Stock Item Alerts*
* **Export Reports:** Instant CSV downloads for Daily P&L and Product Performance.

### 3. 📦 Products & Inventory Management
* **Catalog Management:** Add and edit products with SKU, Barcode, Price, Cost, Category, and Stock alerts.
* **Category Dropdown:** Easy selection of categories with inline `+` button to create new categories on the fly.
* **Stock Adjustments:** Record incoming shipments, stock write-offs (spoilage/damage), and manual count corrections.
* **Low Stock Alerts:** Automatic badge highlighting when items reach or drop below their minimum threshold.

### 4. 💰 Finance & Overheads
* **Store Expenses:** Record overhead costs (utilities, supplies, rent) with category dropdown, custom category creation (`+`), and date selector defaulting to the active shift.
* **Salary Payroll:** Record employee payouts directly by date without rigid pay periods.
* **Commissions:** Track sales commissions with customizable commission types (e.g. Sales, Bonus, Referral) and inline addition.
* **LD Commissions:** Dedicated tracking for volume-based commissions (e.g. per-bottle or per-service payouts).
* **CSV Export:** One-click CSV export available for all finance records.

### 5. ⏱️ Shifts & Cash Drawer Reconciliation
* **Shift Gating:** Protects POS checkout by requiring an open shift with recorded opening float.
* **Cash Drops & Payouts:** Track cash removals during the day without closing the shift.
* **Z-Reading & EOD Close:** Reconciles actual cash count against expected drawer cash, tracks shortages/overages, creates an End-of-Day snapshot, and prints Z-Reading receipts.
* **Shift History:** Review past shifts, drawer discrepancies, and closing notes.

### 6. 🔐 Security & Access Control
* **PIN Authentication:** 4-digit PIN lock screen distinguishing Administrator from Cashier roles.
* **Header Admin Lock:** Instant lock button pinned to the top navigation header for quick screen locking.
* **Admin Overrides:** Sensitive operations (voiding sales, editing inventory, deleting finance entries) require Admin authorization.
* **Audit Trail:** Detailed logs of critical actions (logins, voids, stock changes, shift closures).

### 7. ⚙️ Settings & Multi-Branch Support
* **Modular Menu Toggles:** Enable or disable modules (Expenses, Payroll, Commissions, Store Overview, etc.) to tailor the POS interface to your workflow.
* **Printer Configuration:** Configure thermal printer type (Windows Spooler or ESC/POS Network IP:Port), paper width, and feed lines.
* **Receipt Customization:** Set store name, address, contact numbers, TIN, and custom footer messages.
* **Branch Management:** Switch branches, create localized backups, restore snapshots, or safely factory reset the database.

---

## 🛠️ Technology Stack

| Layer | Technology |
| :--- | :--- |
| **Framework** | [Flutter](https://flutter.dev) (Desktop Windows Native) |
| **Language** | Dart 3 |
| **Database** | Pure Dart FFI [`sqlite3`](https://pub.dev/packages/sqlite3) (Zero native C++ plugins / symlink issues) |
| **Charts** | [`fl_chart`](https://pub.dev/packages/fl_chart) |
| **Thermal Printing** | ESC/POS raw byte builder via Win32 print spooler & TCP sockets |
| **Architecture** | Repository Pattern with `ChangeNotifier` reactive state management |

---

## 🏁 Getting Started

### Prerequisites
* Windows 10 or Windows 11 (64-bit)
* [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (v3.24+ recommended)
* Visual Studio 2022 with **Desktop development with C++** workload installed

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kaedeharakazuha26/Joyce-Pos-Flutter.git
   cd Joyce-Pos-Flutter
   ```

2. **Fetch dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run in development mode:**
   ```bash
   flutter run -d windows
   ```

4. **Run automated test suite:**
   ```bash
   flutter test
   ```

5. **Build release executable:**
   ```bash
   flutter build windows
   ```
   The compiled `.exe` and required runtime assets will be located in:  
   `build\windows\x64\runner\Release\`

---

## 🔑 Default Credentials

* **Default Admin PIN:** `0000` (can be changed in *Settings* → *Admin Security*)
* **Default Branch:** `Main Store`
