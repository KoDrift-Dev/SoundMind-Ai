import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_radius.dart';

/// Dynamic icon widget that automatically switches between `dark-icon.png` (in Dark Mode)
/// and `light-icon.png` (in Light Mode) with liquid glass framing and glow options.
class ThemedIcon extends StatelessWidget {
  const ThemedIcon({
    super.key,
    this.size = 32,
    this.borderRadius = AppRadius.sm,
    this.showGlow = false,
    this.showBorder = true,
    this.accentColor,
  });

  final double size;
  final double borderRadius;
  final bool showGlow;
  final bool showBorder;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconAsset = isDark ? AppAssets.darkIcon : AppAssets.lightIcon;
    final effectiveAccent = accentColor ??
        (isDark ? const Color(0xFF3898FF) : const Color(0xFF0284C7));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(
                color: effectiveAccent.withValues(alpha: isDark ? 0.35 : 0.40),
                width: 1.2,
              )
            : null,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: effectiveAccent.withValues(alpha: isDark ? 0.35 : 0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          iconAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Fallback gracefully to standard brand icon
            return Icon(
              Icons.graphic_eq_rounded,
              color: effectiveAccent,
              size: size * 0.7,
            );
          },
        ),
      ),
    );
  }
}
