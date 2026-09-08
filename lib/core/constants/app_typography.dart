/// Centralized typography references — font families and reusable size scale.
///
/// Font hierarchy:
///   displayFont (Avoiste)  — Brand identity, headers, NOW PLAYING label
///   bodyFont    (JakeKeller) — Thematic accents, pill labels
///   uiFont      (Inter)    — All readable UI text: titles, subtitles, captions
abstract final class AppTypography {
  // ──────────────────────── Font Families ────────────────────────
  static const String displayFont = 'Avoiste';
  static const String bodyFont    = 'JakeKeller';
  static const String uiFont      = 'Inter';   // Google Fonts — primary readable UI

  // ──────────────────────── Display Scale (Avoiste) ────────────────────────
  static const double displayXL   = 48;   // Hero / splash
  static const double displayL    = 36;   // Large page titles
  static const double displayM    = 28;   // App bar / modal titles
  static const double displayS    = 22;   // Section headings

  // ──────────────────────── Heading Scale (Inter Bold) ────────────────────────
  static const double headingXL   = 32;
  static const double headingL    = 26;
  static const double headingM    = 22;
  static const double headingS    = 18;
  static const double headingXS   = 16;

  // ──────────────────────── Body Scale (Inter) ────────────────────────
  static const double bodyL       = 16;
  static const double bodyM       = 14;
  static const double bodyS       = 13;

  // ──────────────────────── Label / Caption Scale ────────────────────────
  static const double labelL      = 13;
  static const double labelM      = 12;
  static const double labelS      = 11;
  static const double caption     = 10;

  // ──────────────────────── Legacy aliases (backward compat) ────────────────────────
  static const double appBarTitle           = displayM;
  static const double screenTitle           = displayS;
  static const double sectionTitle          = headingS;
  static const double subsectionTitle       = headingXS;
  static const double modalTitle            = headingM;
  static const double greetingHeadline      = headingL;
  static const double greetingSubtext       = bodyS;
  static const double pillLabel             = labelL;
  static const double seeAll                = labelM;
  static const double trackTitle            = bodyM;
  static const double trackArtist           = bodyS;
  static const double trackCountLabel       = caption;
  static const double settingsLabel         = bodyL;
  static const double settingsSubLabel      = labelM;
  static const double settingsGroup         = labelS;
  static const double settingsItem          = bodyM;
  static const double searchField           = bodyL;
  static const double searchChip            = bodyS;
  static const double playerNowPlaying      = labelS;
  static const double playerSession         = caption;
  static const double playerTrackTitle      = headingXL;
  static const double playerTrackArtist     = bodyL;
  static const double playerTime            = labelM;
  static const double aiCollectionTitle     = headingM;
  static const double aiIndexedCount        = bodyM;

  // ──────────────────────── Letter Spacing ────────────────────────
  static const double greetingLetterSpacing         = 1.2;
  static const double settingsGroupLetterSpacing     = 2.4;
  static const double playerNowPlayingLetterSpacing  = 3.6;
  static const double playerSessionLetterSpacing     = 1.6;
  static const double displayLetterSpacing           = 0.5;
  static const double labelLetterSpacing             = 0.3;
}
