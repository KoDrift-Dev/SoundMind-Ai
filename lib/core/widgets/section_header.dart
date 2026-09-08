import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_spacing.dart';
import '../constants/app_strings.dart';
import '../constants/app_typography.dart';
import 'glass_container.dart';

/// Section title row encapsulated in a dedicated glass capsule badge with leading indicator pip.
/// Zero raw floating text over wallpaper.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.accentColor,
    required this.onSeeAll,
    this.subtitle,
  });

  final String title;
  final Color accentColor;
  final VoidCallback onSeeAll;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF1E293B);

    return Padding(
      padding: AppSpacing.screenHorizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glass capsule badge for section header
          Flexible(
            child: GlassContainer(
              tier: GlassTier.subtle,
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Leading vertical indicator bar/pip
                  Container(
                    width: 3.5,
                    height: 16,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Title + optional subtitle
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: AppTypography.sectionTitle,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            letterSpacing: -0.2,
                            shadows: [
                              Shadow(
                                blurRadius: 6,
                                color: isDark
                                    ? Colors.black87
                                    : Colors.white.withValues(alpha: 0.85),
                              ),
                            ],
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            subtitle!,
                            maxLines: 1,
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
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // See All proper pill button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onSeeAll();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0C4A6E).withValues(alpha: 0.40)
                      : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.65)
                        : const Color(0xFF0284C7),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.seeAll,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontWeight: FontWeight.w700,
                        fontSize: AppTypography.seeAll,
                        color: isDark
                            ? const Color(0xFF7DD3FC)
                            : const Color(0xFF0C4A6E),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: isDark
                          ? const Color(0xFF7DD3FC)
                          : const Color(0xFF0C4A6E),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
