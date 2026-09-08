import 'package:flutter/material.dart';

import '../constants/app_radius.dart';
import 'glass_container.dart';

/// Circular frosted icon button — home notification style (42×42, icon 20).
class GlassCircleIconButton extends StatelessWidget {
  const GlassCircleIconButton({
    super.key,
    required this.icon,
    this.size = 42,
    this.iconSize = 20,
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
