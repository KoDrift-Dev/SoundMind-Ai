import 'package:flutter/material.dart';

import '../constants/app_typography.dart';
import 'glass_card.dart';
import 'glass_container.dart';

/// Settings-style frosted list row with icon container, label, optional subtitle,
/// optional trailing value text, high-contrast text, and press feedback.
class GlassListTile extends StatefulWidget {
  const GlassListTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.subtitle,
    this.trailingValue,
    this.trailingWidget,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailingValue;
  final Widget? trailingWidget;
  final bool showChevron;

  @override
  State<GlassListTile> createState() => _GlassListTileState();
}

class _GlassListTileState extends State<GlassListTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _press;
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF1E293B);
    final chevronColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF0F172A).withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTapDown: (_) => _press.reverse(),
        onTapUp: (_) {
          _press.forward();
          widget.onTap();
        },
        onTapCancel: () => _press.forward(),
        child: ScaleTransition(
          scale: _scale,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon container with accent tint
                GlassContainer(
                  tier: GlassTier.subtle,
                  borderRadius: 10,
                  borderWidth: 0,
                  width: 38,
                  height: 38,
                  backgroundColor: widget.accentColor.withValues(alpha: 0.15),
                  child: Icon(
                    widget.icon,
                    color: widget.accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),

                // Label + optional subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: AppTypography.settingsItem,
                          fontWeight: FontWeight.w700,
                          color: primaryTextColor,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: AppTypography.labelM,
                            fontWeight: FontWeight.w600,
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Optional trailing value
                if (widget.trailingValue != null)
                  Text(
                    widget.trailingValue!,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: AppTypography.labelM,
                      fontWeight: FontWeight.w700,
                      color: widget.accentColor,
                    ),
                  ),

                // Custom trailing widget
                if (widget.trailingWidget != null) widget.trailingWidget!,

                // Chevron
                if (widget.showChevron && widget.trailingWidget == null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: chevronColor,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
