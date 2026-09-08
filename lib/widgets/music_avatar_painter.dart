import 'package:flutter/material.dart';

/// Distinct silhouette styles for the music avatar bust.
enum AvatarSilhouette {
  /// Rounder, shorter hair silhouette outline with clean geometric curves.
  styleA,

  /// More voluminous, longer flowing hair silhouette outline.
  styleB,
}

/// Configuration object representing a curated music avatar preset.
class MusicAvatarConfig {
  final String id;
  final String label;
  final AvatarSilhouette silhouette;
  final List<Color> gradientColors;
  final bool showHeadphones;

  const MusicAvatarConfig({
    required this.id,
    required this.label,
    required this.silhouette,
    required this.gradientColors,
    this.showHeadphones = true,
  });
}

/// Curated set of 12 distinct music-themed avatar presets.
///
/// Hand-picked configurations alternating between Style A and Style B,
/// paired with SoundMind AI multi-accent gradients, and headphones on for all.
const List<MusicAvatarConfig> kMusicAvatarPresets = [
  // 1. Cyber Beat (Core Blue -> Electric Indigo) - Style A
  MusicAvatarConfig(
    id: 'music_cyber_blue',
    label: 'Cyber Beat',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
    showHeadphones: true,
  ),

  // 2. Synth Wave (Online Violet -> Deep Purple) - Style B
  MusicAvatarConfig(
    id: 'music_synth_violet',
    label: 'Synth Wave',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
    showHeadphones: true,
  ),

  // 3. Sunset Vibe (Favorites Rose -> Downloads Amber) - Style A
  MusicAvatarConfig(
    id: 'music_rose_sunset',
    label: 'Sunset Vibe',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFFE85D75), Color(0xFFF59E0B)],
    showHeadphones: true,
  ),

  // 4. Teal Groove (Playlists Teal -> Core Blue) - Style B
  MusicAvatarConfig(
    id: 'music_teal_groove',
    label: 'Teal Groove',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFF2DD4BF), Color(0xFF0284C7)],
    showHeadphones: true,
  ),

  // 5. Amber Fire (Downloads Amber -> Fire Red) - Style A
  MusicAvatarConfig(
    id: 'music_amber_fire',
    label: 'Amber Fire',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFFF5B84C), Color(0xFFEF4444)],
    showHeadphones: true,
  ),

  // 6. Neon Pulse (Fuchsia Pink -> Violet) - Style B
  MusicAvatarConfig(
    id: 'music_neon_pulse',
    label: 'Neon Pulse',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFFF472B6), Color(0xFF8B5CF6)],
    showHeadphones: true,
  ),

  // 7. Emerald Chill (Mint Emerald -> Deep Teal) - Style A
  MusicAvatarConfig(
    id: 'music_emerald_chill',
    label: 'Emerald Chill',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFF34D399), Color(0xFF0D9488)],
    showHeadphones: true,
  ),

  // 8. Midnight Bass (Soft Indigo -> Sky Blue) - Style B
  MusicAvatarConfig(
    id: 'music_midnight_bass',
    label: 'Midnight Bass',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFF818CF8), Color(0xFF0EA5E9)],
    showHeadphones: true,
  ),

  // 9. Acoustic Gold (Warm Amber -> Golden Honey) - Style A
  MusicAvatarConfig(
    id: 'music_acoustic_gold',
    label: 'Acoustic Gold',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFFFBBF24), Color(0xFFD97706)],
    showHeadphones: true,
  ),

  // 10. Cosmic Drift (Purple Orchid -> Bright Cyan) - Style B
  MusicAvatarConfig(
    id: 'music_cosmic_drift',
    label: 'Cosmic Drift',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFFC084FC), Color(0xFF38BDF8)],
    showHeadphones: true,
  ),

  // 11. Crimson Beat (Rose Petal -> Deep Crimson) - Style A
  MusicAvatarConfig(
    id: 'music_crimson_beat',
    label: 'Crimson Beat',
    silhouette: AvatarSilhouette.styleA,
    gradientColors: [Color(0xFFFB7185), Color(0xFFBE123C)],
    showHeadphones: true,
  ),

  // 12. Deep Abyss (Ocean Blue -> Midnight Slate) - Style B
  MusicAvatarConfig(
    id: 'music_deep_abyss',
    label: 'Deep Abyss',
    silhouette: AvatarSilhouette.styleB,
    gradientColors: [Color(0xFF60A5FA), Color(0xFF1E293B)],
    showHeadphones: true,
  ),
];

