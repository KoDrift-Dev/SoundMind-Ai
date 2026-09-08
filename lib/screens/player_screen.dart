// player_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_blur.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_durations.dart';
import '../core/constants/app_opacity.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/helpers/accent_color_helper.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/download/online_download_helper.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/track_artwork.dart';
import '../utils/duration_formatter.dart';
import 'car_mode_screen.dart';
import 'main_navigation.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  
  bool _isPlaying = false;
  int _currentIndex = 0;

  Duration _totalDuration = Duration.zero;

  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  final bool _isDownloaded = false;
  bool _showRemainingTime = false;

  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufferedNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);

  double _speed = 1.0;
  double _pitch = 1.0;
  double _volume = 1.0;
  bool _isSpeedFlyoutOpen = false;
  int _abSetupStep = 0; // 0: idle, 1: select Point A, 2: select Point B

  late final StreamSubscription _playerStateSub;
  late final StreamSubscription _positionSub;
  late final StreamSubscription _bufferedPositionSub;
  late final StreamSubscription _durationSub;
  late final StreamSubscription _indexSub;
  late final StreamSubscription _shuffleSub;
  late final StreamSubscription _loopSub;
  late final StreamSubscription _volumeSub;

  Track get _currentTrack {
    final cur = AudioPlayerService.instance.currentTrack;
    if (cur != null) return cur;
    final playlist = AudioPlayerService.instance.currentPlaylist;
    if (playlist.isEmpty || _currentIndex < 0 || _currentIndex >= playlist.length) {
      return Track(title: 'Not Playing', artist: 'SoundMind', artUrl: '');
    }
    return playlist[_currentIndex];
  }

  // ───────────────────────── Physics Controllers ─────────────────────────

  late final AnimationController _rotationController;
  late final AnimationController _breathController;
  late final Animation<double> _breathCurve;
  late final AnimationController _waveController;
  late final AnimationController _intensityController;
  late final AnimationController _barController;
  late final AnimationController _cycleController;

  @override
  void initState() {
    super.initState();
    
    _rotationController = AnimationController(
      vsync: this,
      duration: AppDurations.playerRotation,
    );

    _breathController = AnimationController(
      vsync: this,
      duration: AppDurations.playerBreath,
    )..repeat();
    
    _breathCurve = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOut,
    );

    _waveController = AnimationController(
      vsync: this,
      duration: AppDurations.playerWave,
    )..repeat();

    _intensityController = AnimationController(
      vsync: this,
      duration: AppDurations.playerIntensity,
      value: 0.0,
    );

    _barController = AnimationController(
      vsync: this,
      duration: AppDurations.playerBar,
    )..repeat();

    _cycleController = AnimationController(
      vsync: this,
      duration: AppDurations.playerCycle,
    )..repeat();

    _initAudioPlayerListeners();
  }

  void _initAudioPlayerListeners() {
    final audioService = AudioPlayerService.instance;

    _currentIndex = audioService.player.currentIndex ?? 0;
    _isPlaying = audioService.player.playing;
    _speed = audioService.player.speed;
    _volume = audioService.lastKnownDeviceVolume;
    
    final initialDuration = audioService.player.duration ??
        (_currentTrack.duration != null && _currentTrack.duration! > 0
            ? Duration(milliseconds: _currentTrack.duration!)
            : Duration.zero);
    _totalDuration = initialDuration;
    _durationNotifier.value = initialDuration;

    if (_isPlaying) {
      _rotationController.repeat();
      _barController.repeat();
      _intensityController.value = 1.0;
    }

    _playerStateSub = audioService.player.playerStateStream.listen((state) {
      if (!mounted) return;
      final isPlaying = state.playing;
      if (isPlaying != _isPlaying) {
        setState(() => _isPlaying = isPlaying);
        if (isPlaying) {
          _rotationController.repeat();
          _barController.repeat();
          _intensityController.animateTo(1.0, curve: Curves.easeOutCubic);
        } else {
          _rotationController.stop(); // Stops IMMEDIATELY on pause
          _barController.stop();
          _intensityController.animateTo(0.0, curve: Curves.easeInCubic); // Moves needle back out
        }
      }
    });

    _positionSub = audioService.player.positionStream.listen((pos) {
      if (!mounted) return;
      _positionNotifier.value = pos;
    });

    _bufferedPositionSub = audioService.player.bufferedPositionStream.listen((pos) {
      if (!mounted) return;
      _bufferedNotifier.value = pos;
    });

    _durationSub = audioService.player.durationStream.listen((dur) {
      if (!mounted) return;
      final effective = (dur != null && dur > Duration.zero)
          ? dur
          : (_currentTrack.duration != null && _currentTrack.duration! > 0
              ? Duration(milliseconds: _currentTrack.duration!)
              : Duration.zero);
      _durationNotifier.value = effective;
      setState(() => _totalDuration = effective);
    });

    _indexSub = audioService.player.currentIndexStream.listen((index) {
      if (!mounted) return;
      if (index != null && index >= 0 && index < AudioPlayerService.instance.currentPlaylist.length) {
        setState(() {
          _currentIndex = index;
          if (_currentTrack.duration != null && _currentTrack.duration! > 0) {
            final trackDur = Duration(milliseconds: _currentTrack.duration!);
            if (_totalDuration == Duration.zero) {
              _totalDuration = trackDur;
              _durationNotifier.value = trackDur;
            }
          }
        });
      }
    });

    _shuffleSub = audioService.player.shuffleModeEnabledStream.listen((enabled) {
      if (!mounted) return;
      setState(() => _isShuffle = enabled);
    });

    _loopSub = audioService.player.loopModeStream.listen((mode) {
      if (!mounted) return;
      setState(() => _loopMode = mode);
    });

    _volumeSub = audioService.deviceVolumeStream.listen((vol) {
      if (!mounted) return;
      setState(() => _volume = vol);
    });

    audioService.addListener(_onAudioServiceChanged);
  }

  void _onAudioServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    AudioPlayerService.instance.removeListener(_onAudioServiceChanged);
    _playerStateSub.cancel();
    _positionSub.cancel();
    _bufferedPositionSub.cancel();
    _durationSub.cancel();
    _indexSub.cancel();
    _shuffleSub.cancel();
    _loopSub.cancel();
    _volumeSub.cancel();

    _rotationController.dispose();
    _breathController.dispose();
    _waveController.dispose();
    _intensityController.dispose();
    _barController.dispose();
    _cycleController.dispose();

    _positionNotifier.dispose();
    _bufferedNotifier.dispose();
    _durationNotifier.dispose();
    super.dispose();
  }

  // ───────────────────────── Formatting & Logic ─────────────────────────

  String _formatDuration(int? ms) {
    return formatDurationMs(ms, placeholder: '0:00');
  }

  String _formatSize(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  void _closeFlyoutsIfOpen() {
    if (_isSpeedFlyoutOpen) {
      setState(() => _isSpeedFlyoutOpen = false);
    }
  }

  void _showFeedbackToast(String message) {
    if (!mounted) return;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: AppDurations.snackbarShort,
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
        elevation: 8,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white12 : Colors.white24,
            width: 0.8,
          ),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  void _handleScrub(double value) {
    _closeFlyoutsIfOpen();
    final ms = (_totalDuration.inMilliseconds * value).round();
    final pos = Duration(milliseconds: ms);
    _positionNotifier.value = pos;

    if (_abSetupStep == 1) {
      AudioPlayerService.instance.setAbPointA(pos);
      AudioPlayerService.instance.player.seek(pos);
      setState(() => _abSetupStep = 2);
      _showFeedbackToast('Point A set: ${_formatDuration(ms)}. Now tap progress bar for Point B');
      return;
    }

    if (_abSetupStep == 2) {
      final pointA = AudioPlayerService.instance.abPointA;
      if (pointA != null && pos <= pointA) {
        _showFeedbackToast('Point B must be after Point A (${_formatDuration(pointA.inMilliseconds)})');
        return;
      }
      AudioPlayerService.instance.setAbPointB(pos);
      if (pointA != null) {
        AudioPlayerService.instance.player.seek(pointA);
      }
      setState(() => _abSetupStep = 0);
      _showFeedbackToast(
        pointA != null
            ? 'A-B Loop Active: ${_formatDuration(pointA.inMilliseconds)} → ${_formatDuration(ms)}'
            : 'Point B set: ${_formatDuration(ms)}',
      );
      return;
    }

    AudioPlayerService.instance.player.seek(pos);
  }

  void _togglePlayback() {
    _closeFlyoutsIfOpen();
    final player = AudioPlayerService.instance.player;
    if (player.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  void _skipNext() {
    _closeFlyoutsIfOpen();
    AudioPlayerService.instance.skipToNext();
  }
  
  void _skipPrevious() {
    _closeFlyoutsIfOpen();
    AudioPlayerService.instance.player.seekToPrevious();
  }

  void _toggleFavorite() {
    _closeFlyoutsIfOpen();
    AudioPlayerService.instance.toggleFavorite(_currentTrack);
    setState(() {});
    _showFeedbackToast(_currentTrack.isFavorite ? 'Added to favorites' : 'Removed from favorites');
  }
  
  void _toggleShuffle() {
    final player = AudioPlayerService.instance.player;
    final enabled = !player.shuffleModeEnabled;
    player.setShuffleModeEnabled(enabled);
    _showFeedbackToast(enabled ? 'Shuffle On' : 'Shuffle Off');
  }

  void _toggleRepeat() {
    final player = AudioPlayerService.instance.player;
    LoopMode nextMode;
    if (player.loopMode == LoopMode.off) {
      nextMode = LoopMode.all;
    } else if (player.loopMode == LoopMode.all) {
      nextMode = LoopMode.one;
    } else {
      nextMode = LoopMode.off;
    }
    player.setLoopMode(nextMode);
    
    String label = 'Repeat Off';
    if (nextMode == LoopMode.all) label = 'Repeat All';
    if (nextMode == LoopMode.one) label = 'Repeat One';
    
    _showFeedbackToast(label);
  }

  bool get _isCurrentTrackOnline {
    final t = _currentTrack;
    if (t.isDownloaded) return false;
    final path = t.filePath ?? '';
    if (path.startsWith('http://') || path.startsWith('https://')) return true;
    if (path.isEmpty && t.title.isNotEmpty && t.title != 'Not Playing' && t.title != '<unknown>') return true;
    return false;
  }

  void _triggerOnlineDownload(Color accentColor) {
    _closeFlyoutsIfOpen();
    final t = _currentTrack;
    if (!_isCurrentTrackOnline) {
      _showFeedbackToast('Track is already saved locally');
      return;
    }

    OnlineDownloadHelper.openDownloadSheet(
      context,
      accentColor: accentColor,
      currentTrack: t,
      sourceCaller: 'PlayerScreen(ActionBar)',
    );
  }

  void _share() async {
    if (AudioPlayerService.instance.currentPlaylist.isEmpty) {
      _showFeedbackToast('No track selected');
      return;
    }

    final track = _currentTrack;
    final text = '${track.title} by ${track.artist}';
    
    try {
      if (track.filePath != null && track.filePath!.isNotEmpty && !track.filePath!.startsWith('http')) {
        final file = File(track.filePath!);
        if (await file.exists()) {
          await Share.shareXFiles([XFile(track.filePath!)], text: text);
          return;
        }
      }
      // Fallback to text if file is not local or sharing file fails
      await Share.share(text);
    } catch (e) {
      if (!mounted) return;
      _showFeedbackToast('Could not share track');
    }
  }

  void _showPlaylistSearchSheet(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (context) {
        return _PlaylistSearchSheet(accentColor: accentColor);
      },
    );
  }

  // ───────────────────────── Speed / Pitch / Volume ─────────────────────────

  void _setSpeed(double value) {
    AudioPlayerService.instance.player.setSpeed(value);
    setState(() => _speed = value);
  }

  void _setPitch(double value) {
    AudioPlayerService.instance.player.setPitch(value);
    setState(() => _pitch = value);
  }

  void _setVolume(double value) {
    AudioPlayerService.instance.setDeviceVolume(value);
  }

  void _handleAbRepeatTap(Color accentColor) {
    _closeFlyoutsIfOpen();
    final service = AudioPlayerService.instance;
    final bool isAbActive = service.abPointA != null && service.abPointB != null;

    if (isAbActive) {
      service.clearAbRepeat();
      setState(() => _abSetupStep = 0);
      _showFeedbackToast('A-B Repeat cleared');
      return;
    }

    if (_abSetupStep == 0) {
      setState(() => _abSetupStep = 1);
      _showFeedbackToast('Tap progress bar to set Point A');
      return;
    }

    if (_abSetupStep == 1) {
      setState(() => _abSetupStep = 0);
      _showFeedbackToast('A-B setup cancelled');
      return;
    }

    if (_abSetupStep == 2) {
      service.clearAbRepeat();
      setState(() => _abSetupStep = 0);
      _showFeedbackToast('A-B setup cancelled');
      return;
    }
  }

  // ignore: unused_element
  void _showAbRepeatSheet(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color cardBg = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04);
    final Color cardBorder = isDark ? Colors.white12 : Colors.black12;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.repeat_on_rounded, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A-B Repeat Looper',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 17,
                              fontFamily: AppTypography.displayFont,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Loop a specific segment continuously',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                              fontFamily: AppTypography.bodyFont,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Card for Point A
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: accentColor.withValues(alpha: 0.2),
                      child: Text('A', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    title: Text('Point A (Start)', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      AudioPlayerService.instance.abPointA != null
                          ? 'Set at ${_formatDuration(AudioPlayerService.instance.abPointA!.inMilliseconds)}'
                          : 'Not set (current playback)',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        final pos = AudioPlayerService.instance.player.position;
                        AudioPlayerService.instance.setAbPointA(pos);
                        Navigator.pop(sheetContext);
                        setState(() => _abSetupStep = 2);
                        _showFeedbackToast('Point A set: ${_formatDuration(pos.inMilliseconds)}. Now tap progress bar for Point B');
                      },
                      child: Text(
                        AudioPlayerService.instance.abPointA != null ? 'Update A' : 'Set A',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Card for Point B
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: accentColor.withValues(alpha: 0.2),
                      child: Text('B', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    title: Text('Point B (End)', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(
                      AudioPlayerService.instance.abPointB != null
                          ? 'Set at ${_formatDuration(AudioPlayerService.instance.abPointB!.inMilliseconds)}'
                          : 'Not set (current playback)',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        final service = AudioPlayerService.instance;
                        final pos = service.player.position;
                        if (service.abPointA != null && pos <= service.abPointA!) {
                          _showFeedbackToast('Point B must be after Point A.');
                        } else {
                          service.setAbPointB(pos);
                          Navigator.pop(sheetContext);
                          setState(() => _abSetupStep = 0);
                          _showFeedbackToast('Point B set: ${_formatDuration(pos.inMilliseconds)}');
                        }
                      },
                      child: Text(
                        AudioPlayerService.instance.abPointB != null ? 'Update B' : 'Set B',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                if (AudioPlayerService.instance.abPointA != null || AudioPlayerService.instance.abPointB != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        AudioPlayerService.instance.clearAbRepeat();
                        Navigator.pop(sheetContext);
                        setState(() => _abSetupStep = 0);
                        _showFeedbackToast('A-B Repeat cleared');
                      },
                      icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.redAccent),
                      label: const Text('Clear A-B Loop', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpeedPitchSheet(Color accentColor) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                final bool isLightAccent = accentColor.computeLuminance() > 0.5;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Playback Speed', style: TextStyle(color: textColor, fontSize: 15, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold)),
                          Text('${_speed.toStringAsFixed(2)}x', style: TextStyle(color: accentColor, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: speeds.map((s) {
                          final bool selected = (_speed - s).abs() < 0.01;
                          final Color chipLabelColor = selected
                              ? (isLightAccent ? Colors.black87 : Colors.white)
                              : textColor;
                          return ChoiceChip(
                            label: Text('${s}x'),
                            selected: selected,
                            selectedColor: accentColor,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            side: BorderSide(
                              color: selected ? accentColor : (isDark ? Colors.white12 : Colors.black12),
                            ),
                            labelStyle: TextStyle(
                              color: chipLabelColor,
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            ),
                            onSelected: (_) {
                              _setSpeed(s);
                              setSheetState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pitch', style: TextStyle(color: textColor, fontSize: 15, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold)),
                          if ((_pitch - 1.0).abs() > 0.01)
                            GestureDetector(
                              onTap: () {
                                _setPitch(1.0);
                                setSheetState(() {});
                              },
                              child: Text('Reset', style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                        ),
                        child: SizedBox(
                          height: 24,
                          child: Slider(
                            value: _pitch,
                            min: 0.5,
                            max: 1.5,
                            activeColor: accentColor,
                            inactiveColor: isDark ? Colors.white24 : Colors.black12,
                            onChanged: (v) {
                              _setPitch(v);
                              setSheetState(() {});
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('0.5x (Deep)', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                            Text('1.0x (Original)', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                            Text('1.5x (High)', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showVolumeSheet(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color iconColor = isDark ? Colors.white60 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<double>(
                    stream: AudioPlayerService.instance.deviceVolumeStream,
                    initialData: AudioPlayerService.instance.lastKnownDeviceVolume,
                    builder: (context, snapshot) {
                      final vol = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
                      final int pct = (vol * 100).round();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Volume', style: TextStyle(color: textColor, fontSize: 16, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('$pct%', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.volume_down_rounded, color: iconColor),
                              Expanded(
                                child: Slider(
                                  value: vol,
                                  min: 0.0,
                                  max: 1.0,
                                  activeColor: accentColor,
                                  inactiveColor: isDark ? Colors.white24 : Colors.black12,
                                  onChanged: _setVolume,
                                ),
                              ),
                              Icon(Icons.volume_up_rounded, color: iconColor),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Audio Boost', style: TextStyle(color: textColor, fontSize: 16, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Platform.isAndroid ? StreamBuilder<double>(
                    stream: AudioPlayerService.instance.audioBoostStream,
                    initialData: AudioPlayerService.instance.audioBoost,
                    builder: (context, snapshot) {
                      final currentBoost = snapshot.data ?? 1.0;
                      final bool isLightAccent = accentColor.computeLuminance() > 0.5;
                      return Wrap(
                        spacing: 8,
                        children: kAudioBoostLevels.map((level) {
                          final bool selected = (currentBoost - level).abs() < 0.01;
                          final Color chipLabelColor = selected
                              ? (isLightAccent ? Colors.black87 : Colors.white)
                              : textColor;
                          return ChoiceChip(
                            label: Text('${(level * 100).round()}%'),
                            selected: selected,
                            selectedColor: accentColor,
                            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            side: BorderSide(
                              color: selected ? accentColor : (isDark ? Colors.white12 : Colors.black12),
                            ),
                            labelStyle: TextStyle(color: chipLabelColor, fontWeight: selected ? FontWeight.bold : FontWeight.w500),
                            onSelected: (_) => AudioPlayerService.instance.setAudioBoost(level),
                          );
                        }).toList(),
                      );
                    },
                  ) : Text('Audio Boost is not supported on this platform.', style: TextStyle(color: secondaryTextColor, fontSize: 14, fontFamily: AppTypography.bodyFont)),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        EqualizerSheet.show(context, accentColor: accentColor);
                      },
                      icon: Icon(Icons.graphic_eq_rounded, color: accentColor),
                      label: Text('Audio Equalizer & Presets', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CarModeScreen(accentColor: accentColor),
                          ),
                        );
                      },
                      icon: Icon(Icons.directions_car_rounded, color: accentColor),
                      label: Text('Launch Car Mode (Safe Drive)', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────── Lyrics ─────────────────────────

  void _showLyricsSheet(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.55,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.lyrics_outlined, size: 52, color: accentColor),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No lyrics found',
                        style: TextStyle(color: textColor, fontSize: 18, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'SoundMind doesn\'t have lyrics for "${_currentTrack.title}" yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: secondaryTextColor, fontFamily: AppTypography.bodyFont),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ───────────────────────── File actions ─────────────────────────

  void _openFolder() {
    _showFeedbackToast('Open Folder — coming soon');
  }

  void _setAsRingtone() {
    _showFeedbackToast('Set as Ringtone — coming soon');
  }

  void _showAudioDetailsDialog() {
    final t = _currentTrack;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Audio Details', style: TextStyle(color: textColor, fontFamily: AppTypography.displayFont)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('Format', _extensionOf(t.filePath), isDark: isDark),
                _infoRow('Duration', _formatDuration(t.duration), isDark: isDark),
                _infoRow('File Size', t.size != null ? _formatSize(t.size!) : 'Unknown', isDark: isDark),
                _infoRow('Speed', '${_speed.toStringAsFixed(2)}x', isDark: isDark),
                _infoRow('Pitch', _pitch.toStringAsFixed(2), isDark: isDark),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AccentColorHelper.resolve(context), fontFamily: AppTypography.bodyFont)),
            )
          ],
        );
      },
    );
  }

  void _showPropertiesDialog() {
    final t = _currentTrack;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Properties', style: TextStyle(color: textColor, fontFamily: AppTypography.displayFont)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('File Path', t.filePath ?? 'Unknown', isDark: isDark),
                _infoRow('File Size', t.size != null ? _formatSize(t.size!) : 'Unknown', isDark: isDark),
                _infoRow('Date Added', t.dateAdded != null ? DateTime.fromMillisecondsSinceEpoch(t.dateAdded! * 1000).toString().split(' ')[0] : 'Unknown', isDark: isDark),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AccentColorHelper.resolve(context), fontFamily: AppTypography.bodyFont)),
            )
          ],
        );
      },
    );
  }

  String _extensionOf(String? path) {
    if (path == null || !path.contains('.')) return 'Unknown';
    return path.split('.').last.toUpperCase();
  }

  void _confirmDelete() {
    final t = _currentTrack;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Delete track?', style: TextStyle(color: textColor, fontFamily: AppTypography.displayFont)),
          content: Text(
            'This permanently deletes "${t.title}" from your device. This cannot be undone.',
            style: TextStyle(color: secondaryTextColor, fontFamily: AppTypography.bodyFont),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deleteCurrentTrack();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrentTrack() async {
    final t = _currentTrack;
    final indexToRemove = _currentIndex;
    try {
      if (t.filePath != null && t.filePath!.isNotEmpty && !t.filePath!.startsWith('http')) {
        final file = File(t.filePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      AudioPlayerService.instance.removeFromQueue(indexToRemove);
      if (!mounted) return;
      _showFeedbackToast('Deleted "${t.title}"');
      if (AudioPlayerService.instance.currentPlaylist.isEmpty) {
        _handleBack();
      }
    } catch (e) {
      if (!mounted) return;
      _showFeedbackToast('Could not delete file — check storage permission');
    }
  }

  // ───────────────────────── Bottom Sheets ─────────────────────────

  void _showQueueBottomSheet(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (context, scrollController) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!scrollController.hasClients) return;
                final currentIndex = AudioPlayerService.instance.player.currentIndex ?? 0;
                const estimatedTileHeight = 64.0;
                final target = (currentIndex * estimatedTileHeight)
                    .clamp(0.0, scrollController.position.maxScrollExtent);
                scrollController.animateTo(
                  target,
                  duration: AppDurations.snackbarShort,
                  curve: Curves.easeOut,
                );
              });
              return StreamBuilder<SequenceState?>(
                stream: AudioPlayerService.instance.player.sequenceStateStream,
                builder: (context, snapshot) {
                  final service = AudioPlayerService.instance;
                  final sequenceLength = snapshot.data?.sequence.length ?? service.currentPlaylist.length;
                  final safeLength = math.min(service.currentPlaylist.length, sequenceLength);
                  final playlist = service.currentPlaylist.take(safeLength).toList();
                  final activeIndex = snapshot.data?.currentIndex ?? -1;
          
                  if (playlist.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Text('Queue is empty', style: TextStyle(color: secondaryTextColor, fontFamily: AppTypography.bodyFont)),
                      ),
                    );
                  }
          
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Queue',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontFamily: AppTypography.displayFont,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton(
                              onPressed: playlist.length <= 1
                                  ? null
                                  : () => AudioPlayerService.instance.clearQueue(),
                              child: Text('Clear', style: TextStyle(color: accentColor, fontFamily: AppTypography.bodyFont)),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                      Expanded(
                        child: ReorderableListView.builder(
                          scrollController: scrollController,
                          itemCount: playlist.length,
                          onReorderItem: (oldIndex, newIndex) {
                            if (oldIndex < playlist.length) {
                              AudioPlayerService.instance.reorderQueueItem(oldIndex, newIndex);
                            }
                          },
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              color: Colors.transparent,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15), blurRadius: 10, spreadRadius: 2),
                                  ],
                                ),
                                child: child,
                              ),
                            );
                          },
                          itemBuilder: (context, index) {
                            final track = playlist[index];
                            final isPlaying = index == activeIndex;
                            return ListTile(
                              key: ValueKey('${track.onlineId ?? track.id ?? track.title}_$index'),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                              selected: isPlaying,
                              selectedTileColor: accentColor.withValues(alpha: 0.1),
                              leading: TrackArtwork(track: track, width: 48, height: 48, borderRadius: AppRadius.artwork / 2),
                              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isPlaying ? accentColor : textColor, fontFamily: AppTypography.bodyFont, fontWeight: FontWeight.w600)),
                              subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: secondaryTextColor, fontFamily: AppTypography.bodyFont)),
                              onTap: () {
                                final freshList = AudioPlayerService.instance.currentPlaylist;
                                final freshIndex = freshList.indexWhere((t) => t.id == track.id);
                                if (freshIndex != -1) {
                                  AudioPlayerService.instance.player.seek(Duration.zero, index: freshIndex);
                                }
                                Navigator.pop(context);
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black45, size: 20),
                                    onPressed: () {
                                      final freshList = AudioPlayerService.instance.currentPlaylist;
                                      final freshIndex = freshList.indexWhere((t) => t.id == track.id);
                                      if (freshIndex != -1) {
                                        AudioPlayerService.instance.removeFromQueue(freshIndex);
                                      }
                                    },
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(Icons.drag_handle_rounded, color: isDark ? Colors.white30 : Colors.black26),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
              );
            },
          ),
        );
      }
    );
  }

  void _showMoreMenu(Color accentColor) {
    _closeFlyoutsIfOpen();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color sheetBg = isDark ? const Color(0xFF131A2A) : Colors.white;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.50,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.more_horiz_rounded, color: accentColor, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'More Options',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppTypography.displayFont,
                        ),
                      ),
                      const Spacer(),
                      if (_currentTrack.title != '<unknown>')
                        Flexible(
                          child: Text(
                            _currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontSize: 12,
                              fontFamily: AppTypography.bodyFont,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      _buildMenuTile(Icons.stop_circle_outlined, 'Stop Playback', () async {
                        final nav = Navigator.of(this.context);
                        Navigator.pop(context);
                        await AudioPlayerService.instance.stopAndReset();
                        if (mounted) {
                          nav.pop();
                        }
                      }, isDark: isDark),
                      _buildMenuTile(Icons.playlist_play_rounded, 'Play Next', () {
                        AudioPlayerService.instance.insertNext(_currentTrack);
                        Navigator.pop(context);
                        _showFeedbackToast('Playing next');
                      }, isDark: isDark),
                      _buildMenuTile(Icons.queue_music_rounded, 'Add to Queue', () {
                        AudioPlayerService.instance.addToQueue(_currentTrack);
                        Navigator.pop(context);
                        _showFeedbackToast('Added to queue');
                      }, isDark: isDark),
                      _buildMenuTile(
                        _currentTrack.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        _currentTrack.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                        () {
                          _toggleFavorite();
                          Navigator.pop(context);
                        },
                        isDark: isDark,
                      ),
                      _buildMenuTile(Icons.share_rounded, 'Share', () {
                        Navigator.pop(context);
                        _share();
                      }, isDark: isDark),
                      _buildMenuTile(Icons.info_outline_rounded, 'Song Information', () {
                        Navigator.pop(context);
                        _showSongInfo();
                      }, isDark: isDark),
                      StreamBuilder<Duration?>(
                        stream: AudioPlayerService.instance.sleepTimerStream,
                        builder: (context, snapshot) {
                          String label = 'Sleep Timer';
                          if (snapshot.hasData && snapshot.data != null) {
                            if (snapshot.data!.inSeconds == -1) {
                              label = 'Sleep Timer (End of song)';
                            } else {
                              label = 'Sleep Timer (${_formatDuration(snapshot.data!.inMilliseconds)} remaining)';
                            }
                          }
                          return _buildMenuTile(Icons.timer_outlined, label, () {
                            Navigator.pop(context);
                            _showSleepTimerMenu();
                          }, isDark: isDark);
                        },
                      ),
                      _buildMenuTile(Icons.graphic_eq_rounded, 'Equalizer', () {
                        Navigator.pop(context);
                        EqualizerSheet.show(context, accentColor: accentColor);
                      }, isDark: isDark),
                      _buildMenuTile(Icons.lyrics_outlined, 'Lyrics', () {
                        Navigator.pop(context);
                        _showLyricsSheet(accentColor);
                      }, isDark: isDark),
                      _buildMenuTile(Icons.folder_open_rounded, 'Open Folder', () {
                        Navigator.pop(context);
                        _openFolder();
                      }, isDark: isDark),
                      _buildMenuTile(Icons.speed_rounded, 'Playback Speed & Pitch', () {
                        Navigator.pop(context);
                        _showSpeedPitchSheet(accentColor);
                      }, isDark: isDark),
                      _buildMenuTile(Icons.tune_rounded, 'Audio Details', () {
                        Navigator.pop(context);
                        _showAudioDetailsDialog();
                      }, isDark: isDark),
                      _buildMenuTile(Icons.notifications_active_outlined, 'Set as Ringtone', () {
                        Navigator.pop(context);
                        _setAsRingtone();
                      }, isDark: isDark),
                      _buildMenuTile(Icons.description_outlined, 'Properties', () {
                        Navigator.pop(context);
                        _showPropertiesDialog();
                      }, isDark: isDark),
                      _buildMenuTile(Icons.delete_outline_rounded, 'Delete', () {
                        Navigator.pop(context);
                        _confirmDelete();
                      }, isDark: isDark, isDestructive: true),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSongInfo() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        final t = _currentTrack;
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Song Information', style: TextStyle(color: textColor, fontFamily: AppTypography.displayFont)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('Title', t.title, isDark: isDark),
                _infoRow('Artist', t.artist, isDark: isDark),
                _infoRow('Album', t.album ?? 'Unknown Album', isDark: isDark),
                _infoRow('Duration', _formatDuration(t.duration), isDark: isDark),
                _infoRow('File Size', t.size != null ? _formatSize(t.size!) : 'Unknown', isDark: isDark),
                _infoRow('File Path', t.filePath ?? 'Unknown', isDark: isDark),
                _infoRow('Date Added', t.dateAdded != null ? DateTime.fromMillisecondsSinceEpoch(t.dateAdded! * 1000).toString().split(' ')[0] : 'Unknown', isDark: isDark),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AccentColorHelper.resolve(context), fontFamily: AppTypography.bodyFont)),
            )
          ],
        );
      }
    );
  }

  Widget _infoRow(String label, String value, {bool isDark = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12, fontFamily: AppTypography.bodyFont)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, fontFamily: AppTypography.bodyFont)),
        ],
      ),
    );
  }

  void _showSleepTimerMenu() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor = AccentColorHelper.resolve(context);
    final Color sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (context) {
        return SafeArea(
          child: StreamBuilder<Duration?>(
            stream: AudioPlayerService.instance.sleepTimerStream,
            builder: (context, snapshot) {
              final activeDuration = snapshot.data;
              final bool isOff = activeDuration == null || activeDuration == Duration.zero;
              final bool isEndOfSong = activeDuration != null && activeDuration.inSeconds == -1;

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16.0),
                      child: Text('Sleep Timer', style: TextStyle(color: textColor, fontSize: 18, fontFamily: AppTypography.displayFont, fontWeight: FontWeight.bold)),
                    ),
                    _buildMenuTile(
                      Icons.timer_off_outlined,
                      'Off',
                      () {
                        AudioPlayerService.instance.setSleepTimer(Duration.zero);
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: isOff,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.timer_outlined,
                      '10 Minutes',
                      () {
                        AudioPlayerService.instance.setSleepTimer(const Duration(minutes: 10));
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: !isOff && !isEndOfSong && activeDuration.inMinutes == 10,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.timer_outlined,
                      '20 Minutes',
                      () {
                        AudioPlayerService.instance.setSleepTimer(const Duration(minutes: 20));
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: !isOff && !isEndOfSong && activeDuration.inMinutes == 20,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.timer_outlined,
                      '30 Minutes',
                      () {
                        AudioPlayerService.instance.setSleepTimer(const Duration(minutes: 30));
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: !isOff && !isEndOfSong && activeDuration.inMinutes == 30,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.timer_outlined,
                      '45 Minutes',
                      () {
                        AudioPlayerService.instance.setSleepTimer(const Duration(minutes: 45));
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: !isOff && !isEndOfSong && activeDuration.inMinutes == 45,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.timer_outlined,
                      '60 Minutes',
                      () {
                        AudioPlayerService.instance.setSleepTimer(const Duration(minutes: 60));
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: !isOff && !isEndOfSong && activeDuration.inMinutes == 60,
                      accentColor: accentColor,
                    ),
                    _buildMenuTile(
                      Icons.music_off_outlined,
                      'End of Current Song',
                      () {
                        AudioPlayerService.instance.setSleepTimerToEndOfSong();
                        Navigator.pop(context);
                      },
                      isDark: isDark,
                      isSelected: isEndOfSong,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildMenuTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    bool isDark = true,
    bool isDestructive = false,
    bool isSelected = false,
    Color? accentColor,
  }) {
    final Color iconColor = isDestructive
        ? Colors.redAccent
        : (isSelected
            ? (accentColor ?? (isDark ? Colors.white : Colors.black87))
            : (isDark ? Colors.white70 : Colors.black54));
    final Color textColor = isDestructive
        ? Colors.redAccent
        : (isSelected
            ? (accentColor ?? (isDark ? Colors.white : Colors.black87))
            : (isDark ? Colors.white : Colors.black87));

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      leading: Icon(icon, color: iconColor, size: 21),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontFamily: AppTypography.bodyFont,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: accentColor ?? textColor, size: 18)
          : null,
      onTap: onTap,
    );
  }

  // ───────────────────────── Back handling ─────────────────────────
  
  void _handleBack() {
    final navState = context.findAncestorStateOfType<State<MainNavigation>>();
    if (navState != null) {
      (navState as dynamic).goBackFromPlayer();
    } else {
      MainNavigation.navKey.currentState?.goBackFromPlayer();
    }
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final Color accentColor = AccentColorHelper.resolve(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: StreamBuilder<SequenceState?>(
        stream: AudioPlayerService.instance.player.sequenceStateStream,
        builder: (context, snapshot) {
          if (AudioPlayerService.instance.currentPlaylist.isEmpty) {
            return Scaffold(
              backgroundColor: isDark ? const Color(0xFF070B14) : const Color(0xFFF1F5F9),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      isDark ? 'assets/bg/dark-bg.png' : 'assets/bg/light-bg.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        _Header(
                          accentColor: accentColor,
                          onBackTap: _handleBack,
                          onQueueTap: () {},
                          onMoreTap: () {},
                        ),
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.music_off_rounded,
                                  size: 64,
                                  color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No media selected',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                    fontSize: 18,
                                    fontFamily: AppTypography.bodyFont,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF070B14) : const Color(0xFFF1F5F9),
            body: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity! > 300) {
                  _handleBack();
                }
              },
              child: Stack(
                fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    isDark ? 'assets/bg/dark-bg.png' : 'assets/bg/light-bg.png',
                    fit: BoxFit.cover,
                  ),
                ),
                SafeArea(
                  top: true,
                  bottom: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      _Header(
                        accentColor: accentColor,
                        onBackTap: _handleBack,
                        onQueueTap: () => _showQueueBottomSheet(accentColor),
                        onMoreTap: () => _showMoreMenu(accentColor),
                      ),

                      Expanded(
                        child: RepaintBoundary(
                          child: _DiscStage(
                            accentColor: accentColor,
                            isPlaying: _isPlaying,
                            track: _currentTrack,
                            rotationController: _rotationController,
                            breathCurve: _breathCurve,
                            intensityController: _intensityController,
                            barController: _barController,
                            speed: _speed,
                            volume: _volume,
                            pitch: _pitch,
                            isAbRepeatActive: (AudioPlayerService.instance.abPointA != null && AudioPlayerService.instance.abPointB != null) || _abSetupStep > 0,
                            isSpeedFlyoutOpen: _isSpeedFlyoutOpen,
                            onSpeedTap: () {
                              setState(() => _isSpeedFlyoutOpen = !_isSpeedFlyoutOpen);
                            },
                            onCloseSpeedFlyout: () {
                              if (_isSpeedFlyoutOpen) setState(() => _isSpeedFlyoutOpen = false);
                            },
                            onSpeedChanged: _setSpeed,
                            onPitchChanged: _setPitch,
                            onVolumeTap: () {
                              _closeFlyoutsIfOpen();
                              _showVolumeSheet(accentColor);
                            },
                            onAbRepeatTap: () {
                              _closeFlyoutsIfOpen();
                              _handleAbRepeatTap(accentColor);
                            },
                            onLyricsTap: () {
                              _closeFlyoutsIfOpen();
                              _showLyricsSheet(accentColor);
                            },
                            onSleepTimerTap: () {
                              _closeFlyoutsIfOpen();
                              _showSleepTimerMenu();
                            },
                            isDark: isDark,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<Duration>(
                        valueListenable: _positionNotifier,
                        builder: (context, position, _) {
                          return ValueListenableBuilder<Duration>(
                            valueListenable: _bufferedNotifier,
                            builder: (context, buffered, child) {
                              final trackDuration = _currentTrack.duration != null && _currentTrack.duration! > 0
                                  ? Duration(milliseconds: _currentTrack.duration!)
                                  : Duration.zero;
                              final total = _totalDuration > Duration.zero ? _totalDuration : trackDuration;
                              final double safeProgress = total.inMilliseconds > 0
                                  ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0;
                              final double safeBuffered = total.inMilliseconds > 0
                                  ? (buffered.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0;
                              final String positionText = _formatDuration(position.inMilliseconds);
                              final Duration remaining = total - position;
                              final String remainingText =
                                  '-${_formatDuration(remaining.inMilliseconds < 0 ? 0 : remaining.inMilliseconds)}';
                              final String totalText = total.inMilliseconds > 0 ? _formatDuration(total.inMilliseconds) : '--:--';
                              final String endTimeText = _showRemainingTime ? remainingText : totalText;
                              final String trackDurationText = total.inMilliseconds > 0 ? _formatDuration(total.inMilliseconds) : '';

                              return ClipPath(
                                clipper: const _ArchedDomeClipper(archHeight: 38),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                                  child: CustomPaint(
                                    painter: _ArchedDomeBorderPainter(
                                      borderColor: isDark
                                          ? Colors.white.withValues(alpha: 0.28)
                                          : Colors.black.withValues(alpha: 0.14),
                                      archHeight: 38,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF050811).withValues(alpha: 0.88)
                                            : Colors.white.withValues(alpha: 0.88),
                                      ),
                                      child: _BottomStage(
                                        barController: _barController,
                                        accentColor: accentColor,
                                        isPlaying: _isPlaying,
                                        progress: safeProgress,
                                        buffered: safeBuffered,
                                        totalDurationMs: total.inMilliseconds,
                                        positionText: _currentTrack.isResolving ? '--:--' : positionText,
                                        durationText: _currentTrack.isResolving
                                            ? (total.inMilliseconds > 0 ? totalText : 'Loading stream...')
                                            : (_currentTrack.resolutionError != null ? 'Stream error' : endTimeText),
                                        trackDurationText: trackDurationText,
                                        isResolving: _currentTrack.isResolving,
                                        resolutionError: _currentTrack.resolutionError,
                                        title: _currentTrack.title == '<unknown>' ? 'Unknown Title' : _currentTrack.title,
                                        artist: _currentTrack.artist == '<unknown>' ? 'Unknown Artist' : _currentTrack.artist,
                                        isShuffle: _isShuffle,
                                        loopMode: _loopMode,
                                        abStartFraction: (AudioPlayerService.instance.abPointA != null && total.inMilliseconds > 0)
                                            ? (AudioPlayerService.instance.abPointA!.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                                            : null,
                                        abEndFraction: (AudioPlayerService.instance.abPointB != null && total.inMilliseconds > 0)
                                            ? (AudioPlayerService.instance.abPointB!.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                                            : null,
                                        abPointAText: AudioPlayerService.instance.abPointA != null ? _formatDuration(AudioPlayerService.instance.abPointA!.inMilliseconds) : null,
                                        abPointBText: AudioPlayerService.instance.abPointB != null ? _formatDuration(AudioPlayerService.instance.abPointB!.inMilliseconds) : null,
                                        abSetupStep: _abSetupStep,
                                        onClearAbRepeat: () {
                                          AudioPlayerService.instance.clearAbRepeat();
                                          setState(() => _abSetupStep = 0);
                                          _showFeedbackToast('A-B Repeat cleared');
                                        },
                                        onScrub: _handleScrub,
                                        onTogglePlay: _togglePlayback,
                                        onShuffleTap: _toggleShuffle,
                                        onRepeatTap: _toggleRepeat,
                                        onSkipPrevious: _skipPrevious,
                                        onSkipNext: _skipNext,
                                        onEndTimeTap: () => setState(() => _showRemainingTime = !_showRemainingTime),
                                        isFavorite: _currentTrack.isFavorite,
                                        isDownloaded: _isDownloaded,
                                        onFavoriteTap: _toggleFavorite,
                                        onSearchTap: () => _showPlaylistSearchSheet(accentColor),
                                        showDownloadButton: _isCurrentTrackOnline,
                                        onDownloadTap: () => _triggerOnlineDownload(accentColor),
                                        onShareTap: _share,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
    );
  }
}

// ════════════════════════════ HEADER ════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.accentColor,
    required this.onBackTap,
    required this.onQueueTap,
    required this.onMoreTap,
  });
  final Color accentColor;
  final VoidCallback onBackTap;
  final VoidCallback onQueueTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color iconColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color containerColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.85);
    final Color buttonColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
    final Color borderColor = isDark ? Colors.white.withValues(alpha: AppOpacity.glassBorder) : const Color(0xFFCBD5E1);

    return Padding(
      padding: AppSpacing.playerHeaderPadding,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: borderColor),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: onBackTap,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: buttonColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: iconColor, size: 24),
              ),
            ),
            Column(
              children: [
                Text(
                  AppStrings.nowPlaying,
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: AppTypography.playerNowPlaying,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.studioSessions,
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: AppTypography.playerSession,
                    fontWeight: FontWeight.w500,
                    color: accentColor.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onQueueTap,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: buttonColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.queue_music_rounded, color: iconColor, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onMoreTap,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: buttonColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.more_vert_rounded, color: iconColor, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════ PLAYLIST SEARCH SHEET ════════════════════════════

class _PlaylistSearchSheet extends StatefulWidget {
  final Color accentColor;
  const _PlaylistSearchSheet({required this.accentColor});

  @override
  State<_PlaylistSearchSheet> createState() => _PlaylistSearchSheetState();
}

class _PlaylistSearchSheetState extends State<_PlaylistSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  late List<Track> _allTracks;
  late List<Track> _results;

  @override
  void initState() {
    super.initState();
    _allTracks = AudioPlayerService.instance.currentPlaylist;
    _results = _allTracks;
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _results = _allTracks.where((t) {
        return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
      }).toList();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _controller,
                onChanged: _filter,
                style: TextStyle(color: textColor, fontFamily: AppTypography.bodyFont),
                decoration: InputDecoration(
                  hintText: 'Search in playlist...',
                  hintStyle: TextStyle(color: secondaryTextColor),
                  prefixIcon: Icon(Icons.search_rounded, color: widget.accentColor),
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _results.length,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final track = _results[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: TrackArtwork(track: track, width: 48, height: 48, borderRadius: AppRadius.artwork / 2),
                    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontFamily: AppTypography.bodyFont, fontWeight: FontWeight.w600)),
                    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: secondaryTextColor, fontFamily: AppTypography.bodyFont)),
                    onTap: () {
                      final realIndex = _allTracks.indexWhere((t) => t.id == track.id);
                      if (realIndex != -1) {
                        AudioPlayerService.instance.player.seek(Duration.zero, index: realIndex);
                      }
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}


// ════════════════════════════ DISC STAGE ════════════════════════════

class _DiscStage extends StatelessWidget {
  const _DiscStage({
    required this.accentColor,
    required this.isPlaying,
    required this.track,
    required this.rotationController,
    required this.breathCurve,
    required this.intensityController,
    required this.barController,
    required this.speed,
    required this.volume,
    this.pitch = 1.0,
    required this.isAbRepeatActive,
    this.isSpeedFlyoutOpen = false,
    required this.onSpeedTap,
    required this.onCloseSpeedFlyout,
    required this.onSpeedChanged,
    required this.onPitchChanged,
    required this.onAbRepeatTap,
    required this.onVolumeTap,
    required this.onLyricsTap,
    required this.onSleepTimerTap,
    this.isDark = true,
  });

  final Color accentColor;
  final bool isPlaying;
  final Track track;
  final AnimationController rotationController;
  final Animation<double> breathCurve;
  final AnimationController intensityController;
  final AnimationController barController;
  final double speed;
  final double volume;
  final double pitch;
  final bool isAbRepeatActive;
  final bool isSpeedFlyoutOpen;
  final VoidCallback onSpeedTap;
  final VoidCallback onCloseSpeedFlyout;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onAbRepeatTap;
  final VoidCallback onVolumeTap;
  final VoidCallback onLyricsTap;
  final VoidCallback onSleepTimerTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double discSize = math.min(constraints.maxWidth * 0.54, 216);
        final double discLeft = (constraints.maxWidth - discSize) / 2;
        final double discTop = (constraints.maxHeight - discSize) / 2 + 8;

        return _DiscInteractiveArea(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Ambient breathing glow underneath the vinyl (precisely centered)
              Positioned(
                top: discTop,
                left: discLeft,
                width: discSize,
                height: discSize,
                child: Center(
                  child: AnimatedBuilder(
                    animation: breathCurve,
                    builder: (context, _) {
                      final double glowScale = 0.90 + (breathCurve.value * 0.16);
                      final double glowOpacity = isPlaying
                          ? (0.24 + (breathCurve.value * 0.20))
                          : 0.10;

                      return Transform.scale(
                        scale: glowScale,
                        child: Container(
                          width: discSize * 0.95,
                          height: discSize * 0.95,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: glowOpacity),
                                blurRadius: 52,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Vinyl Disc + Drop Shadow (Dead-Center in screen)
              Positioned(
                top: discTop,
                left: discLeft,
                width: discSize,
                height: discSize,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Disc subtle drop shadow
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: discSize * 0.75,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: RadialGradient(
                            colors: [
                              Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Spinning vinyl record
                    AnimatedBuilder(
                      animation: rotationController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: rotationController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: _VinylDisc(
                        size: discSize,
                        accentColor: accentColor,
                        track: track,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
              // Tonearm with smooth engagement needle animation (Anchored on upper-left of vinyl disc)
              Positioned(
                top: discTop + (discSize * 0.22) - 14,
                left: discLeft + (discSize * 0.12) - 14,
                child: AnimatedBuilder(
                  animation: intensityController,
                  builder: (context, _) {
                    return _Tonearm(
                      size: discSize,
                      accentColor: accentColor,
                      engagement: intensityController.value,
                      isDark: isDark,
                    );
                  },
                ),
              ),
              // Barrier to dismiss flyout when tapping outside
              if (isSpeedFlyoutOpen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCloseSpeedFlyout,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              // Left-Side Floating Quick Controls Rail (Moved to edge, perfectly clear of the disc)
              Positioned(
                left: 10,
                top: discTop + (discSize - 192) / 2,
                child: _DiscSideRail(
                  accentColor: accentColor,
                  speed: speed,
                  volume: volume,
                  isAbRepeatActive: isAbRepeatActive,
                  isSpeedActive: isSpeedFlyoutOpen || speed != 1.0,
                  onSpeedTap: onSpeedTap,
                  onAbRepeatTap: onAbRepeatTap,
                  onVolumeTap: onVolumeTap,
                  onLyricsTap: onLyricsTap,
                  onSleepTimerTap: onSleepTimerTap,
                  isDark: isDark,
                ),
              ),
              // Smart Translucent In-Place Speed Flyout anchored right next to the left rail
              if (isSpeedFlyoutOpen)
                Positioned(
                  left: 54,
                  top: discTop - 8,
                  child: _SpeedFlyout(
                    speed: speed,
                    pitch: pitch,
                    accentColor: accentColor,
                    isDark: isDark,
                    maxWidth: math.min(140.0, constraints.maxWidth - 66.0),
                    onSpeedChanged: onSpeedChanged,
                    onPitchChanged: onPitchChanged,
                    onClose: onCloseSpeedFlyout,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DiscSideRail extends StatelessWidget {
  const _DiscSideRail({
    required this.accentColor,
    required this.speed,
    required this.volume,
    required this.isAbRepeatActive,
    this.isSpeedActive = false,
    required this.onSpeedTap,
    required this.onAbRepeatTap,
    required this.onVolumeTap,
    required this.onLyricsTap,
    required this.onSleepTimerTap,
    this.isDark = true,
  });

  final Color accentColor;
  final double speed;
  final double volume;
  final bool isAbRepeatActive;
  final bool isSpeedActive;
  final VoidCallback onSpeedTap;
  final VoidCallback onAbRepeatTap;
  final VoidCallback onVolumeTap;
  final VoidCallback onLyricsTap;
  final VoidCallback onSleepTimerTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.38)
            : Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SideRailButton(
            icon: Icons.speed_rounded,
            tooltip: 'Playback Speed',
            label: '${speed.toStringAsFixed(1)}x',
            isActive: isSpeedActive,
            accentColor: accentColor,
            isDark: isDark,
            onTap: onSpeedTap,
          ),
          const SizedBox(height: 5),
          _SideRailButton(
            icon: Icons.compare_arrows_rounded,
            tooltip: 'A-B Loop',
            label: 'A-B',
            isActive: isAbRepeatActive,
            accentColor: accentColor,
            isDark: isDark,
            onTap: onAbRepeatTap,
          ),
          const SizedBox(height: 5),
          _SideRailButton(
            icon: volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            tooltip: 'Volume & Audio FX',
            label: null,
            isActive: volume != 1.0,
            accentColor: accentColor,
            isDark: isDark,
            onTap: onVolumeTap,
          ),
          const SizedBox(height: 5),
          _SideRailButton(
            icon: Icons.lyrics_outlined,
            tooltip: 'Lyrics',
            label: null,
            isActive: false,
            accentColor: accentColor,
            isDark: isDark,
            onTap: onLyricsTap,
          ),
          const SizedBox(height: 5),
          _SideRailButton(
            icon: Icons.timer_outlined,
            tooltip: 'Sleep Timer',
            label: null,
            isActive: false,
            accentColor: accentColor,
            isDark: isDark,
            onTap: onSleepTimerTap,
          ),
        ],
      ),
    );
  }
}

class _SpeedFlyout extends StatelessWidget {
  const _SpeedFlyout({
    required this.speed,
    required this.pitch,
    required this.accentColor,
    required this.isDark,
    required this.maxWidth,
    required this.onSpeedChanged,
    required this.onPitchChanged,
    required this.onClose,
  });

  final double speed;
  final double pitch;
  final Color accentColor;
  final bool isDark;
  final double maxWidth;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<double> onPitchChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final Color secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color cardBg = isDark
        ? const Color(0xF20D1528)
        : Colors.white.withValues(alpha: 0.94);
    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.12);

    final List<double> presetSpeeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final bool isLightAccent = accentColor.computeLuminance() > 0.5;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: maxWidth,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 16,
                offset: const Offset(2, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.speed_rounded, color: accentColor, size: 11),
                      const SizedBox(width: 3),
                      Text(
                        'SPEED',
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                          fontFamily: AppTypography.uiFont,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((speed - 1.0).abs() > 0.01 || (pitch - 1.0).abs() > 0.01)
                        GestureDetector(
                          onTap: () {
                            onSpeedChanged(1.0);
                            onPitchChanged(1.0);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Reset',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: onClose,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded, size: 10, color: secondaryTextColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 3),

              // Micro Stepper Hero Display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _FlyoutStepButton(
                      icon: Icons.remove_rounded,
                      isDark: isDark,
                      size: 18,
                      onTap: () {
                        final next = (speed - 0.05).clamp(0.5, 2.5);
                        onSpeedChanged(double.parse(next.toStringAsFixed(2)));
                      },
                    ),
                    Text(
                      '${speed.toStringAsFixed(2)}x',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppTypography.displayFont,
                        color: (speed - 1.0).abs() > 0.01 ? accentColor : textColor,
                      ),
                    ),
                    _FlyoutStepButton(
                      icon: Icons.add_rounded,
                      isDark: isDark,
                      size: 18,
                      onTap: () {
                        final next = (speed + 0.05).clamp(0.5, 2.5);
                        onSpeedChanged(double.parse(next.toStringAsFixed(2)));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),

              // 3x2 Matrix of Speed Tiles (Only 2 rows instead of 3 rows)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: presetSpeeds.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                  childAspectRatio: 1.9,
                ),
                itemBuilder: (context, idx) {
                  final s = presetSpeeds[idx];
                  final bool isSelected = (speed - s).abs() < 0.02;
                  final Color tileTextColor = isSelected
                      ? (isLightAccent ? Colors.black87 : Colors.white)
                      : textColor;

                  return GestureDetector(
                    onTap: () => onSpeedChanged(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [accentColor, accentColor.withValues(alpha: 0.85)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: isSelected
                            ? null
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.04)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? accentColor
                              : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: tileTextColor,
                          fontFamily: AppTypography.uiFont,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 3),

              // Mini Pitch Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pitch: ${pitch.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: secondaryTextColor,
                    ),
                  ),
                  if ((pitch - 1.0).abs() > 0.01)
                    GestureDetector(
                      onTap: () => onPitchChanged(1.0),
                      child: Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                  activeTrackColor: accentColor,
                  inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
                  thumbColor: accentColor,
                ),
                child: SizedBox(
                  height: 16,
                  child: Slider(
                    value: pitch,
                    min: 0.5,
                    max: 1.5,
                    onChanged: onPitchChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlyoutStepButton extends StatelessWidget {
  const _FlyoutStepButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.size = 22,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}

class _SideRailButton extends StatelessWidget {
  const _SideRailButton({
    required this.icon,
    required this.tooltip,
    this.label,
    required this.isActive,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final bool isActive;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = isActive
        ? accentColor
        : (isDark ? Colors.white70 : const Color(0xFF1E293B));
    final Color bgColor = isActive
        ? accentColor.withValues(alpha: 0.18)
        : Colors.transparent;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: isActive
                ? Border.all(color: accentColor.withValues(alpha: 0.4), width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: iconColor),
              if (label != null)
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                    height: 1.0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tonearm extends StatelessWidget {
  const _Tonearm({
    required this.size,
    required this.accentColor,
    required this.engagement,
    this.isDark = true,
  });

  final double size;
  final Color accentColor;
  final double engagement;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Proportional dimensions for left-anchored tonearm
    final double armWidth = size * 0.36;
    final double armHeight = size * 0.68;
    const Offset pivot = Offset(14, 14);

    // Engagement rotation around the pivot:
    // When engagement == 1.0 (playing): needle sits in play position on vinyl grooves (angle = 0.0)
    // When engagement == 0.0 (stopped): needle smoothly lifts/swings outward to the left (angle = 0.22 rad)
    final double angle = (1.0 - engagement) * 0.22;

    return Transform.rotate(
      alignment: Alignment(
        (pivot.dx / armWidth) * 2 - 1,
        (pivot.dy / armHeight) * 2 - 1,
      ),
      angle: angle,
      child: SizedBox(
        width: armWidth,
        height: armHeight,
        child: CustomPaint(
          size: Size(armWidth, armHeight),
          painter: _TonearmPainter(
            accentColor: accentColor,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  final Color accentColor;
  final bool isDark;

  _TonearmPainter({required this.accentColor, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    const Offset pivot = Offset(14, 14);

    // 1. Sleek metallic tonearm tube (starts below pivot, goes down along left edge, bends right onto disc)
    final Path armPath = Path();
    armPath.moveTo(pivot.dx, pivot.dy + 6);
    armPath.lineTo(pivot.dx, size.height * 0.65);

    final Offset headshellPos = Offset(size.width * 0.72, size.height * 0.82);
    armPath.cubicTo(
      pivot.dx,
      size.height * 0.86,
      size.width * 0.38,
      size.height * 0.93,
      headshellPos.dx,
      headshellPos.dy,
    );

    // Soft drop shadow beneath tube
    final Paint armShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(armPath.shift(const Offset(1, 2)), armShadow);

    // Metallic tube gradient
    final Paint armPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(pivot.dx, pivot.dy),
        headshellPos,
        [
          const Color(0xFFFFFFFF),
          const Color(0xFFCBD5E1),
          const Color(0xFF94A3B8),
          const Color(0xFFE2E8F0),
        ],
        [0.0, 0.35, 0.75, 1.0],
      );
    canvas.drawPath(armPath, armPaint);

    // 2. Headshell / Cartridge (angled onto vinyl groove)
    canvas.save();
    canvas.translate(headshellPos.dx, headshellPos.dy);
    canvas.rotate(-0.52);

    final RRect cartridgeRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, -4.5, 17, 9),
      const Radius.circular(2.5),
    );

    // Cartridge drop shadow
    canvas.drawRRect(
      cartridgeRRect.shift(const Offset(1, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Cartridge body
    canvas.drawRRect(
      cartridgeRRect,
      Paint()..color = const Color(0xFF1E293B),
    );

    // Cartridge metallic trim
    canvas.drawRRect(
      cartridgeRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFF64748B),
    );

    // Needle stylus tip (accent color)
    canvas.drawCircle(
      const Offset(15, 0),
      2.2,
      Paint()..color = accentColor,
    );

    // Stylus glow
    canvas.drawCircle(
      const Offset(15, 0),
      4.5,
      Paint()
        ..color = accentColor.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.restore();

    // 3. Compact Pivot Base (circle size made smaller as requested)
    const double outerRadius = 10.0;
    const double innerRadius = 6.0;
    const double accentRadius = 2.8;

    // Base Shadow
    final Paint baseShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    canvas.drawCircle(pivot + const Offset(0, 2), outerRadius, baseShadow);

    // Outer metallic bevel ring
    final Paint baseOuter = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFE2E8F0), Color(0xFF94A3B8), Color(0xFF475569)],
        stops: [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: pivot, radius: outerRadius));
    canvas.drawCircle(pivot, outerRadius, baseOuter);

    // Inner brushed metal plate
    final Paint baseInner = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFF8FAFC), Color(0xFF64748B)],
      ).createShader(Rect.fromCircle(center: pivot, radius: innerRadius));
    canvas.drawCircle(pivot, innerRadius, baseInner);

    // Center Accent Dot
    canvas.drawCircle(pivot, accentRadius, Paint()..color = accentColor);
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor || oldDelegate.isDark != isDark;
}

class _DiscInteractiveArea extends StatefulWidget {
  final double width;
  final double height;
  final Widget child;

  const _DiscInteractiveArea({
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  State<_DiscInteractiveArea> createState() => _DiscInteractiveAreaState();
}

class _DiscInteractiveAreaState extends State<_DiscInteractiveArea> {
  String? _badgeText;
  IconData? _badgeIcon;
  Alignment _badgeAlignment = Alignment.center;
  Timer? _dismissTimer;

  void _triggerFeedback(String text, IconData icon, Alignment alignment) {
    _dismissTimer?.cancel();
    setState(() {
      _badgeText = text;
      _badgeIcon = icon;
      _badgeAlignment = alignment;
    });
    _dismissTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _badgeText = null;
          _badgeIcon = null;
        });
      }
    });
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final dx = details.localPosition.dx;
    final totalWidth = widget.width;

    if (dx < totalWidth * 0.35) {
      // Double tap on left side of entire stage: seek -10 sec
      HapticFeedback.mediumImpact();
      final cur = AudioPlayerService.instance.player.position;
      final target = cur - const Duration(seconds: 10);
      AudioPlayerService.instance.player.seek(target < Duration.zero ? Duration.zero : target);
      _triggerFeedback('-10s', Icons.replay_10_rounded, const Alignment(-0.65, 0.0));
    } else if (dx > totalWidth * 0.65) {
      // Double tap on right side of entire stage: seek +10 sec
      HapticFeedback.mediumImpact();
      final cur = AudioPlayerService.instance.player.position;
      final dur = AudioPlayerService.instance.player.duration ?? Duration.zero;
      final target = cur + const Duration(seconds: 10);
      AudioPlayerService.instance.player.seek(target > dur ? dur : target);
      _triggerFeedback('+10s', Icons.forward_10_rounded, const Alignment(0.65, 0.0));
    } else {
      // Double tap in center: stop / pause music
      HapticFeedback.heavyImpact();
      final isPlaying = AudioPlayerService.instance.player.playing;
      if (isPlaying) {
        AudioPlayerService.instance.player.pause();
        _triggerFeedback('Paused', Icons.pause_rounded, Alignment.center);
      } else {
        AudioPlayerService.instance.player.play();
        _triggerFeedback('Playing', Icons.play_arrow_rounded, Alignment.center);
      }
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: _handleDoubleTapDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          if (_badgeText != null)
            Align(
              alignment: _badgeAlignment,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _badgeText != null ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.85),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.45),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_badgeIcon != null) ...[
                        Icon(_badgeIcon, color: Colors.white, size: 20),
                        const SizedBox(width: 7),
                      ],
                      Text(
                        _badgeText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppTypography.displayFont,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VinylDisc extends StatelessWidget {
  const _VinylDisc({
    required this.size,
    required this.accentColor,
    required this.track,
    this.isDark = true,
  });

  final double size;
  final Color accentColor;
  final Track track;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final double labelSize = size * 0.42;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.75),
                  blurRadius: 36,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.8),
                  blurRadius: 6,
                  spreadRadius: -2,
                ),
              ],
      ),
      child: CustomPaint(
        painter: _VinylGroovePainter(accentColor: accentColor, isDark: isDark),
        child: Center(
          child: Container(
            width: labelSize,
            height: labelSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.15),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: TrackArtwork(
                      track: track,
                      width: labelSize * 0.85,
                      height: labelSize * 0.85,
                      borderRadius: labelSize / 2,
                      showShadow: false,
                    ),
                  ),
                  if (track.isResolving)
                    Container(
                      width: labelSize * 0.85,
                      height: labelSize * 0.85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                    )
                  else if (track.resolutionError != null)
                    Container(
                      width: labelSize * 0.85,
                      height: labelSize * 0.85,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      child: const Center(
                        child: Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 30),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VinylGroovePainter extends CustomPainter {
  final Color accentColor;
  final bool isDark;
  _VinylGroovePainter({required this.accentColor, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2;

    // 1. Base Vinyl Disc Body
    final basePaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    canvas.drawCircle(center, radius, basePaint);

    // 2. Realistic Radial Gradient Depth
    final depth = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? [const Color(0xFF1E293B), const Color(0xFF090D16)]
            : [const Color(0xFFFFFFFF), const Color(0xFFE2E8F0)],
        stops: const [0.35, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, depth);

    // 3. Concentric Vinyl Grooves
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    for (double r = radius * 0.44; r < radius * 0.98; r += 2.8) {
      groovePaint.color = isDark
          ? Colors.white.withValues(alpha: 0.035)
          : Colors.black.withValues(alpha: 0.035);
      canvas.drawCircle(center, r, groovePaint);
    }

    // Prominent track separator rings
    final trackSeparator = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = isDark ? Colors.black.withValues(alpha: 0.6) : const Color(0xFFCBD5E1);
    canvas.drawCircle(center, radius * 0.66, trackSeparator);
    canvas.drawCircle(center, radius * 0.84, trackSeparator);

    // 4. Butterfly Sheen / Specular Light Reflection
    final sheen = Paint()
      ..shader = SweepGradient(
        colors: isDark
            ? [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
                Colors.transparent,
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.16),
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
              ]
            : [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.4),
                Colors.white.withValues(alpha: 0.8),
                Colors.white.withValues(alpha: 0.4),
                Colors.transparent,
                Colors.transparent,
                Colors.white.withValues(alpha: 0.4),
                Colors.white.withValues(alpha: 0.8),
                Colors.white.withValues(alpha: 0.4),
                Colors.transparent,
              ],
        stops: const [0.0, 0.12, 0.25, 0.38, 0.5, 0.5, 0.62, 0.75, 0.88, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.saveLayer(Rect.fromCircle(center: center, radius: radius), Paint());
    canvas.drawCircle(center, radius, sheen);
    // Mask center label hole
    canvas.drawCircle(center, radius * 0.42, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VinylGroovePainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.accentColor != accentColor;
}



// ════════════════════════════ BOTTOM STAGE ════════════════════════════

class _BottomStage extends StatefulWidget {
  const _BottomStage({
    required this.barController,
    required this.accentColor,
    required this.isPlaying,
    required this.progress,
    required this.buffered,
    required this.totalDurationMs,
    required this.positionText,
    required this.durationText,
    this.trackDurationText,
    required this.title,
    required this.artist,
    required this.isShuffle,
    required this.loopMode,
    required this.onScrub,
    required this.onTogglePlay,
    required this.onShuffleTap,
    required this.onRepeatTap,
    required this.onSkipPrevious,
    required this.onSkipNext,
    this.abStartFraction,
    this.abEndFraction,
    this.abPointAText,
    this.abPointBText,
    this.abSetupStep = 0,
    this.onClearAbRepeat,
    required this.onEndTimeTap,
    required this.isFavorite,
    required this.isDownloaded,
    required this.onFavoriteTap,
    required this.onSearchTap,
    this.showDownloadButton = false,
    required this.onDownloadTap,
    required this.onShareTap,
    this.isResolving = false,
    this.resolutionError,
  });

  final Color accentColor;
  final bool isPlaying;
  final double progress;
  final double buffered;
  final int totalDurationMs;
  final String positionText;
  final String durationText;
  final String? trackDurationText;
  final String title;
  final String artist;
  final bool isShuffle;
  final LoopMode loopMode;
  final ValueChanged<double> onScrub;
  final VoidCallback onTogglePlay;
  final VoidCallback onShuffleTap;
  final VoidCallback onRepeatTap;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final double? abStartFraction;
  final double? abEndFraction;
  final String? abPointAText;
  final String? abPointBText;
  final int abSetupStep;
  final VoidCallback? onClearAbRepeat;
  final VoidCallback onEndTimeTap;
  final bool isFavorite;
  final bool isDownloaded;
  final VoidCallback onFavoriteTap;
  final VoidCallback onSearchTap;
  final bool showDownloadButton;
  final VoidCallback onDownloadTap;
  final VoidCallback onShareTap;
  final AnimationController barController;
  final bool isResolving;
  final String? resolutionError;

  @override
  State<_BottomStage> createState() => _BottomStageState();
}

class _BottomStageState extends State<_BottomStage> {
  double? _dragProgress;
  Timer? _dragEndCooldown;

  @override
  void dispose() {
    _dragEndCooldown?.cancel();
    super.dispose();
  }

  String _formatMilliseconds(int ms) {
    if (ms <= 0) return '0:00';
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color secondaryTextColor = isDark ? Colors.white.withValues(alpha: AppOpacity.textSecondary) : Colors.black54;
    final Color inactiveColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1);
    final Color controlInactiveColor = isDark ? Colors.white.withValues(alpha: AppOpacity.playerControlInactive) : Colors.black38;

    IconData repeatIcon = Icons.repeat_rounded;
    if (widget.loopMode == LoopMode.one) repeatIcon = Icons.repeat_one_rounded;

    // Use dragged progress if currently dragging, otherwise current player stream progress
    final double currentProgress = _dragProgress ?? widget.progress;

    // Format position text smoothly in real-time when dragging
    final String displayPositionText;
    if (_dragProgress != null && widget.totalDurationMs > 0) {
      final int scrubMs = (widget.totalDurationMs * _dragProgress!).round();
      displayPositionText = _formatMilliseconds(scrubMs);
    } else {
      displayPositionText = widget.positionText;
    }

    return Padding(
      padding: AppSpacing.playerBottomPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FadingTitle(
            key: ValueKey(widget.title),
            text: widget.title,
            style: TextStyle(
              fontFamily: AppTypography.uiFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textColor,
              height: 1.2,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  widget.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: secondaryTextColor,
                  ),
                ),
              ),
              if (widget.trackDurationText != null &&
                  widget.trackDurationText!.isNotEmpty &&
                  widget.trackDurationText != '--:--' &&
                  widget.trackDurationText != '0:00') ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '•',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: secondaryTextColor.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Text(
                  widget.trackDurationText!,
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: double.infinity,
                height: 32,
                alignment: Alignment.center,
                child: AnimatedBuilder(
                  animation: widget.barController,
                  builder: (context, _) {
                    final Color dynamicThumbColor = Color.lerp(
                      _WaveformTrackPainter.waveStartColor,
                      _WaveformTrackPainter.waveEndColor,
                      currentProgress,
                    ) ?? const Color(0xFF6366F1);

                    return CustomPaint(
                      size: const Size(double.infinity, 32),
                      painter: _WaveformTrackPainter(
                        progress: currentProgress,
                        buffered: widget.buffered,
                        activeColor: dynamicThumbColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                        t: widget.isPlaying ? widget.barController.value : 0.0,
                      ),
                    );
                  },
                ),
              ),
              if (widget.abStartFraction != null && widget.abEndFraction != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final double left = constraints.maxWidth * widget.abStartFraction!;
                    final double width = constraints.maxWidth * (widget.abEndFraction! - widget.abStartFraction!);
                    return Positioned(
                      left: left,
                      width: width.clamp(2.0, constraints.maxWidth),
                      child: IgnorePointer(
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Builder(
                builder: (context) {
                  final Color dynamicThumbColor = Color.lerp(
                    _WaveformTrackPainter.waveStartColor,
                    _WaveformTrackPainter.waveEndColor,
                    currentProgress,
                  ) ?? const Color(0xFF6366F1);

                  return SliderTheme(
                    data: SliderThemeData(
                      trackShape: const _FullWidthTrackShape(),
                      trackHeight: 32,
                      padding: EdgeInsets.zero,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6, elevation: isDark ? 4 : 2),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      overlayColor: dynamicThumbColor.withValues(alpha: 0.20),
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: dynamicThumbColor,
                    ),
                    child: Slider(
                      value: currentProgress,
                      onChangeStart: widget.isResolving
                          ? null
                          : (val) {
                              _dragEndCooldown?.cancel();
                              setState(() => _dragProgress = val);
                            },
                      onChanged: widget.isResolving
                          ? null
                          : (val) {
                              setState(() => _dragProgress = val);
                            },
                      onChangeEnd: widget.isResolving
                          ? null
                          : (val) {
                              widget.onScrub(val);
                              _dragEndCooldown?.cancel();
                              _dragEndCooldown = Timer(const Duration(milliseconds: 250), () {
                                if (mounted) {
                                  setState(() => _dragProgress = null);
                                }
                              });
                            },
                    ),
                  );
                },
              ),
            ],
          ),

          if (widget.abSetupStep == 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded, color: widget.accentColor, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        'Tap timeline to set Point A',
                        style: TextStyle(color: widget.accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (widget.onClearAbRepeat != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.onClearAbRepeat,
                          child: Icon(Icons.close_rounded, color: widget.accentColor, size: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else if (widget.abSetupStep == 2)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_rounded, color: widget.accentColor, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        'A: ${widget.abPointAText ?? "--:--"} • Tap timeline for Point B',
                        style: TextStyle(color: widget.accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (widget.onClearAbRepeat != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.onClearAbRepeat,
                          child: Icon(Icons.close_rounded, color: widget.accentColor, size: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else if (widget.abPointAText != null && widget.abPointBText != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text('A ${widget.abPointAText}', style: TextStyle(color: widget.accentColor, fontSize: 11, fontFamily: AppTypography.bodyFont, fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.repeat_on_rounded, size: 14, color: widget.accentColor),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text('B ${widget.abPointBText}', style: TextStyle(color: widget.accentColor, fontSize: 11, fontFamily: AppTypography.bodyFont, fontWeight: FontWeight.bold)),
                ),
                if (widget.onClearAbRepeat != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onClearAbRepeat,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 13, color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
          ],
          // 1. Time Row (Position & Duration) directly below waveform
          Padding(
            padding: const EdgeInsets.only(top: 2.0, bottom: 6.0, left: 2.0, right: 2.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: widget.onEndTimeTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    displayPositionText,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onEndTimeTap,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    widget.durationText,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 2. Playback Row: Modern frosted playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: widget.onShuffleTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isShuffle
                        ? widget.accentColor.withValues(alpha: 0.20)
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                    border: Border.all(
                      color: widget.isShuffle
                          ? widget.accentColor.withValues(alpha: 0.50)
                          : (isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Icon(
                    widget.isShuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                    color: widget.isShuffle ? widget.accentColor : controlInactiveColor,
                    size: 20,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: widget.isResolving ? null : widget.onSkipPrevious,
                    behavior: HitTestBehavior.opaque,
                    child: Opacity(
                      opacity: widget.isResolving ? 0.35 : 1.0,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(Icons.skip_previous_rounded, color: textColor, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Centered Pulsing Play/Pause Button
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: AnimatedBuilder(
                      animation: widget.barController,
                      builder: (context, _) {
                        final double t = widget.isPlaying ? widget.barController.value : 0.0;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glowing Ripple 1
                            if (widget.isPlaying && !widget.isResolving)
                              Container(
                                width: 58 + (16 * t),
                                height: 58 + (16 * t),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: widget.accentColor.withValues(alpha: (0.40 * (1.0 - t)).clamp(0.0, 1.0)),
                                    width: 1.8,
                                  ),
                                ),
                              ),
                            // Glowing Ripple 2
                            if (widget.isPlaying && !widget.isResolving)
                              Container(
                                width: 58 + (16 * ((t + 0.5) % 1.0)),
                                height: 58 + (16 * ((t + 0.5) % 1.0)),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: widget.accentColor.withValues(alpha: (0.40 * (1.0 - ((t + 0.5) % 1.0))).clamp(0.0, 1.0)),
                                    width: 1.8,
                                  ),
                                ),
                              ),
                            // Main Play Button Core
                            GestureDetector(
                              onTap: widget.isResolving ? null : widget.onTogglePlay,
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.accentColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: widget.accentColor.withValues(alpha: widget.isPlaying ? 0.45 : 0.25),
                                      blurRadius: widget.isPlaying ? 18 : 10,
                                      spreadRadius: widget.isPlaying ? 2 : 1,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: widget.isResolving
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.isResolving ? null : widget.onSkipNext,
                    behavior: HitTestBehavior.opaque,
                    child: Opacity(
                      opacity: widget.isResolving ? 0.35 : 1.0,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Icon(Icons.skip_next_rounded, color: textColor, size: 28),
                      ),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: widget.onRepeatTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.loopMode != LoopMode.off
                        ? widget.accentColor.withValues(alpha: 0.20)
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                    border: Border.all(
                      color: widget.loopMode != LoopMode.off
                          ? widget.accentColor.withValues(alpha: 0.50)
                          : (isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Icon(
                    repeatIcon,
                    color: widget.loopMode != LoopMode.off ? widget.accentColor : controlInactiveColor,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 3. Quick Action Buttons: Modern frosted glass round suite
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: widget.onFavoriteTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isFavorite
                        ? const Color(0xFFFF2E7E).withValues(alpha: 0.18)
                        : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                    border: Border.all(
                      color: widget.isFavorite
                          ? const Color(0xFFFF2E7E).withValues(alpha: 0.50)
                          : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                    ),
                    boxShadow: widget.isFavorite ? [
                      BoxShadow(
                        color: const Color(0xFFFF2E7E).withValues(alpha: 0.40),
                        blurRadius: 12,
                        spreadRadius: 1,
                      )
                    ] : null,
                  ),
                  child: Icon(
                    widget.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: widget.isFavorite ? const Color(0xFFFF2E7E) : controlInactiveColor,
                    size: 20,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onSearchTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(Icons.search_rounded, color: controlInactiveColor, size: 20),
                ),
              ),
              if (widget.showDownloadButton)
                GestureDetector(
                  onTap: widget.onDownloadTap,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isDownloaded
                          ? widget.accentColor.withValues(alpha: 0.18)
                          : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                      border: Border.all(
                        color: widget.isDownloaded
                            ? widget.accentColor.withValues(alpha: 0.45)
                            : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: Icon(
                      widget.isDownloaded ? Icons.download_done_rounded : Icons.arrow_circle_down_rounded,
                      color: widget.isDownloaded ? widget.accentColor : controlInactiveColor,
                      size: 21,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: widget.onShareTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(Icons.ios_share_rounded, color: controlInactiveColor, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Smooth single-line title marquee that prevents layout shifts & jitters
class _FadingTitle extends StatefulWidget {
  const _FadingTitle({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_FadingTitle> createState() => _FadingTitleState();
}

class _FadingTitleState extends State<_FadingTitle> {
  final ScrollController _scrollController = ScrollController();
  Timer? _marqueeTimer;

  @override
  void initState() {
    super.initState();
    _startMarqueeSequence();
  }

  @override
  void didUpdateWidget(covariant _FadingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stopMarquee();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _startMarqueeSequence();
    }
  }

  void _startMarqueeSequence() {
    _marqueeTimer?.cancel();
    _marqueeTimer = Timer(const Duration(seconds: 2), _scrollForward);
  }

  void _stopMarquee() {
    _marqueeTimer?.cancel();
  }

  Future<void> _scrollForward() async {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      _startMarqueeSequence();
      return;
    }
    final durationMs = (maxScroll * 35).clamp(1500, 7000).toInt();
    await _scrollController.animateTo(
      maxScroll,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.linear,
    );
    if (!mounted) return;
    _marqueeTimer = Timer(const Duration(seconds: 1), _scrollBack);
  }

  Future<void> _scrollBack() async {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final durationMs = (maxScroll * 35).clamp(1500, 7000).toInt();
    await _scrollController.animateTo(
      0,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.linear,
    );
    if (!mounted) return;
    _startMarqueeSequence();
  }

  @override
  void dispose() {
    _stopMarquee();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
          ),
        );
      },
    );
  }
}

/// Full-width rectangular track shape that eliminates Flutter's internal
/// [isRounded] thumb padding (which defaults to trackHeight/2 = 16px inset).
/// This ensures the slider thumb starts precisely at 0:00 (leftmost edge)
/// and reaches the exact duration ending point (rightmost edge) without any offset.
class _FullWidthTrackShape extends RectangularSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  bool get isRounded => false;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 32;
    const double thumbRadius = 6.0;
    // Align track so thumb center at 0.0 is exactly at thumbRadius from left edge,
    // making the thumb circle touch the exact left boundary (0:00) without overhang,
    // and at 1.0 finish flush against the right edge!
    final double trackLeft = offset.dx + thumbRadius;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = math.max(0.0, parentBox.size.width - (thumbRadius * 2));
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    // Custom waveform painter handles all track painting.
  }
}


// ════════════════════════════ BACKGROUND ════════════════════════════

class VoidWavePainter extends CustomPainter {
  final double progress;
  final double intensity;
  final double cycle;
  final Color accentColor;

  VoidWavePainter({
    required this.progress,
    required this.intensity,
    required this.cycle,
    required this.accentColor,
  });

  static const List<Color> _palette = AppColors.voidWavePalette;

  Color _cycledColor(double t) {
    final double scaled = t * _palette.length;
    final int i = scaled.floor() % _palette.length;
    final int j = (i + 1) % _palette.length;
    final double localT = scaled - scaled.floor();
    return Color.lerp(_palette[i], _palette[j], localT)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.voidDeep,
    );

    final Color huedAccent = Color.lerp(accentColor, _cycledColor(cycle), 0.55)!;

    final List<Color> blobColors = [
      huedAccent,
      _cycledColor((cycle + 0.33) % 1.0),
      _cycledColor((cycle + 0.66) % 1.0),
    ];

    for (int i = 0; i < 3; i++) {
      final double t = (progress + i / 3) % 1.0;
      final double angle = t * 2 * math.pi;
      final Offset blobCenter = Offset(
        size.width * 0.5 + math.cos(angle + i) * size.width * 0.30,
        size.height * 0.32 + math.sin(angle * 1.3 + i) * size.height * 0.18,
      );
      final double radius = size.width * (0.45 + 0.05 * math.sin(angle));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            blobColors[i].withValues(alpha: 0.16 * intensity + 0.04),
            blobColors[i].withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: blobCenter, radius: radius))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, AppBlur.voidWaveMask);
      canvas.drawCircle(blobCenter, radius, paint);
    }

    final Offset center = Offset(size.width / 2, size.height * 0.40);
    final double maxRadius = size.height * 0.85;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i < 4; i++) {
      final double waveProgress = (progress + i * 0.25) % 1.0;
      final double r = maxRadius * waveProgress;
      final double opacity = (waveProgress < 0.2
          ? (waveProgress / 0.2)
          : (1.0 - waveProgress) / 0.8) *
          0.10 *
          intensity;
      ring.color = huedAccent.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(center, r, ring);
    }
  }

  @override
  bool shouldRepaint(covariant VoidWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.cycle != cycle ||
        oldDelegate.accentColor != accentColor;
  }
}

class _WaveformTrackPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDark;
  final double t;

  _WaveformTrackPainter({
    required this.t,
    required this.progress,
    required this.buffered,
    required this.activeColor,
    required this.inactiveColor,
    this.isDark = true,
  });

  static const Color waveStartColor = Color(0xFF4361EE); // Electric Blurple / Royal Blue
  static const Color waveEndColor = Color(0xFF8B5CF6);   // Vibrant Purple / Violet

  @override
  void paint(Canvas canvas, Size size) {
    final int barCount = 56;
    const double thumbRadius = 6.0;
    final double availableWidth = math.max(10.0, size.width - (thumbRadius * 2));
    final double barStep = availableWidth / (barCount - 1);
    final double w = math.max(2.0, (availableWidth / barCount) * 0.65);

    final Paint inactivePaint = Paint()..color = inactiveColor..strokeCap = StrokeCap.round..strokeWidth = w;
    final Paint bufferedPaint = Paint()..color = inactiveColor.withValues(alpha: 0.35)..strokeCap = StrokeCap.round..strokeWidth = w;

    // Smooth rhythmic continuous phase loop for natural musical wave motion
    final double phase = t * 2 * math.pi;

    for (int i = 0; i < barCount; i++) {
      final double x = thumbRadius + (i * barStep);
      final double normalizedX = i / (barCount - 1);
      
      // Smooth rhythmic harmonic traveling equalizer
      final double wave1 = math.sin((i * 0.26) - phase);
      final double wave2 = math.cos((i * 0.16) + (phase * 0.8));
      final double wave3 = math.sin((i * 0.42) + (phase * 1.2));
      final double combined = (wave1 * 0.50 + wave2 * 0.30 + wave3 * 0.20) * 0.5 + 0.5;
      
      // Musical frequency response curve with dynamic envelope
      final double distFromCenter = (normalizedX - 0.45).abs();
      final double envelope = 0.45 + 0.55 * math.exp(-distFromCenter * 1.5);

      final double dynamicBase = (t > 0.0)
          ? (0.16 + 0.84 * combined * envelope)
          : (0.24 + 0.36 * envelope * (math.sin(i * 0.35).abs()));
      final double h = (dynamicBase * (size.height - 4.0)).clamp(4.0, size.height - 2.0);
      
      final Offset top = Offset(x, (size.height - h) / 2);
      final Offset bottom = Offset(x, size.height - (size.height - h) / 2);

      if (normalizedX <= progress) {
        final Color barColor = Color.lerp(waveStartColor, waveEndColor, normalizedX) ?? waveStartColor;
        final Paint activePaint = Paint()..color = barColor..strokeCap = StrokeCap.round..strokeWidth = w;
        final Paint activeGlowPaint = Paint()
          ..color = isDark ? barColor.withValues(alpha: 0.50) : barColor.withValues(alpha: 0.25)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
        canvas.drawLine(top, bottom, activeGlowPaint);
        canvas.drawLine(top, bottom, activePaint);
      } else if (normalizedX <= buffered) {
        canvas.drawLine(top, bottom, bufferedPaint);
      } else {
        canvas.drawLine(top, bottom, inactivePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.buffered != buffered ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.t != t;
  }
}

class _ArchedDomeClipper extends CustomClipper<Path> {
  final double archHeight;
  const _ArchedDomeClipper({this.archHeight = 38});

  @override
  Path getClip(Size size) {
    final Path path = Path();
    path.moveTo(0, archHeight);
    path.quadraticBezierTo(size.width / 2, -4, size.width, archHeight);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _ArchedDomeClipper oldClipper) =>
      oldClipper.archHeight != archHeight;
}

class _ArchedDomeBorderPainter extends CustomPainter {
  final Color borderColor;
  final double archHeight;

  _ArchedDomeBorderPainter({
    required this.borderColor,
    this.archHeight = 38,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final Path path = Path();
    path.moveTo(0, archHeight);
    path.quadraticBezierTo(size.width / 2, -4, size.width, archHeight);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArchedDomeBorderPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor ||
      oldDelegate.archHeight != archHeight;
}


