// equalizer_content.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../services/equalizer_service.dart';
import 'equalizer_visualizer.dart';

/// Reusable Equalizer Content widget designed with an adaptive "Sound Lab" aesthetic
/// supporting both Light and Dark themes. Embedded within both [EqualizerScreen] and [EqualizerSheet].
class EqualizerContent extends StatefulWidget {
  final Color accentColor;
  final ScrollController? scrollController;

  const EqualizerContent({
    super.key,
    this.accentColor = AppColors.abyssAccent,
    this.scrollController,
  });

  @override
  State<EqualizerContent> createState() => _EqualizerContentState();
}

class _EqualizerContentState extends State<EqualizerContent> {
  final EqualizerService _eq = EqualizerService.instance;
  late Widget _cachedVisualizer;

  @override
  void initState() {
    super.initState();
    _cachedVisualizer = EqualizerVisualizer(
      height: 96,
      accentColor: widget.accentColor,
    );
  }

  @override
  void didUpdateWidget(EqualizerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accentColor != widget.accentColor) {
      _cachedVisualizer = EqualizerVisualizer(
        height: 96,
        accentColor: widget.accentColor,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: _eq,
      builder: (context, _) {
        if (!_eq.isSupported) {
          return _buildUnsupportedView(isDark);
        }

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
          ),
          child: SingleChildScrollView(
            controller: widget.scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header: Status & Master Switch
                _buildSoundLabHeader(isDark),
                const SizedBox(height: 16),

                // Simulated Reactive Animated Visualizer (cached to preserve internal animation lifecycle)
                _cachedVisualizer,
                const SizedBox(height: 20),

                // Presets Section Header & Reset Button
                _buildPresetsHeader(isDark),
                const SizedBox(height: 10),

                // Presets Horizontal Carousel
                _buildPresetsCarousel(isDark),
                const SizedBox(height: 22),

                // Hardware Knobs: Bass Boost & Preamp Gain (Horizontal Sliders)
                _buildDspKnobsCard(isDark),
                const SizedBox(height: 22),

                // Multi-Band Frequency Section Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'FREQUENCY BANDS (${_eq.bands.length})',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : const Color(0xFF64748B),
                        fontSize: 11,
                        fontFamily: AppTypography.displayFont,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      '${_eq.minLevelDb.toInt()} dB to +${_eq.maxLevelDb.toInt()} dB',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.4)
                            : const Color(0xFF94A3B8),
                        fontSize: 10,
                        fontFamily: AppTypography.bodyFont,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Vertical Multi-Band Sliders Rack
                _buildBandSlidersRack(isDark),
                const SizedBox(height: 28),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnsupportedView(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Colors.redAccent,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Equalizer Not Supported',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 18,
                fontFamily: AppTypography.displayFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Native hardware equalizer effects aren't supported on this device or OEM audio driver. Playback will continue without audio distortion.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
                fontSize: 13,
                fontFamily: AppTypography.bodyFont,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundLabHeader(bool isDark) {
    final isEnabled = _eq.isEnabled;
    final cardBg = isDark ? const Color(0xFF0F1523) : Colors.white;
    final borderColor = isEnabled
        ? widget.accentColor.withValues(alpha: 0.3)
        : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isEnabled
                ? widget.accentColor.withValues(alpha: isDark ? 0.15 : 0.08)
                : Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled
                  ? const Color(0xFF00E676)
                  : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
              boxShadow: isEnabled
                  ? [
                      const BoxShadow(
                        color: Color(0xFF00E676),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'SOUND LAB DSP',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        fontSize: 13,
                        fontFamily: AppTypography.displayFont,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? widget.accentColor.withValues(alpha: isDark ? 0.2 : 0.12)
                            : (isDark ? Colors.white10 : const Color(0xFFEDF2F7)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _eq.currentPreset.label.toUpperCase(),
                        style: TextStyle(
                          color: isEnabled
                              ? widget.accentColor
                              : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isEnabled
                      ? (_eq.isHardwareBound
                          ? 'Hardware DSP Active • 32-bit Floating Engine'
                          : 'Awaiting Audio Session...')
                      : 'Equalizer & Bass Boost Bypassed',
                  style: TextStyle(
                    color: isEnabled
                        ? (isDark ? widget.accentColor.withValues(alpha: 0.85) : widget.accentColor)
                        : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                    fontSize: 11,
                    fontFamily: AppTypography.bodyFont,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _eq.isEnabled,
            activeColor: widget.accentColor,
            activeTrackColor: widget.accentColor.withValues(alpha: 0.4),
            inactiveThumbColor: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            inactiveTrackColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            onChanged: (val) => _eq.setEnabled(val),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'PRESETS',
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.6)
                : const Color(0xFF64748B),
            fontSize: 11,
            fontFamily: AppTypography.displayFont,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        GestureDetector(
          onTap: _eq.isEnabled ? () => _eq.resetToFlat() : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.restart_alt_rounded,
                  color: _eq.isEnabled
                      ? (isDark ? Colors.white70 : const Color(0xFF475569))
                      : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                  size: 13,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reset to Flat',
                  style: TextStyle(
                    color: _eq.isEnabled
                        ? (isDark ? Colors.white70 : const Color(0xFF475569))
                        : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetsCarousel(bool isDark) {
    final presets = EqualizerPreset.values;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = presets[index];
          final isSelected = _eq.currentPreset == preset;

          final Color itemBg = isSelected
              ? widget.accentColor.withValues(alpha: isDark ? 0.25 : 0.16)
              : (isDark ? const Color(0xFF131A29) : const Color(0xFFF1F5F9));

          final Color itemBorder = isSelected
              ? widget.accentColor
              : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0));

          final Color itemText = isSelected
              ? (isDark ? Colors.white : widget.accentColor)
              : (_eq.isEnabled
                  ? (isDark ? Colors.white70 : const Color(0xFF334155))
                  : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)));

          return GestureDetector(
            onTap: _eq.isEnabled ? () => _eq.setPreset(preset) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: itemBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: itemBorder,
                  width: isSelected ? 1.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: widget.accentColor.withValues(alpha: isDark ? 0.35 : 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (preset == EqualizerPreset.custom) ...[
                      Icon(
                        Icons.tune_rounded,
                        size: 13,
                        color: itemText,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      preset.label,
                      style: TextStyle(
                        color: itemText,
                        fontSize: 12,
                        fontFamily: AppTypography.bodyFont,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDspKnobsCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F1523) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0);
    final sliderTrackInactive = isDark ? Colors.white10 : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bass Boost Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3D00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.electric_bolt_rounded,
                      color: Color(0xFFFF3D00),
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Bass Boost',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 13,
                      fontFamily: AppTypography.displayFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${(_eq.bassBoostStrength / 10).round()}%',
                style: const TextStyle(
                  color: Color(0xFFFF3D00),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              activeTrackColor: const Color(0xFFFF3D00),
              inactiveTrackColor: sliderTrackInactive,
              thumbColor: const Color(0xFFFF3D00),
              overlayColor: const Color(0xFFFF3D00).withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _eq.bassBoostStrength.toDouble(),
              min: 0,
              max: 1000,
              divisions: 100,
              onChanged: _eq.isEnabled && _eq.bassBoostSupported
                  ? (val) => _eq.setBassBoostStrength(val.round())
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // Preamp Gain Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.volume_up_rounded,
                      color: widget.accentColor,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Preamp Gain',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontSize: 13,
                      fontFamily: AppTypography.displayFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${_eq.preampGainDb >= 0 ? '+' : ''}${_eq.preampGainDb.toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: widget.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              activeTrackColor: widget.accentColor,
              inactiveTrackColor: sliderTrackInactive,
              thumbColor: widget.accentColor,
              overlayColor: widget.accentColor.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: _eq.preampGainMillibels.toDouble(),
              min: -600,
              max: 600,
              divisions: 24,
              onChanged: _eq.isEnabled
                  ? (val) => _eq.setPreampGain(val.round())
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandSlidersRack(bool isDark) {
    final bands = _eq.bands;
    final cardBg = isDark ? const Color(0xFF0D1322) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bandWidth = (constraints.maxWidth / bands.length).clamp(44.0, 75.0);

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: bands.map((band) {
              return SizedBox(
                width: bandWidth,
                child: _VerticalBandSlider(
                  band: band,
                  minLevelMb: _eq.minLevelMillibels,
                  maxLevelMb: _eq.maxLevelMillibels,
                  isEnabled: _eq.isEnabled,
                  isDark: isDark,
                  accentColor: widget.accentColor,
                  onChanged: (newMb) => _eq.setBandLevel(band.index, newMb),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

/// Custom vertical slider built directly with gesture detection for studio feel.
class _VerticalBandSlider extends StatelessWidget {
  final EqualizerBandModel band;
  final int minLevelMb;
  final int maxLevelMb;
  final bool isEnabled;
  final bool isDark;
  final Color accentColor;
  final ValueChanged<int> onChanged;

  const _VerticalBandSlider({
    required this.band,
    required this.minLevelMb,
    required this.maxLevelMb,
    required this.isEnabled,
    required this.isDark,
    required this.accentColor,
    required this.onChanged,
  });

  static const double kSliderTrackHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final range = math.max(1, maxLevelMb - minLevelMb).toDouble();
    final fraction = ((band.levelMillibels - minLevelMb) / range).clamp(0.0, 1.0);

    final slotBg = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);
    final guidelineColor = isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFCBD5E1);
    final knobBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final freqColor = isEnabled
        ? (isDark ? Colors.white : const Color(0xFF0F172A))
        : (isDark ? Colors.white38 : const Color(0xFF94A3B8));
    final bandNameColor = isDark ? Colors.white.withValues(alpha: 0.35) : const Color(0xFF64748B);
    final dbTextColor = band.levelMillibels != 0 && isEnabled
        ? accentColor
        : (isDark ? Colors.white38 : const Color(0xFF94A3B8));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // dB Readout
        Container(
          height: 20,
          alignment: Alignment.center,
          child: Text(
            '${band.levelDb >= 0 ? '+' : ''}${band.levelDb.toStringAsFixed(1)}',
            style: TextStyle(
              color: dbTextColor,
              fontSize: 10,
              fontFamily: AppTypography.displayFont,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Vertical Slider Track
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: isEnabled
              ? (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localPos = box.globalToLocal(details.globalPosition);
                  final yInTrack = (localPos.dy - 26).clamp(0.0, kSliderTrackHeight);
                  final dragFrac = 1.0 - (yInTrack / kSliderTrackHeight);
                  final calculatedMb = (minLevelMb + dragFrac * range).round();
                  onChanged(calculatedMb);
                }
              : null,
          onTapDown: isEnabled
              ? (details) {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final localPos = box.globalToLocal(details.globalPosition);
                  final yInTrack = (localPos.dy - 26).clamp(0.0, kSliderTrackHeight);
                  final tapFrac = 1.0 - (yInTrack / kSliderTrackHeight);
                  final calculatedMb = (minLevelMb + tapFrac * range).round();
                  onChanged(calculatedMb);
                }
              : null,
          child: SizedBox(
            height: kSliderTrackHeight,
            width: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background Slot
                Container(
                  width: 5,
                  height: kSliderTrackHeight,
                  decoration: BoxDecoration(
                    color: slotBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),

                // Center 0 dB Guideline
                Positioned(
                  top: kSliderTrackHeight / 2 - 1,
                  child: Container(
                    width: 14,
                    height: 2,
                    decoration: BoxDecoration(
                      color: guidelineColor,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),

                // Active Gain Level Bar (from 0 dB midpoint to current position)
                _buildActiveLevelBar(fraction),

                // Thumb Knob
                Positioned(
                  bottom: (fraction * (kSliderTrackHeight - 22)).clamp(0.0, kSliderTrackHeight - 22),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: knobBg,
                      border: Border.all(
                        color: isEnabled
                            ? accentColor
                            : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                        width: 2,
                      ),
                      boxShadow: isEnabled
                          ? [
                              BoxShadow(
                                color: accentColor.withValues(alpha: isDark ? 0.4 : 0.25),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEnabled
                              ? (isDark ? Colors.white : accentColor)
                              : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Frequency Label
        Text(
          band.freqLabel,
          style: TextStyle(
            color: freqColor,
            fontSize: 11,
            fontFamily: AppTypography.displayFont,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),

        // Band Name (e.g. Bass, Mid, Treble)
        Text(
          band.bandName,
          style: TextStyle(
            color: bandNameColor,
            fontSize: 9,
            fontFamily: AppTypography.bodyFont,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveLevelBar(double fraction) {
    final double midY = kSliderTrackHeight * 0.5;
    final double currentY = kSliderTrackHeight * (1.0 - fraction);

    final double top = math.min(midY, currentY);
    final double height = (midY - currentY).abs();

    return Positioned(
      top: top,
      child: Container(
        width: 5,
        height: math.max(0, height),
        decoration: BoxDecoration(
          color: isEnabled
              ? accentColor.withValues(alpha: isDark ? 0.8 : 0.9)
              : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
