// equalizer_screen.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../services/equalizer_service.dart';
import '../widgets/equalizer_content.dart';

/// Full-screen Equalizer route accessible from Settings.
/// Uses the same underlying [EqualizerContent] and [EqualizerService] as the player bottom sheet,
/// supporting both Light and Dark modes.
class EqualizerScreen extends StatelessWidget {
  final Color accentColor;

  const EqualizerScreen({
    super.key,
    this.accentColor = AppColors.abyssAccent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF070B14) : const Color(0xFFF8FAFC);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white38 : const Color(0xFF64748B);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF334155);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: titleColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Equalizer & Sound Lab',
              style: TextStyle(
                color: titleColor,
                fontSize: 18,
                fontFamily: AppTypography.displayFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Hardware DSP Audio Effects',
              style: TextStyle(
                color: subtitleColor,
                fontSize: 11,
                fontFamily: AppTypography.bodyFont,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reset to Flat',
            icon: Icon(Icons.restart_alt_rounded, color: iconColor),
            onPressed: () => EqualizerService.instance.resetToFlat(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: EqualizerContent(
          accentColor: accentColor,
        ),
      ),
    );
  }
}
