import 'dart:ui';
import 'package:flutter/material.dart';

import '../constants/app_radius.dart';

/// Glass tier — determines default blur, background alpha, and border alpha.
enum GlassTier {
  /// Hairline tint — nested/inset surfaces
  subtle,
  /// Standard card/tile — primary glass surface
  primary,
  /// Stronger card — elevated secondary surface
  secondary,
  /// Floating elements — mini-player, bottom nav, modals
  floating,
}

/// Frosted liquid glass container with electric blue corner glow, clean layout separation,
/// and dynamic theme-adaptive styling.
///
/// Performance-optimized: Full GPU [BackdropFilter] is reserved for static/hero elements
/// ([GlassTier.floating] or explicit `enableBlur: true`), while scrollable cards and tiles
/// use high-performance semi-transparent color fills and luminous borders to maintain
/// 60/120 FPS scrolling without GPU fill-rate jank.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.tier = GlassTier.primary,
    this.borderRadius = AppRadius.glassCard,
    this.padding,
    this.width,
    this.height,
    this.backgroundColor,
    this.backgroundAlpha,
    this.borderColor,
    this.borderWidth = 1.2,
    this.shadows,
    this.clipBehavior = Clip.antiAlias,
    this.enableBlur,
  });

  final Widget child;
  final GlassTier tier;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final double? backgroundAlpha;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadows;
  final Clip clipBehavior;
  /// If null, defaults to true only for [GlassTier.floating] to ensure 60+ FPS scrolling.
  final bool? enableBlur;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Multi-tier background alpha settings
    final double defaultBgAlpha;
    switch (tier) {
      case GlassTier.subtle:
        defaultBgAlpha = isDarkMode ? 0.04 : 0.25;
        break;
      case GlassTier.primary:
        defaultBgAlpha = isDarkMode ? 0.08 : 0.40;
        break;
      case GlassTier.secondary:
        defaultBgAlpha = isDarkMode ? 0.12 : 0.45;
        break;
      case GlassTier.floating:
        defaultBgAlpha = isDarkMode ? 0.16 : 0.55;
        break;
    }

    final double effectiveBgAlpha = backgroundAlpha ?? defaultBgAlpha;
    final Color effectiveBaseColor = backgroundColor ??
        (isDarkMode ? const Color(0xFF091428) : Colors.white);
    final resolvedBg = effectiveBaseColor.withValues(alpha: effectiveBgAlpha);

    // Neon glowing border color (Dark: Electric Blue #3898FF / Light: Azure #0284C7)
    final resolvedBorderColor = borderColor ??
        (isDarkMode
            ? const Color(0xFF3898FF).withValues(alpha: 0.38)
            : const Color(0xFF0284C7).withValues(alpha: 0.35));

    final bool shouldApplyBlur = enableBlur ?? (tier == GlassTier.floating);

    final innerContainer = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: resolvedBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: resolvedBorderColor,
          width: borderWidth,
        ),
      ),
      child: child,
    );

    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadows ??
              [
                // Ambient drop shadow
                BoxShadow(
                  color: isDarkMode
                      ? Colors.black.withValues(alpha: 0.35)
                      : const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                // Electric Blue Corner Glow Aura
                BoxShadow(
                  color: isDarkMode
                      ? const Color(0xFF00D2FF).withValues(alpha: 0.20)
                      : const Color(0xFF0284C7).withValues(alpha: 0.14),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          clipBehavior: clipBehavior,
          child: shouldApplyBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: innerContainer,
                )
              : innerContainer,
        ),
      ),
    );
  }
}
