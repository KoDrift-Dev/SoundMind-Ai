import 'package:flutter/material.dart';

import '../constants/app_radius.dart';
import 'glass_container.dart';

/// Square frosted icon button — player header style (40×40, icon 22).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 22,
    this.iconColor,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = iconColor ?? (isDark ? Colors.white : const Color(0xFF0B132B));

    return GlassContainer(
      tier: GlassTier.secondary,
      borderRadius: AppRadius.glassIcon,
      width: size,
      height: size,
      child: Center(
        child: Icon(icon, color: effectiveIconColor, size: iconSize),
      ),
    );
  }
}
