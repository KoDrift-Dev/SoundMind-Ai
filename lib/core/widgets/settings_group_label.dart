import 'package:flutter/material.dart';

import '../constants/app_opacity.dart';
import '../constants/app_typography.dart';

/// Uppercase group label used on the settings screen.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel({
    super.key,
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTypography.bodyFont,
          fontSize: AppTypography.settingsGroup,
          letterSpacing: AppTypography.settingsGroupLetterSpacing,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: AppOpacity.settingsGroupLabel),
        ),
      ),
    );
  }
}
