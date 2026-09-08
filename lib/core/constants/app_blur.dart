/// Centralized backdrop blur sigma values — 3-tier glass system.
abstract final class AppBlur {
  // ──────────────────────── 3-Tier Glass System ────────────────────────
  /// Subtle glass — track tiles, chips, secondary surfaces
  static const double glass1 = 8;
  /// Standard glass — cards, list tiles, modals
  static const double glass2 = 16;
  /// Heavy glass — player background, bottom sheets, ambient layers
  static const double glass3 = 28;
  /// Ultra blur — full-screen background frosting
  static const double glass4 = 48;

  // ──────────────────────── Legacy aliases (backward compat) ────────────────────────
  static const double standard   = glass2;
  static const double modal      = glass2;
  static const double actionPill = glass2;
  static const double waveform   = glass1;
  static const double voidWaveMask = 70;
}
