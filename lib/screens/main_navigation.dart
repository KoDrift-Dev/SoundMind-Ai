// main_navigation.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_durations.dart';
import '../core/constants/app_blur.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_typography.dart';
import '../core/navigation/app_navigation.dart';
import '../core/theme/soundmind_theme.dart';
import '../core/widgets/ambient_background.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_player_service.dart';
import 'ai_collections_screen.dart';
import 'home_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../widgets/mini_player.dart';
import '../widgets/floating_music_bubble.dart';
import '../core/theme/section_accents.dart';

import '../services/user_preferences_service.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  static final GlobalKey<MainNavigationState> navKey =
      GlobalKey<MainNavigationState>();

  static void navigateToDownloads({int subTab = 0}) {
    final state = navKey.currentState ?? MainNavigationState.instance;
    if (state != null) {
      state.navigateToLibraryDownloads(subTab: subTab);
    } else {
      debugPrint('MainNavigation: state is null, cannot navigate to library downloads');
    }
  }

  @override
  State<MainNavigation> createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  static MainNavigationState? instance;

  int _currentIndex = AppNavigation.homeTab;
  int _previousIndex = AppNavigation.homeTab;
  late bool _isThemeOne;
  bool _isMiniPlayerFloating = false;

  List<Track> _deviceLibrary = [];
  String? _libraryCategory;

  @override
  void initState() {
    super.initState();
    instance = this;

    _isThemeOne = UserPreferencesService.instance.isThemeOne;
    UserPreferencesService.instance.addListener(_onPreferencesChanged);
    AudioRepository.instance.addListener(_loadAudioLibrary);
    // Non-blocking background library scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAudioLibrary();
    });
  }

  @override
  void dispose() {
    if (instance == this) instance = null;
    UserPreferencesService.instance.removeListener(_onPreferencesChanged);
    AudioRepository.instance.removeListener(_loadAudioLibrary);
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (mounted && _isThemeOne != UserPreferencesService.instance.isThemeOne) {
      setState(() {
        _isThemeOne = UserPreferencesService.instance.isThemeOne;
      });
    }
  }

  Future<void> _loadAudioLibrary() async {
    try {
      final tracks = await AudioRepository.instance.getMusicOnlyTracks();
      if (mounted) {
        setState(() {
          _deviceLibrary = tracks;
        });
      }
    } catch (e, st) {
      debugPrint('MainNavigation: Failed to load audio library: $e\n$st');
    }
  }


  void playTrack(List<Track> playlist, int index) {
    AudioPlayerService.instance.loadPlaylist(playlist, index);
    setState(() {
      _isMiniPlayerFloating = false;
      _previousIndex = _currentIndex;
      _currentIndex = AppNavigation.playerTab;
    });
  }

  void goBackFromPlayer() {
    setState(() {
      _currentIndex = _previousIndex;
    });
  }

  void navigateToLibraryDownloads({int subTab = 0}) {
    setState(() {
      _libraryCategory = null;
      _previousIndex = _currentIndex;
      _currentIndex = AppNavigation.libraryTab;
    });

    void trySwitch() {
      final collections =
          AiCollectionsScreen.globalKey.currentState ?? AiCollectionsScreenState.instance;
      collections?.switchToDownloadTab(subTab: subTab);
    }

    trySwitch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      trySwitch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = _isThemeOne;
    final Color accentColor = SoundMindTheme.accent(isDark);

    // Apply system UI overlay
    SystemChrome.setSystemUIOverlayStyle(SoundMindTheme.overlayStyle(isDark));


    final List<Widget> screens = [
      HomeScreen(
        accentColor: accentColor,
        isThemeOne: isDark,
        tracks: _deviceLibrary,
        onPlaySelected: playTrack,
        onNavigateToLibrary: (category) {
          setState(() {
            _libraryCategory = category;
            _currentIndex = AppNavigation.libraryTab;
          });
        },
        onNavigateToSearch: () {
          setState(() {
            _currentIndex = AppNavigation.searchTab;
          });
        },
      ),
      SearchScreen(
        accentColor: accentColor,
        isThemeOne: isDark,
        localTracks: _deviceLibrary,
        onPlaySelected: playTrack,
      ),
      const PlayerScreen(),
      AiCollectionsScreen(
        key: _libraryCategory == null
            ? AiCollectionsScreen.globalKey
            : ValueKey(_libraryCategory),
        initialCategory: _libraryCategory,
        allTracks: _deviceLibrary,
        onPlaySelected: playTrack,
      ),
      SettingsScreen(
        accentColor: SectionAccents.settings(isDark),
        isThemeOne: isDark,
        onThemeToggle: (value) {
          UserPreferencesService.instance.setTheme(value);
          setState(() => _isThemeOne = value);
        },
      ),
    ];

    return Theme(
      data: SoundMindTheme.data(isThemeOne: isDark),
      child: Scaffold(
        // No AppBar — each screen has its own PageHeader
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Ambient background — base layer
            Positioned.fill(
              child: AmbientBackground(isThemeOne: isDark),
            ),

            // Screens
            Positioned.fill(
              child: IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
            ),

            // Floating Circle Bubble when mini player is collapsed
            if (_isMiniPlayerFloating && _currentIndex != AppNavigation.playerTab)
              FloatingMusicBubble(
                accentColor: accentColor,
                onOpenPlayer: () {
                  setState(() {
                    _previousIndex = _currentIndex;
                    _currentIndex = AppNavigation.playerTab;
                  });
                },
                onDismiss: () {
                  setState(() {
                    _isMiniPlayerFloating = false;
                  });
                },
                onRestoreMiniPlayer: () {
                  setState(() {
                    _isMiniPlayerFloating = false;
                  });
                },
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          bottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini player above nav (hidden when in floating mode)
              if (_currentIndex != AppNavigation.playerTab && !_isMiniPlayerFloating)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: MiniPlayer(
                    accentColor: accentColor,
                    onTap: () {
                      setState(() {
                        _previousIndex = _currentIndex;
                        _currentIndex = AppNavigation.playerTab;
                      });
                    },
                    onConvertToFloating: () {
                      setState(() {
                        _isMiniPlayerFloating = true;
                      });
                    },
                  ),
                ),

              // Bottom nav — floating glass pill
              _BottomNav(
                currentIndex: _currentIndex,
                accentColor: accentColor,
                isThemeOne: isDark,
                onTabSelected: (index) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ──────────────────────── Bottom Nav ────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.accentColor,
    required this.isThemeOne,
    required this.onTabSelected,
  });

  final int currentIndex;
  final Color accentColor;
  final bool isThemeOne;
  final ValueChanged<int> onTabSelected;

  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.search_rounded, label: 'Search'),
    _NavItem(icon: Icons.play_circle_fill_rounded, label: 'Player'),
    _NavItem(icon: Icons.grid_view_rounded, label: 'Library'),
    _NavItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // Ensure active element color has strong contrast in both dark and light modes
    final effectiveAccent = isThemeOne
        ? accentColor
        : (accentColor == const Color(0xFF38BDF8)
            ? const Color(0xFF0284C7)
            : accentColor);

    return Padding(
      padding: AppSpacing.bottomNavOuter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppBlur.glass2,
            sigmaY: AppBlur.glass2,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isThemeOne
                  ? const Color(0xFF091428).withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(
                color: isThemeOne
                    ? Colors.white.withValues(alpha: 0.10)
                    : const Color(0xFFCBD5E1),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isThemeOne
                      ? Colors.black.withValues(alpha: 0.40)
                      : const Color(0xFF0F172A).withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                _items.length,
                (i) => Expanded(
                  child: _NavTab(
                    item: _items[i],
                    isSelected: currentIndex == i,
                    accentColor: effectiveAccent,
                    isThemeOne: isThemeOne,
                    onTap: () => onTabSelected(i),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.isSelected,
    required this.accentColor,
    required this.isThemeOne,
    required this.onTap,
  });

  final _NavItem item;
  final bool isSelected;
  final Color accentColor;
  final bool isThemeOne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactiveColor = isThemeOne
        ? Colors.white.withValues(alpha: 0.60)
        : const Color(0xFF475569);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppDurations.pillTab,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: isThemeOne ? 0.18 : 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(
                  color: accentColor.withValues(alpha: isThemeOne ? 0.45 : 0.35),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: AppDurations.fast,
              child: Icon(
                item.icon,
                key: ValueKey('${item.label}_$isSelected'),
                size: 22,
                color: isSelected ? accentColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: TextStyle(
                color: isSelected ? accentColor : inactiveColor,
                fontFamily: AppTypography.uiFont,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}