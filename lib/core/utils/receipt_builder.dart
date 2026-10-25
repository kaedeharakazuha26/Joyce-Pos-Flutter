import 'dart:math';
import 'dart:typed_data';
import 'dates.dart';
import 'money.dart';

class ReceiptBuilder {
  static String sanitizeAscii(String input) {
    final replaced = input.replaceAll('₱', 'P');
    final sb = StringBuffer();
    for (int i = 0; i < replaced.length; i++) {
      final code = replaced.codeUnitAt(i);
      if (code == 10 || code == 13 || (code >= 32 && code <= 126)) {
        sb.writeCharCode(code);
      } else {
        sb.write('?');
      }
    }
    return sb.toString();
  }

  static int resolveWidth(Map<String, String> settings) {
    final parsed = int.tryParse(settings['chars_per_line'] ?? '');
    if (parsed != null && parsed >= 20 && parsed <= 80) return parsed;
    return (settings['paper_width'] == '80') ? 48 : 32;
  }

  static String twoColumn(String left, String right, int width) {
    final l = sanitizeAscii(left);
    final r = sanitizeAscii(right);
    final maxLeft = max(1, width - r.length - 1);
    final truncLeft = l.length > maxLeft ? l.substring(0, maxLeft) : l;
    final spaces = max(1, width - truncLeft.length - r.length);
    return '$truncLeft${' ' * spaces}$r';
  }

  static String alignLine(String text, String align, int width) {
    final clean = sanitizeAscii(text);
    if (clean.length >= width) return clean.substring(0, width);
    final mode = align.toLowerCase();
    if (mode == 'right') {
      return clean.padLeft(width);
    } else if (mode == 'center') {
      final leftPad = (width - clean.length) ~/ 2;
      return '${' ' * leftPad}$clean';
    }
    return clean;
  }

  static String buildReceiptText(
    Map<String, dynamic> sale,
    Map<String, String> settings,
  ) {
    final w = resolveWidth(settings);
    final storeName = (settings['store_name'] ?? 'JOYCE POS').trim();
    final address = (settings['store_address'] ?? '').trim();
    final phone = (settings['store_phone'] ?? '').trim();
    final header = (settings['receipt_header'] ?? '').trim();
    final footer = (settings['receipt_footer'] ?? 'Thank you! Come again.').trim();
    final headerAlign = settings['header_align'] ?? 'center';
    final footerAlign = settings['footer_align'] ?? 'center';
    final rule = '-' * w;

    final lines = <String>[];
    if (storeName.isNotEmpty) {
      lines.add(alignLine(storeName, headerAlign, w));
    }
    if (address.isNotEmpty) lines.add(alignLine(address, headerAlign, w));
    if (phone.isNotEmpty) lines.add(alignLine(phone, headerAlign, w));
    if (header.isNotEmpty) lines.add(alignLine(header, headerAlign, w));
    lines.add(rule);

    final receiptNo = (sale['receipt_no'] ?? '').toString();
    final createdAt = (sale['created_at'] ?? '').toString();
    lines.add(sanitizeAscii('Receipt: $receiptNo').substring(
      0,
      min(w, sanitizeAscii('Receipt: $receiptNo').length),
    ));
    lines.add(sanitizeAscii('Date: $createdAt').substring(
      0,
      min(w, sanitizeAscii('Date: $createdAt').length),
    ));
    if (sale['status'] == 'voided') {
      lines.add(alignLine('*** VOIDED ***', 'center', w));
    }
    lines.add(rule);

    final items = (sale['items'] as List? ?? const []);
    for (final raw in items) {
      if (raw is! Map) continue;
      final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
      final name = (raw['name'] ?? '').toString();
      final vName = (raw['variant_name'] ?? '').toString().trim();
      final unitPrice = r2((raw['unit_price'] as num?) ?? 0);
      final subtotal = r2((raw['subtotal'] as num?) ?? (unitPrice * qty));
      final label = vName.isNotEmpty ? '${qty}x $name ($vName)' : '${qty}x $name';
      lines.add(twoColumn(label, subtotal.toStringAsFixed(2), w));
      if (qty > 1) {
        final subLine = '   @ ${unitPrice.toStringAsFixed(2)}';
        lines.add(subLine.length > w ? subLine.substring(0, w) : subLine);
      }
    }

    lines.add(rule);
    final total = r2((sale['total'] as num?) ?? 0);
    final paid = r2((sale['paid'] as num?) ?? total);
    final change = r2((sale['change_amt'] as num?) ?? (paid - total));

    lines.add(twoColumn('TOTAL', total.toStringAsFixed(2), w));
    lines.add(twoColumn('Cash', paid.toStringAsFixed(2), w));
    lines.add(twoColumn('Change', change.toStringAsFixed(2), w));
    lines.add(rule);

    if (footer.isNotEmpty) {
      lines.add(alignLine(footer, footerAlign, w));
    }

    return lines.join('\n');
  }

