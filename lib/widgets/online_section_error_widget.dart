import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_typography.dart';
import '../core/theme/online_theme.dart';

/// Helper to classify exceptions into offline vs generic error.
bool isNetworkOrOfflineError(dynamic error) {
  if (error == null) return false;
  if (error is SocketException) return true;
  final str = error.toString().toLowerCase();
  return str.contains('socket') ||
      str.contains('failed host lookup') ||
      str.contains('network is unreachable') ||
      str.contains('connection timed out') ||
      str.contains('connection refused') ||
      str.contains('handshake failed') ||
      str.contains('clientexception') ||
      str.contains('no address associated with hostname');
}

/// A scoped, in-place error widget for isolated online sections.
/// Renders distinct "No internet connection" or "Something went wrong" states
/// without leaking errors to other sections or showing raw stack traces.
class OnlineSectionErrorWidget extends StatelessWidget {
  final dynamic error;
  final VoidCallback onRetry;
  final double height;
  final EdgeInsetsGeometry margin;

  const OnlineSectionErrorWidget({
    super.key,
    required this.error,
    required this.onRetry,
    this.height = 160,
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = OnlineTheme.accent(isDark);
    final isOffline = isNetworkOrOfflineError(error);

    final title = isOffline ? 'No internet connection' : 'Something went wrong';
    final subtitle = isOffline
        ? 'Check your connection and try again.'
        : 'Tap below to retry loading this section.';
    final icon = isOffline ? Icons.wifi_off_rounded : Icons.refresh_rounded;

    return Container(
      constraints: BoxConstraints(minHeight: height),
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.22 : 0.16),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                onRetry();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.replay_rounded, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Try Again',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
