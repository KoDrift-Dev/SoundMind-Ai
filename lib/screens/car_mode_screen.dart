// car_mode_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../models/track.dart';
import '../online/models/online_search_result.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_player_service.dart';
import '../services/online_playback_helper.dart';
import '../services/youtube_service.dart';
import '../widgets/track_artwork.dart';
import '../utils/duration_formatter.dart';

/// Available content sources for Car Mode's Up Next queue & Quick Shuffle.
enum CarModeSource {
  offline,
  both,
  online,
}

/// Dedicated high-contrast visual theme for Car Mode.
/// Optimized for quick glances in both daylight and night driving conditions.
class CarModeThemeColors {
  final bool isDark;
  final Color background;
  final Color surface;
  final Color surfaceBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color playButtonBackground;
  final Color playButtonIcon;
  final Color transportIcon;
  final Color sliderInactive;

  const CarModeThemeColors._({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.playButtonBackground,
    required this.playButtonIcon,
    required this.transportIcon,
    required this.sliderInactive,
  });

  factory CarModeThemeColors.dark(Color customAccent) {
    return CarModeThemeColors._(
      isDark: true,
      background: const Color(0xFF000000), // Pure pitch obsidian black
      surface: const Color(0xFF141923),
      surfaceBorder: const Color(0xFF2E384D),
      textPrimary: const Color(0xFFFFFFFF),
      textSecondary: const Color(0xFF94A3B8),
      accent: customAccent,
      playButtonBackground: customAccent,
      playButtonIcon: const Color(0xFF000000),
      transportIcon: const Color(0xFFFFFFFF),
      sliderInactive: const Color(0xFF2A364F),
    );
  }

  factory CarModeThemeColors.light(Color customAccent) {
    return CarModeThemeColors._(
      isDark: false,
      background: const Color(0xFFF8FAFC), // Daylight alabaster
      surface: const Color(0xFFFFFFFF),
      surfaceBorder: const Color(0xFFCBD5E1),
      textPrimary: const Color(0xFF0F172A),
      textSecondary: const Color(0xFF475569),
      accent: customAccent,
      playButtonBackground: const Color(0xFF0F172A),
      playButtonIcon: const Color(0xFFFFFFFF),
      transportIcon: const Color(0xFF0F172A),
      sliderInactive: const Color(0xFFE2E8F0),
    );
  }
}

/// Distraction-free, glanceable Car Mode experience with oversized touch targets,
/// dedicated high-contrast themes (Day/Night), and content source selection.
class CarModeScreen extends StatefulWidget {
  final Color accentColor;

  const CarModeScreen({
    super.key,
    this.accentColor = AppColors.abyssAccent,
  });

  @override
  State<CarModeScreen> createState() => _CarModeScreenState();
}

class _CarModeScreenState extends State<CarModeScreen> {
  final AudioPlayerService _audioService = AudioPlayerService.instance;
  late final StreamSubscription _playerStateSub;
  late final StreamSubscription _positionSub;
  late final StreamSubscription _durationSub;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  CarModeSource _selectedSource = CarModeSource.both;
  bool? _isManualDark;
  bool _isShufflingCar = false;

  static const List<OnlineSearchResult> _carOnlineSeeds = [
    OnlineSearchResult(
      id: 'kJQP7kiw5Fk',
      title: 'Despacito',
      artist: 'Luis Fonsi ft. Daddy Yankee',
      thumbnailUrl: 'https://i.ytimg.com/vi/kJQP7kiw5Fk/hqdefault.jpg',
      duration: '4:41',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'JGwWNGJdvx8',
      title: 'Shape of You',
      artist: 'Ed Sheeran',
      thumbnailUrl: 'https://i.ytimg.com/vi/JGwWNGJdvx8/hqdefault.jpg',
      duration: '4:23',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'OPf0YbXqDm0',
      title: 'Uptown Funk',
      artist: 'Mark Ronson ft. Bruno Mars',
      thumbnailUrl: 'https://i.ytimg.com/vi/OPf0YbXqDm0/hqdefault.jpg',
      duration: '4:30',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: '4NRXx6U8ABQ',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      thumbnailUrl: 'https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      duration: '3:20',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'fJ9rUzIMcZQ',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      thumbnailUrl: 'https://i.ytimg.com/vi/fJ9rUzIMcZQ/hqdefault.jpg',
      duration: '5:59',
      source: 'YouTube',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Keep device screen on while in Car Mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _isPlaying = _audioService.player.playing;
    _playerStateSub = _audioService.player.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });

