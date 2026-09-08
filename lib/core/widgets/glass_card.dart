import 'package:flutter/material.dart';

import '../constants/app_radius.dart';
import 'glass_container.dart';

/// Full-width frosted liquid card — settings, list tiles, info panels.
/// Features electric blue corner glow with clean layout padding.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.tier = GlassTier.primary,
    this.borderRadius = AppRadius.glassCard,
    this.glowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final GlassTier tier;
  final double borderRadius;
  /// Optional glow shadow color (e.g., accent color for selected state)
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      tier: tier,
      borderRadius: borderRadius,
      padding: padding,
      width: double.infinity,
      shadows: glowColor != null
          ? [
              BoxShadow(
                color: glowColor!.withValues(alpha: 0.28),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
              if (isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ]
          : null,
      child: child,
    );
  }
}