  static Uint8List buildReceiptBytes(
    Map<String, dynamic> sale,
    Map<String, String> settings,
  ) {
    final w = resolveWidth(settings);
    final storeName = (settings['store_name'] ?? 'JOYCE POS').trim();
    final address = (settings['store_address'] ?? '').trim();
    final phone = (settings['store_phone'] ?? '').trim();
    final header = (settings['receipt_header'] ?? '').trim();
    final footer = (settings['receipt_footer'] ?? 'Thank you! Come again.').trim();
    final headerAlign = _alignByte(settings['header_align'] ?? 'center');
    final footerAlign = _alignByte(settings['footer_align'] ?? 'center');
    final isLarge = (settings['font_size'] == 'large');
    final feedLines = (int.tryParse(settings['feed_lines'] ?? '3') ?? 3).clamp(0, 10);
    final cutPaper = (settings['cut_paper'] ?? '1') == '1';
    final openDrawer = (settings['open_drawer'] ?? '0') == '1';
    final copies = (int.tryParse(settings['copies'] ?? '1') ?? 1).clamp(1, 5);
    final rule = '-' * w;

    final single = <int>[];
    void writeCmd(List<int> cmd) => single.addAll(cmd);
    void writeLine(String s) {
      final clean = sanitizeAscii(s);
      single.addAll(clean.codeUnits);
      single.add(0x0A);
    }

    // ESC @ init
    writeCmd([0x1B, 0x40]);
    // Header align
    writeCmd([0x1B, 0x61, headerAlign]);
    // Bold on + Size
    writeCmd([0x1B, 0x45, 1]);
    writeCmd([0x1D, 0x21, isLarge ? 0x11 : 0x01]);
    if (storeName.isNotEmpty) writeLine(storeName);
    // Reset size + bold off
    writeCmd([0x1D, 0x21, 0x00]);
    writeCmd([0x1B, 0x45, 0]);

    if (address.isNotEmpty) writeLine(address);
    if (phone.isNotEmpty) writeLine(phone);
    if (header.isNotEmpty) writeLine(header);

    // Left align
    writeCmd([0x1B, 0x61, 0]);
    writeLine(rule);
    writeLine('Receipt: ${sale['receipt_no'] ?? ''}');
    writeLine('Date: ${sale['created_at'] ?? ''}');
    if (sale['status'] == 'voided') {
      writeCmd([0x1B, 0x61, 1]);
      writeCmd([0x1B, 0x45, 1]);
      writeLine('*** VOIDED ***');
      writeCmd([0x1B, 0x45, 0]);
      writeCmd([0x1B, 0x61, 0]);
    }
    writeLine(rule);

    final items = (sale['items'] as List? ?? const []);
    for (final raw in items) {
      if (raw is! Map) continue;
      final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
      final name = (raw['name'] ?? '').toString();
      final vName = (raw['variant_name'] ?? '').toString().trim();
      final unitPrice = r2((raw['unit_price'] as num?) ?? 0);
      final subtotal = r2((raw['subtotal'] as num?) ?? (unitPrice * qty));
      final label = vName.isNotEmpty ? '${qty}x $name ($vName)' : '${qty}x $name';
      writeLine(twoColumn(label, subtotal.toStringAsFixed(2), w));
      if (qty > 1) {
        writeLine('   @ ${unitPrice.toStringAsFixed(2)}');
      }
    }

    writeLine(rule);
    final total = r2((sale['total'] as num?) ?? 0);
    final paid = r2((sale['paid'] as num?) ?? total);
    final change = r2((sale['change_amt'] as num?) ?? (paid - total));

    writeCmd([0x1B, 0x45, 1]);
    writeLine(twoColumn('TOTAL', total.toStringAsFixed(2), w));
    writeCmd([0x1B, 0x45, 0]);
    writeLine(twoColumn('Cash', paid.toStringAsFixed(2), w));
    writeLine(twoColumn('Change', change.toStringAsFixed(2), w));
    writeLine(rule);

    if (footer.isNotEmpty) {
      writeCmd([0x1B, 0x61, footerAlign]);
      writeLine(footer);
      writeCmd([0x1B, 0x61, 0]);
    }

    // Feed lines
    writeCmd([0x1B, 0x64, feedLines]);
    if (cutPaper) {
      writeCmd([0x1D, 0x56, 66, 0]);
    }
    if (openDrawer) {
      writeCmd([0x1B, 0x70, 0, 25, 250]);
    }

    final totalBytes = <int>[];
    for (int c = 0; c < copies; c++) {
      totalBytes.addAll(single);
    }
    return Uint8List.fromList(totalBytes);
  }

