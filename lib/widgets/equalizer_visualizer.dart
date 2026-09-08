// equalizer_visualizer.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';
import '../services/equalizer_service.dart';

/// Simulated, reactive animated visualizer.
///
/// Features:
/// - Animated loop that pulses ONLY while [isPlaying == true], freezing when paused.
/// - Resting amplitude of each bar is shaped by the corresponding hardware EQ band level.
/// - Animated pseudo-randomized sine oscillation layered per-bar with unique phase offsets.
/// - Dynamic color gradient shifting from cool neon cyan/violet to intense fiery red as
///   Bass Boost or low-frequency bands are boosted.
class EqualizerVisualizer extends StatefulWidget {
  final double height;
  final Color accentColor;

  const EqualizerVisualizer({
    super.key,
    this.height = 95,
    this.accentColor = const Color(0xFF6366F1),
  });

  @override
  State<EqualizerVisualizer> createState() => _EqualizerVisualizerState();
}

class _EqualizerVisualizerState extends State<EqualizerVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  StreamSubscription<bool>? _playingSub;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _isPlaying = AudioPlayerService.instance.player.playing;
    if (_isPlaying) {
      _animController.repeat();
    }

    _playingSub = AudioPlayerService.instance.player.playingStream.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (playing) {
          if (!_animController.isAnimating) {
            _animController.repeat();
          }
        } else {
          _animController.stop();
        }
      });
    });
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eq = EqualizerService.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: Listenable.merge([eq, _animController]),
      builder: (context, _) {
        return Container(
          height: widget.height,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF070B14).withValues(alpha: 0.85)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _EqualizerVisualizerPainter(
              animValue: _animController.value,
              isPlaying: _isPlaying && eq.isEnabled,
              bands: eq.bands,
              minLevelMb: eq.minLevelMillibels,
              maxLevelMb: eq.maxLevelMillibels,
              bassBoostStrength: eq.bassBoostStrength,
              accentColor: widget.accentColor,
            ),
          ),
        );
      },
    );
  }
}

class _EqualizerVisualizerPainter extends CustomPainter {
  final double animValue;
  final bool isPlaying;
  final List<EqualizerBandModel> bands;
  final int minLevelMb;
  final int maxLevelMb;
  final int bassBoostStrength;
  final Color accentColor;

  static const int kBarCount = 28;

  _EqualizerVisualizerPainter({
    required this.animValue,
    required this.isPlaying,
    required this.bands,
    required this.minLevelMb,
    required this.maxLevelMb,
    required this.bassBoostStrength,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double totalWidth = size.width;
    final double barSpacing = 4.0;
    final double totalSpacing = barSpacing * (kBarCount - 1);
    final double barWidth = math.max(2.5, (totalWidth - totalSpacing) / kBarCount);

    // Compute bass intensity (0.0 = low/flat, 1.0 = heavy bass boost / low EQ maxed)
    final double bassGainNorm = bands.isNotEmpty
        ? (bands.first.levelMillibels.clamp(0, math.max(1, maxLevelMb)) /
            math.max(1, maxLevelMb).toDouble())
        : 0.0;
    final double bassBoostNorm = bassBoostStrength / 1000.0;
    final double bassIntensity = (bassBoostNorm * 0.65 + bassGainNorm * 0.35).clamp(0.0, 1.0);

    // Color gradient interpolation:
    // Cool: Neon Cyan (#00E5FF) -> Vibrant Azure (#0088FF) -> Deep Violet (#8A2BE2)
    // Warm: Warm Coral (#FF6F00) -> Neon Sunset (#FF3D00) -> Fiery Crimson (#FF0055)
    final Color bottomCool = const Color(0xFF00E5FF);
    final Color topCool = const Color(0xFF8A2BE2);

    final Color bottomWarm = const Color(0xFFFF5252);
    final Color topWarm = const Color(0xFFFF0055);

    final Color effectiveBottom = Color.lerp(bottomCool, bottomWarm, bassIntensity)!;
    final Color effectiveTop = Color.lerp(topCool, topWarm, bassIntensity)!;

    final Paint barPaint = Paint()..isAntiAlias = true;

    for (int i = 0; i < kBarCount; i++) {
      final double fraction = i / (kBarCount - 1);
      final double x = i * (barWidth + barSpacing);

      // Baseline resting height mapped from corresponding EQ band level
      final double bandGain = _interpolateBandLevel(fraction);
      final double range = math.max(1.0, (maxLevelMb - minLevelMb).toDouble());
      final double normalizedGain = (bandGain - minLevelMb) / range; // 0.0 to 1.0
      double baseHeightFrac = 0.20 + (normalizedGain * 0.50); // resting between 0.20 and 0.70

      // Add dynamic pseudo-random oscillation if playing
      double dynamicOffset = 0.0;
      if (isPlaying) {
        final double phase1 = fraction * 3.5 * math.pi;
        final double phase2 = fraction * 5.8 * math.pi;
        final double sine1 = math.sin(animValue * 2 * math.pi * 1.4 + phase1);
        final double sine2 = math.cos(animValue * 2 * math.pi * 2.3 + phase2);
        dynamicOffset = (sine1 * 0.15) + (sine2 * 0.09);
      }

      final double totalFrac = (baseHeightFrac + dynamicOffset).clamp(0.08, 0.96);
      final double barHeight = totalFrac * size.height;
      final double y = size.height - barHeight;

      final Rect barRect = Rect.fromLTWH(x, y, barWidth, barHeight);

      // Gradient per bar
      barPaint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          effectiveBottom.withValues(alpha: 0.85),
          effectiveTop,
        ],
      ).createShader(barRect);

      final RRect roundedBar = RRect.fromRectAndRadius(
        barRect,
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(roundedBar, barPaint);

      // Subtle glow cap on top of each bar
      if (isPlaying) {
        final Paint capPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
        canvas.drawCircle(
          Offset(x + barWidth / 2, y + 2),
          barWidth / 2.5,
          capPaint,
        );
      }
    }
  }

  double _interpolateBandLevel(double fraction) {
    if (bands.isEmpty) return 0.0;
    if (bands.length == 1) return bands.first.levelMillibels.toDouble();

    final double pos = fraction * (bands.length - 1);
    final int lowIdx = pos.floor().clamp(0, bands.length - 1);
    final int highIdx = pos.ceil().clamp(0, bands.length - 1);

    if (lowIdx == highIdx) {
      return bands[lowIdx].levelMillibels.toDouble();
    }

    final double t = pos - lowIdx;
    return bands[lowIdx].levelMillibels * (1.0 - t) +
        bands[highIdx].levelMillibels * t;
  }

  @override
  bool shouldRepaint(covariant _EqualizerVisualizerPainter oldDelegate) {
    return oldDelegate.animValue != animValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.bands != bands ||
        oldDelegate.bassBoostStrength != bassBoostStrength ||
        oldDelegate.minLevelMb != minLevelMb ||
        oldDelegate.maxLevelMb != maxLevelMb;
  }
}
