/// Centralized border radius values — systematic scale.
abstract final class AppRadius {
  // ──────────────────────── Systematic Scale ────────────────────────
  static const double xs   = 6;
  static const double sm   = 10;
  static const double md   = 16;
  static const double lg   = 22;
  static const double xl   = 30;
  static const double xxl  = 40;
  static const double full = 999;  // Pill / circle

  // ──────────────────────── Legacy aliases (backward compat) ────────────────────────
  static const double bottomNav        = xl;
  static const double pill             = xl;
  static const double pillSmall        = lg;
  static const double glassCard        = lg;
  static const double glassIcon        = sm;
  static const double artwork          = md;
  static const double appIcon          = sm;
  static const double modalTop         = xl;
  static const double actionPill       = full;
  static const double trackTileArt     = sm;
  static const double aiCollectionTile = md;
}
