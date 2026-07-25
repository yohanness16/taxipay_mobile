import 'package:flutter/material.dart';

/// Central design language for the app: a "modern fintech dashboard" look
/// -- deep charcoal surfaces, a vivid green primary (keeps the Telebirr
/// association drivers already trust), and a warm amber accent for
/// highlights/streaks -- instead of default flat Material white.
class AppTheme {
  AppTheme._();

  static const primary = Color(0xFF00C766);
  static const primaryDark = Color(0xFF00A651);
  static const accentAmber = Color(0xFFFFB020);
  static const surfaceDark = Color(0xFF12181A);
  static const surfaceCard = Color(0xFF1B2422);
  static const bgLight = Color(0xFFF4F7F5);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primaryDark,
      secondary: accentAmber,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: bgLight,
      textTheme: _textTheme(base.textTheme, Colors.black87),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          side: const BorderSide(color: primaryDark, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryDark, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? Colors.white : Colors.white,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? primaryDark : Colors.grey.shade300,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 4,
        height: 66,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryDark.withOpacity(0.14),
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(MaterialState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(MaterialState.selected) ? primaryDark : Colors.grey.shade600,
          ),
        ),
        iconTheme: MaterialStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(MaterialState.selected) ? primaryDark : Colors.grey.shade600),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        width: 300,
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade200, thickness: 1),
    );
  }

  /// Modern black-and-green dark theme -- true near-black surfaces (not
  /// just inverted grey) with the same brand green carried through as the
  /// primary accent, so it feels like a deliberate premium look rather
  /// than an auto-generated dark mode.
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      secondary: accentAmber,
      surface: surfaceCard,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF000000),
      textTheme: _textTheme(base.textTheme, Colors.white.withOpacity(0.94)),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withOpacity(0.6), width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? Colors.black : Colors.white70,
        ),
        trackColor: MaterialStateProperty.resolveWith(
          (states) => states.contains(MaterialState.selected) ? primary : Colors.white24,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 4,
        height: 66,
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(MaterialState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(MaterialState.selected) ? primary : Colors.white60,
          ),
        ),
        iconTheme: MaterialStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(MaterialState.selected) ? primary : Colors.white60),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        width: 300,
        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withOpacity(0.08), thickness: 1),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) => base.copyWith(
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: color),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: color),
        bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500, color: color),
        bodyMedium: base.bodyMedium?.copyWith(color: color),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      );
}
