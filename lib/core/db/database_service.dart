import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import '../utils/dates.dart';

bool _sqliteLoaderInitialized = false;

void ensureSqliteLoaded() {
  if (_sqliteLoaderInitialized) return;
  _sqliteLoaderInitialized = true;
  if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, () {
      try {
        return DynamicLibrary.open('sqlite3.dll');
      } catch (_) {
        return DynamicLibrary.open('winsqlite3.dll');
      }
    });
  }
}

class DatabaseService {
  Database? _db;
  String? _activePath;

  Database get db {
    final current = _db;
    if (current == null) {
      throw StateError('Database has not been opened yet.');
    }
    return current;
  }

  String get activePath => _activePath ?? '';

  void openPath(String dbPath) {
    ensureSqliteLoaded();
    close();
    final parent = File(dbPath).parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    _db = sqlite3.open(dbPath);
    _activePath = dbPath;
    _db!.execute('PRAGMA journal_mode=WAL;');
    _db!.execute('PRAGMA foreign_keys=OFF;');
    init();
  }

  void init() {
    final d = db;
    d.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
        barcode TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '',
        price REAL NOT NULL DEFAULT 0,
        cost REAL NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        low_stock INTEGER NOT NULL DEFAULT 5,
        image TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS variants(
        id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL,
        name TEXT NOT NULL, qty INTEGER NOT NULL, price REAL NOT NULL
      );

      CREATE TABLE IF NOT EXISTS sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT, receipt_no TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0, paid REAL NOT NULL DEFAULT 0, change_amt REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'completed',
        created_at TEXT NOT NULL, voided_at TEXT, void_reason TEXT,
        voided_by TEXT NOT NULL DEFAULT '', shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL,
        variant_id INTEGER, name TEXT NOT NULL, variant_name TEXT NOT NULL DEFAULT '',
        units_per INTEGER NOT NULL DEFAULT 1, unit_price REAL NOT NULL, quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL, cost_total REAL NOT NULL DEFAULT 0
      );

