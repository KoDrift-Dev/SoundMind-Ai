import 'package:flutter/material.dart';

import '../constants/app_typography.dart';
import 'themed_icon.dart';

/// Unified page header widget used at the top of all screens.
/// Properly padded and aligned below dynamic island / notch.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.accentColor,
    this.subtitle,
    this.showBack = false,
    this.onBack,
    this.actions = const [],
    this.useDisplayFont = true,
    this.showAppIcon = false,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 8),
  });

  final String title;
  final Color accentColor;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool useDisplayFont;
  final bool showAppIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showBack) ...[
            GestureDetector(
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: accentColor,
                  size: 16,
                ),
              ),
            ),
          ] else if (showAppIcon) ...[
            ThemedIcon(
              size: 38,
              accentColor: accentColor,
              showGlow: true,
            ),
            const SizedBox(width: 12),
          ],

          // Title + subtitle column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: useDisplayFont
                        ? AppTypography.displayFont
                        : AppTypography.uiFont,
                    fontSize: useDisplayFont
                        ? AppTypography.displayM
                        : AppTypography.headingL,
                    fontWeight: useDisplayFont
                        ? FontWeight.normal
                        : FontWeight.w700,
                    color: accentColor,
                    letterSpacing: useDisplayFont
                        ? AppTypography.displayLetterSpacing
                        : -0.5,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: AppTypography.bodyS,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action widgets
          ...actions.map(
            (a) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: a,
            ),
          ),
        ],
      ),
    );
  }
}
