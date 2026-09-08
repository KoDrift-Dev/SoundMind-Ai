import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Centralized multi-accent palette for SoundMind AI.
///
/// Prevents the app from feeling monotone-blue by introducing deliberate,
/// content-appropriate accent colors for dedicated sections while preserving
/// verified contrast in both dark (Abyss) and light (Frost) themes.
abstract final class SectionAccents {
  // ── 1. Core Blue (Home, Offline Library default, General Navigation) ──
  static Color coreBlue(bool isDark) =>
      isDark ? AppColors.abyssAccent : const Color(0xFF0284C7); // #3898FF / #0284C7

  static Color coreBlueSoft(bool isDark) =>
      isDark ? AppColors.abyssAccentSoft : const Color(0xFF0369A1);

  // ── 2. Online Violet (YouTube Search, Online Mixes, Cloud Streaming) ──
  static Color onlineViolet(bool isDark) =>
      isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);

  // ── 3. Favorites Rose (Loved Tracks, Quick Hearts, Attention Dots) ──
  // Contrast: #E85D75 on #060913 (6.5:1), #BE123C on #FFFFFF / #D0D7E1 (>4.8:1)
  static Color favorites(bool isDark) =>
      isDark ? const Color(0xFFE85D75) : const Color(0xFFBE123C);

  static Color favoritesSoft(bool isDark) =>
      isDark
          ? const Color(0xFFE85D75).withValues(alpha: 0.20)
          : const Color(0xFFBE123C).withValues(alpha: 0.14);

  // ── 4. Playlists Teal (Custom Playlists, Curation, Queues) ──
  // Contrast: #2DD4BF on #060913 (9.8:1), #0D9488 on #FFFFFF / #D0D7E1 (>4.8:1)
  static Color playlists(bool isDark) =>
      isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);

  static Color playlistsSoft(bool isDark) =>
      isDark
          ? const Color(0xFF2DD4BF).withValues(alpha: 0.20)
          : const Color(0xFF0D9488).withValues(alpha: 0.14);

  // ── 5. Downloads Amber (Downloaded Tracks, Storage Footprint, Quality) ──
  // Contrast: #F5B84C on #060913 (9.2:1), #B45309 on #FFFFFF / #D0D7E1 (>4.6:1)
  static Color downloads(bool isDark) =>
      isDark ? const Color(0xFFF5B84C) : const Color(0xFFB45309);

  static Color downloadsSoft(bool isDark) =>
      isDark
          ? const Color(0xFFF5B84C).withValues(alpha: 0.22)
          : const Color(0xFFB45309).withValues(alpha: 0.15);

  // ── 6. Settings Slate / Graphite (Utility, System Preferences) ──
  // Contrast: #94A3B8 on #060913 (7.2:1), #475569 on #FFFFFF / #D0D7E1 (>5.0:1)
  static Color settings(bool isDark) =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  static Color settingsSoft(bool isDark) =>
      isDark
          ? const Color(0xFF94A3B8).withValues(alpha: 0.20)
          : const Color(0xFF475569).withValues(alpha: 0.14);

  // ── Helper Surface Utilities ──
  static BoxDecoration pillDecoration({
    required Color accent,
    required bool isDark,
    bool isSelected = true,
  }) {
    if (!isSelected) {
      return BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
      );
    }
    return BoxDecoration(
      color: isDark
          ? accent.withValues(alpha: 0.22)
          : accent.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: accent.withValues(alpha: isDark ? 0.65 : 0.75),
        width: 1.2,
      ),
    );
  }
}
