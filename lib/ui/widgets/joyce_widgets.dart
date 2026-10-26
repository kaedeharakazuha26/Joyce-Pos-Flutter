import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/dates.dart';
import '../../data/pos_repository.dart';

void showJoyceToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final c = context.joyce;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 420,
        backgroundColor: isError ? c.bad : c.cardSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isError ? c.bad : c.accent),
        ),
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? Colors.white : c.ok,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? Colors.white : c.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
}

class JoyceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  const JoyceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardSolid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? c.borderSubtle),
      ),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: card,
    );
  }
}

class JoyceButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outline;
  final bool danger;
  final bool compact;

  const JoyceButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.outline = false,
    this.danger = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 11);

    if (outline || danger) {
      final color = danger ? c.bad : c.accent;
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.55)),
          padding: pad,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 15 : 17),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: compact ? 12 : 13,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: pad,
          decoration: BoxDecoration(
            gradient: onPressed == null ? null : c.buttonGradient,
            color: onPressed == null ? c.borderSubtle : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: compact ? 15 : 17,
                  color: onPressed == null ? c.muted : c.btnText,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: onPressed == null ? c.muted : c.btnText,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}

class RangeBar extends StatelessWidget {
  final String from;
  final String to;
  final String activeBusinessDate;
  final void Function(String from, String to, String preset) onChanged;
  final String selectedPreset;

  const RangeBar({
    super.key,
    required this.from,
    required this.to,
    required this.activeBusinessDate,
    required this.onChanged,
    this.selectedPreset = 'today',
  });

  static const List<({String id, String label})> presets = [
    (id: 'today', label: 'Today'),
    (id: 'yesterday', label: 'Yesterday'),
    (id: 'this_week', label: 'This Week'),
    (id: 'last_week', label: 'Last Week'),
    (id: 'this_month', label: 'This Month'),
    (id: 'last_month', label: 'Last Month'),
    (id: 'this_quarter', label: 'This Quarter'),
    (id: 'this_year', label: 'This Year'),
  ];

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    final initial = parseLocalDate(isFrom ? from : to);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      final str = formatDate(picked);
      if (isFrom) {
        onChanged(str, to.compareTo(str) < 0 ? str : to, 'custom');
      } else {
        onChanged(from.compareTo(str) > 0 ? str : from, str, 'custom');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return JoyceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in presets)
            ChoiceChip(
              label: Text(p.label, style: const TextStyle(fontSize: 12)),
              selected: selectedPreset == p.id,
              selectedColor: c.accent.withValues(alpha: 0.25),
              onSelected: (_) {
                final r = resolveDatePreset(p.id, activeBusinessDate);
                onChanged(r.from, r.to, p.id);
              },
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _pickDate(context, true),
            icon: const Icon(Icons.calendar_today, size: 14),
            label: Text('From: $from', style: const TextStyle(fontSize: 12)),
          ),
          OutlinedButton.icon(
            onPressed: () => _pickDate(context, false),
            icon: const Icon(Icons.calendar_today, size: 14),
            label: Text('To: $to', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const PaginationBar({
    super.key,
    required this.currentPage,
    required this.totalItems,
    this.pageSize = 20,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final totalPages = (totalItems / pageSize).ceil().clamp(1, 99999);
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${(currentPage - 1) * pageSize + 1}–${(currentPage * pageSize).clamp(0, totalItems)} of $totalItems',
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          Row(
            children: [
              IconButton(
                onPressed:
                    currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Page $currentPage / $totalPages',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              IconButton(
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReceiptPreviewWidget extends StatelessWidget {
  final String receiptText;
  final int columns;

  const ReceiptPreviewWidget({
    super.key,
    required this.receiptText,
    this.columns = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: columns > 40 ? 380 : 290,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black26),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SelectableText(
        receiptText,
        style: const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 12,
          height: 1.35,
          color: Color(0xFF1A1A1A),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: c.muted.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(color: c.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 14),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmAdminPinIfRequired(
  BuildContext context, {
  required PosRepository repo,
  required bool isAlreadyAdmin,
  String title = 'Admin Authorization Required',
}) async {
  if (isAlreadyAdmin) return true;
  final ctrl = TextEditingController();
  String? err;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final c = ctx.joyce;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter the Administrator PIN to authorize this action.',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Admin PIN',
                    errorText: err,
                  ),
                  onSubmitted: (_) {
                    final adminPin = repo.getSettings()['admin_pin'] ?? '0000';
                    if (ctrl.text.trim() == adminPin) {
                      Navigator.of(ctx).pop(true);
                    } else {
                      setState(() => err = 'Invalid Admin PIN');
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            JoyceButton(
              label: 'Authorize',
              onPressed: () {
                final adminPin = repo.getSettings()['admin_pin'] ?? '0000';
                if (ctrl.text.trim() == adminPin) {
                  Navigator.of(ctx).pop(true);
                } else {
                  setState(() => err = 'Invalid Admin PIN');
                }
              },
            ),
          ],
        );
      },
    ),
  );
  return res == true;
}
