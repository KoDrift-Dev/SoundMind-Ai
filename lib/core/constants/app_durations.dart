/// Centralized animation and timing durations.
abstract final class AppDurations {
  // ──────────────────────── Micro-interaction Scale ────────────────────────
  static const Duration instant  = Duration(milliseconds: 80);
  static const Duration fast     = Duration(milliseconds: 140);
  static const Duration normal   = Duration(milliseconds: 240);
  static const Duration slow     = Duration(milliseconds: 400);
  static const Duration xslow    = Duration(milliseconds: 600);

  // ──────────────────────── Page / Navigation ────────────────────────
  static const Duration page         = Duration(milliseconds: 320);
  static const Duration pageReverse  = Duration(milliseconds: 260);
  static const Duration modal        = Duration(milliseconds: 380);

  // ──────────────────────── Ambient / Background ────────────────────────
  static const Duration ambientBlob  = Duration(seconds: 7);
  static const Duration ambientCycle = Duration(seconds: 10);

  // ──────────────────────── Legacy aliases (backward compat) ────────────────────────
  static const Duration pillTab      = normal;
  static const Duration categoryPill = Duration(milliseconds: 220);
  static const Duration playerToggle = Duration(milliseconds: 260);
  static const Duration waveformBar  = Duration(milliseconds: 130);
  static const Duration snackbarShort  = Duration(seconds: 1);
  static const Duration snackbarMedium = Duration(seconds: 2);

  // Player physics — unchanged
  static const Duration playerRotation  = Duration(seconds: 9);
  static const Duration playerBreath    = Duration(milliseconds: 1100);
  static const Duration playerWave      = Duration(seconds: 10);
  static const Duration playerIntensity = Duration(milliseconds: 500);
  static const Duration playerBar       = Duration(milliseconds: 1800);
  static const Duration playerCycle     = Duration(seconds: 6);
}
