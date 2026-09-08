import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_typography.dart';
import '../core/theme/online_theme.dart';
import '../screens/search_screen.dart' show kBrowseGenres;

/// A reusable 3-column grid for picking genres, shared between
/// Onboarding and the Settings "Music Preferences" section.
class GenreSelectorGrid extends StatelessWidget {
  final Set<String> selectedGenres;
  final ValueChanged<String> onGenreToggled;
  final bool isDark;
  final Color? accentColor;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  const GenreSelectorGrid({
    super.key,
    required this.selectedGenres,
    required this.onGenreToggled,
    this.isDark = true,
    this.accentColor,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
  });

  static List<String> get eligibleGenres => kBrowseGenres
      .where((g) => g != 'All' && g != 'Trending')
      .toList();

  static IconData genreIcon(String genre) {
    switch (genre.toLowerCase()) {
      case 'pop':
        return Icons.star_rounded;
      case 'rock':
        return Icons.electric_bolt_rounded;
      case 'hip hop':
        return Icons.speaker_rounded;
      case 'classical':
        return Icons.piano_rounded;
      case 'qawali':
        return Icons.volunteer_activism_rounded;
      case 'sufi':
        return Icons.wb_sunny_rounded;
      case 'jazz':
        return Icons.album_rounded;
      case 'lo-fi':
        return Icons.headphones_rounded;
      case 'slow and reverb':
        return Icons.waves_rounded;
      case 'edm':
        return Icons.graphic_eq_rounded;
      case 'bollywood':
        return Icons.movie_filter_rounded;
      case 'hollywood':
        return Icons.theaters_rounded;
      case 'coke studio':
        return Icons.mic_external_on_rounded;
      case 'punjabi':
        return Icons.celebration_rounded;
      case 'indie':
        return Icons.palette_rounded;
      case 'acoustic':
        return Icons.audiotrack_rounded;
      case 'instrumental':
        return Icons.music_note_rounded;
      case 'devotional':
        return Icons.spa_rounded;
      case 'ghazal':
        return Icons.menu_book_rounded;
      case 'r&b':
        return Icons.nightlife_rounded;
      case 'trap':
        return Icons.flash_on_rounded;
      case 'ambient':
        return Icons.cloud_circle_rounded;
      case 'folk':
        return Icons.park_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? OnlineTheme.accent(isDark);
    final genres = eligibleGenres;

    final cardBg = isDark ? const Color(0xFF141A28) : Colors.white;
    final borderUnselected = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.07);

    return GridView.builder(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      physics: physics ?? const BouncingScrollPhysics(),
      shrinkWrap: shrinkWrap,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.92,
      ),
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        final isSelected = selectedGenres.contains(genre);
        final icon = genreIcon(genre);

        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onGenreToggled(genre);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? accent : cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? accent : borderUnselected,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? 0.38 : 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Corner Checkmark Badge
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        size: 13,
                        color: accent,
                      ),
                    ),
                  ),

                // Centered Icon & Genre Label
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.20)
                                : accent.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 20,
                            color: isSelected ? Colors.white : accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          genre,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? Colors.white
                                    : const Color(0xFF1E293B)),
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
      },
    );
  }
}
