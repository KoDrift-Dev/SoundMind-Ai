import 'dart:ui';
import 'package:flutter/material.dart';

import '../constants/app_assets.dart';

/// Universal full-screen ambient background.
/// Renders frosted blurred Sound Void artwork (sigma 8.0) with atmospheric dimming overlay
/// preventing text collisions while keeping the boy with glowing headphones and wave patterns
/// elegantly visible behind all liquid glass cards.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.isThemeOne,
    this.child,
  });

  final bool isThemeOne;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = isThemeOne;
    final primaryBg = isDarkMode ? AppAssets.darkBg : AppAssets.lightBg;

    final backgroundStack = Stack(
      fit: StackFit.expand,
      children: [
        // 1. Frosted Blurred Image Layer (sigma 8.0)
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: Image.asset(
              primaryBg,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => Image.asset(
                isDarkMode ? 'assets/bg/dark-bg.jpg' : 'assets/bg/light-bg.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: const Color(0xFF020712)),
              ),
            ),
          ),
        ),

        // 2. Atmospheric dimming overlay (Soft tone down, avoids harsh glaring white)
        Positioned.fill(
          child: Container(
            color: isDarkMode
                ? const Color(0xFF020712).withValues(alpha: 0.55)
                : const Color(0xFF94A3B8).withValues(alpha: 0.75),
          ),
        ),

        // 3. Foreground Screen Content (if provided)
        if (child != null)
          Positioned.fill(
            child: SafeArea(
              top: true,
              bottom: false,
              child: child!,
            ),
          ),
      ],
    );

    return RepaintBoundary(child: backgroundStack);
  }
}
