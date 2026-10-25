import 'dart:convert';
import 'dart:math';
import 'package:sqlite3/sqlite3.dart';
import '../core/db/branch_manager.dart';
import '../core/db/database_service.dart';
import '../core/utils/dates.dart';
import '../core/utils/money.dart';

class PosRepository {
  final DatabaseService dbService;
  final BranchManager branchManager;

  PosRepository({
    required this.dbService,
    required this.branchManager,
  });

  Database get _db => dbService.db;

  // --- Shift & Business Date Helpers ---

  Map<String, dynamic>? _getOpenShiftRow() {
    final rows = _db.select(
      "SELECT * FROM shifts WHERE status = 'open' ORDER BY id DESC LIMIT 1",
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  String activeBusinessDate() {
    final open = _getOpenShiftRow();
    if (open != null) {
      final bd = (open['business_date'] as String? ?? '').trim();
      if (bd.isNotEmpty) return bd;
    }
    return todayDateString();
  }

  int? activeShiftId() {
    final open = _getOpenShiftRow();
    return open?['id'] as int?;
  }

  String currentBusinessNow() {
    return businessNow(activeBusinessDate());
  }

  // --- Settings & Module Toggles ---

  Map<String, String> getSettings() {
    final defaults = <String, String>{
      'theme': 'dark',
      'store_name': 'JOYCE POS',
      'store_address': '',
      'store_phone': '',
      'receipt_header': '',
      'receipt_footer': 'Thank you! Come again.',
      'paper_width': '58',
      'chars_per_line': '32',
      'font_size': 'normal',
      'header_align': 'center',
      'footer_align': 'center',
      'printer_conn': 'none',
      'usb_vid': '',
      'usb_pid': '',
      'serial_path': 'COM1',
      'network_addr': '192.168.1.100:9100',
      'auto_print': '0',
      'copies': '1',
      'feed_lines': '3',
      'cut_paper': '1',
      'open_drawer': '0',
      'disabled_menus': '[]',
      'admin_pin': '0000',
    };
    final rows = _db.select('SELECT key, value FROM settings');
    for (final r in rows) {
      defaults[r['key'] as String] = r['value'] as String;
    }
    return defaults;
  }

  Map<String, String> setSettings(
    Map<String, String> values, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    _db.execute('BEGIN TRANSACTION');
    try {
      for (final entry in values.entries) {
        _db.execute(
          '''INSERT INTO settings(key, value) VALUES(?, ?)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
          [entry.key, entry.value],
        );
      }
      dbService.logAudit(
        actor: actor,
        role: role,
        action: 'UPDATE',
        entityType: 'settings',
        summary: 'Updated settings (${values.keys.join(", ")})',
        details: values,
      );
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return getSettings();
  }

  Set<String> getDisabledMenus() {
    final s = getSettings();
    final raw = s['disabled_menus'] ?? '[]';
    final out = <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          final k = item.toString().trim().toLowerCase();
          if (k.isEmpty) continue;
          out.add(k);
          if (k == 'salary' || k == 'salaries') {
            out.addAll(['salary', 'salaries']);
          } else if (k == 'commission' || k == 'commissions') {
            out.addAll(['commission', 'commissions']);
          } else if (k == 'ld-commission' || k == 'ld_commission' || k == 'ld-commissions') {
            out.addAll(['ld-commission', 'ld_commission', 'ld-commissions']);
          }
        }
      }
    } catch (_) {}
    return out;
  }

  bool isModuleEnabled(String moduleId, [Set<String>? disabled]) {
    final set = disabled ?? getDisabledMenus();
    return !set.contains(moduleId.toLowerCase());
  }

  // --- Auth & Cashiers ---

  Map<String, dynamic> verifyPin(String pin) {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) {
      throw Exception('Please enter a PIN');
    }
    final settings = getSettings();
    final adminPin = settings['admin_pin'] ?? '0000';
    if (trimmed == adminPin) {
      return {
        'id': 0,
        'name': 'Administrator',
        'role': 'admin',
        'permissions': <String>['*'],
      };
    }

    final rows = _db.select('SELECT * FROM cashiers WHERE pin = ? LIMIT 1', [trimmed]);
    if (rows.isEmpty) {
      throw Exception('Incorrect PIN. Please try again.');
    }
    final c = rows.first;
    List<String> perms = ['pos', 'transactions'];
    try {
      final parsed = jsonDecode(c['permissions'] as String? ?? '[]');
      if (parsed is List && parsed.isNotEmpty) {
        perms = parsed.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return {
      'id': c['id'] as int,
      'name': c['name'] as String,
      'role': 'cashier',
      'permissions': perms,
    };
  }

  void changeAdminPin(
    String oldPin,
    String newPin, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final n = newPin.trim();
    if (n.length < 4) {
      throw Exception('New PIN must be at least 4 digits');
    }
    final settings = getSettings();
    final currentAdmin = settings['admin_pin'] ?? '0000';
    if (oldPin.trim() != currentAdmin) {
      throw Exception('Current admin PIN is incorrect');
    }
    final clash = _db.select('SELECT id FROM cashiers WHERE pin = ? LIMIT 1', [n]);
    if (clash.isNotEmpty) {
      throw Exception('Another cashier is already using this PIN');
    }
    _db.execute(
      '''INSERT INTO settings(key, value) VALUES('admin_pin', ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
      [n],
    );
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'SECURITY',
      entityType: 'admin_pin',
      summary: 'Changed administrator PIN',
    );
  }

  List<Map<String, dynamic>> listCashiers() {
    final rows = _db.select('SELECT * FROM cashiers ORDER BY name COLLATE NOCASE ASC');
    return rows.map((r) {
      List<String> perms = ['pos', 'transactions'];
      try {
        final parsed = jsonDecode(r['permissions'] as String? ?? '[]');
        if (parsed is List && parsed.isNotEmpty) {
          perms = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return {
        'id': r['id'] as int,
        'name': r['name'] as String,
        'pin': r['pin'] as String,
        'permissions': r['permissions'] as String,
        'permissions_list': perms,
        'created_at': r['created_at'] as String,
      };
    }).toList();
  }

  int saveCashier(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final name = (data['name']?.toString() ?? '').trim();
    final pin = (data['pin']?.toString() ?? '').trim();
    if (name.isEmpty) throw Exception('Cashier name is required');
    if (pin.length < 4) throw Exception('PIN must be at least 4 digits');

    final adminPin = getSettings()['admin_pin'] ?? '0000';
    if (pin == adminPin) {
      throw Exception('Another cashier is already using this PIN');
    }

    final existing = id == null
        ? _db.select('SELECT id FROM cashiers WHERE pin = ?', [pin])
        : _db.select('SELECT id FROM cashiers WHERE pin = ? AND id != ?', [pin, id]);
    if (existing.isNotEmpty) {
      throw Exception('Another cashier is already using this PIN');
    }

    List<String> perms = ['pos', 'transactions'];
    if (data['permissions_list'] is List) {
      final list = (data['permissions_list'] as List).map((e) => e.toString()).toList();
      if (list.isNotEmpty) perms = list;
    } else if (data['permissions'] is String && (data['permissions'] as String).isNotEmpty) {
      try {
        final parsed = jsonDecode(data['permissions'] as String);
        if (parsed is List && parsed.isNotEmpty) {
          perms = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    final permsJson = jsonEncode(perms);

    if (id == null) {
      final now = formatDateTime(DateTime.now());
      _db.execute(
        'INSERT INTO cashiers(name, pin, permissions, created_at) VALUES(?, ?, ?, ?)',
        [name, pin, permsJson, now],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: actor,
        role: role,
        action: 'CREATE',
        entityType: 'cashier',
        entityId: newId.toString(),
        summary: 'Created cashier $name',
        details: {'name': name, 'permissions': perms},
      );
      return newId;
    } else {
      _db.execute(
        'UPDATE cashiers SET name = ?, pin = ?, permissions = ? WHERE id = ?',
        [name, pin, permsJson, id],
      );
      dbService.logAudit(
        actor: actor,
        role: role,
        action: 'UPDATE',
        entityType: 'cashier',
        entityId: id.toString(),
        summary: 'Updated cashier $name',
        details: {'name': name, 'permissions': perms},
      );
      return id;
    }
  }

  void deleteCashier(
    int id, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final rows = _db.select('SELECT name FROM cashiers WHERE id = ?', [id]);
    final name = rows.isNotEmpty ? (rows.first['name'] as String) : '#$id';
    _db.execute('DELETE FROM cashiers WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'DELETE',
      entityType: 'cashier',
      entityId: id.toString(),
      summary: 'Deleted cashier $name',
    );
  }

  // --- Shifts (SOD / EOD) ---

  Map<String, dynamic> _computeShiftLiveTotals(Map<String, dynamic> shiftRow) {
    final shiftId = shiftRow['id'] as int;
    final openedAt = shiftRow['opened_at'] as String;
    final openingCash = r2((shiftRow['opening_cash'] as num?) ?? 0);
    final disabled = getDisabledMenus();

    final salesAgg = _db.select(
      '''SELECT COALESCE(SUM(total), 0) AS total_sales, COUNT(*) AS cnt
         FROM sales
         WHERE status = 'completed'
           AND (shift_id = ? OR (shift_id IS NULL AND created_at >= ?))''',
      [shiftId, openedAt],
    ).first;
    final cashSales = r2((salesAgg['total_sales'] as num?) ?? 0);
    final ordersCount = (salesAgg['cnt'] as int?) ?? 0;

    double sumByShift(String table) {
      final r = _db.select(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM $table WHERE shift_id = ?',
        [shiftId],
      ).first;
      return r2((r['total'] as num?) ?? 0);
    }

    final rawExpenses = sumByShift('expenses');
    final rawSalaries = sumByShift('salaries');
    final rawCommissions = sumByShift('commissions');
    final rawLd = sumByShift('ld_commissions');

    final expenses = isModuleEnabled('expenses', disabled) ? rawExpenses : 0.0;
    final salaries = isModuleEnabled('salary', disabled) ? rawSalaries : 0.0;
    final commissions = isModuleEnabled('commission', disabled) ? rawCommissions : 0.0;
    final ldCommissions = isModuleEnabled('ld-commission', disabled) ? rawLd : 0.0;

    final totalOutflows = r2(expenses + salaries + commissions + ldCommissions);
    final expectedCash = r2(openingCash + cashSales - totalOutflows);
    final netOperating = r2(cashSales - totalOutflows);

    final soldRows = _db.select(
      '''SELECT si.name, si.variant_name,
                SUM(si.quantity) AS quantity,
                SUM(si.subtotal) AS amount
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         WHERE s.status = 'completed'
           AND (s.shift_id = ? OR (s.shift_id IS NULL AND s.created_at >= ?))
         GROUP BY si.name, si.variant_name
         ORDER BY amount DESC''',
      [shiftId, openedAt],
    );

    final soldItems = soldRows.map((r) => {
          'name': r['name'] as String,
          'variant_name': r['variant_name'] as String? ?? '',
          'quantity': (r['quantity'] as num?)?.toInt() ?? 0,
          'amount': r2((r['amount'] as num?) ?? 0),
        }).toList();

    return {
      ...shiftRow,
      'opening_cash': openingCash,
      'cash_sales': cashSales,
      'gross_sales': cashSales,
      'orders_count': ordersCount,
      'expenses': expenses,
      'salaries': salaries,
      'commissions': commissions,
      'ld_commissions': ldCommissions,
      'total_outflows': totalOutflows,
      'expected_cash': expectedCash,
      'net_operating': netOperating,
      'sold_items': soldItems,
    };
  }

  Map<String, dynamic> getShiftStatus() {
    final open = _getOpenShiftRow();
    if (open != null) {
      return {
        'is_open': true,
        'shift': _computeShiftLiveTotals(open),
      };
    }
    final lastRows = _db.select(
      'SELECT * FROM shifts ORDER BY id DESC LIMIT 1',
    );
    return {
      'is_open': false,
      'shift': null,
      'last_shift': lastRows.isNotEmpty
          ? Map<String, dynamic>.from(lastRows.first)
          : null,
    };
  }

  Map<String, dynamic> startDay({
    String? businessDate,
    required String openedBy,
    double openingCash = 0,
    String notes = '',
  }) {
    final existing = _getOpenShiftRow();
    if (existing != null) {
      throw Exception(
        'A business day shift is already open. Please end the current day first.',
      );
    }
    final bDate = (businessDate == null || businessDate.trim().isEmpty)
        ? todayDateString()
        : businessDate.trim();
    final who = openedBy.trim().isEmpty ? 'Administrator' : openedBy.trim();
    final now = formatDateTime(DateTime.now());
    final openAmt = r2(openingCash);

    _db.execute(
      '''INSERT INTO shifts(business_date, status, opened_by, opened_at, opening_cash, notes)
         VALUES(?, 'open', ?, ?, ?, ?)''',
      [bDate, who, now, openAmt, notes.trim()],
    );
    final id = _db.lastInsertRowId;
    dbService.logAudit(
      actor: who,
      role: 'admin',
      action: 'SHIFT_OPEN',
      entityType: 'shift',
      entityId: id.toString(),
      summary: 'Opened shift #$id for $bDate (Opening float: ${formatPeso(openAmt)})',
      details: {'business_date': bDate, 'opening_cash': openAmt},
    );
    return getShiftStatus();
  }

  Map<String, dynamic> endDay({
    required double closingCash,
    required String closedBy,
    String notes = '',
  }) {
    final open = _getOpenShiftRow();
    if (open == null) {
      throw Exception('No open shift to close');
    }
    final live = _computeShiftLiveTotals(open);
    final shiftId = open['id'] as int;
    final bDate = open['business_date'] as String;
    final who = closedBy.trim().isEmpty ? 'Administrator' : closedBy.trim();
    final closedAt = formatDateTime(DateTime.now());
    final closeAmt = r2(closingCash);
    final expectedAmt = r2(live['expected_cash'] as num);
    final variance = r2(closeAmt - expectedAmt);
    final finalNotes = notes.trim().isNotEmpty
        ? notes.trim()
        : (open['notes'] as String? ?? '');

    _db.execute(
      '''UPDATE shifts
         SET status = 'closed',
             closed_by = ?,
             closed_at = ?,
             closing_cash = ?,
             expected_cash = ?,
             cash_sales = ?,
             expenses = ?,
             salaries = ?,
             commissions = ?,
             ld_commissions = ?,
             notes = ?
         WHERE id = ?''',
      [
        who,
        closedAt,
        closeAmt,
        expectedAmt,
        live['cash_sales'],
        live['expenses'],
        live['salaries'],
        live['commissions'],
        live['ld_commissions'],
        finalNotes,
        shiftId,
      ],
    );

    dbService.logAudit(
      actor: who,
      role: 'admin',
      action: 'SHIFT_CLOSE',
      entityType: 'shift',
      entityId: shiftId.toString(),
      summary:
          'Closed shift #$shiftId ($bDate) — Expected: ${formatPeso(expectedAmt)}, Counted: ${formatPeso(closeAmt)}, Variance: ${formatPeso(variance)}',
      details: {
        'shift_id': shiftId,
        'business_date': bDate,
        'expected_cash': expectedAmt,
        'closing_cash': closeAmt,
        'variance': variance,
      },
    );

    final backupRes = branchManager.performEodSnapshot('EOD_$bDate');
    return {
      ...live,
      'status': 'closed',
      'closed_by': who,
      'closed_at': closedAt,
      'closing_cash': closeAmt,
      'expected_cash': expectedAmt,
      'variance': variance,
      'notes': finalNotes,
      'eod_backup': backupRes,
    };
  }

  List<Map<String, dynamic>> listShifts({int limit = 30}) {
    final rows = _db.select(
      'SELECT * FROM shifts ORDER BY id DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  void updateShiftNotes(
    int id,
    String notes, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    _db.execute('UPDATE shifts SET notes = ? WHERE id = ?', [notes.trim(), id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'UPDATE',
      entityType: 'shift',
      entityId: id.toString(),
      summary: 'Updated notes for shift #$id',
      details: {'notes': notes.trim()},
    );
  }

  Map<String, dynamic> getZReadingData({
    int? shiftId,
    double? closingCash,
    String? closingNotes,
    String? closedBy,
  }) {
    Map<String, dynamic>? row;
    if (shiftId != null) {
      final rows = _db.select('SELECT * FROM shifts WHERE id = ?', [shiftId]);
      if (rows.isNotEmpty) row = Map<String, dynamic>.from(rows.first);
    }
    row ??= _getOpenShiftRow();
    if (row == null) {
      final rows = _db.select('SELECT * FROM shifts ORDER BY id DESC LIMIT 1');
      if (rows.isNotEmpty) row = Map<String, dynamic>.from(rows.first);
    }
    if (row == null) {
      throw Exception('No shift found for Z-Reading');
    }
    final live = _computeShiftLiveTotals(row);
    final actualClosing = closingCash ??
        ((row['closing_cash'] as num?) != null && (row['closing_cash'] as num) > 0
            ? r2(row['closing_cash'] as num)
            : (live['expected_cash'] as double));
    final variance = r2(actualClosing - (live['expected_cash'] as double));
    return {
      ...live,
      'closing_cash': actualClosing,
      'variance': variance,
      'closed_by': (closedBy != null && closedBy.trim().isNotEmpty)
          ? closedBy.trim()
          : (row['closed_by'] as String? ?? 'Administrator'),
      'notes': (closingNotes != null && closingNotes.trim().isNotEmpty)
          ? closingNotes.trim()
          : (row['notes'] as String? ?? ''),
    };
  }

  // --- Products & Inventory ---

  List<Map<String, dynamic>> listProducts() {
    final prodRows = _db.select(
      'SELECT * FROM products WHERE active = 1 ORDER BY name COLLATE NOCASE ASC',
    );
    final varRows = _db.select(
      'SELECT * FROM variants ORDER BY qty ASC, id ASC',
    );
    final variantsByProduct = <int, List<Map<String, dynamic>>>{};
    for (final v in varRows) {
      final pid = v['product_id'] as int;
      variantsByProduct.putIfAbsent(pid, () => []).add({
        'id': v['id'] as int,
        'product_id': pid,
        'name': v['name'] as String,
        'qty': (v['qty'] as num).toInt(),
        'price': r2(v['price'] as num),
      });
    }

    return prodRows.map((p) {
      final pid = p['id'] as int;
      return {
        'id': pid,
        'name': p['name'] as String,
        'barcode': p['barcode'] as String? ?? '',
        'category': p['category'] as String? ?? '',
        'price': r2(p['price'] as num),
        'cost': r2(p['cost'] as num),
        'stock': (p['stock'] as num).toInt(),
        'low_stock': (p['low_stock'] as num?)?.toInt() ?? 5,
        'image': p['image'] as String? ?? '',
        'active': (p['active'] as num?)?.toInt() ?? 1,
        'created_at': p['created_at'] as String,
        'variants': variantsByProduct[pid] ?? <Map<String, dynamic>>[],
      };
    }).toList();
  }

  int saveProduct(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final name = (data['name']?.toString() ?? '').trim();
    if (name.isEmpty) {
      throw Exception('Product name is required');
    }
    final barcode = (data['barcode']?.toString() ?? '').trim();
    final category = (data['category']?.toString() ?? '').trim();
    final price = r2(num.tryParse(data['price']?.toString() ?? '0') ?? 0);
    final cost = r2(num.tryParse(data['cost']?.toString() ?? '0') ?? 0);
    if (price < 0 || cost < 0) {
      throw Exception('Price and cost cannot be negative');
    }
    final lowStock = int.tryParse(data['low_stock']?.toString() ?? '5') ?? 5;
    final image = data['image']?.toString() ?? '';
    final hasStockField = data.containsKey('stock') && data['stock'] != null;
    final stockVal = int.tryParse(data['stock']?.toString() ?? '0') ?? 0;

    _db.execute('BEGIN TRANSACTION');
    try {
      late int productId;
      if (id == null) {
        final now = formatDateTime(DateTime.now());
        _db.execute(
          '''INSERT INTO products(name, barcode, category, price, cost, stock, low_stock, image, active, created_at)
             VALUES(?, ?, ?, ?, ?, ?, ?, ?, 1, ?)''',
          [name, barcode, category, price, cost, stockVal, lowStock, image, now],
        );
        productId = _db.lastInsertRowId;
      } else {
        productId = id;
        if (hasStockField) {
          _db.execute(
            '''UPDATE products
               SET name = ?, barcode = ?, category = ?, price = ?, cost = ?, stock = ?, low_stock = ?, image = ?
               WHERE id = ?''',
            [name, barcode, category, price, cost, stockVal, lowStock, image, id],
          );
        } else {
          _db.execute(
            '''UPDATE products
               SET name = ?, barcode = ?, category = ?, price = ?, cost = ?, low_stock = ?, image = ?
               WHERE id = ?''',
            [name, barcode, category, price, cost, lowStock, image, id],
          );
        }
        _db.execute('DELETE FROM variants WHERE product_id = ?', [id]);
      }

      if (data['variants'] is List) {
        for (final rawVar in (data['variants'] as List)) {
          if (rawVar is! Map) continue;
          final vName = (rawVar['name']?.toString() ?? '').trim();
          final vQty = int.tryParse(rawVar['qty']?.toString() ?? '0') ?? 0;
          final vPrice = r2(num.tryParse(rawVar['price']?.toString() ?? '0') ?? 0);
          if (vName.isNotEmpty && vQty > 0) {
            _db.execute(
              'INSERT INTO variants(product_id, name, qty, price) VALUES(?, ?, ?, ?)',
              [productId, vName, vQty, vPrice],
            );
          }
        }
      }

      dbService.logAudit(
        actor: (data['actor']?.toString() ?? actor),
        role: (data['actor_role']?.toString() ?? role),
        action: id == null ? 'CREATE' : 'UPDATE',
        entityType: 'product',
        entityId: productId.toString(),
        summary: '${id == null ? "Created" : "Updated"} product $name',
        details: {'id': productId, 'name': name, 'price': price, 'cost': cost},
      );

      _db.execute('COMMIT');
      return productId;
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteProduct(
    int id, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final rows = _db.select('SELECT name FROM products WHERE id = ?', [id]);
    final name = rows.isNotEmpty ? (rows.first['name'] as String) : '#$id';
    _db.execute('UPDATE products SET active = 0 WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'ARCHIVE',
      entityType: 'product',
      entityId: id.toString(),
      summary: 'Archived product $name',
    );
  }

  void restock({
    required int productId,
    required int qty,
    double unitCost = 0,
    String note = '',
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    if (qty <= 0) {
      throw Exception('Restock quantity must be greater than 0');
    }
    final prodRows = _db.select('SELECT * FROM products WHERE id = ?', [productId]);
    if (prodRows.isEmpty) {
      throw Exception('Product not found');
    }
    final prod = prodRows.first;
    final prodName = prod['name'] as String;
    final cleanCost = r2(unitCost);
    final shiftId = activeShiftId();
    final ts = currentBusinessNow();

    _db.execute('BEGIN TRANSACTION');
    try {
      if (cleanCost > 0) {
        _db.execute(
          'UPDATE products SET stock = stock + ?, cost = ? WHERE id = ?',
          [qty, cleanCost, productId],
        );
      } else {
        _db.execute(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [qty, productId],
        );
      }
      _db.execute(
        '''INSERT INTO restocks(product_id, product_name, qty, unit_cost, note, created_at, shift_id)
           VALUES(?, ?, ?, ?, ?, ?, ?)''',
        [productId, prodName, qty, cleanCost, note.trim(), ts, shiftId],
      );
      final restockId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: actor,
        role: role,
        action: 'RESTOCK',
        entityType: 'product',
        entityId: productId.toString(),
        summary: 'Restocked +$qty $prodName',
        details: {
          'restock_id': restockId,
          'product_id': productId,
          'qty': qty,
          'unit_cost': cleanCost,
        },
      );
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, dynamic>> listRestocks({int limit = 300}) {
    final rows = _db.select(
      '''SELECT r.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = r.shift_id), date(r.created_at)) AS business_date
         FROM restocks r
         ORDER BY r.id DESC
         LIMIT ?''',
      [limit],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static String generateBarcode() {
    final ms = DateTime.now().millisecondsSinceEpoch.toString();
    final last9 = ms.length >= 9 ? ms.substring(ms.length - 9) : ms.padLeft(9, '0');
    final rand2 = (10 + Random().nextInt(90)).toString();
    return '2$last9$rand2';
  }

  // --- Sales & Voids ---

  Map<String, dynamic> createSale({
    required List<Map<String, dynamic>> items,
    required double paid,
    String actor = 'Cashier',
    String role = 'cashier',
  }) {
    if (items.isEmpty) {
      throw Exception('Cart is empty');
    }

    final openShift = _getOpenShiftRow();
    final shiftId = openShift?['id'] as int?;
    final bizDate = openShift != null
        ? (openShift['business_date'] as String)
        : todayDateString();

    _db.execute('BEGIN TRANSACTION');
    try {
      final countRow = _db.select(
        'SELECT COUNT(*) AS cnt FROM sales WHERE date(created_at) = ?',
        [bizDate],
      ).first;
      final nextSeq = ((countRow['cnt'] as int?) ?? 0) + 1;
      final dateNoDashes = bizDate.replaceAll('-', '');
      final receiptNo = 'JP-$dateNoDashes-${nextSeq.toString().padLeft(4, '0')}';
      final createdAt = businessNow(bizDate);

      _db.execute(
        '''INSERT INTO sales(receipt_no, total, paid, change_amt, status, created_at, shift_id)
           VALUES(?, 0, 0, 0, 'completed', ?, ?)''',
        [receiptNo, createdAt, shiftId],
      );
      final saleId = _db.lastInsertRowId;

      double runningTotal = 0.0;
      final insertedItems = <Map<String, dynamic>>[];

      for (final rawItem in items) {
        final productId = (rawItem['product_id'] as num?)?.toInt();
        final variantId = (rawItem['variant_id'] as num?)?.toInt();
        final quantity = (rawItem['quantity'] as num?)?.toInt() ?? 0;

        if (productId == null || quantity <= 0) {
          throw Exception('Invalid quantity');
        }

        final prodRows = _db.select(
          'SELECT * FROM products WHERE id = ? LIMIT 1',
          [productId],
        );
        if (prodRows.isEmpty) {
          throw Exception('Product #$productId not found');
        }
        final prod = prodRows.first;
        final prodName = prod['name'] as String;
        final baseCost = r2(prod['cost'] as num);

        String variantName = '';
        int unitsPer = 1;
        double unitPrice = r2(prod['price'] as num);

        if (variantId != null && variantId > 0) {
          final varRows = _db.select(
            'SELECT * FROM variants WHERE id = ? AND product_id = ? LIMIT 1',
            [variantId, productId],
          );
          if (varRows.isEmpty) {
            throw Exception('Variant not found for $prodName');
          }
          final v = varRows.first;
          variantName = v['name'] as String;
          unitsPer = (v['qty'] as num).toInt();
          unitPrice = r2(v['price'] as num);
        }

        final totalUnitsToDeduct = unitsPer * quantity;
        final subtotal = r2(unitPrice * quantity);
        final costTotal = r2(baseCost * totalUnitsToDeduct);
        runningTotal = r2(runningTotal + subtotal);

        _db.execute(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [totalUnitsToDeduct, productId],
        );

        _db.execute(
          '''INSERT INTO sale_items(sale_id, product_id, variant_id, name, variant_name, units_per, unit_price, quantity, subtotal, cost_total)
             VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            saleId,
            productId,
            variantId,
            prodName,
            variantName,
            unitsPer,
            unitPrice,
            quantity,
            subtotal,
            costTotal,
          ],
        );
        final itemId = _db.lastInsertRowId;
        insertedItems.add({
          'id': itemId,
          'sale_id': saleId,
          'product_id': productId,
          'variant_id': variantId,
          'name': prodName,
          'variant_name': variantName,
          'units_per': unitsPer,
          'unit_price': unitPrice,
          'quantity': quantity,
          'subtotal': subtotal,
          'cost_total': costTotal,
        });
      }

      final total = r2(runningTotal);
      final paidClean = r2(paid);
      if (paidClean + 1e-9 < total) {
        throw Exception('Payment is less than the total');
      }
      final changeAmt = r2(paidClean - total);

      _db.execute(
        'UPDATE sales SET total = ?, paid = ?, change_amt = ? WHERE id = ?',
        [total, paidClean, changeAmt, saleId],
      );

      dbService.logAudit(
        actor: actor,
        role: role,
        action: 'SALE',
        entityType: 'sale',
        entityId: receiptNo,
        summary: 'Completed sale $receiptNo (${formatPeso(total)})',
        details: {
          'sale_id': saleId,
          'receipt_no': receiptNo,
          'total': total,
          'paid': paidClean,
          'change_amt': changeAmt,
        },
      );

      _db.execute('COMMIT');
      return {
        'id': saleId,
        'receipt_no': receiptNo,
        'total': total,
        'paid': paidClean,
        'change_amt': changeAmt,
        'status': 'completed',
        'created_at': createdAt,
        'business_date': bizDate,
        'shift_id': shiftId,
        'items': insertedItems,
      };
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, dynamic>> listSales({
    required String from,
    required String to,
    String status = '',
    int limit = 1000,
  }) {
    final params = <Object?>[from, to];
    String statusFilter = '';
    if (status.trim().isNotEmpty) {
      statusFilter = ' AND s.status = ?';
      params.add(status.trim());
    }
    params.add(limit);

    final salesRows = _db.select(
      '''SELECT s.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) AS business_date
         FROM sales s
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         $statusFilter
         ORDER BY s.id DESC
         LIMIT ?''',
      params,
    );

    if (salesRows.isEmpty) return [];
    final saleIds = salesRows.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final itemRows = _db.select(
      'SELECT * FROM sale_items WHERE sale_id IN ($placeholders) ORDER BY id ASC',
      saleIds,
    );
    final itemsBySale = <int, List<Map<String, dynamic>>>{};
    for (final item in itemRows) {
      final sid = item['sale_id'] as int;
      itemsBySale.putIfAbsent(sid, () => []).add(Map<String, dynamic>.from(item));
    }

    return salesRows.map((s) {
      final sid = s['id'] as int;
      return {
        ...Map<String, dynamic>.from(s),
        'total': r2(s['total'] as num),
        'paid': r2(s['paid'] as num),
        'change_amt': r2(s['change_amt'] as num),
        'items': itemsBySale[sid] ?? <Map<String, dynamic>>[],
      };
    }).toList();
  }

  Map<String, dynamic> getSaleById(int saleId) {
    final rows = _db.select('SELECT * FROM sales WHERE id = ? LIMIT 1', [saleId]);
    if (rows.isEmpty) {
      throw Exception('Sale #$saleId not found');
    }
    final s = Map<String, dynamic>.from(rows.first);
    final items = _db
        .select('SELECT * FROM sale_items WHERE sale_id = ? ORDER BY id ASC', [saleId])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    return {
      ...s,
      'items': items,
    };
  }

  void voidSale({
    required int id,
    required String reason,
    required String voidedBy,
  }) {
    final saleRows = _db.select('SELECT * FROM sales WHERE id = ? LIMIT 1', [id]);
    if (saleRows.isEmpty) {
      throw Exception('Sale not found');
    }
    final sale = saleRows.first;
    if (sale['status'] != 'completed') {
      throw Exception('This sale is already voided');
    }

    final itemRows = _db.select('SELECT * FROM sale_items WHERE sale_id = ?', [id]);
    final itemsList = itemRows.map((r) => Map<String, dynamic>.from(r)).toList();

    final ts = currentBusinessNow();
    final who = voidedBy.trim().isEmpty ? 'Administrator' : voidedBy.trim();
    final cleanReason = reason.trim();
    final openShiftId = activeShiftId() ?? (sale['shift_id'] as int?);

    _db.execute('BEGIN TRANSACTION');
    try {
      for (final item in itemsList) {
        final pid = item['product_id'] as int;
        final unitsPer = (item['units_per'] as num?)?.toInt() ?? 1;
        final qty = (item['quantity'] as num).toInt();
        _db.execute(
          'UPDATE products SET stock = stock + ? WHERE id = ?',
          [unitsPer * qty, pid],
        );
      }

      _db.execute(
        '''UPDATE sales
           SET status = 'voided', voided_at = ?, void_reason = ?, voided_by = ?
           WHERE id = ?''',
        [ts, cleanReason, who, id],
      );

      _db.execute(
        '''INSERT INTO voided_sales(sale_id, receipt_no, total, reason, items_json, sold_at, voided_at, voided_by, shift_id)
           VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          id,
          sale['receipt_no'],
          r2(sale['total'] as num),
          cleanReason,
          jsonEncode(itemsList),
          sale['created_at'],
          ts,
          who,
          openShiftId,
        ],
      );

      dbService.logAudit(
        actor: who,
        role: 'admin',
        action: 'VOID',
        entityType: 'sale',
        entityId: sale['receipt_no'] as String,
        summary:
            'Voided sale ${sale['receipt_no']} (${formatPeso(sale['total'] as num)}) — Reason: ${cleanReason.isEmpty ? "None" : cleanReason}',
        details: {
          'sale_id': id,
          'receipt_no': sale['receipt_no'],
          'total': sale['total'],
          'reason': cleanReason,
          'voided_by': who,
        },
      );

      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, dynamic>> listVoided({
    required String from,
    required String to,
  }) {
    final rows = _db.select(
      '''SELECT v.*,
                COALESCE(
                  (SELECT business_date FROM shifts WHERE id = v.shift_id),
                  (SELECT sh.business_date FROM sales s JOIN shifts sh ON sh.id = s.shift_id WHERE s.id = v.sale_id),
                  date(v.voided_at)
                ) AS business_date
         FROM voided_sales v
         WHERE COALESCE(
                 (SELECT business_date FROM shifts WHERE id = v.shift_id),
                 (SELECT sh.business_date FROM sales s JOIN shifts sh ON sh.id = s.shift_id WHERE s.id = v.sale_id),
                 date(v.voided_at)
               ) BETWEEN ? AND ?
         ORDER BY v.id DESC''',
      [from, to],
    );

    return rows.map((r) {
      List<dynamic> parsedItems = [];
      try {
        parsedItems = jsonDecode(r['items_json'] as String? ?? '[]') as List;
      } catch (_) {}
      return {
        ...Map<String, dynamic>.from(r),
        'total': r2(r['total'] as num),
        'items': parsedItems,
      };
    }).toList();
  }

  // --- Finance (Expenses, Salaries, Commissions, LD Commissions) ---

  List<Map<String, dynamic>> listExpenses({required String from, required String to}) {
    final rows = _db.select(
      '''SELECT e.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = e.shift_id), e.date) AS business_date
         FROM expenses e
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = e.shift_id), e.date) BETWEEN ? AND ?
         ORDER BY business_date DESC, e.id DESC''',
      [from, to],
    );
    return rows.map((r) => {...Map<String, dynamic>.from(r), 'amount': r2(r['amount'] as num)}).toList();
  }

  int saveExpense(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final rawCat = (data['category']?.toString() ?? '').trim();
    final category = rawCat.isEmpty ? 'General' : rawCat;
    final description = (data['description']?.toString() ?? '').trim();
    final amount = r2(num.tryParse(data['amount']?.toString() ?? '0') ?? 0);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final rawDate = (data['date']?.toString() ?? '').trim();
    final date = rawDate.isEmpty ? activeBusinessDate() : rawDate;

    if (id == null) {
      final shiftId = activeShiftId();
      _db.execute(
        'INSERT INTO expenses(category, description, amount, date, shift_id) VALUES(?, ?, ?, ?, ?)',
        [category, description, amount, date, shiftId],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'CREATE',
        entityType: 'expense',
        entityId: newId.toString(),
        summary: 'Added expense $category (${formatPeso(amount)})',
        details: {'category': category, 'description': description, 'amount': amount, 'date': date},
      );
      return newId;
    } else {
      _db.execute(
        'UPDATE expenses SET category = ?, description = ?, amount = ?, date = ? WHERE id = ?',
        [category, description, amount, date, id],
      );
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'UPDATE',
        entityType: 'expense',
        entityId: id.toString(),
        summary: 'Updated expense $category (${formatPeso(amount)})',
        details: {'category': category, 'description': description, 'amount': amount, 'date': date},
      );
      return id;
    }
  }

  void deleteExpense(int id, {String actor = 'Administrator', String role = 'admin'}) {
    _db.execute('DELETE FROM expenses WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'DELETE',
      entityType: 'expense',
      entityId: id.toString(),
      summary: 'Deleted expense #$id',
    );
  }

  List<Map<String, dynamic>> listSalaries({required String from, required String to}) {
    final rows = _db.select(
      '''SELECT s.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), s.date) AS business_date
         FROM salaries s
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), s.date) BETWEEN ? AND ?
         ORDER BY business_date DESC, s.id DESC''',
      [from, to],
    );
    return rows.map((r) => {...Map<String, dynamic>.from(r), 'amount': r2(r['amount'] as num)}).toList();
  }

  int saveSalary(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final employee = (data['employee']?.toString() ?? '').trim();
    if (employee.isEmpty) throw Exception('Employee name is required');
    final amount = r2(num.tryParse(data['amount']?.toString() ?? '0') ?? 0);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final period = (data['period']?.toString() ?? '').trim();
    final note = (data['note']?.toString() ?? '').trim();
    final rawDate = (data['date']?.toString() ?? '').trim();
    final date = rawDate.isEmpty ? activeBusinessDate() : rawDate;

    if (id == null) {
      final shiftId = activeShiftId();
      _db.execute(
        'INSERT INTO salaries(employee, amount, period, date, note, shift_id) VALUES(?, ?, ?, ?, ?, ?)',
        [employee, amount, period, date, note, shiftId],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'CREATE',
        entityType: 'salary',
        entityId: newId.toString(),
        summary: 'Paid salary to $employee (${formatPeso(amount)})',
        details: {'employee': employee, 'amount': amount, 'period': period, 'date': date},
      );
      return newId;
    } else {
      _db.execute(
        'UPDATE salaries SET employee = ?, amount = ?, period = ?, date = ?, note = ? WHERE id = ?',
        [employee, amount, period, date, note, id],
      );
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'UPDATE',
        entityType: 'salary',
        entityId: id.toString(),
        summary: 'Updated salary for $employee (${formatPeso(amount)})',
        details: {'employee': employee, 'amount': amount, 'period': period, 'date': date},
      );
      return id;
    }
  }

  void deleteSalary(int id, {String actor = 'Administrator', String role = 'admin'}) {
    _db.execute('DELETE FROM salaries WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'DELETE',
      entityType: 'salary',
      entityId: id.toString(),
      summary: 'Deleted salary record #$id',
    );
  }

  List<String> listCommissionTypes() {
    final rows = _db.select('SELECT name FROM commission_types ORDER BY id ASC');
    return rows.map((r) => r['name'] as String).toList();
  }

  List<String> addCommissionType(String name) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      _db.execute('INSERT OR IGNORE INTO commission_types(name) VALUES(?)', [trimmed]);
    }
    return listCommissionTypes();
  }

  List<Map<String, dynamic>> listCommissions({required String from, required String to}) {
    final rows = _db.select(
      '''SELECT c.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = c.shift_id), c.date) AS business_date
         FROM commissions c
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = c.shift_id), c.date) BETWEEN ? AND ?
         ORDER BY business_date DESC, c.id DESC''',
      [from, to],
    );
    return rows.map((r) => {...Map<String, dynamic>.from(r), 'amount': r2(r['amount'] as num)}).toList();
  }

  int saveCommission(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final employeeId = (data['employee_id'] as num?)?.toInt();
    final employeeName = (data['employee_name']?.toString() ?? '').trim();
    if (employeeName.isEmpty) throw Exception('Employee name is required');
    final type = (data['type']?.toString() ?? '').trim();
    if (type.isEmpty) throw Exception('Commission type is required');
    final amount = r2(num.tryParse(data['amount']?.toString() ?? '0') ?? 0);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final rawDate = (data['date']?.toString() ?? '').trim();
    final date = rawDate.isEmpty ? activeBusinessDate() : rawDate;

    addCommissionType(type);

    if (id == null) {
      final shiftId = activeShiftId();
      _db.execute(
        'INSERT INTO commissions(date, employee_id, employee_name, type, amount, shift_id) VALUES(?, ?, ?, ?, ?, ?)',
        [date, employeeId, employeeName, type, amount, shiftId],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'CREATE',
        entityType: 'commission',
        entityId: newId.toString(),
        summary: 'Paid $type commission to $employeeName (${formatPeso(amount)})',
        details: {'employee_name': employeeName, 'type': type, 'amount': amount, 'date': date},
      );
      return newId;
    } else {
      _db.execute(
        'UPDATE commissions SET date = ?, employee_id = ?, employee_name = ?, type = ?, amount = ? WHERE id = ?',
        [date, employeeId, employeeName, type, amount, id],
      );
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'UPDATE',
        entityType: 'commission',
        entityId: id.toString(),
        summary: 'Updated commission for $employeeName (${formatPeso(amount)})',
        details: {'employee_name': employeeName, 'type': type, 'amount': amount, 'date': date},
      );
      return id;
    }
  }

  void deleteCommission(int id, {String actor = 'Administrator', String role = 'admin'}) {
    _db.execute('DELETE FROM commissions WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'DELETE',
      entityType: 'commission',
      entityId: id.toString(),
      summary: 'Deleted commission #$id',
    );
  }

  List<Map<String, dynamic>> listLdCommissions({required String from, required String to}) {
    final rows = _db.select(
      '''SELECT l.*,
                COALESCE((SELECT business_date FROM shifts WHERE id = l.shift_id), l.date) AS business_date
         FROM ld_commissions l
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = l.shift_id), l.date) BETWEEN ? AND ?
         ORDER BY business_date DESC, l.id DESC''',
      [from, to],
    );
    return rows.map((r) => {...Map<String, dynamic>.from(r), 'amount': r2(r['amount'] as num)}).toList();
  }

  int saveLdCommission(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final employeeId = (data['employee_id'] as num?)?.toInt();
    final employeeName = (data['employee_name']?.toString() ?? '').trim();
    if (employeeName.isEmpty) throw Exception('Employee name is required');
    final quantity = max(1, int.tryParse(data['quantity']?.toString() ?? '1') ?? 1);
    final amount = r2(num.tryParse(data['amount']?.toString() ?? '0') ?? 0);
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    final rawDate = (data['date']?.toString() ?? '').trim();
    final date = rawDate.isEmpty ? activeBusinessDate() : rawDate;

    if (id == null) {
      final shiftId = activeShiftId();
      _db.execute(
        'INSERT INTO ld_commissions(date, employee_id, employee_name, quantity, amount, shift_id) VALUES(?, ?, ?, ?, ?, ?)',
        [date, employeeId, employeeName, quantity, amount, shiftId],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'CREATE',
        entityType: 'ld_commission',
        entityId: newId.toString(),
        summary: 'Paid LD commission to $employeeName ($quantity × ${formatPeso(amount)})',
        details: {'employee_name': employeeName, 'quantity': quantity, 'amount': amount, 'date': date},
      );
      return newId;
    } else {
      _db.execute(
        'UPDATE ld_commissions SET date = ?, employee_id = ?, employee_name = ?, quantity = ?, amount = ? WHERE id = ?',
        [date, employeeId, employeeName, quantity, amount, id],
      );
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'UPDATE',
        entityType: 'ld_commission',
        entityId: id.toString(),
        summary: 'Updated LD commission for $employeeName (${formatPeso(amount)})',
        details: {'employee_name': employeeName, 'quantity': quantity, 'amount': amount, 'date': date},
      );
      return id;
    }
  }

  void deleteLdCommission(int id, {String actor = 'Administrator', String role = 'admin'}) {
    _db.execute('DELETE FROM ld_commissions WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'DELETE',
      entityType: 'ld_commission',
      entityId: id.toString(),
      summary: 'Deleted LD commission #$id',
    );
  }

  // --- Employees ---

  List<Map<String, dynamic>> listEmployees() {
    final rows = _db.select(
      'SELECT * FROM employees WHERE active = 1 ORDER BY name COLLATE NOCASE ASC',
    );
    return rows
        .map((r) => {
              ...Map<String, dynamic>.from(r),
              'commission': r2(r['commission'] as num),
              'ld_commission': r2(r['ld_commission'] as num),
              'salary': r2(r['salary'] as num),
            })
        .toList();
  }

  int saveEmployee(
    Map<String, dynamic> data, {
    String actor = 'Administrator',
    String role = 'admin',
  }) {
    final id = data['id'] as int?;
    final name = (data['name']?.toString() ?? '').trim();
    if (name.isEmpty) throw Exception('Employee name is required');
    final position = (data['position']?.toString() ?? '').trim();
    final commission = r2(num.tryParse(data['commission']?.toString() ?? '0') ?? 0);
    final ldCommission = r2(num.tryParse(data['ld_commission']?.toString() ?? '0') ?? 0);
    final salary = r2(num.tryParse(data['salary']?.toString() ?? '0') ?? 0);

    if (id == null) {
      final now = formatDateTime(DateTime.now());
      _db.execute(
        '''INSERT INTO employees(name, position, commission, ld_commission, salary, active, created_at)
           VALUES(?, ?, ?, ?, ?, 1, ?)''',
        [name, position, commission, ldCommission, salary, now],
      );
      final newId = _db.lastInsertRowId;
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'CREATE',
        entityType: 'employee',
        entityId: newId.toString(),
        summary: 'Added employee $name ($position)',
        details: {'name': name, 'position': position},
      );
      return newId;
    } else {
      _db.execute(
        '''UPDATE employees
           SET name = ?, position = ?, commission = ?, ld_commission = ?, salary = ?
           WHERE id = ?''',
        [name, position, commission, ldCommission, salary, id],
      );
      dbService.logAudit(
        actor: data['actor']?.toString() ?? actor,
        role: data['actor_role']?.toString() ?? role,
        action: 'UPDATE',
        entityType: 'employee',
        entityId: id.toString(),
        summary: 'Updated employee $name ($position)',
        details: {'name': name, 'position': position},
      );
      return id;
    }
  }

  void deleteEmployee(int id, {String actor = 'Administrator', String role = 'admin'}) {
    final rows = _db.select('SELECT name FROM employees WHERE id = ?', [id]);
    final name = rows.isNotEmpty ? (rows.first['name'] as String) : '#$id';
    _db.execute('UPDATE employees SET active = 0 WHERE id = ?', [id]);
    dbService.logAudit(
      actor: actor,
      role: role,
      action: 'ARCHIVE',
      entityType: 'employee',
      entityId: id.toString(),
      summary: 'Archived employee $name',
    );
  }

  // --- Dashboards (Store Overview & Admin Executive) ---

  Map<String, dynamic> _computeCoreMetrics(
    String from,
    String to,
    Set<String> disabled,
  ) {
    final salesRow = _db.select(
      '''SELECT COALESCE(SUM(s.total), 0) AS revenue, COUNT(*) AS orders
         FROM sales s
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?''',
      [from, to],
    ).first;

    final cogsRow = _db.select(
      '''SELECT COALESCE(SUM(si.cost_total), 0) AS cogs
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?''',
      [from, to],
    ).first;

    final voidRow = _db.select(
      '''SELECT COALESCE(SUM(s.total), 0) AS voided_total, COUNT(*) AS voided_count
         FROM sales s
         WHERE s.status = 'voided'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?''',
      [from, to],
    ).first;

    double sumModule(String table) {
      final r = _db.select(
        '''SELECT COALESCE(SUM(t.amount), 0) AS total
           FROM $table t
           WHERE COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), t.date) BETWEEN ? AND ?''',
        [from, to],
      ).first;
      return r2((r['total'] as num?) ?? 0);
    }

    int countModule(String table) {
      final r = _db.select(
        '''SELECT COUNT(*) AS cnt
           FROM $table t
           WHERE COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), t.date) BETWEEN ? AND ?''',
        [from, to],
      ).first;
      return (r['cnt'] as int?) ?? 0;
    }

    final revenue = r2((salesRow['revenue'] as num?) ?? 0);
    final orders = (salesRow['orders'] as int?) ?? 0;
    final cogs = r2((cogsRow['cogs'] as num?) ?? 0);
    final grossProfit = r2(revenue - cogs);

    final expEnabled = isModuleEnabled('expenses', disabled);
    final salEnabled = isModuleEnabled('salary', disabled);
    final comEnabled = isModuleEnabled('commission', disabled);
    final ldEnabled = isModuleEnabled('ld-commission', disabled);

    final expenses = expEnabled ? sumModule('expenses') : 0.0;
    final salaries = salEnabled ? sumModule('salaries') : 0.0;
    final commissions = comEnabled ? sumModule('commissions') : 0.0;
    final ldCommissions = ldEnabled ? sumModule('ld_commissions') : 0.0;

    final financeSummary = {
      'expenses': {'enabled': expEnabled, 'total': expenses, 'count': expEnabled ? countModule('expenses') : 0},
      'salaries': {'enabled': salEnabled, 'total': salaries, 'count': salEnabled ? countModule('salaries') : 0},
      'commissions': {'enabled': comEnabled, 'total': commissions, 'count': comEnabled ? countModule('commissions') : 0},
      'ld_commissions': {'enabled': ldEnabled, 'total': ldCommissions, 'count': ldEnabled ? countModule('ld_commissions') : 0},
    };

    final overheads = r2(expenses + salaries + commissions + ldCommissions);
    final netProfit = r2(grossProfit - overheads);
    final grossMargin = revenue > 0 ? r2((grossProfit / revenue) * 100) : 0.0;
    final netMargin = revenue > 0 ? r2((netProfit / revenue) * 100) : 0.0;
    final avgTicket = orders > 0 ? r2(revenue / orders) : 0.0;

    final voidedTotal = r2((voidRow['voided_total'] as num?) ?? 0);
    final voidedCount = (voidRow['voided_count'] as int?) ?? 0;
    final voidRate = (revenue + voidedTotal) > 0
        ? r2((voidedTotal / (revenue + voidedTotal)) * 100)
        : 0.0;

    final invRow = _db.select(
      '''SELECT COALESCE(SUM(MAX(stock, 0) * cost), 0) AS inv_cost,
                COALESCE(SUM(MAX(stock, 0) * price), 0) AS inv_retail
         FROM products WHERE active = 1''',
    ).first;
    final inventoryCost = r2((invRow['inv_cost'] as num?) ?? 0);
    final inventoryRetail = r2((invRow['inv_retail'] as num?) ?? 0);
    final potentialProfit = r2(inventoryRetail - inventoryCost);

    // Daily breakdown across range
    final startDt = parseLocalDate(from);
    final endDt = parseLocalDate(to);
    final span = max(1, min(366, endDt.difference(startDt).inDays + 1));

    final salesByDay = <String, Map<String, num>>{};
    for (final r in _db.select(
      '''SELECT COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) AS bdate,
                COALESCE(SUM(s.total), 0) AS rev,
                COUNT(*) AS cnt
         FROM sales s
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY bdate''',
      [from, to],
    )) {
      salesByDay[r['bdate'] as String] = {
        'rev': (r['rev'] as num?) ?? 0,
        'cnt': (r['cnt'] as int?) ?? 0,
      };
    }

    final cogsByDay = <String, double>{};
    for (final r in _db.select(
      '''SELECT COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) AS bdate,
                COALESCE(SUM(si.cost_total), 0) AS cogs
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY bdate''',
      [from, to],
    )) {
      cogsByDay[r['bdate'] as String] = r2((r['cogs'] as num?) ?? 0);
    }

    Map<String, double> groupOutflowByDay(String table) {
      final out = <String, double>{};
      for (final r in _db.select(
        '''SELECT COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), t.date) AS bdate,
                  COALESCE(SUM(t.amount), 0) AS total
           FROM $table t
           WHERE COALESCE((SELECT business_date FROM shifts WHERE id = t.shift_id), t.date) BETWEEN ? AND ?
           GROUP BY bdate''',
        [from, to],
      )) {
        out[r['bdate'] as String] = r2((r['total'] as num?) ?? 0);
      }
      return out;
    }

    final expByDay = isModuleEnabled('expenses', disabled) ? groupOutflowByDay('expenses') : <String, double>{};
    final salByDay = isModuleEnabled('salary', disabled) ? groupOutflowByDay('salaries') : <String, double>{};
    final comByDay = isModuleEnabled('commission', disabled) ? groupOutflowByDay('commissions') : <String, double>{};
    final ldByDay = isModuleEnabled('ld-commission', disabled) ? groupOutflowByDay('ld_commissions') : <String, double>{};

    final daily = <Map<String, dynamic>>[];
    for (int i = 0; i < span; i++) {
      final dStr = formatDate(startDt.add(Duration(days: i)));
      final s = r2(salesByDay[dStr]?['rev'] ?? 0);
      final oCnt = (salesByDay[dStr]?['cnt'] ?? 0).toInt();
      final c = r2(cogsByDay[dStr] ?? 0);
      final e = r2(expByDay[dStr] ?? 0);
      final sal = r2(salByDay[dStr] ?? 0);
      final com = r2(comByDay[dStr] ?? 0);
      final ld = r2(ldByDay[dStr] ?? 0);
      final dayOverheads = r2(e + sal + com + ld);
      final dayGross = r2(s - c);
      daily.add({
        'date': dStr,
        'sales': s,
        'revenue': s,
        'orders': oCnt,
        'cogs': c,
        'gross_profit': dayGross,
        'expenses': e,
        'salaries': sal,
        'commissions': com,
        'ld_commissions': ld,
        'overheads': dayOverheads,
        'net': r2(s - dayOverheads), // Sales - overheads (without COGS) per spec §6
        'net_after_cogs': r2(dayGross - dayOverheads),
      });
    }

    return {
      'revenue': revenue,
      'orders': orders,
      'cogs': cogs,
      'gross_profit': grossProfit,
      'expenses': expenses,
      'salaries': salaries,
      'commissions': commissions,
      'ld_commissions': ldCommissions,
      'overheads': overheads,
      'net_profit': netProfit,
      'gross_margin': grossMargin,
      'net_margin': netMargin,
      'avg_ticket': avgTicket,
      'voided_total': voidedTotal,
      'voided_count': voidedCount,
      'void_rate': voidRate,
      'inventory_cost': inventoryCost,
      'inventory_retail': inventoryRetail,
      'potential_profit': potentialProfit,
      'daily': daily,
      'finance_summary': financeSummary,
    };
  }

  static const List<String> kDefaultDashboardCardOrder = [
    'kpis',
    'daily_trend',
    'finance_breakdown',
    'top_employees',
    'top_products',
    'variant_sales',
    'stock_alerts',
    'shift_history',
  ];

  List<String> getDashboardCardOrder() {
    final raw = getSettings()['dashboard_card_order'];
    if (raw == null || raw.trim().isEmpty) {
      return List<String>.from(kDefaultDashboardCardOrder);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = decoded.map((e) => e.toString()).toList();
        for (final card in kDefaultDashboardCardOrder) {
          if (!list.contains(card)) list.add(card);
        }
        return list;
      }
    } catch (_) {}
    return List<String>.from(kDefaultDashboardCardOrder);
  }

  void saveDashboardCardOrder(List<String> order) {
    final jsonStr = jsonEncode(order);
    setSettings({'dashboard_card_order': jsonStr});
  }

  Map<String, dynamic> dashboard({required String from, required String to}) {
    final disabled = getDisabledMenus();
    final core = _computeCoreMetrics(from, to, disabled);

    final topRows = _db.select(
      '''SELECT si.product_id, si.name,
                SUM(si.quantity * si.units_per) AS units_sold,
                SUM(si.quantity) AS qty_sold,
                SUM(si.subtotal) AS revenue,
                SUM(si.cost_total) AS cogs
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY si.product_id, si.name
         ORDER BY revenue DESC
         LIMIT 8''',
      [from, to],
    );

    final top = topRows.map((r) {
      final rev = r2((r['revenue'] as num?) ?? 0);
      final cg = r2((r['cogs'] as num?) ?? 0);
      return {
        'product_id': r['product_id'],
        'name': r['name'],
        'units_sold': (r['units_sold'] as num?)?.toInt() ?? 0,
        'qty_sold': (r['qty_sold'] as num?)?.toInt() ?? 0,
        'revenue': rev,
        'cogs': cg,
        'gross_profit': r2(rev - cg),
      };
    }).toList();

    final variantSales = _db.select(
      '''SELECT si.product_id, si.name, si.variant_name, si.units_per,
                SUM(si.quantity) AS packs_sold,
                SUM(si.quantity * si.units_per) AS base_units_sold,
                SUM(si.subtotal) AS revenue,
                SUM(si.cost_total) AS cogs
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY si.product_id, si.name, si.variant_name, si.units_per
         ORDER BY revenue DESC''',
      [from, to],
    ).map((r) {
      final rev = r2((r['revenue'] as num?) ?? 0);
      final cg = r2((r['cogs'] as num?) ?? 0);
      return {
        ...Map<String, dynamic>.from(r),
        'revenue': rev,
        'cogs': cg,
        'gross_profit': r2(rev - cg),
      };
    }).toList();

    final lowStock = _db.select(
      '''SELECT id, name, category, stock, low_stock, price, cost
         FROM products
         WHERE active = 1 AND stock <= low_stock
         ORDER BY stock ASC, name COLLATE NOCASE ASC
         LIMIT 10''',
    ).map((r) => Map<String, dynamic>.from(r)).toList();

    final inventoryReport = _db.select(
      '''SELECT p.id, p.name, p.category, p.stock, p.low_stock, p.price, p.cost,
                COALESCE(SUM(CASE WHEN s.status = 'completed' AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ? THEN si.quantity * si.units_per ELSE 0 END), 0) AS units_sold,
                COALESCE(SUM(CASE WHEN s.status = 'completed' AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ? THEN si.subtotal ELSE 0 END), 0) AS revenue
         FROM products p
         LEFT JOIN sale_items si ON si.product_id = p.id
         LEFT JOIN sales s ON s.id = si.sale_id
         WHERE p.active = 1
         GROUP BY p.id
         ORDER BY revenue DESC, p.name COLLATE NOCASE ASC''',
      [from, to, from, to],
    ).map((r) => Map<String, dynamic>.from(r)).toList();

    return {
      ...core,
      'finance_summary': core['finance_summary'],
      'shift_history': listShifts(limit: 30),
      'top': top,
      'top_employees': _computeTopEmployees(from, to, disabled),
      'variant_sales': variantSales,
      'low_stock': lowStock,
      'inventory_report': inventoryReport,
    };
  }

  List<Map<String, dynamic>> _computeTopEmployees(
    String from,
    String to,
    Set<String> disabled,
  ) {
    final map = <String, Map<String, double>>{};

    void accumulate(String name, String field, double amount) {
      final clean = name.trim();
      if (clean.isEmpty) return;
      final entry = map.putIfAbsent(
        clean,
        () => {'salary': 0.0, 'commission': 0.0, 'ld_commission': 0.0, 'total': 0.0},
      );
      entry[field] = r2((entry[field] ?? 0) + amount);
      entry['total'] = r2(
        (entry['salary'] ?? 0) + (entry['commission'] ?? 0) + (entry['ld_commission'] ?? 0),
      );
    }

    if (isModuleEnabled('salary', disabled)) {
      for (final r in listSalaries(from: from, to: to)) {
        accumulate(r['employee'] as String, 'salary', (r['amount'] as num).toDouble());
      }
    }
    if (isModuleEnabled('commission', disabled)) {
      for (final r in listCommissions(from: from, to: to)) {
        accumulate(r['employee_name'] as String, 'commission', (r['amount'] as num).toDouble());
      }
    }
    if (isModuleEnabled('ld-commission', disabled)) {
      for (final r in listLdCommissions(from: from, to: to)) {
        accumulate(r['employee_name'] as String, 'ld_commission', (r['amount'] as num).toDouble());
      }
    }

    final list = map.entries
        .map((e) => {
              'employee': e.key,
              'salary': e.value['salary'] ?? 0.0,
              'commission': e.value['commission'] ?? 0.0,
              'ld_commission': e.value['ld_commission'] ?? 0.0,
              'total': e.value['total'] ?? 0.0,
            })
        .toList();
    list.sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return list.take(15).toList();
  }

  Map<String, dynamic> adminDashboard({required String from, required String to}) {
    final disabled = getDisabledMenus();
    final core = _computeCoreMetrics(from, to, disabled);
    final prevWin = previousPeriodWindow(from, to);
    final prevCore = _computeCoreMetrics(prevWin.prevFrom, prevWin.prevTo, disabled);

    final bDate = activeBusinessDate();
    final mtdStart = resolveDatePreset('this_month', bDate).from;
    final todayMetrics = _computeCoreMetrics(bDate, bDate, disabled);
    final mtdMetrics = _computeCoreMetrics(mtdStart, bDate, disabled);

    // Counts
    final prodCounts = _db.select(
      '''SELECT
           COUNT(*) AS active_cnt,
           SUM(CASE WHEN stock > low_stock THEN 1 ELSE 0 END) AS healthy_cnt,
           SUM(CASE WHEN stock > 0 AND stock <= low_stock THEN 1 ELSE 0 END) AS low_cnt,
           SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END) AS out_cnt
         FROM products WHERE active = 1''',
    ).first;

    final empCount = (_db.select('SELECT COUNT(*) AS c FROM employees WHERE active = 1').first['c'] as int?) ?? 0;
    final cashiersCount = (_db.select('SELECT COUNT(*) AS c FROM cashiers').first['c'] as int?) ?? 0;
    final openShiftsCount = (_db.select("SELECT COUNT(*) AS c FROM shifts WHERE status = 'open'").first['c'] as int?) ?? 0;
    final expCount = (_db.select('SELECT COUNT(*) AS c FROM expenses').first['c'] as int?) ?? 0;
    final salCount = (_db.select('SELECT COUNT(*) AS c FROM salaries').first['c'] as int?) ?? 0;
    final comCount = (_db.select('SELECT COUNT(*) AS c FROM commissions').first['c'] as int?) ?? 0;
    final ldCount = (_db.select('SELECT COUNT(*) AS c FROM ld_commissions').first['c'] as int?) ?? 0;

    final counts = {
      'products_active': (prodCounts['active_cnt'] as num?)?.toInt() ?? 0,
      'products_healthy': (prodCounts['healthy_cnt'] as num?)?.toInt() ?? 0,
      'products_low': (prodCounts['low_cnt'] as num?)?.toInt() ?? 0,
      'products_out': (prodCounts['out_cnt'] as num?)?.toInt() ?? 0,
      'employees_active': empCount,
      'cashiers_count': cashiersCount,
      'open_shifts_count': openShiftsCount,
      'completed_sales': core['orders'],
      'voided_sales': core['voided_count'],
      'expenses_count': expCount,
      'salaries_count': salCount,
      'commissions_count': comCount,
      'ld_commissions_count': ldCount,
      'total_records': ((core['orders'] as int) + expCount + salCount + comCount + ldCount),
    };

    // Hourly breakdown
    final hourly = _db.select(
      '''SELECT strftime('%H', s.created_at) AS hour,
                COUNT(*) AS count,
                COALESCE(SUM(s.total), 0) AS revenue
         FROM sales s
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY hour
         ORDER BY hour ASC''',
      [from, to],
    ).map((r) => {
          'hour': r['hour'] ?? '00',
          'count': (r['count'] as num?)?.toInt() ?? 0,
          'revenue': r2((r['revenue'] as num?) ?? 0),
        }).toList();

    // Categories breakdown
    final categories = _db.select(
      '''SELECT CASE WHEN TRIM(COALESCE(p.category, '')) = '' THEN 'General' ELSE p.category END AS category,
                SUM(si.quantity * si.units_per) AS units,
                SUM(si.subtotal) AS revenue,
                SUM(si.subtotal - si.cost_total) AS gross_profit
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id
         LEFT JOIN products p ON p.id = si.product_id
         WHERE s.status = 'completed'
           AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
         GROUP BY category
         ORDER BY revenue DESC''',
      [from, to],
    ).map((r) => {
          'category': r['category'],
          'units': (r['units'] as num?)?.toInt() ?? 0,
          'revenue': r2((r['revenue'] as num?) ?? 0),
          'gross_profit': r2((r['gross_profit'] as num?) ?? 0),
        }).toList();

    // Catalog performance
    final catalogPerformance = _db.select(
      '''SELECT p.id, p.name, p.category, p.price, p.cost, p.stock, p.low_stock,
                COALESCE(SUM(CASE WHEN s.status = 'completed' AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ? THEN si.quantity * si.units_per ELSE 0 END), 0) AS units_sold,
                COALESCE(SUM(CASE WHEN s.status = 'completed' AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ? THEN si.subtotal ELSE 0 END), 0) AS revenue,
                COALESCE(SUM(CASE WHEN s.status = 'completed' AND COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ? THEN si.cost_total ELSE 0 END), 0) AS cogs
         FROM products p
         LEFT JOIN sale_items si ON si.product_id = p.id
         LEFT JOIN sales s ON s.id = si.sale_id
         WHERE p.active = 1
         GROUP BY p.id
         ORDER BY revenue DESC, p.name COLLATE NOCASE ASC''',
      [from, to, from, to, from, to],
    ).map((r) {
      final rev = r2((r['revenue'] as num?) ?? 0);
      final cg = r2((r['cogs'] as num?) ?? 0);
      final gp = r2(rev - cg);
      final price = r2((r['price'] as num?) ?? 0);
      final cost = r2((r['cost'] as num?) ?? 0);
      final marginPct = rev > 0
          ? r2((gp / rev) * 100)
          : (price > 0 ? r2(((price - cost) / price) * 100) : 0.0);
      return {
        ...Map<String, dynamic>.from(r),
        'revenue': rev,
        'cogs': cg,
        'gross_profit': gp,
        'margin_pct': marginPct,
      };
    }).toList();

    final productPerformance = catalogPerformance
        .where((p) => ((p['units_sold'] as num?) ?? 0) > 0)
        .toList();

    final expenseCategories = isModuleEnabled('expenses', disabled)
        ? _db.select(
            '''SELECT CASE WHEN TRIM(category) = '' THEN 'General' ELSE category END AS category,
                      COUNT(*) AS count,
                      COALESCE(SUM(amount), 0) AS amount
               FROM expenses e
               WHERE COALESCE((SELECT business_date FROM shifts WHERE id = e.shift_id), e.date) BETWEEN ? AND ?
               GROUP BY category
               ORDER BY amount DESC''',
            [from, to],
          ).map((r) => {
                'category': r['category'],
                'count': (r['count'] as num?)?.toInt() ?? 0,
                'amount': r2((r['amount'] as num?) ?? 0),
              }).toList()
        : <Map<String, dynamic>>[];

    final lowStockItems = _db.select(
      '''SELECT id, name, category, stock, low_stock, price, cost
         FROM products
         WHERE active = 1 AND stock <= low_stock
         ORDER BY stock ASC, name COLLATE NOCASE ASC''',
    ).map((r) => Map<String, dynamic>.from(r)).toList();

    final alerts = computeAlerts(from: from, to: to, coreMetrics: core, counts: counts);

    return {
      ...core,
      'previous_period': prevCore,
      'today': {
        'revenue': todayMetrics['revenue'],
        'orders': todayMetrics['orders'],
        'net': todayMetrics['net_profit'],
      },
      'mtd': {
        'revenue': mtdMetrics['revenue'],
        'orders': mtdMetrics['orders'],
        'net': mtdMetrics['net_profit'],
      },
      'counts': counts,
      'hourly': hourly,
      'categories': categories,
      'product_performance': productPerformance,
      'catalog_performance': catalogPerformance,
      'variant_sales': dashboard(from: from, to: to)['variant_sales'],
      'low_stock_items': lowStockItems,
      'expense_categories': expenseCategories,
      'shift_history': listShifts(limit: 100),
      'top_employees': _computeTopEmployees(from, to, disabled),
      'recent_sales': listSales(from: from, to: to, limit: 25),
      'recent_activity': listAuditLogs(from: from, to: to, limit: 60),
      'alerts': alerts,
    };
  }

  List<Map<String, dynamic>> computeAlerts({
    String? from,
    String? to,
    Map<String, dynamic>? coreMetrics,
    Map<String, dynamic>? counts,
  }) {
    final bDate = activeBusinessDate();
    final f = from ?? resolveDatePreset('this_month', bDate).from;
    final t = to ?? bDate;
    final disabled = getDisabledMenus();
    final core = coreMetrics ?? _computeCoreMetrics(f, t, disabled);

    int outCount = counts?['products_out'] as int? ?? 0;
    int lowCount = counts?['products_low'] as int? ?? 0;
    if (counts == null) {
      final pc = _db.select(
        '''SELECT
             SUM(CASE WHEN stock <= 0 THEN 1 ELSE 0 END) AS out_cnt,
             SUM(CASE WHEN stock > 0 AND stock <= low_stock THEN 1 ELSE 0 END) AS low_cnt
           FROM products WHERE active = 1''',
      ).first;
      outCount = (pc['out_cnt'] as num?)?.toInt() ?? 0;
      lowCount = (pc['low_cnt'] as num?)?.toInt() ?? 0;
    }

    final nowTs = formatDateTime(DateTime.now());
    final alerts = <Map<String, dynamic>>[];

    if (outCount > 0) {
      alerts.add({
        'id': 'alert-out-of-stock',
        'severity': 'bad',
        'title': '$outCount Product(s) Out of Stock',
        'description': 'Restock items with 0 or negative inventory.',
        'timestamp': nowTs,
        'target_tab': 'products',
        'filter': 'out_of_stock',
      });
    }
    if (lowCount > 0) {
      alerts.add({
        'id': 'alert-low-stock',
        'severity': 'warn',
        'title': '$lowCount Product(s) Low on Stock',
        'description': 'Inventory is at or below the low-stock threshold.',
        'timestamp': nowTs,
        'target_tab': 'products',
        'filter': 'low_stock',
      });
    }
    if (_getOpenShiftRow() == null) {
      alerts.add({
        'id': 'alert-shift-closed',
        'severity': 'info',
        'title': 'No Active Business Shift',
        'description': 'Start of Day (SOD) is required before POS or finance entries.',
        'timestamp': nowTs,
        'target_tab': 'shifts',
        'filter': 'open_sod',
      });
    }
    final voidRate = (core['void_rate'] as num?)?.toDouble() ?? 0.0;
    final voidCount = (core['voided_count'] as num?)?.toInt() ?? 0;
    if (voidRate >= 5.0 && voidCount > 0) {
      alerts.add({
        'id': 'alert-high-void-rate',
        'severity': 'warn',
        'title': 'High Void Rate (${voidRate.toStringAsFixed(1)}%)',
        'description': '$voidCount voided sale(s) recorded in the selected period.',
        'timestamp': nowTs,
        'target_tab': 'sales',
        'filter': 'voided',
      });
    }
    final net = (core['net_profit'] as num?)?.toDouble() ?? 0.0;
    final rev = (core['revenue'] as num?)?.toDouble() ?? 0.0;
    final ovh = (core['overheads'] as num?)?.toDouble() ?? 0.0;
    if (net < 0 && (rev > 0 || ovh > 0)) {
      alerts.add({
        'id': 'alert-negative-net',
        'severity': 'bad',
        'title': 'Negative Net Profit (${formatPeso(net)})',
        'description': 'COGS and overheads exceeded gross revenue for the period.',
        'timestamp': nowTs,
        'target_tab': 'overview',
        'filter': 'negative_net',
      });
    }
    final shortageShifts = _db.select(
      '''SELECT COUNT(*) AS cnt FROM shifts
         WHERE status = 'closed'
           AND business_date BETWEEN ? AND ?
           AND (closing_cash - expected_cash) < -0.01''',
      [f, t],
    ).first;
    final shortageCnt = (shortageShifts['cnt'] as num?)?.toInt() ?? 0;
    if (shortageCnt > 0) {
      alerts.add({
        'id': 'alert-shift-shortage',
        'severity': 'bad',
        'title': '$shortageCnt Shift(s) With Cash Shortage',
        'description': 'Counted drawer cash was less than expected cash at EOD.',
        'timestamp': nowTs,
        'target_tab': 'shifts',
        'filter': 'shortage',
      });
    }

    return alerts;
  }

  // --- Audit Feed & Global Search ---

  List<Map<String, dynamic>> listAuditLogs({
    required String from,
    required String to,
    int limit = 200,
  }) {
    final rows = _db.select(
      '''SELECT id, timestamp, actor, role, action, entity_type, entity_id, summary, details_json
         FROM audit_logs
         WHERE date(timestamp) BETWEEN ? AND ?
         UNION ALL
         SELECT (1000000 + s.id) AS id, s.created_at AS timestamp, 'Cashier' AS actor, 'cashier' AS role,
                'SALE' AS action, 'sale' AS entity_type, s.receipt_no AS entity_id,
                ('Completed sale ' || s.receipt_no) AS summary, '{}' AS details_json
         FROM sales s
         WHERE COALESCE((SELECT business_date FROM shifts WHERE id = s.shift_id), date(s.created_at)) BETWEEN ? AND ?
           AND NOT EXISTS (SELECT 1 FROM audit_logs a WHERE a.action = 'SALE' AND a.entity_id = s.receipt_no)
         ORDER BY timestamp DESC
         LIMIT ?''',
      [from, to, from, to, limit],
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Map<String, List<Map<String, dynamic>>> globalSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      return {
        'products': [],
        'sales': [],
        'expenses': [],
        'salaries': [],
        'commissions': [],
        'ld_commissions': [],
        'employees': [],
        'shifts': [],
      };
    }
    final pat = '%$q%';
    return {
      'products': _db
          .select(
            '''SELECT * FROM products
               WHERE active = 1 AND (name LIKE ? OR category LIKE ? OR barcode LIKE ?)
               ORDER BY name COLLATE NOCASE ASC LIMIT 12''',
            [pat, pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'sales': _db
          .select(
            '''SELECT * FROM sales
               WHERE receipt_no LIKE ? OR status LIKE ? OR COALESCE(void_reason, '') LIKE ?
               ORDER BY id DESC LIMIT 12''',
            [pat, pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'expenses': _db
          .select(
            '''SELECT * FROM expenses
               WHERE category LIKE ? OR description LIKE ? OR date LIKE ?
               ORDER BY id DESC LIMIT 10''',
            [pat, pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'salaries': _db
          .select(
            '''SELECT * FROM salaries
               WHERE employee LIKE ? OR period LIKE ? OR note LIKE ?
               ORDER BY id DESC LIMIT 10''',
            [pat, pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'commissions': _db
          .select(
            '''SELECT * FROM commissions
               WHERE employee_name LIKE ? OR type LIKE ?
               ORDER BY id DESC LIMIT 10''',
            [pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'ld_commissions': _db
          .select(
            '''SELECT * FROM ld_commissions
               WHERE employee_name LIKE ?
               ORDER BY id DESC LIMIT 10''',
            [pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'employees': _db
          .select(
            '''SELECT * FROM employees
               WHERE active = 1 AND (name LIKE ? OR position LIKE ?)
               ORDER BY name COLLATE NOCASE ASC LIMIT 10''',
            [pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
      'shifts': _db
          .select(
            '''SELECT * FROM shifts
               WHERE business_date LIKE ? OR opened_by LIKE ? OR closed_by LIKE ? OR notes LIKE ?
               ORDER BY id DESC LIMIT 8''',
            [pat, pat, pat, pat],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
    };
  }
}