/// Fallback resolver for previous icon-based preset IDs.
MusicAvatarConfig resolveAvatarConfig(String presetId) {
  // Direct match
  for (final config in kMusicAvatarPresets) {
    if (config.id == presetId) return config;
  }

  // Graceful legacy icon ID mappings
  switch (presetId) {
    case 'headphones':
      return kMusicAvatarPresets[0]; // music_cyber_blue
    case 'music':
      return kMusicAvatarPresets[1]; // music_synth_violet
    case 'mic':
      return kMusicAvatarPresets[2]; // music_rose_sunset
    case 'wave':
      return kMusicAvatarPresets[3]; // music_teal_groove
    case 'fire':
      return kMusicAvatarPresets[4]; // music_amber_fire
    case 'dj':
      return kMusicAvatarPresets[5]; // music_neon_pulse
    case 'star':
      return kMusicAvatarPresets[8]; // music_acoustic_gold
    case 'ai':
      return kMusicAvatarPresets[11]; // music_deep_abyss
    default:
      return kMusicAvatarPresets[0];
  }
}

/// CustomPainter that renders a flat bust silhouette with transparent background,
/// gradient fill, and headphone iconography at a fixed 200x200 logical coordinate space.
class MusicAvatarPainter extends CustomPainter {
  final AvatarSilhouette silhouette;
  final List<Color> gradientColors;
  final bool showHeadphones;
  final Color? headphonesColor;

