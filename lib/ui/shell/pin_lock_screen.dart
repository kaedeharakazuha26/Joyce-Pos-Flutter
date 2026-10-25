import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/joyce_widgets.dart';

class PinLockScreen extends StatefulWidget {
  final AppState appState;

  const PinLockScreen({super.key, required this.appState});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  final List<_GoldParticle> _particles = [];
  Offset _cursor = const Offset(400, 300);

  String _pin = '';
  bool _keyboardMode = false;
  bool _obscurePassword = true;
  String? _error;
  final TextEditingController _pwdCtrl = TextEditingController();
  final FocusNode _keyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final rng = Random(42);
    for (int i = 0; i < 45; i++) {
      _particles.add(
        _GoldParticle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          radius: 1.2 + rng.nextDouble() * 2.5,
          vx: (rng.nextDouble() - 0.5) * 0.0012,
          vy: (rng.nextDouble() - 0.5) * 0.0012,
          alpha: 0.2 + rng.nextDouble() * 0.55,
        ),
      );
    }
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pwdCtrl.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _appendDigit(String d) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  void _clear() {
    setState(() {
      _pin = '';
      _pwdCtrl.clear();
      _error = null;
    });
  }

  void _submitPin() {
    final targetPin = _keyboardMode ? _pwdCtrl.text : _pin;
    final err = widget.appState.loginWithPin(targetPin);
    if (err != null) {
      setState(() {
        _error = err;
        _pin = '';
        _pwdCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    final storeName = widget.appState.settings['store_name'] ?? 'JOYCE POS';
    final isOpen = widget.appState.isShiftOpen;
    final branchName = widget.appState.activeBranchName;

    return KeyboardListener(
      focusNode: _keyFocus,
      autofocus: !_keyboardMode,
      onKeyEvent: (event) {
        if (_keyboardMode || event is! KeyDownEvent) return;
        final label = event.logicalKey.keyLabel;
        if (RegExp(r'^[0-9]$').hasMatch(label)) {
          _appendDigit(label);
        } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _backspace();
        } else if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _submitPin();
        } else if (event.logicalKey == LogicalKeyboardKey.escape) {
          _clear();
        }
      },
      child: MouseRegion(
        onHover: (e) => _cursor = e.localPosition,
        child: Scaffold(
          backgroundColor: c.bg,
          body: Stack(
            children: [
              // Animated Gold-Dust Particle & Rotating Rings Canvas
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _animCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _GoldDustPainter(
                        particles: _particles,
                        progress: _animCtrl.value,
                        cursor: _cursor,
                        accent: c.accent,
                      ),
                    );
                  },
                ),
              ),
              // Top bar badges & theme toggle
              Positioned(
                top: 24,
                left: 28,
                right: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _BadgeChip(
                          icon: Icons.storefront_outlined,
                          label: branchName,
                          color: c.accent,
                        ),
                        const SizedBox(width: 10),
                        _BadgeChip(
                          icon: isOpen
                              ? Icons.play_circle_outline
                              : Icons.pause_circle_outline,
                          label: isOpen ? 'Shift Open' : 'Shift Closed',
                          color: isOpen ? c.ok : c.muted,
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: 'Toggle Theme',
                      onPressed: widget.appState.toggleTheme,
                      icon: Icon(
                        widget.appState.themeMode == ThemeMode.dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        color: c.accent,
                      ),
                    ),
                  ],
                ),
              ),
              // Center PIN Lock Card
              Center(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: c.cardSolid.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border, width: 1.4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 36,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: c.buttonGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.point_of_sale,
                          color: c.btnText,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        storeName,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enter your Cashier or Administrator PIN',
                        style: TextStyle(color: c.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 18),
                      // Mode switcher
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('Touch Keypad'),
                            selected: !_keyboardMode,
                            onSelected: (_) =>
                                setState(() => _keyboardMode = false),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Keyboard Input'),
                            selected: _keyboardMode,
                            onSelected: (_) =>
                                setState(() => _keyboardMode = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (!_keyboardMode) ...[
                        // PIN Dots
                        Container(
                          height: 48,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: c.input,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _error != null ? c.bad : c.borderSubtle,
                            ),
                          ),
                          child: _pin.isEmpty
                              ? Text(
                                  '• • • •',
                                  style: TextStyle(
                                    color: c.muted.withValues(alpha: 0.4),
                                    fontSize: 22,
                                    letterSpacing: 8,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(
                                    _pin.length,
                                    (_) => Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: c.accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        // Touch Keypad Grid
                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.65,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (final d in [
                              '1',
                              '2',
                              '3',
                              '4',
                              '5',
                              '6',
                              '7',
                              '8',
                              '9'
                            ])
                              _KeypadButton(
                                label: d,
                                onTap: () => _appendDigit(d),
                              ),
                            _KeypadButton(
                              label: 'CLR',
                              isMuted: true,
                              onTap: _clear,
                            ),
                            _KeypadButton(
                              label: '0',
                              onTap: () => _appendDigit('0'),
                            ),
                            _KeypadButton(
                              icon: Icons.backspace_outlined,
                              isMuted: true,
                              onTap: _backspace,
                            ),
                          ],
                        ),
                      ] else ...[
                        TextField(
                          controller: _pwdCtrl,
                          obscureText: _obscurePassword,
                          autofocus: true,
                          onSubmitted: (_) => _submitPin(),
                          decoration: InputDecoration(
                            labelText: 'Enter PIN',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: c.bad,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: JoyceButton(
                          label: 'Unlock Terminal',
                          icon: Icons.lock_open_outlined,
                          onPressed: _submitPin,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Default Admin PIN: 0000 (Change in Settings > Security)',
                        style: TextStyle(color: c.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BadgeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.cardSolid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: c.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isMuted;

  const _KeypadButton({
    this.label,
    this.icon,
    required this.onTap,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.joyce;
    return Material(
      color: c.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.borderSubtle),
          ),
          child: icon != null
              ? Icon(icon, color: isMuted ? c.muted : c.text, size: 20)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    color: isMuted ? c.muted : c.text,
                    fontSize: isMuted ? 13 : 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}

class _GoldParticle {
  double x;
  double y;
  final double radius;
  final double vx;
  final double vy;
  final double alpha;

  _GoldParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.vx,
    required this.vy,
    required this.alpha,
  });
}

class _GoldDustPainter extends CustomPainter {
  final List<_GoldParticle> particles;
  final double progress;
  final Offset cursor;
  final Color accent;

  _GoldDustPainter({
    required this.particles,
    required this.progress,
    required this.cursor,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Subtle radial glow
    final bgGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.shortestSide * 0.55));
    canvas.drawCircle(center, size.shortestSide * 0.55, bgGlow);

    // Rotating dashed ring
    final ringPaint = Paint()
      ..color = accent.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * pi);
    canvas.drawCircle(Offset.zero, 270, ringPaint);
    canvas.restore();

    // Gold-dust particles
    for (final p in particles) {
      p.x = (p.x + p.vx) % 1.0;
      p.y = (p.y + p.vy) % 1.0;
      if (p.x < 0) p.x += 1.0;
      if (p.y < 0) p.y += 1.0;

      var pos = Offset(p.x * size.width, p.y * size.height);
      final dist = (pos - cursor).distance;
      if (dist < 120 && dist > 1) {
        final push = (pos - cursor) / dist * ((120 - dist) * 0.15);
        pos += push;
      }

      final paint = Paint()..color = accent.withValues(alpha: p.alpha * 0.55);
      canvas.drawCircle(pos, p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GoldDustPainter oldDelegate) => true;
}
