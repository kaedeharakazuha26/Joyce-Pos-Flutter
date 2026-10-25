import 'package:intl/intl.dart';

final NumberFormat _pesoGrouping = NumberFormat('#,##0.00', 'en_US');

double r2(num v) {
  if (v.isNaN || v.isInfinite) return 0.0;
  return (v * 100).roundToDouble() / 100.0;
}

String formatPeso(num v, {bool showSign = true}) {
  final rounded = r2(v);
  final isNeg = rounded < -0.0001;
  final absVal = rounded.abs();
  final formatted = _pesoGrouping.format(absVal);
  final prefix = showSign ? '₱' : '';
  return isNeg ? '-$prefix$formatted' : '$prefix$formatted';
}

String pesoShort(num v) {
  final rounded = r2(v);
  final isNeg = rounded < -0.0001;
  final absVal = rounded.abs();
  final sign = isNeg ? '-' : '';
  if (absVal >= 1000000) {
    return '$sign₱${(absVal / 1000000).toStringAsFixed(2)}M';
  }
  if (absVal >= 10000) {
    return '$sign₱${(absVal / 1000).toStringAsFixed(1)}k';
  }
  return formatPeso(rounded);
}
