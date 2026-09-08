import 'package:flutter/material.dart';

/// Centralized color palette — values must not change without design approval.
///
/// Two premium themes:
///   Abyss  — ultra-deep dark, warm gold accent, violet secondary (isThemeOne = true)
///   Frost  — cool light-neutral, indigo accent, violet secondary (isThemeOne = false)
abstract final class AppColors {
  // ──────────────────────── Abyss (Dark Theme - from dark-bg.png) ───────────
  static const Color abyssBase        = Color(0xFF060913);  // Deep obsidian navy
  static const Color abyssSurface     = Color(0xFF0D1424);  // Cards, sheets
  static const Color abyssCard        = Color(0xFF111B30);  // Elevated cards
  static const Color abyssElevated    = Color(0xFF17233D);  // Floating elements
  static const Color abyssAccent      = Color(0xFF3898FF);  // Electric neon blue
  static const Color abyssAccentSoft  = Color(0xFF00D2FF);  // Vibrant cyan wave
  static const Color abyssBottomBar   = Color(0xFF0A0F1F);  // Nav surface

  // ──────────────────────── Frost (Light Theme - from light-bg.png) ──────────
  static const Color frostBase        = Color(0xFFD0D7E1);  // Noticeably dimmed cool grey
  static const Color frostSurface     = Color(0xFFF8FAFC);  // Cards, sheets
  static const Color frostCard        = Color(0xFFF8FAFC);  // Elevated cards
  static const Color frostElevated    = Color(0xFFB0BBD1);  // Floating elements
  static const Color frostAccent      = Color(0xFF0284C7);  // Vivid ocean sky blue
  static const Color frostAccentSoft  = Color(0xFF2563EB);  // Electric royal blue
  static const Color frostBottomBar   = Color(0xFFF8FAFC);  // Nav surface

  // ──────────────────────── Legacy aliases (isThemeOne) ────────────────────────
  static const Color themeOneBackground = abyssBase;
  static const Color themeOneAccent     = abyssAccent;
  static const Color themeOneBottomBar  = abyssBottomBar;

  static const Color themeTwoBackground = frostBase;
  static const Color themeTwoAccent     = frostAccent;
  static const Color themeTwoBottomBar  = frostBottomBar;


  // ──────────────────────── Semantic System Colors ────────────────────────
  static const Color success    = Color(0xFF34D399);
  static const Color warning    = Color(0xFFFBBF24);
  static const Color error      = Color(0xFFF87171);
  static const Color info       = Color(0xFF60A5FA);

  // ──────────────────────── Shared Void Surfaces (Player) ────────────────────────
  static const Color playerBackground = Color(0xFF050508);
  static const Color voidOverlay      = Color(0xFF05050A);
  static const Color voidDeep         = Color(0xFF030307);
  static const Color radialOverlay    = Color(0xE6020205);

  // ──────────────────────── Vinyl Colors (Player) ────────────────────────
  static const Color vinylInnerDark = Color(0xFF141418);
  static const Color vinylOuterDark = Color(0xFF030307);

  // ──────────────────────── Void Wave Palette (Player) ────────────────────────
  static const List<Color> voidWavePalette = [
    Color(0xFF1E1030),
    Color(0xFF0F1E30),
    Color(0xFF151030),
    Color(0xFF251020),
  ];

  // ──────────────────────── Semantic shorthands ────────────────────────
  static const Color selectedForeground = Colors.black87;
  static const Color white              = Colors.white;
  static const Color white70            = Colors.white70;
  static const Color white54            = Colors.white54;
  static const Color white60            = Colors.white60;
  static const Color white10            = Colors.white10;
  static const Color white24            = Colors.white24;
  static const Color black12            = Colors.black12;
  static const Color transparent        = Colors.transparent;
}