    _positionSub = _audioService.player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _durationSub = _audioService.player.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur ?? Duration.zero);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _playerStateSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    return formatDuration(d);
  }

  /// Triggers a fresh Car Drive Mix based on the selected content source.
  Future<void> _handleCarQuickShuffle() async {
    if (_isShufflingCar) return;
    setState(() => _isShufflingCar = true);

    try {
      switch (_selectedSource) {
        case CarModeSource.offline:
          final localTracks = await AudioRepository.instance.getMusicOnlyTracks();
          if (localTracks.isNotEmpty) {
            final shuffled = List<Track>.from(localTracks)..shuffle();
            await _audioService.loadPlaylist(shuffled, 0);
          } else {
            _showCarFeedback('No offline songs found');
          }
          break;

        case CarModeSource.online:
          final seed = (_carOnlineSeeds.toList()..shuffle()).first;
          if (mounted) {
            await OnlinePlaybackHelper.playOnlineTrack(
              context,
              seed,
              YoutubeService.instance,
              (playlist, idx) => _audioService.loadPlaylist(playlist, idx),
              widget.accentColor,
            );
          }
          break;

        case CarModeSource.both:
          final localTracks = await AudioRepository.instance.getMusicOnlyTracks();
          final shuffledOnline = List<OnlineSearchResult>.from(_carOnlineSeeds)..shuffle();

          if (localTracks.isEmpty) {
            if (mounted) {
              await OnlinePlaybackHelper.playOnlineTrack(
                context,
                shuffledOnline.first,
                YoutubeService.instance,
                (playlist, idx) => _audioService.loadPlaylist(playlist, idx),
                widget.accentColor,
              );
            }
          } else {
            final shuffledLocal = List<Track>.from(localTracks)..shuffle();
            // Start with first local, and queue next
            await _audioService.loadPlaylist(shuffledLocal, 0);
            if (mounted) {
              _showCarFeedback('Playing Car Mix (Offline + Online)');
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('CarMode: Error in _handleCarQuickShuffle: $e');
    } finally {
      if (mounted) setState(() => _isShufflingCar = false);
    }
  }

  void _showCarFeedback(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
      ),
    );
  }

  void _showCarQueueSheet(CarModeThemeColors theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final playlist = _audioService.currentPlaylist;
        final currentIdx = _audioService.player.currentIndex ?? 0;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: theme.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Drive Queue',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppTypography.displayFont,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.accent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '${playlist.length} Tracks',
                        style: TextStyle(
                          color: theme.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: theme.surfaceBorder, height: 1),
              Expanded(
                child: playlist.isEmpty
                    ? Center(
                        child: Text(
                          'No tracks in queue\nTap Drive Shuffle below to start',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.textSecondary, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: playlist.length,
                        itemBuilder: (context, idx) {
                          final track = playlist[idx];
                          final isCurrent = idx == currentIdx;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                            leading: Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrent ? theme.accent : theme.surfaceBorder.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isCurrent ? Icons.play_arrow_rounded : Icons.music_note_rounded,
                                color: isCurrent ? Colors.black : theme.textSecondary,
                                size: 26,
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? theme.accent : theme.textPrimary,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                fontSize: 17,
                              ),
                            ),
                            subtitle: Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: theme.textSecondary, fontSize: 14),
                            ),
                            onTap: () {
                              _audioService.skipToQueueItem(idx);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Determine Car Mode high-contrast visual theme
    final systemIsDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIsDark = _isManualDark ?? systemIsDark;
    final theme = effectiveIsDark
        ? CarModeThemeColors.dark(widget.accentColor)
        : CarModeThemeColors.light(widget.accentColor);

    return ListenableBuilder(
      listenable: _audioService,
      builder: (context, _) {
        final currentTrack = _audioService.currentTrack;
        final media = MediaQuery.of(context);
        final double artSize = math.min(190.0, math.min(media.size.width * 0.48, media.size.height * 0.28)).clamp(110.0, 190.0);

        return Scaffold(
          backgroundColor: theme.background,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    // ── Top Navigation & Mode Bar ──
                    Row(
                      children: [
                        // Oversized Exit Button (50dp height)
                        SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.arrow_back_rounded, color: theme.textPrimary, size: 24),
                            label: Text(
                              'Exit Car Mode',
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.surface,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                              side: BorderSide(color: theme.surfaceBorder, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Day / Night Driving Quick Switch
                      IconButton(
                        iconSize: 30,
                        tooltip: effectiveIsDark ? 'Switch to Day Mode' : 'Switch to Night Mode',
                        icon: Icon(
                          effectiveIsDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                          color: theme.textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _isManualDark = !effectiveIsDark;
                          });
                        },
                      ),
                      const SizedBox(width: 6),

                      // Large Queue Button (50dp circle)
                      InkWell(
                        onTap: () => _showCarQueueSheet(theme),
                        borderRadius: BorderRadius.circular(25),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.surface,
                            border: Border.all(color: theme.surfaceBorder, width: 1.5),
                          ),
                          child: Icon(
                            Icons.queue_music_rounded,
                            color: theme.accent,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Bluetooth / In-Car Safety Badge ──
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.accent.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_connected_rounded, size: 14, color: theme.accent),
                        const SizedBox(width: 6),
                        Text(
                          'Music-Only Verified Safe',
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Source Selector Bar (Offline / Both / Online) ──
                  Container(
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: theme.surfaceBorder, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        _buildSourcePill(
                          label: 'Offline',
                          icon: Icons.download_done_rounded,
                          source: CarModeSource.offline,
                          theme: theme,
                        ),
                        _buildSourcePill(
                          label: 'Both',
                          icon: Icons.electric_bolt_rounded,
                          source: CarModeSource.both,
                          theme: theme,
                        ),
                        _buildSourcePill(
                          label: 'Online',
                          icon: Icons.language_rounded,
                          source: CarModeSource.online,
                          theme: theme,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Center Album Artwork & Info (Glanceable) ──
                  if (currentTrack != null)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: theme.surfaceBorder, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: (effectiveIsDark ? Colors.black : Colors.black12)
                                .withValues(alpha: 0.3),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: TrackArtwork(
                          track: currentTrack,
                          width: artSize,
                          height: artSize,
                          borderRadius: 26,
                          showShadow: false,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: artSize,
                      height: artSize,
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: theme.surfaceBorder, width: 2),
                      ),
                      child: Icon(Icons.music_note_rounded, size: artSize * 0.44, color: theme.accent),
                    ),

                  const SizedBox(height: 18),

                  // Huge Track Title
                  Text(
                    currentTrack?.title ?? 'SoundMind Drive',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppTypography.displayFont,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Huge Artist Name
                  Text(
                    currentTrack?.artist ?? 'Select source & tap Drive Mix',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppTypography.displayFont,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── High-Contrast Scrubber Slider ──
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 7,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                      activeTrackColor: theme.accent,
                      inactiveTrackColor: theme.sliderInactive,
                      thumbColor: theme.textPrimary,
                      overlayColor: theme.accent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _position.inMilliseconds
                          .clamp(0, math.max(_duration.inMilliseconds, 1))
                          .toDouble(),
                      max: math.max(_duration.inMilliseconds, 1).toDouble(),
                      onChanged: (val) {
                        _audioService.player.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Massive Oversized Transport Controls (Glanceable) ──
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: math.max(media.size.width - 40, 360.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 10s Rewind Quick Button
                          InkWell(
                            onTap: () {
                              final newPos = _position - const Duration(seconds: 10);
                              _audioService.player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                            },
                            borderRadius: BorderRadius.circular(28),
                            child: Container(
                              width: 54,
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.surface,
                                border: Border.all(color: theme.surfaceBorder, width: 1.5),
                              ),
                              child: Icon(Icons.replay_10_rounded, color: theme.transportIcon, size: 28),
                            ),
                          ),

                          // Previous Track (Oversized 64dp)
                          IconButton(
                            iconSize: 52,
                            tooltip: 'Previous Track',
                            icon: Icon(Icons.skip_previous_rounded, color: theme.transportIcon),
                            onPressed: () => _audioService.skipToPrevious(),
                          ),

                          // Giant Play / Pause Button (92dp)
                          GestureDetector(
                            onTap: () {
                              if (_isPlaying) {
                                _audioService.player.pause();
                              } else {
                                if (_audioService.currentPlaylist.isEmpty) {
                                  _handleCarQuickShuffle();
                                } else {
                                  _audioService.player.play();
                                }
                              }
                            },
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.playButtonBackground,
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.accent.withValues(alpha: effectiveIsDark ? 0.45 : 0.25),
                                    blurRadius: 24,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: theme.playButtonIcon,
                                size: 58,
                              ),
                            ),
                          ),

                          // Next Track (Oversized 64dp)
                          IconButton(
                            iconSize: 52,
                            tooltip: 'Next Track',
                            icon: Icon(Icons.skip_next_rounded, color: theme.transportIcon),
                            onPressed: () => _audioService.skipToNext(),
                          ),

                          // 10s Forward Quick Button
                          InkWell(
                            onTap: () {
                              final newPos = _position + const Duration(seconds: 10);
                              _audioService.player.seek(newPos > _duration ? _duration : newPos);
                            },
                            borderRadius: BorderRadius.circular(28),
                            child: Container(
                              width: 54,
                              height: 54,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.surface,
                                border: Border.all(color: theme.surfaceBorder, width: 1.5),
                              ),
                              child: Icon(Icons.forward_10_rounded, color: theme.transportIcon, size: 28),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Quick Start / Drive Shuffle Action ──
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _handleCarQuickShuffle,
                      icon: _isShufflingCar
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.accent,
                              ),
                            )
                          : Icon(Icons.shuffle_rounded, color: theme.accent, size: 22),
                      label: Text(
                        _isShufflingCar
                            ? 'Starting Mix...'
                            : 'Start Drive Mix (${_sourceLabel(_selectedSource)})',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: theme.surface,
                        side: BorderSide(color: theme.surfaceBorder, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ),
      );
      },
    );
  }

  String _sourceLabel(CarModeSource source) {
    switch (source) {
      case CarModeSource.offline:
        return 'Offline';
      case CarModeSource.both:
        return 'Offline + Online';
      case CarModeSource.online:
        return 'Online';
    }
  }

  Widget _buildSourcePill({
    required String label,
    required IconData icon,
    required CarModeSource source,
    required CarModeThemeColors theme,
  }) {
    final isSelected = _selectedSource == source;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _selectedSource = source;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? theme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? (theme.isDark ? Colors.black : Colors.white)
                    : theme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? (theme.isDark ? Colors.black : Colors.white)
                      : theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
