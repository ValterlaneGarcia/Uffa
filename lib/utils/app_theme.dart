import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  // ── Backgrounds ──────────────────────────────────────────────
  static const background  = Color(0xFFF5F6FA);
  static const surface     = Color(0xFFFFFFFF);
  static const card        = Color(0xFFFFFFFF);
  static const cardLight   = Color(0xFFF0F2F5);
  static const divider     = Color(0xFFECEFF4);

  // Dark variants
  static const backgroundDark = Color(0xFF0F1117);
  static const surfaceDark    = Color(0xFF1C1F2A);
  static const cardDark       = Color(0xFF1C1F2A);
  static const cardLightDark  = Color(0xFF252836);
  static const dividerDark    = Color(0xFF2E3244);

  // ── Brand ─────────────────────────────────────────────────────
  static const green       = Color(0xFF16A34A);
  static const greenLight  = Color(0xFFDCFCE7);
  static const greenDeep   = Color(0xFF15803D);

  static const blue        = Color(0xFF2563EB);
  static const blueLight   = Color(0xFFDBEAFE);
  static const blueDeep    = Color(0xFF1D4ED8);

  static const red         = Color(0xFFDC2626);
  static const redLight    = Color(0xFFFEE2E2);

  static const amber       = Color(0xFFD97706);
  static const amberLight  = Color(0xFFFEF3C7);

  static const purple      = Color(0xFF7C3AED);
  static const purpleLight = Color(0xFFEDE9FE);

  static const cyan        = Color(0xFF0891B2);

  // ── Text ──────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary  = Color(0xFF9CA3AF);

  static const textPrimaryDark   = Color(0xFFF1F5F9);
  static const textSecondaryDark = Color(0xFF94A3B8);
  static const textTertiaryDark  = Color(0xFF64748B);

  // Aliases kept for compatibility with existing screens
  static const white    = Color(0xFF111827);   // primary text on light bg
  static const grey     = Color(0xFF6B7280);
  static const greyDark = Color(0xFF374151);

  // ── Gradients ─────────────────────────────────────────────────
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [green, Color(0xFF059669)],
  );

  static const gradientHeader = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15803D), Color(0xFF16A34A)],
  );

  static const gradientCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
  );

  static const gradientVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, surface],
  );
}

class AppTheme {
  /// Build a light [ThemeData] using [primary] as the brand color.
  static ThemeData light({Color primary = AppColors.green}) => ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.light(
          primary: primary,
          secondary: AppColors.blue,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: primary,
          labelColor: primary,
          unselectedLabelColor: AppColors.textSecondary,
          dividerColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: primary,
          unselectedItemColor: AppColors.textSecondary,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          hintStyle: const TextStyle(color: AppColors.textTertiary),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textTertiary,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? primary
                : AppColors.cardLight,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: AppColors.textPrimary),
          bodyMedium: TextStyle(color: AppColors.textSecondary),
          labelLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      );

  /// Build a dark [ThemeData] using [primary] as the brand color.
  static ThemeData dark({Color primary = AppColors.green}) => ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        colorScheme: ColorScheme.dark(
          primary: primary,
          secondary: AppColors.blue,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimaryDark,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.textPrimaryDark,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.textPrimaryDark,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: const IconThemeData(color: AppColors.textPrimaryDark),
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.dividerDark, width: 1),
          ),
        ),
        tabBarTheme: TabBarThemeData(
          indicatorColor: primary,
          labelColor: primary,
          unselectedLabelColor: AppColors.textSecondaryDark,
          dividerColor: Colors.transparent,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          selectedItemColor: primary,
          unselectedItemColor: AppColors.textSecondaryDark,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: BorderSide(color: primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardLightDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          hintStyle: const TextStyle(color: AppColors.textTertiaryDark),
          labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textTertiaryDark,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? primary
                : AppColors.cardLightDark,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.dividerDark,
          thickness: 1,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
              color: AppColors.textPrimaryDark, fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(
              color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(
              color: AppColors.textPrimaryDark, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(
              color: AppColors.textPrimaryDark, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: AppColors.textPrimaryDark),
          bodyMedium: TextStyle(color: AppColors.textSecondaryDark),
          labelLarge: TextStyle(
              color: AppColors.textPrimaryDark, fontWeight: FontWeight.w600),
        ),
      );
}
// ─── BuildContext theme extensions ────────────────────────────────────────────
// Use these instead of AppColors.X constants in widget build() methods so that
// light/dark mode and the user-chosen primary color are always reflected.
//
// Usage:  context.primary   context.surface   context.textPrimary  etc.

extension AppThemeContext on BuildContext {
  ColorScheme get _cs => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // ── Brand / primary ────────────────────────────────────────────
  Color get primary        => _cs.primary;
  Color get primaryLight   => _cs.primary.withOpacity(0.12);

  // ── Backgrounds ────────────────────────────────────────────────
  Color get appBackground  => isDark ? AppColors.backgroundDark  : AppColors.background;
  Color get appSurface     => isDark ? AppColors.surfaceDark      : AppColors.surface;
  Color get appCard        => isDark ? AppColors.cardDark         : AppColors.card;
  Color get appCardLight   => isDark ? AppColors.cardLightDark    : AppColors.cardLight;
  Color get appDivider     => isDark ? AppColors.dividerDark      : AppColors.divider;

  // ── Text ───────────────────────────────────────────────────────
  Color get textPrimary    => isDark ? AppColors.textPrimaryDark   : AppColors.textPrimary;
  Color get textSecondary  => isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
  Color get textTertiary   => isDark ? AppColors.textTertiaryDark  : AppColors.textTertiary;
}