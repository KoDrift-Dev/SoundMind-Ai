import 'package:flutter/material.dart';

/// Shared color helpers for glass surfaces and text hierarchy.
extension ColorAlphaExtension on Color {
  Color glassBackground([double alpha = 0.06]) => withValues(alpha: alpha);

  Color glassBorder([double alpha = 0.08]) => withValues(alpha: alpha);
}
