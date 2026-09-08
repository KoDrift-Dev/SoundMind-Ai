/// Centralized opacity / alpha values for glass surfaces and text hierarchy.
///
/// Glass surface system (dark theme):
///   glassSubtle    — hairline tint, used for inset/nested surfaces
///   glassPrimary   — standard card/tile background
///   glassSecondary — slightly stronger card
///   glassFloating  — floating elements like mini-player, bottom nav
///
/// Multiply any glass alpha by 0.5 for the Frost (light) theme.
abstract final class AppOpacity {
  // ──────────────────────── Glass Backgrounds (dark) ────────────────────────
  static const double glassSubtle            = 0.05;
  static const double glassBackground        = 0.10;   // Raised from 0.06
  static const double glassPrimary           = 0.12;
  static const double glassSecondary         = 0.09;
  static const double glassFloating          = 0.18;   // Mini-player, nav pill

  // ──────────────────────── Glass Borders ────────────────────────
  static const double glassBorder            = 0.14;   // Raised from 0.08
  static const double glassActionBorder      = 0.18;   // Raised from 0.10
  static const double glassBorderStrong      = 0.22;   // Accent borders

  // ──────────────────────── Legacy aliases (backward compat) ────────────────────────
  static const double glassBackgroundSubtle  = glassSubtle;

  // ──────────────────────── Text Hierarchy ────────────────────────
  static const double textPrimary            = 1.00;
  static const double textSecondary          = 0.70;   // Raised from 0.50
  static const double textMuted              = 0.55;
  static const double textSubtle             = 0.45;
  static const double textHint               = 0.35;
  static const double textFaint              = 0.30;

  // ──────────────────────── Icon Opacity ────────────────────────
  static const double iconPrimary            = 0.90;
  static const double iconMuted              = 0.55;
  static const double iconFaint              = 0.40;

  // ──────────────────────── Accent ────────────────────────
  static const double accentSoft             = 0.12;
  static const double accentLink             = 0.90;   // Raised from 0.85
  static const double accentGlow             = 0.30;

  // ──────────────────────── Notification / Badge ────────────────────────
  static const double notificationGlow       = 0.55;

  // ──────────────────────── Modal / Overlay ────────────────────────
  static const double modalBackground        = 0.85;
  static const double overlayScrim           = 0.60;

  // ──────────────────────── Player ────────────────────────
  static const double playerHeader           = 0.60;
  static const double playerSubheader        = 0.88;
  static const double playerInactiveTrack    = 0.12;
  static const double playerTime             = 0.50;
  static const double playerControlInactive  = 0.55;
  static const double playerGlowPlaying      = 0.50;
  static const double playerGlowIdle         = 0.28;

  // ──────────────────────── Vinyl ────────────────────────
  static const double vinylAccentRing        = 0.45;
  static const double vinylGlow              = 0.20;
  static const double vinylShadow            = 0.65;
  static const double vinylLabelBorder       = 0.10;
  static const double vinylGroove            = 0.04;
  static const double vinylSpokeEven         = 0.08;
  static const double vinylSpokeOdd          = 0.04;
  static const double vinylTick              = 0.95;
  static const double vinylTickGlow          = 0.28;
  static const double vinylSheen             = 0.10;

  // ──────────────────────── Waveform ────────────────────────
  static const double waveformBackground     = 0.40;

  // ──────────────────────── Other ────────────────────────
  static const double discShadow             = 0.48;
  static const double settingsGroupLabel     = 0.45;
  static const double artworkTint            = 0.20;
}
