import 'package:flutter/material.dart';

/// Central design language for the app: a "modern fintech dashboard" look
/// -- deep charcoal surfaces, a vivid green primary (keeps the Telebirr
/// association drivers already trust), and a warm amber accent for
/// highlights/streaks -- instead of default flat Material white.
///
/// Everything visual should come from here rather than being spelled out
/// at the call site. Screens that hardcode their own greys are the reason
/// several surfaces used to look correct in light mode and washed-out or
/// invisible in dark mode; the [AppThemeX] context extension at the bottom
/// exists so a screen can ask for "the subtle text colour" without needing
/// to know which brightness it is currently rendering under.
class AppTheme {
  AppTheme._();

  // --- Brand -------------------------------------------------------------
  static const primary = Color(0xFF00C766);
  static const primaryDark = Color(0xFF00A651);
  static const accentAmber = Color(0xFFFFB020);

  /// Semantic accents. Screens used to reach for raw Material swatches
  /// (Colors.blue, Colors.deepOrange, Colors.purple...) which sit slightly
  /// off the brand's hue family and read as clashing next to the green.
  /// These are tuned to sit alongside it.
  static const danger = Color(0xFFE5484D);
  static const info = Color(0xFF3B82F6);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);

  // --- Surfaces ----------------------------------------------------------
  static const surfaceDark = Color(0xFF12181A);
  static const surfaceCard = Color(0xFF1B2422);
  static const bgLight = Color(0xFFF4F7F5);

  // --- Spacing scale -----------------------------------------------------
  // A 4pt scale. Using these instead of ad-hoc numbers is what makes
  // unrelated screens line up with each other.
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;

  // --- Corner radii ------------------------------------------------------
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 26;

  // --- Motion ------------------------------------------------------------
  // One set of durations/curves so transitions across the app feel like
  // they belong to the same product. easeOutCubic is the default because
  // it decelerates into place, which reads as "settled" rather than abrupt.
  static const Duration dFast = Duration(milliseconds: 160);
  static const Duration dBase = Duration(milliseconds: 260);
  static const Duration dSlow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve easeEmphasised = Curves.easeOutBack;

  /// Soft ambient shadow for raised surfaces. Deliberately tinted toward
  /// the brand green rather than pure black when [tint] is supplied -- a
  /// coloured shadow under a coloured card is what makes it read as
  /// "glowing" instead of "cut out".
  static List<BoxShadow> shadow({Color? tint, double opacity = 0.18, double blur = 18, double y = 8}) => [
        BoxShadow(
          color: (tint ?? Colors.black).withValues(alpha: opacity),
          blurRadius: blur,
          offset: Offset(0, y),
        ),
      ];

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
      textTheme: _textTheme(base.textTheme, const Color(0xFF111827)),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Color(0xFF111827),
        titleTextStyle: TextStyle(
          color: Color(0xFF111827),
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: const BorderSide(color: Color(0xFFE6EAE8)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          side: const BorderSide(color: primaryDark, width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: Color(0xFFD8DEDB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: Color(0xFFD8DEDB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: primaryDark, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primaryDark : const Color(0xFFD8DEDB),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryDark.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primaryDark : const Color(0xFF6B7280),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primaryDark : const Color(0xFF6B7280),
          ),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        width: 300,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE6EAE8), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F2937),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primaryDark),
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
      scaffoldBackgroundColor: Colors.black,
      textTheme: _textTheme(base.textTheme, Colors.white.withValues(alpha: 0.94)),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.6), width: 1.4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: primary, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.black : Colors.white70,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : Colors.white24,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.2),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? primary : Colors.white60,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? primary : Colors.white60),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        width: 300,
        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.08), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceCard,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }

  static TextTheme _textTheme(TextTheme base, Color color) => base.copyWith(
        headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, color: color),
        headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color),
        titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: color),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
        titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: color),
        bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500, color: color),
        bodyMedium: base.bodyMedium?.copyWith(color: color),
        labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      );
}

/// Brightness-aware neutrals.
///
/// Screens previously hardcoded light-mode greys (`Colors.grey.shade100`
/// fills, `Colors.grey.shade600` captions, `Colors.amber.shade50` banners),
/// which meant every one of those surfaces was wrong in dark mode -- a pale
/// grey circle on a black background, or near-black caption text on a
/// near-black card. Asking the context for the role instead of naming a
/// swatch keeps both themes correct from a single call site.
extension AppThemeX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// De-emphasised body text: captions, timestamps, helper copy.
  Color get subtleText => isDark ? Colors.white60 : const Color(0xFF6B7280);

  /// Even quieter than [subtleText] -- trailing metadata, disabled hints.
  Color get faintText => isDark ? Colors.white38 : const Color(0xFF9CA3AF);

  /// Neutral fill for chips, empty-state medallions, inert containers.
  Color get faintFill => isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFEFF2F0);

  /// Hairline borders on cards and dividers.
  Color get hairline => isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE6EAE8);

  /// Tinted background for a semantic accent (warning banners, stat cards)
  /// that stays legible in both themes -- dark mode needs a much lower
  /// alpha over black than light mode does over white.
  Color tintedSurface(Color accent) => accent.withValues(alpha: isDark ? 0.16 : 0.10);
}