      CREATE TABLE IF NOT EXISTS voided_sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, receipt_no TEXT NOT NULL,
        total REAL NOT NULL, reason TEXT NOT NULL DEFAULT '', items_json TEXT NOT NULL,
        sold_at TEXT NOT NULL, voided_at TEXT NOT NULL, voided_by TEXT NOT NULL DEFAULT '',
        shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS restocks(
        id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, product_name TEXT NOT NULL,
        qty INTEGER NOT NULL, unit_cost REAL NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '', amount REAL NOT NULL, date TEXT NOT NULL, shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS salaries(
        id INTEGER PRIMARY KEY AUTOINCREMENT, employee TEXT NOT NULL, amount REAL NOT NULL,
        period TEXT NOT NULL DEFAULT '', date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS employees(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, position TEXT NOT NULL DEFAULT '',
        commission REAL NOT NULL DEFAULT 0,
        ld_commission REAL NOT NULL DEFAULT 0,
        salary REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS commission_types(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE
      );
      INSERT OR IGNORE INTO commission_types(name) VALUES('Sales'),('Bonus'),('Referral');

      CREATE TABLE IF NOT EXISTS commissions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, employee_id INTEGER,
        employee_name TEXT NOT NULL, type TEXT NOT NULL DEFAULT '', amount REAL NOT NULL, shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS ld_commissions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, employee_id INTEGER,
        employee_name TEXT NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, amount REAL NOT NULL, shift_id INTEGER DEFAULT NULL
      );

      CREATE TABLE IF NOT EXISTS cashiers(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, pin TEXT NOT NULL UNIQUE,
        permissions TEXT NOT NULL,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS settings(
        key TEXT PRIMARY KEY, value TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT, business_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open',
        opened_by TEXT NOT NULL DEFAULT '', opened_at TEXT NOT NULL, opening_cash REAL NOT NULL DEFAULT 0,
        closed_by TEXT NOT NULL DEFAULT '', closed_at TEXT, closing_cash REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0, cash_sales REAL NOT NULL DEFAULT 0,
        expenses REAL NOT NULL DEFAULT 0, salaries REAL NOT NULL DEFAULT 0,
        commissions REAL NOT NULL DEFAULT 0, ld_commissions REAL NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT ''
      );

      CREATE TABLE IF NOT EXISTS audit_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL,
        actor TEXT NOT NULL DEFAULT 'Administrator', role TEXT NOT NULL DEFAULT 'admin',
        action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL, details_json TEXT NOT NULL DEFAULT '{}'
      );

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
    ''');

    // Best-effort legacy column migrations
    const migrations = [
      "ALTER TABLE sales ADD COLUMN voided_by TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE sales ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE sale_items ADD COLUMN cost_total REAL NOT NULL DEFAULT 0",
      "ALTER TABLE voided_sales ADD COLUMN voided_by TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE voided_sales ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE restocks ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE expenses ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE salaries ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE commissions ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE ld_commissions ADD COLUMN shift_id INTEGER DEFAULT NULL",
      "ALTER TABLE ld_commissions ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1",
    ];
    for (final sql in migrations) {
      try {
        d.execute(sql);
      } catch (_) {}
    }
  }

  void logAudit({
    String actor = 'Administrator',
    String role = 'admin',
    required String action,
    required String entityType,
    String entityId = '',
    required String summary,
    Map<String, dynamic>? details,
  }) {
    try {
      final safeActor = actor.trim().isEmpty ? 'Administrator' : actor.trim();
      final safeRole = role.trim().isEmpty ? 'admin' : role.trim();
      final ts = formatDateTime(DateTime.now());
      final jsonStr = jsonEncode(details ?? const <String, dynamic>{});
      db.execute(
        '''INSERT INTO audit_logs(timestamp, actor, role, action, entity_type, entity_id, summary, details_json)
           VALUES(?, ?, ?, ?, ?, ?, ?, ?)''',
        [ts, safeActor, safeRole, action, entityType, entityId, summary, jsonStr],
      );
    } catch (_) {
      // Never fail parent operation
    }
  }

  void backupDb(String targetPath, {String actor = 'Administrator', String role = 'admin'}) {
    final outFile = File(targetPath);
    if (outFile.existsSync()) {
      outFile.deleteSync();
    }
    if (!outFile.parent.existsSync()) {
      outFile.parent.createSync(recursive: true);
    }
    final escaped = targetPath.replaceAll("'", "''");
    db.execute("VACUUM INTO '$escaped'");
    logAudit(
      actor: actor,
      role: role,
      action: 'BACKUP',
      entityType: 'system',
      entityId: targetPath,
      summary: 'Database backed up to $targetPath',
      details: {'path': targetPath},
    );
  }

  void restoreDb(String sourcePath, {String actor = 'Administrator', String role = 'admin'}) {
    ensureSqliteLoaded();
    final srcFile = File(sourcePath);
    if (!srcFile.existsSync()) {
      throw Exception('Backup file does not exist');
    }

    // Validate required tables in source DB
    final checkDb = sqlite3.open(sourcePath, mode: OpenMode.readOnly);
    try {
      final rows = checkDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('products','sales','settings')",
      );
      final found = rows.map((r) => r['name'] as String).toSet();
      if (!found.containsAll({'products', 'sales', 'settings'})) {
        throw Exception('Not a valid JOYCE POS backup');
      }
    } finally {
      checkDb.dispose();
    }

    final currentPath = _activePath;
    if (currentPath == null || currentPath.isEmpty) {
      throw StateError('No active database path to restore into');
    }

    close();
    final walFile = File('$currentPath-wal');
    final shmFile = File('$currentPath-shm');
    if (walFile.existsSync()) walFile.deleteSync();
    if (shmFile.existsSync()) shmFile.deleteSync();

    srcFile.copySync(currentPath);
    openPath(currentPath);
    logAudit(
      actor: actor,
      role: role,
      action: 'RESTORE',
      entityType: 'system',
      entityId: sourcePath,
      summary: 'Database restored from $sourcePath',
      details: {'source': sourcePath},
    );
  }

  void resetDb(
    String pin,
    bool keepCatalog, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final rows = db.select("SELECT value FROM settings WHERE key='admin_pin'");
    final adminPin = rows.isNotEmpty ? (rows.first['value'] as String) : '0000';
    if (pin.trim() != adminPin) {
      throw Exception('Incorrect admin PIN');
    }

    db.execute('BEGIN TRANSACTION');
    try {
      const txTables = [
        'sales',
        'sale_items',
        'voided_sales',
        'restocks',
        'expenses',
        'salaries',
        'commissions',
        'ld_commissions',
        'shifts',
      ];
      for (final t in txTables) {
        db.execute('DELETE FROM $t');
      }
      if (!keepCatalog) {
        for (final t in ['products', 'variants', 'employees', 'cashiers']) {
          db.execute('DELETE FROM $t');
        }
      }
      logAudit(
        actor: actor,
        role: role,
        action: 'RESET_DB',
        entityType: 'system',
        summary: keepCatalog
            ? 'Reset database transactions (kept catalog)'
            : 'Full database reset (cleared transactions and catalog)',
        details: {'keep_catalog': keepCatalog},
      );
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}
