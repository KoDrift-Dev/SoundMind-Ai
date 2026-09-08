import 'package:flutter/material.dart';

/// Centralized spacing, padding, and margin values — systematic scale.
abstract final class AppSpacing {
  // ──────────────────────── Raw Spacing Scale ────────────────────────
  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 16;
  static const double lg   = 24;
  static const double xl   = 36;
  static const double xxl  = 52;

  // ──────────────────────── Screen Layout ────────────────────────
  static const double horizontalScreen    = 20;
  static const double bottomNavClearance  = 140;
  static const double miniPlayerHeight    = 72;

  // ──────────────────────── EdgeInsets ────────────────────────
  static const EdgeInsets screenHorizontal =
      EdgeInsets.symmetric(horizontal: horizontalScreen);

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: horizontalScreen, vertical: md);

  static const EdgeInsets homeScrollPadding =
      EdgeInsets.only(top: 8, bottom: bottomNavClearance);

  static const EdgeInsets settingsScrollPadding =
      EdgeInsets.fromLTRB(20, 10, 20, bottomNavClearance);

  static const EdgeInsets searchTitlePadding =
      EdgeInsets.fromLTRB(20, 12, 20, 6);

  static const EdgeInsets playerHeaderPadding =
      EdgeInsets.fromLTRB(20, 14, 20, 6);

  static const EdgeInsets playerBottomPadding =
      EdgeInsets.fromLTRB(22, 54, 22, 118);

  static const EdgeInsets greetingPadding =
      EdgeInsets.fromLTRB(20, 12, 20, 4);

  static const EdgeInsets bottomNavOuter =
      EdgeInsets.only(left: 14, right: 14, bottom: 16);

  static const EdgeInsets bottomNavInner =
      EdgeInsets.symmetric(horizontal: 10, vertical: 10);

  // ──────────────────────── Gap Constants ────────────────────────
  static const double sectionGapLarge  = 32;
  static const double sectionGapMedium = 24;
  static const double sectionGapSmall  = 16;
  static const double chipSpacing      = 10;
  static const double railItemSpacing  = 14;
  static const double categoryPillHeight = 42;
  static const double cardGap          = 12;
  static const double tileGap          = 8;

  // ──────────────────────── Common SizedBox Widgets ────────────────────────
  static const Widget gapXS  = SizedBox(height: xs);
  static const Widget gapSM  = SizedBox(height: sm);
  static const Widget gapMD  = SizedBox(height: md);
  static const Widget gapLG  = SizedBox(height: lg);
  static const Widget gapXL  = SizedBox(height: xl);
  static const Widget gapHXS = SizedBox(width: xs);
  static const Widget gapHSM = SizedBox(width: sm);
  static const Widget gapHMD = SizedBox(width: md);
  static const Widget gapHLG = SizedBox(width: lg);
}
