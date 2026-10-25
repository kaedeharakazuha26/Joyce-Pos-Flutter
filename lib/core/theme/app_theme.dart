import 'package:flutter/material.dart';

class JoyceColors extends ThemeExtension<JoyceColors> {
  final Color bg;
  final Color bg2;
  final Color cardSolid;
  final Color card;
  final Color border;
  final Color borderSubtle;
  final Color text;
  final Color muted;
  final Color input;
  final Color accent;
  final Color accentHover;
  final Color accent2;
  final Color accentDeep;
  final Color btnText;
  final LinearGradient buttonGradient;
  final Color ok;
  final Color warn;
  final Color bad;
  final Color info;
  final Color purple;

  const JoyceColors({
    required this.bg,
    required this.bg2,
    required this.cardSolid,
    required this.card,
    required this.border,
    required this.borderSubtle,
    required this.text,
    required this.muted,
    required this.input,
    required this.accent,
    required this.accentHover,
    required this.accent2,
    required this.accentDeep,
    required this.btnText,
    required this.buttonGradient,
    this.ok = const Color(0xFF2FCF8A),
    this.warn = const Color(0xFFD4AF37),
    this.bad = const Color(0xFFFF5470),
    this.info = const Color(0xFF38BDF8),
    this.purple = const Color(0xFFA855F7),
  });

  static const dark = JoyceColors(
    bg: Color(0xFF0A0B10),
    bg2: Color(0xFF12131B),
    cardSolid: Color(0xFF161823),
    card: Color(0x0AD4AF37),
    border: Color(0x38D4AF37),
    borderSubtle: Color(0x14FFFFFF),
    text: Color(0xFFF7F6F0),
    muted: Color(0xFFA4A093),
    input: Color(0xFF11121C),
    accent: Color(0xFFD4AF37),
    accentHover: Color(0xFFE8C65A),
    accent2: Color(0xFFF2D98D),
    accentDeep: Color(0xFF997519),
    btnText: Color(0xFF120E03),
    buttonGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF7D468), Color(0xFFD4AF37), Color(0xFF9E7518)],
      stops: [0.0, 0.5, 1.0],
    ),
  );

  static const light = JoyceColors(
    bg: Color(0xFFFAF9F5),
    bg2: Color(0xFFFFFFFF),
    cardSolid: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    border: Color(0x38B88A28),
    borderSubtle: Color(0x1FB88A28),
    text: Color(0xFF1B1914),
    muted: Color(0xFF6E695D),
    input: Color(0xFFF5F3EB),
    accent: Color(0xFFB88A28),
    accentHover: Color(0xFF9E731B),
    accent2: Color(0xFFCAA03E),
    accentDeep: Color(0xFF7A540A),
    btnText: Color(0xFFFFFFFF),
    buttonGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD8B24E), Color(0xFFB88A28), Color(0xFF8C6312)],
      stops: [0.0, 0.6, 1.0],
    ),
  );

  @override
  JoyceColors copyWith({
    Color? bg,
    Color? bg2,
    Color? cardSolid,
    Color? card,
    Color? border,
    Color? borderSubtle,
    Color? text,
    Color? muted,
    Color? input,
    Color? accent,
    Color? accentHover,
    Color? accent2,
    Color? accentDeep,
    Color? btnText,
    LinearGradient? buttonGradient,
  }) {
    return JoyceColors(
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      cardSolid: cardSolid ?? this.cardSolid,
      card: card ?? this.card,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      input: input ?? this.input,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accent2: accent2 ?? this.accent2,
      accentDeep: accentDeep ?? this.accentDeep,
      btnText: btnText ?? this.btnText,
      buttonGradient: buttonGradient ?? this.buttonGradient,
    );
  }

  @override
  JoyceColors lerp(ThemeExtension<JoyceColors>? other, double t) {
    if (other is! JoyceColors) return this;
    return this;
  }
}

class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, JoyceColors.dark);
  static ThemeData light() => _build(Brightness.light, JoyceColors.light);

  static ThemeData _build(Brightness brightness, JoyceColors c) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg2,
      cardColor: c.cardSolid,
      dividerColor: c.borderSubtle,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.btnText,
        secondary: c.accent2,
        onSecondary: c.btnText,
        error: c.bad,
        onError: Colors.white,
        surface: c.cardSolid,
        onSurface: c.text,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.text, fontSize: 14),
        bodyMedium: TextStyle(color: c.text, fontSize: 13),
        bodySmall: TextStyle(color: c.muted, fontSize: 12),
        titleLarge: TextStyle(
          color: c.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: c.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.input,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        hintStyle: TextStyle(color: c.muted, fontSize: 13),
        labelStyle: TextStyle(color: c.muted, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.accent, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.cardSolid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border),
        ),
      ),
      extensions: [c],
    );
  }
}

extension JoyceThemeContext on BuildContext {
  JoyceColors get joyce =>
      Theme.of(this).extension<JoyceColors>() ?? JoyceColors.dark;
}