  const MusicAvatarPainter({
    required this.silhouette,
    required this.gradientColors,
    this.showHeadphones = true,
    this.headphonesColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Scale from logical 200x200 canvas to requested display size
    final scaleX = size.width / 200.0;
    final scaleY = size.height / 200.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    // 1. Prepare gradient fill for silhouette
    final Rect bounds = const Rect.fromLTWH(0, 0, 200, 200);
    final effectiveColors = gradientColors.length >= 2
        ? gradientColors
        : [const Color(0xFF38BDF8), const Color(0xFF1D4ED8)];

    final Paint silhouettePaint = Paint()
      ..shader = LinearGradient(
        colors: effectiveColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 2. Build the bust silhouette path (head, hair, neck, shoulders)
    final Path silhouettePath = silhouette == AvatarSilhouette.styleA
        ? _buildStyleAPath()
        : _buildStyleBPath();

    // Draw the silhouette (fully transparent background, no rect behind)
    canvas.drawPath(silhouettePath, silhouettePaint);

    // 3. Draw headphones if enabled
    if (showHeadphones) {
      _drawHeadphones(canvas);
    }

    canvas.restore();
  }

  /// Style A: Clean, rounded shorter hair silhouette with neck and shoulders.
  Path _buildStyleAPath() {
    // Shoulders and neck base
    final torsoPath = Path()
      ..moveTo(22, 200)
      ..cubicTo(26, 170, 54, 146, 76, 138) // Left shoulder up to neck
      ..lineTo(78, 116)                    // Left neck up
      ..lineTo(122, 116)                   // Across neck
      ..lineTo(124, 138)                   // Right neck down
      ..cubicTo(146, 146, 174, 170, 178, 200) // Right shoulder down
      ..close();

    // Head + Short cropped round hair outline
    final headPath = Path()
      ..moveTo(100, 136) // Chin center
      ..cubicTo(82, 136, 68, 122, 66, 100) // Left jaw to ear
      ..cubicTo(64, 64, 80, 42, 100, 42)   // Left temple over crown
      ..cubicTo(120, 42, 136, 64, 134, 100) // Right crown down to ear
      ..cubicTo(132, 122, 118, 136, 100, 136) // Right jaw to chin
      ..close();

    return Path.combine(PathOperation.union, torsoPath, headPath);
  }

  /// Style B: Voluminous, fuller flowing hair silhouette with shoulders.
  Path _buildStyleBPath() {
    // Shoulders and torso base
    final torsoPath = Path()
      ..moveTo(22, 200)
      ..cubicTo(26, 170, 54, 146, 76, 138)
      ..lineTo(78, 116)
      ..lineTo(122, 116)
      ..lineTo(124, 138)
      ..cubicTo(146, 146, 174, 170, 178, 200)
      ..close();

    // Voluminous, stylish flowing hair outline
    final hairPath = Path()
      ..moveTo(100, 136) // Chin
      ..cubicTo(82, 136, 70, 122, 68, 104) // Inner jaw
      ..cubicTo(50, 108, 48, 76, 52, 54)   // Left hair volume swelling out
      ..cubicTo(56, 32, 78, 28, 100, 28)   // Crown volume
      ..cubicTo(122, 28, 144, 32, 148, 54) // Right crown volume
      ..cubicTo(152, 76, 150, 108, 132, 104) // Right hair volume swelling out
      ..cubicTo(130, 122, 118, 136, 100, 136) // Down to chin
      ..close();

    return Path.combine(PathOperation.union, torsoPath, hairPath);
  }

  /// Draws modern, clean studio headphones (arc band + ear cups).
  void _drawHeadphones(Canvas canvas) {
    final hpDarkColor = headphonesColor ?? const Color(0xFF334155);
    const hpLightAccent = Colors.white;

    // Headband arc peak height depends slightly on hair volume
    final double bandTopY = silhouette == AvatarSilhouette.styleA ? 32.0 : 20.0;
    const double leftCupX = 58.0;
    const double rightCupX = 142.0;
    const double cupCenterY = 92.0;

    // 1. Headband Arc
    final Path bandPath = Path()
      ..moveTo(leftCupX, cupCenterY - 14)
      ..cubicTo(leftCupX - 2, bandTopY, 78, bandTopY - 2, 100, bandTopY - 2)
      ..cubicTo(122, bandTopY - 2, rightCupX + 2, bandTopY, rightCupX, cupCenterY - 14);

    // Outer headband cushion
    final Paint bandOuterPaint = Paint()
      ..color = hpDarkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Inner headband metallic highlight
    final Paint bandInnerPaint = Paint()
      ..color = hpLightAccent.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    canvas.drawPath(bandPath, bandOuterPaint);
    canvas.drawPath(bandPath, bandInnerPaint);

    // 2. Ear Cups (Rounded-rectangles on left & right sides)
    final RRect leftCup = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(leftCupX, cupCenterY), width: 15, height: 32),
      const Radius.circular(7),
    );

    final RRect rightCup = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(rightCupX, cupCenterY), width: 15, height: 32),
      const Radius.circular(7),
    );

    final Paint cupFillPaint = Paint()
      ..color = hpDarkColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Paint cupBorderPaint = Paint()
      ..color = hpLightAccent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..isAntiAlias = true;

    // Draw Left Cup
    canvas.drawRRect(leftCup, cupFillPaint);
    canvas.drawRRect(leftCup, cupBorderPaint);

    // Draw Right Cup
    canvas.drawRRect(rightCup, cupFillPaint);
    canvas.drawRRect(rightCup, cupBorderPaint);

    // 3. Inner cushion accents
    final Paint cushionPaint = Paint()
      ..color = hpLightAccent.withValues(alpha: 0.70)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Small metallic pivot pins
    canvas.drawCircle(const Offset(leftCupX, cupCenterY - 10), 2.2, cushionPaint);
    canvas.drawCircle(const Offset(rightCupX, cupCenterY - 10), 2.2, cushionPaint);
  }

  @override
  bool shouldRepaint(covariant MusicAvatarPainter oldDelegate) {
    return oldDelegate.silhouette != silhouette ||
        oldDelegate.gradientColors != gradientColors ||
        oldDelegate.showHeadphones != showHeadphones ||
        oldDelegate.headphonesColor != headphonesColor;
  }
}

/// Widget wrapper for [MusicAvatarPainter] that scales cleanly at any display size.
class MusicAvatar extends StatelessWidget {
  final AvatarSilhouette silhouette;
  final List<Color> gradientColors;
  final bool showHeadphones;
  final Color? headphonesColor;
  final double size;

  const MusicAvatar({
    super.key,
    required this.silhouette,
    required this.gradientColors,
    this.showHeadphones = true,
    this.headphonesColor,
    this.size = 60,
  });

  /// Convenience constructor from a [MusicAvatarConfig].
  factory MusicAvatar.fromConfig(
    MusicAvatarConfig config, {
    Key? key,
    double size = 60,
    Color? headphonesColor,
  }) {
    return MusicAvatar(
      key: key,
      silhouette: config.silhouette,
      gradientColors: config.gradientColors,
      showHeadphones: config.showHeadphones,
      headphonesColor: headphonesColor,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: MusicAvatarPainter(
        silhouette: silhouette,
        gradientColors: gradientColors,
        showHeadphones: showHeadphones,
        headphonesColor: headphonesColor,
      ),
    );
  }
}