  static String buildZReadingText(
    Map<String, dynamic> zData,
    Map<String, String> settings,
    Set<String> disabledModules,
  ) {
    final w = resolveWidth(settings);
    final storeName = (settings['store_name'] ?? 'JOYCE POS').trim();
    final address = (settings['store_address'] ?? '').trim();
    final phone = (settings['store_phone'] ?? '').trim();
    final eqRule = '=' * w;
    final dashRule = '-' * w;

    bool enabled(String mod) => !disabledModules.contains(mod.toLowerCase());

    final lines = <String>[];
    if (storeName.isNotEmpty) lines.add(alignLine(storeName, 'center', w));
    if (address.isNotEmpty) lines.add(alignLine(address, 'center', w));
    if (phone.isNotEmpty) lines.add(alignLine(phone, 'center', w));
    lines.add(alignLine('*** END OF DAY / Z-READING ***', 'center', w));
    lines.add(eqRule);

    lines.add('Shift ID : #${zData['id'] ?? ''}');
    lines.add('Date     : ${zData['business_date'] ?? ''}');
    lines.add('Opened At: ${zData['opened_at'] ?? ''}');
    lines.add('Opened By: ${zData['opened_by'] ?? ''}');
    lines.add('Closed By: ${zData['closed_by'] ?? 'Administrator'}');
    lines.add(dashRule);
    lines.add('PRODUCTS SOLD (QTY x AMOUNT):');

    final sold = (zData['sold_items'] as List? ?? const []);
    if (sold.isEmpty) {
      lines.add('No products sold in shift.');
    } else {
      for (final item in sold) {
        if (item is! Map) continue;
        final n = (item['name'] ?? '').toString();
        final vn = (item['variant_name'] ?? '').toString().trim();
        final q = (item['quantity'] as num?)?.toInt() ?? 0;
        final amt = r2((item['amount'] as num?) ?? 0);
        final label = vn.isNotEmpty ? '$n ($vn) x $q' : '$n x $q';
        lines.add(twoColumn(label, amt.toStringAsFixed(2), w));
      }
    }

    lines.add(eqRule);
    final gross = r2((zData['gross_sales'] as num?) ?? (zData['cash_sales'] as num?) ?? 0);
    final exp = enabled('expenses') ? r2((zData['expenses'] as num?) ?? 0) : 0.0;
    final sal = enabled('salary') ? r2((zData['salaries'] as num?) ?? 0) : 0.0;
    final ld = enabled('ld-commission') ? r2((zData['ld_commissions'] as num?) ?? 0) : 0.0;
    final com = enabled('commission') ? r2((zData['commissions'] as num?) ?? 0) : 0.0;
    final enabledOutflows = r2(exp + sal + ld + com);
    final netOperating = r2(gross - enabledOutflows);

    lines.add(twoColumn('TOTAL GROSS SALES', gross.toStringAsFixed(2), w));
    if (enabled('expenses')) {
      lines.add(twoColumn('- Store Expenses', '-${exp.toStringAsFixed(2)}', w));
    }
    if (enabled('salary')) {
      lines.add(twoColumn('- Salaries Paid', '-${sal.toStringAsFixed(2)}', w));
    }
    if (enabled('ld-commission')) {
      lines.add(twoColumn('- LD Comm Paid', '-${ld.toStringAsFixed(2)}', w));
    }
    if (enabled('commission')) {
      lines.add(twoColumn('- Commissions Paid', '-${com.toStringAsFixed(2)}', w));
    }
    lines.add(dashRule);
    lines.add(twoColumn('= NET OPERATING PROFIT', netOperating.toStringAsFixed(2), w));
    lines.add(eqRule);

    final opening = r2((zData['opening_cash'] as num?) ?? 0);
    final expected = r2(opening + gross - enabledOutflows);
    final rawClosing = r2((zData['closing_cash'] as num?) ?? 0);
    final actual = rawClosing > 0 ? rawClosing : expected;
    final variance = r2(actual - expected);

    String varLabel;
    if (variance.abs() < 0.01) {
      varLabel = '0.00 (Balanced)';
    } else if (variance > 0) {
      varLabel = '+${variance.toStringAsFixed(2)} (Overage)';
    } else {
      varLabel = '${variance.toStringAsFixed(2)} (Shortage)';
    }

    lines.add(twoColumn('Opening Float', opening.toStringAsFixed(2), w));
    lines.add(twoColumn('+ Cash Sales', gross.toStringAsFixed(2), w));
    lines.add(twoColumn('- Total Outflows', '-${enabledOutflows.toStringAsFixed(2)}', w));
    lines.add(twoColumn('Expected in Drawer', expected.toStringAsFixed(2), w));
    lines.add(twoColumn('Actual Cash Counted', actual.toStringAsFixed(2), w));
    lines.add(twoColumn('Variance', varLabel, w));

    final notes = (zData['notes'] ?? '').toString().trim();
    if (notes.isNotEmpty) {
      lines.add('Notes: ${sanitizeAscii(notes)}');
    }
    lines.add(eqRule);
    lines.add(alignLine('______________________', 'center', w));
    lines.add(alignLine('Cashier Signature', 'center', w));
    lines.add(alignLine('______________________', 'center', w));
    lines.add(alignLine('Manager Signature', 'center', w));
    lines.add(alignLine('Printed: ${formatDateTime(DateTime.now())}', 'center', w));

    return lines.join('\n');
  }

  static Uint8List buildZReadingBytes(
    Map<String, dynamic> zData,
    Map<String, String> settings,
    Set<String> disabledModules,
  ) {
    final text = buildZReadingText(zData, settings, disabledModules);
    final feedLines = (int.tryParse(settings['feed_lines'] ?? '3') ?? 3).clamp(0, 10);
    final cutPaper = (settings['cut_paper'] ?? '1') == '1';
    final openDrawer = (settings['open_drawer'] ?? '0') == '1';

    final out = <int>[0x1B, 0x40]; // ESC @
    for (final line in text.split('\n')) {
      out.addAll(sanitizeAscii(line).codeUnits);
      out.add(0x0A);
    }
    out.addAll([0x1B, 0x64, feedLines]);
    if (cutPaper) out.addAll([0x1D, 0x56, 66, 0]);
    if (openDrawer) out.addAll([0x1B, 0x70, 0, 25, 250]);
    return Uint8List.fromList(out);
  }

  static int _alignByte(String align) {
    switch (align.toLowerCase()) {
      case 'center':
        return 1;
      case 'right':
        return 2;
      default:
        return 0;
    }
  }
}
