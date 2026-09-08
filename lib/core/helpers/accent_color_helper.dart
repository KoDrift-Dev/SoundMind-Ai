import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Resolves accent color from theme context with the same fallback chain
/// used before the foundation refactor.
abstract final class AccentColorHelper {
  static Color resolve(BuildContext context) {
    return Theme.of(context).appBarTheme.foregroundColor ??
        AppColors.themeOneAccent;
  }
}
