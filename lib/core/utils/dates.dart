import 'money.dart';

String formatDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String formatDateTime(DateTime dt) {
  final date = formatDate(dt);
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$date $h:$min:$s';
}

String todayDateString([DateTime? now]) {
  return formatDate(now ?? DateTime.now());
}

String businessNow(String activeBusinessDate, [DateTime? now]) {
  final t = now ?? DateTime.now();
  final datePart = activeBusinessDate.trim().isEmpty
      ? formatDate(t)
      : activeBusinessDate.trim();
  final h = t.hour.toString().padLeft(2, '0');
  final min = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  return '$datePart $h:$min:$s';
}

/// Parses 'YYYY-MM-DD' at 12:00 local time to avoid DST boundary issues.
DateTime parseLocalDate(String ymd) {
  final parts = ymd.trim().split('-');
  if (parts.length != 3) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 12);
  }
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  final d = int.tryParse(parts[2]) ?? 1;
  return DateTime(y, m, d, 12);
}

({String from, String to}) resolveDatePreset(
  String preset,
  String anchorBusinessDate,
) {
  final anchor = parseLocalDate(anchorBusinessDate);
  final anchorStr = formatDate(anchor);

  switch (preset) {
    case 'today':
      return (from: anchorStr, to: anchorStr);
    case 'yesterday':
      final y = anchor.subtract(const Duration(days: 1));
      final yStr = formatDate(y);
      return (from: yStr, to: yStr);
    case 'this_week':
      // Monday = 1 .. Sunday = 7
      final diffToMonday = anchor.weekday - DateTime.monday;
      final mon = anchor.subtract(Duration(days: diffToMonday));
      return (from: formatDate(mon), to: anchorStr);
    case 'last_week':
      final diffToMonday = anchor.weekday - DateTime.monday;
      final thisMon = anchor.subtract(Duration(days: diffToMonday));
      final lastMon = thisMon.subtract(const Duration(days: 7));
      final lastSun = thisMon.subtract(const Duration(days: 1));
      return (from: formatDate(lastMon), to: formatDate(lastSun));
    case 'this_month':
      final first = DateTime(anchor.year, anchor.month, 1, 12);
      return (from: formatDate(first), to: anchorStr);
    case 'last_month':
      final firstLastMonth = DateTime(anchor.year, anchor.month - 1, 1, 12);
      final lastLastMonth = DateTime(anchor.year, anchor.month, 0, 12);
      return (from: formatDate(firstLastMonth), to: formatDate(lastLastMonth));
    case 'this_quarter':
      final qStartMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
      final firstQ = DateTime(anchor.year, qStartMonth, 1, 12);
      return (from: formatDate(firstQ), to: anchorStr);
    case 'this_year':
      final firstY = DateTime(anchor.year, 1, 1, 12);
      return (from: formatDate(firstY), to: anchorStr);
    default:
      return (from: anchorStr, to: anchorStr);
  }
}

({String prevFrom, String prevTo, int spanDays}) previousPeriodWindow(
  String from,
  String to,
) {
  final f = parseLocalDate(from);
  final t = parseLocalDate(to);
  final span = t.difference(f).inDays.abs() + 1;
  final prevToDt = f.subtract(const Duration(days: 1));
  final prevFromDt = prevToDt.subtract(Duration(days: span - 1));
  return (
    prevFrom: formatDate(prevFromDt),
    prevTo: formatDate(prevToDt),
    spanDays: span,
  );
}

({double pct, bool isNew}) pctChange(num cur, num prev) {
  final c = cur.toDouble();
  final p = prev.toDouble();
  if (p.abs() < 1e-9) {
    final isNonZero = c.abs() >= 1e-9;
    return (pct: isNonZero ? 100.0 : 0.0, isNew: isNonZero);
  }
  return (pct: r2(((c - p) / p.abs()) * 100.0), isNew: false);
}
