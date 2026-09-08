import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../constants/app_opacity.dart';
import '../constants/app_radius.dart';
import '../constants/app_typography.dart';

/// Builds [ThemeData] and exposes per-theme design tokens.
///
/// Abyss  (isThemeOne = true)  — ultra-deep dark, warm gold accent
/// Frost  (isThemeOne = false) — cool neutral light, indigo accent
abstract final class SoundMindTheme {
  // ──────────────────────── Color Accessors ────────────────────────

  static Color background(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssBase : AppColors.frostBase;

  static Color surface(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssSurface : AppColors.frostSurface;

  static Color cardColor(bool isThemeOne) =>
      isThemeOne
          ? const Color(0xFF0E172A).withValues(alpha: 0.75)
          : Colors.white.withValues(alpha: 0.98);

  static Color elevated(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssElevated : AppColors.frostElevated;

  static Color accent(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssAccent : AppColors.frostAccent;

  static Color accentSoft(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssAccentSoft : AppColors.frostAccentSoft;

  static Color bottomBar(bool isThemeOne) =>
      isThemeOne ? AppColors.abyssBottomBar : AppColors.frostBottomBar;

  static Color textPrimary(bool isThemeOne) =>
      isThemeOne ? Colors.white : const Color(0xFF0B132B);

  static Color textSecondary(bool isThemeOne) =>
      isThemeOne ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B);

  static Color textMuted(bool isThemeOne) =>
      isThemeOne ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  static Color glassBackground(bool isThemeOne) =>
      isThemeOne
          ? const Color(0xFF0D1527).withValues(alpha: 0.65)
          : Colors.white.withValues(alpha: 0.98);

  static Color glassBorder(bool isThemeOne) =>
      isThemeOne
          ? const Color(0xFF3898FF).withValues(alpha: 0.25)
          : const Color(0xFF0284C7).withValues(alpha: 0.32);

  static Color divider(bool isThemeOne) =>
      isThemeOne
          ? const Color(0xFF3898FF).withValues(alpha: 0.12)
          : const Color(0xFF0284C7).withValues(alpha: 0.12);


  // ──────────────────────── System UI Overlay ────────────────────────

  static SystemUiOverlayStyle overlayStyle(bool isThemeOne) =>
      isThemeOne
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: AppColors.abyssBase,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: AppColors.frostBase,
              systemNavigationBarIconBrightness: Brightness.dark,
            );

  // ──────────────────────── ThemeData ────────────────────────

  static ThemeData data({required bool isThemeOne}) {
    final bool isDark = isThemeOne;
    final Color bg = background(isDark);
    final Color fg = textPrimary(isDark);
    final Color acc = accent(isDark);
    final Color cardC = cardColor(isDark);

    final TextTheme interTextTheme = GoogleFonts.interTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    final ColorScheme colorScheme = isDark
        ? ColorScheme.dark(
            primary: acc,
            secondary: AppColors.abyssAccentSoft,
            surface: AppColors.abyssSurface,
            error: AppColors.error,
            onPrimary: Colors.black87,
            onSecondary: Colors.white,
            onSurface: Colors.white,
          )
        : ColorScheme.light(
            primary: acc,
            secondary: AppColors.frostAccentSoft,
            surface: AppColors.frostSurface,
            error: AppColors.error,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: const Color(0xFF0F0F1A),
          );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      cardColor: cardC,

      // Typography
      textTheme: interTextTheme,
      fontFamily: AppTypography.uiFont,

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: acc,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.displayFont,
          fontSize: AppTypography.appBarTitle,
          color: acc,
          letterSpacing: AppTypography.displayLetterSpacing,
        ),
        systemOverlayStyle: overlayStyle(isThemeOne),
      ),

      // Card
      cardTheme: CardThemeData(
        color: cardC,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.glassCard),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: AppOpacity.glassBorder)
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: divider(isDark),
        thickness: 1,
        space: 1,
      ),

      // Icons
      iconTheme: IconThemeData(
        color: fg.withValues(alpha: AppOpacity.iconMuted),
        size: 24,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: glassBackground(isDark),
        side: BorderSide(
          color: glassBorder(isDark),
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        labelStyle: TextStyle(
          fontFamily: AppTypography.uiFont,
          fontSize: AppTypography.labelL,
          color: fg,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) return acc;
          return isDark ? Colors.white38 : Colors.black26;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return acc.withValues(alpha: 0.35);
          }
          return isDark ? Colors.white12 : Colors.black12;
        }),
      ),

      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: acc,
        inactiveTrackColor: fg.withValues(alpha: AppOpacity.playerInactiveTrack),
        thumbColor: acc,
        overlayColor: acc.withValues(alpha: 0.15),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: acc,
        linearTrackColor: fg.withValues(alpha: 0.10),
      ),

      // Snack Bar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.uiFont,
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      // Bottom Sheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.abyssSurface : AppColors.frostSurface,
        modalBackgroundColor: isDark ? AppColors.abyssSurface : AppColors.frostSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        dragHandleColor: isDark ? Colors.white24 : Colors.black12,
        showDragHandle: true,
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassBackground(isDark),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: glassBorder(isDark), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: glassBorder(isDark), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: acc, width: 1.5),
        ),
        hintStyle: TextStyle(
          fontFamily: AppTypography.uiFont,
          color: fg.withValues(alpha: AppOpacity.textHint),
          fontSize: AppTypography.bodyM,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
