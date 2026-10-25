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
