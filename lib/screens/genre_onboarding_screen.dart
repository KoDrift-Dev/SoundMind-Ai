import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_typography.dart';
import '../core/theme/online_theme.dart';
import '../services/user_preferences_service.dart';
import '../widgets/genre_selector_grid.dart';
import 'main_navigation.dart';

/// Spotify-style one-time genre onboarding screen shown on first app use.
class GenreOnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const GenreOnboardingScreen({
    super.key,
    this.onComplete,
  });

  @override
  State<GenreOnboardingScreen> createState() => _GenreOnboardingScreenState();
}

class _GenreOnboardingScreenState extends State<GenreOnboardingScreen> {
  final Set<String> _selectedGenres = {};
  bool _isSaving = false;

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  Future<void> _finish({required bool skipped}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final listToSave = skipped ? <String>[] : _selectedGenres.toList();

      await prefs.setString('preferred_genres', jsonEncode(listToSave));
      await prefs.setBool('has_completed_genre_onboarding', true);
      await UserPreferencesService.instance.setGenreOnboardingCompleted(true);
    } catch (e, st) {
      debugPrint('Error persisting onboarding genres: $e\n$st');
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MainNavigation(key: MainNavigation.navKey),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );

    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = OnlineTheme.accent(isDark);
    final count = _selectedGenres.length;
    final canContinue = count >= 3;

    final bgColors = isDark
        ? [const Color(0xFF070B14), const Color(0xFF0D121F), const Color(0xFF090D18)]
        : [const Color(0xFFF7F9FD), const Color(0xFFECEFF8), const Color(0xFFE4E9F6)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar with Skip Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                          const SizedBox(width: 6),
                          Text(
                            'Personalize',
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
                    TextButton(
                      onPressed: () => _finish(skipped: true),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.white60 : Colors.black54,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Title and Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What do you love\nlistening to?',
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: isDark ? Colors.white : const Color(0xFF0D1117),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick a few — we\'ll use this to personalize what you discover.',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 14,
                        color: isDark ? const Color(0xFF8B9CB5) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3-Column Grid of Selectable Genre Cards
              Expanded(
                child: GenreSelectorGrid(
                  selectedGenres: _selectedGenres,
                  onGenreToggled: _toggleGenre,
                  isDark: isDark,
                  accentColor: accent,
                ),
              ),

              // Bottom Bar: Requirement Helper + Continue Button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0D111A).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Helper text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          canContinue
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 15,
                          color: canContinue
                              ? accent
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          canContinue
                              ? '$count genres selected'
                              : 'Pick at least ${3 - count} more to continue',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: canContinue
                                ? accent
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: canContinue ? 1.0 : 0.45,
                        child: ElevatedButton(
                          onPressed: canContinue ? () => _finish(skipped: false) : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: accent.withValues(alpha: 0.3),
                            disabledForegroundColor: Colors.white70,
                            elevation: canContinue ? 6 : 0,
                            shadowColor: accent.withValues(alpha: 0.45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontFamily: AppTypography.uiFont,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
