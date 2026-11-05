import 'package:flutter/material.dart';

import '../models/models.dart';

/// 목업 기준 다크 테마 토큰.
class AppColors {
  static const bg = Color(0xFF111216);
  static const surface = Color(0xFF1B1D23);
  static const surfaceHigh = Color(0xFF24272F);
  static const divider = Color(0xFF2A2D35);
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF9097A3);
  static const textTertiary = Color(0xFF666C78);
  static const accent = Color(0xFFF2A066);
  static const onAccent = Color(0xFF1A1206);
  static const danger = Color(0xFFE5484D);

  static const krUp = Color(0xFFF0616D);
  static const krDown = Color(0xFF5B8DEF);
  static const glUp = Color(0xFF3DBE7A);
  static const glDown = Color(0xFFF0616D);

  static Color change(double? pct, ChangeColorScheme scheme) {
    if (pct == null || pct == 0) return textSecondary;
    final up = pct > 0;
    return switch (scheme) {
      ChangeColorScheme.korean => up ? krUp : krDown,
      ChangeColorScheme.global => up ? glUp : glDown,
    };
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      surface: AppColors.bg,
      onSurface: AppColors.textPrimary,
    ),
    dividerColor: AppColors.divider,
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bg,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? AppColors.textPrimary
              : AppColors.textTertiary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected)
              ? AppColors.textPrimary
              : AppColors.textTertiary,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? AppColors.accent : null),
      checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
    ),
    radioTheme: const RadioThemeData(
      fillColor: WidgetStatePropertyAll(AppColors.accent),
    ),
  );
}

class TextStyles {
  static const section = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
  static const symbol = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const sub = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const price = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const caption = TextStyle(fontSize: 12, color: AppColors.textTertiary);
}
