// audio_player_service.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import 'equalizer_service.dart';
import 'youtube_service.dart';

/// Supported Audio Boost levels, shown to the user as percentages.
/// These NEVER touch `player.volume` (which must stay within 0.0-1.0).
/// Boost is implemented as a real Android LoudnessEnhancer audio effect
/// measured in decibels, completely independent of the volume slider.
const List<double> kAudioBoostLevels = [1.0, 1.25, 1.5, 1.75, 2.0];

/// Converts a boost multiplier (e.g. 1.25 = 125%) to the decibel gain
/// LoudnessEnhancer expects. 100% => 0 dB (no boost).
/// Multiplied by 100.0 because the native API expects millibels (mB).
double _boostToDecibels(double multiplier) => (20 * math.log(multiplier) / math.ln10) * 100.0;

class AudioPlayerService extends ChangeNotifier {
  static final AudioPlayerService instance = AudioPlayerService._internal();

  // A single AndroidLoudnessEnhancer attached to the one-and-only player
  // via an AudioPipeline. This is a real audio effect (not a fake slider):
  // on non-Android platforms it simply has no effect, which is a genuine
  // just_audio/platform limitation, not something we're hiding behind a
  // "coming soon" label.
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer player = AudioPlayer(
    audioPipeline: AudioPipeline(androidAudioEffects: [
      _loudnessEnhancer,
    ]),
  );

  List<Track> currentPlaylist = [];
  // ignore: deprecated_member_use
  ConcatenatingAudioSource? _playlistSource;
  int? _resolvingTrackIndex;

  BaseAudioHandler? _audioHandler;

  /// Attaches the global audio handler for OS foreground service and MediaSession lifecycle coordination.
  void attachAudioHandler(BaseAudioHandler handler) {
    _audioHandler = handler;
  }

  @visibleForTesting
  Track? testTrackOverride;

  /// True only after the user explicitly calls [loadPlaylist] or [playMusicOnly].
  /// Reset to false by [stopAndReset]. Prevents the mini player from appearing
  /// after a quiet [restorePersistedQueue] on app launch.
  bool hasUserStartedPlayback = false;

  /// Returns currently playing track or null.
  Track? get currentTrack {
    if (testTrackOverride != null) return testTrackOverride;
    if (!hasUserStartedPlayback) return null;
    if (_resolvingTrackIndex != null &&
        _resolvingTrackIndex! >= 0 &&
        _resolvingTrackIndex! < currentPlaylist.length) {
      return currentPlaylist[_resolvingTrackIndex!];
    }
    final idx = player.currentIndex;
    if (idx != null && idx >= 0 && idx < currentPlaylist.length) {
      return currentPlaylist[idx];
    }
    return null;
  }

  // ───────────────────────── Playback History ─────────────────────────

  final List<Track> _playbackHistory = [];
  List<Track> get playbackHistory => List.unmodifiable(_playbackHistory);

  Timer? _sleepTimer;
  DateTime? _sleepEndTime;
  final StreamController<Duration?> _sleepTimerStreamCtrl = StreamController<Duration?>.broadcast();
  Stream<Duration?> get sleepTimerStream => _sleepTimerStreamCtrl.stream;

  // ───────────────────────── A-B Repeat ─────────────────────────
  Duration? abPointA;
  Duration? abPointB;
  final StreamController<void> _abRepeatStreamCtrl = StreamController<void>.broadcast();
  Stream<void> get abRepeatStream => _abRepeatStreamCtrl.stream;
  bool _abSeekInFlight = false;

  // ───────────────────────── Device Volume (hardware) ─────────────────────────
  // This IS the physical media volume: the slider moves the hardware
  // buttons, and the hardware buttons move the slider. `player.volume`
  // itself is intentionally left at a fixed 1.0 always — it is not used
  // as a second, competing volume control.
  final StreamController<double> _deviceVolumeStreamCtrl = StreamController<double>.broadcast();
  Stream<double> get deviceVolumeStream => _deviceVolumeStreamCtrl.stream;
  double _lastKnownDeviceVolume = 1.0;
  double get lastKnownDeviceVolume => _lastKnownDeviceVolume;

  // ───────────────────────── Audio Boost ─────────────────────────
  double _audioBoost = 1.0;
  double get audioBoost => _audioBoost;
  final StreamController<double> _audioBoostStreamCtrl = StreamController<double>.broadcast();
  Stream<double> get audioBoostStream => _audioBoostStreamCtrl.stream;

  bool _initialized = false;

  AudioPlayerService._internal() {
    // player.volume is a fixed unity gain — never surfaced to the UI —
    // so nothing can ever feed an out-of-range value into a 0.0-1.0 Slider.
    player.setVolume(1.0);

    _initAudioSession();
    _initDeviceVolume();

    // Hook native hardware audio effects (Equalizer, BassBoost) into ExoPlayer session
    player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId != null && sessionId > 0) {
        EqualizerService.instance.attachToSession(sessionId);
      }
    });

    // A-B repeat, guarded against re-entrant seeks (positionStream can
    // emit again before an in-flight seek resolves).
    player.positionStream.listen((pos) async {
      final a = abPointA;
      final b = abPointB;
      if (a == null || b == null || _abSeekInFlight) return;
      if (pos >= b) {
        _abSeekInFlight = true;
        try {
          await player.seek(a);
        } finally {
          _abSeekInFlight = false;
        }
      }
    });

    // Listen for playback events and decode errors to gracefully skip corrupted tracks
    player.playbackEventStream.listen(
      (event) {},
      onError: (Object e, StackTrace st) {
        debugPrint('AudioPlayerService: Playback stream error caught: $e');
        final cur = player.currentIndex;
        if (cur != null) {
          _recoverFromLoadFailure(cur);
        }
      },
    );

    // Auto-advance when track finishes if at the end of queue and auto-next is enabled
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _isAutoNextEnabled) {
        debugPrint('AudioPlayerService: Track completed with auto-next active');
        _handleAutoNextAtEnd();
      }
    });

    // Handle track changes (History & A-B Repeat Reset)
    player.currentIndexStream.listen((index) {
      if (abPointA != null || abPointB != null) {
        abPointA = null;
        abPointB = null;
        _abRepeatStreamCtrl.add(null);
      }

      if (index != null && index >= 0 && index < currentPlaylist.length) {
        final track = currentPlaylist[index];
        
        // Remove track if it exists to bubble it to the top
        _playbackHistory.removeWhere((t) => t.id == track.id);
        _playbackHistory.insert(0, track);
        
        // Cap history to 50 items to prevent memory growth
        if (_playbackHistory.length > 50) {
          _playbackHistory.removeLast();
        }

        // Persist playback history to SQLite database
        if (track.id != null) {
          AudioRepository.instance.recordPlayback(track.id!);
        }

        // Persist active queue state
        _persistCurrentQueue();
        
        // Notify listening UI screens (Home & Collections)
        notifyListeners();

        // Check if queue needs auto-next replenishment
        if (_isAutoNextEnabled) {
          _checkAndReplenishAutoNext();
        }
      }
    });
  }

  Future<void> _initAudioSession() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      // With handleInterruptions (default true on AudioPlayer) and this
      // session configuration, just_audio automatically:
      //  - ducks/pauses on transient focus loss (calls, nav prompts, other apps)
      //  - pauses on permanent focus loss
      //  - pauses when headphones are unplugged / Bluetooth disconnects
      //    (audio_session's "becoming noisy" handling)
      // without any extra code here.
    } catch (e) {
      debugPrint('AudioPlayerService: failed to configure AudioSession: $e');
    }
  }

  Future<void> _initDeviceVolume() async {
    try {
      await FlutterVolumeController.setAndroidAudioStream(stream: AudioStream.music);
      final vol = await FlutterVolumeController.getVolume();
      _lastKnownDeviceVolume = vol ?? 1.0;
      _deviceVolumeStreamCtrl.add(vol ?? 1.0);
    } catch (e) {
      debugPrint('AudioPlayerService: failed to read device volume: $e');
    }
    // Hardware buttons -> UI. This listener is global to the plugin, and
    // this service is the single owner of it.
    FlutterVolumeController.addListener((volume) {
      _lastKnownDeviceVolume = volume;
      _deviceVolumeStreamCtrl.add(volume);
    });
  }

  /// UI -> hardware. Range is always 0.0-1.0.
  Future<void> setDeviceVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _lastKnownDeviceVolume = clamped;
    _deviceVolumeStreamCtrl.add(clamped);
    try {
      await FlutterVolumeController.setVolume(clamped);
    } catch (e) {
      debugPrint('AudioPlayerService: failed to set device volume: $e');
    }
  }

  /// Sets Audio Boost. Must be one of [kAudioBoostLevels]. Implemented as a
  /// real LoudnessEnhancer gain in decibels — structurally unable to leak
  /// into player.volume or any 0.0-1.0 Slider.
  Future<void> setAudioBoost(double multiplier) async {
    if (!kAudioBoostLevels.contains(multiplier)) return;
    _audioBoost = multiplier;
    _audioBoostStreamCtrl.add(_audioBoost);
    try {
      final db = _boostToDecibels(multiplier);
      await _loudnessEnhancer.setEnabled(multiplier > 1.0);
      await _loudnessEnhancer.setTargetGain(db);
    } catch (e) {
      // Genuine platform limitation: LoudnessEnhancer is Android-only.
      // On iOS/desktop this is a no-op rather than a crash.
      debugPrint('AudioPlayerService: Audio Boost unavailable on this platform: $e');
    }
  }

  // ───────────────────────── Auto-Next Online Queue ─────────────────────────
  bool _isAutoNextEnabled = false;
  bool get isAutoNextEnabled => _isAutoNextEnabled;

  final Set<String> _queuedOnlineIds = {};
  bool _isReplenishingAutoNext = false;
  String? _currentAutoNextSeedVideoId;
  String? _currentAutoNextSeedTitle;
  String? _currentAutoNextSeedArtist;

  /// Activates auto-next for an online track and begins replenishing the queue.
  void startAutoNextForOnlineTrack({
    required String seedTrackId,
    required String title,
    required String artist,
  }) {
    debugPrint('AudioPlayerService: Enabling Auto-Next for "$title" by "$artist" ($seedTrackId)');
    _isAutoNextEnabled = true;
    _currentAutoNextSeedVideoId = seedTrackId;
    _currentAutoNextSeedTitle = title;
    _currentAutoNextSeedArtist = artist;
    _queuedOnlineIds.clear();
    if (seedTrackId.isNotEmpty) {
      _queuedOnlineIds.add(seedTrackId);
    }
    for (final t in currentPlaylist) {
      if (t.onlineId != null && t.onlineId!.isNotEmpty) {
        _queuedOnlineIds.add(t.onlineId!);
      }
    }
    _checkAndReplenishAutoNext();
  }

  /// Disables auto-next mode (e.g. when playing local tracks or stopping).
  void stopAutoNext() {
    _isAutoNextEnabled = false;
    _queuedOnlineIds.clear();
    _currentAutoNextSeedVideoId = null;
    _currentAutoNextSeedTitle = null;
    _currentAutoNextSeedArtist = null;
    _isReplenishingAutoNext = false;
  }

  void _checkAndReplenishAutoNext() {
    if (!_isAutoNextEnabled || _isReplenishingAutoNext) return;
    final curIdx = player.currentIndex ?? 0;
    final remaining = (currentPlaylist.length - 1) - curIdx;
    if (remaining < 3) {
      _replenishAutoNextQueue();
    }
  }

  Future<void> _replenishAutoNextQueue() async {
    if (!_isAutoNextEnabled || _isReplenishingAutoNext) return;
    _isReplenishingAutoNext = true;

    try {
      final seedId = _currentAutoNextSeedVideoId ?? currentTrack?.onlineId ?? '';
      final seedTitle = _currentAutoNextSeedTitle ?? currentTrack?.title ?? '';
      final seedArtist = _currentAutoNextSeedArtist ?? currentTrack?.artist ?? '';

      if (seedId.isEmpty && seedTitle.isEmpty) {
        _isReplenishingAutoNext = false;
        return;
      }

      debugPrint('AudioPlayerService: Fetching auto-next recommendations for "$seedTitle" ($seedId)...');
      final candidates = await YoutubeService.instance.getRelatedOrAutoNextTracks(
        seedId,
        seedTitle,
        seedArtist,
      );

      final unqueuedCandidates = candidates.where((c) {
        if (_queuedOnlineIds.contains(c.id)) return false;
        if (currentPlaylist.any((t) => t.onlineId == c.id)) return false;
        return true;
      }).toList();

      debugPrint('AudioPlayerService: Found ${unqueuedCandidates.length} candidate auto-next tracks');

      int addedCount = 0;
      for (final candidate in unqueuedCandidates) {
        if (addedCount >= 2) break;
        if (!_isAutoNextEnabled) break;

        try {
          debugPrint('AudioPlayerService: Resolving auto-next stream for "${candidate.title}" (${candidate.id})...');
          final streamUrl = await YoutubeService.instance.getAudioStreamUrl(candidate.id);
          if (streamUrl != null && streamUrl.isNotEmpty) {
            final track = Track(
              onlineId: candidate.id,
              filePath: streamUrl,
              title: candidate.title,
              artist: candidate.artist,
              album: candidate.album,
              artUrl: candidate.thumbnailUrl ?? '',
              isMusic: true,
              isResolving: false,
            );

            _queuedOnlineIds.add(candidate.id);
            await addToQueue(track);
            addedCount++;

            // Shift seed to the latest queued track so recommendations keep evolving
            _currentAutoNextSeedVideoId = candidate.id;
            _currentAutoNextSeedTitle = candidate.title;
            _currentAutoNextSeedArtist = candidate.artist;
            debugPrint('AudioPlayerService: Successfully auto-queued "${candidate.title}"');
          }
        } catch (e) {
          debugPrint('AudioPlayerService: Failed to resolve auto-next candidate ${candidate.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('AudioPlayerService: Error in _replenishAutoNextQueue: $e');
    } finally {
      _isReplenishingAutoNext = false;
    }
  }

  Future<void> _handleAutoNextAtEnd() async {
    if (!_isAutoNextEnabled) return;
    if (_isReplenishingAutoNext) {
      for (int i = 0; i < 15; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!_isReplenishingAutoNext) break;
      }
    } else {
      await _replenishAutoNextQueue();
    }

    if (player.hasNext) {
      try {
        await player.seekToNext();
        player.play();
      } catch (e) {
        debugPrint('AudioPlayerService: Error advancing to auto-next track: $e');
      }
    }
  }

  Future<void> loadPlaylist(List<Track> tracks, int initialIndex) async {
    if (tracks.isEmpty) return;

    // P5.3 RED TEAM: Strictly filter out any non-music track to guarantee music-only playback
    final safeTracks = tracks.where((t) => t.isMusic).toList();
    if (safeTracks.isEmpty) {
      debugPrint('AudioPlayerService: Blocked loadPlaylist - no verified music tracks in list');
      return;
    }

    final hasOnlineTracks = safeTracks.any((t) => t.onlineId != null || (t.filePath != null && t.filePath!.startsWith('http')));
    if (!hasOnlineTracks) {
      stopAutoNext();
    } else if (safeTracks.length == 1) {
      final single = safeTracks.first;
      if (!single.isResolving && single.onlineId != null) {
        startAutoNextForOnlineTrack(
          seedTrackId: single.onlineId!,
          title: single.title,
          artist: single.artist,
        );
      }
    }

    final targetTrack = (initialIndex >= 0 && initialIndex < tracks.length) ? tracks[initialIndex] : null;
    int safeIndex = 0;
    if (targetTrack != null && targetTrack.isMusic) {
      safeIndex = safeTracks.indexOf(targetTrack);
      if (safeIndex < 0) safeIndex = 0;
    } else {
      safeIndex = initialIndex.clamp(0, safeTracks.length - 1);
    }

    // If target track is still resolving its stream URL:
    if (safeTracks[safeIndex].isResolving) {
      currentPlaylist = List.from(safeTracks);
      _resolvingTrackIndex = safeIndex;
      hasUserStartedPlayback = true;
      clearAbRepeat();
      try {
        await player.stop();
      } catch (_) {}
      notifyListeners();
      return;
    }

    _resolvingTrackIndex = null;

    bool isSamePlaylist = currentPlaylist.length == safeTracks.length &&
        currentPlaylist.isNotEmpty &&
        currentPlaylist.first.id == safeTracks.first.id;

    bool isSameIndex = player.currentIndex == safeIndex;

    if (isSamePlaylist && isSameIndex) {
      hasUserStartedPlayback = true;
      if (!player.playing) {
        player.play();
      }
      return;
    }

    currentPlaylist = List.from(safeTracks);
    clearAbRepeat();

    final audioSources = currentPlaylist.map(_createAudioSource).toList();
    // ignore: deprecated_member_use
    _playlistSource = ConcatenatingAudioSource(children: audioSources);

    try {
      hasUserStartedPlayback = true;
      await player.setAudioSource(_playlistSource!, initialIndex: safeIndex);
      player.play();
      _persistCurrentQueue();
    } on PlayerException {
      await _recoverFromLoadFailure(safeIndex);
    } on PlayerInterruptedException {
      // A newer load call superseded this one — safe to ignore.
    } catch (_) {
      // Unknown failure: leave state as-is rather than crash the app.
    }
  }

  /// Hydrates a pending online track with the resolved audio stream URL and starts playback.
  Future<void> hydratePendingTrack(String streamUrl) async {
    final idx = _resolvingTrackIndex ?? 0;
    if (idx >= 0 && idx < currentPlaylist.length) {
      final track = currentPlaylist[idx];
      track.filePath = streamUrl;
      track.isResolving = false;
      track.resolutionError = null;

      final audioSources = currentPlaylist.map(_createAudioSource).toList();
      // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
      _resolvingTrackIndex = null;

      try {
        hasUserStartedPlayback = true;
        // Pre-signal playWhenReady to ExoPlayer so audio starts immediately upon first buffer packets
        player.play();
        final readySw = Stopwatch()..start();
        await player.setAudioSource(_playlistSource!, initialIndex: idx);
        readySw.stop();
        debugPrint('AudioPlayerService [PROFILER]: ExoPlayer audio source prepared in ${readySw.elapsedMilliseconds}ms');
        _persistCurrentQueue();
      } on PlayerException {
        await _recoverFromLoadFailure(idx);
      } catch (e) {
        debugPrint('AudioPlayerService: failed to play hydrated stream: $e');
        track.resolutionError = 'Failed to load audio stream';
      }
      notifyListeners();

      // Automatically enable and kick off auto-next if this is an online track
      if (track.onlineId != null && track.onlineId!.isNotEmpty) {
        startAutoNextForOnlineTrack(
          seedTrackId: track.onlineId!,
          title: track.title,
          artist: track.artist,
        );
      }
    }
  }

  /// Marks the current pending online track as failed to resolve so the UI can show an error.
  void markPendingTrackFailed(String error) {
    final idx = _resolvingTrackIndex ?? 0;
    if (idx >= 0 && idx < currentPlaylist.length) {
      final track = currentPlaylist[idx];
      track.isResolving = false;
      track.resolutionError = error;
      notifyListeners();
    }
  }

  /// Centralized Bluetooth-safe playback initiator.
  /// Strictly queries verified Music tracks only and loads them into player.
  Future<void> playMusicOnly({int initialIndex = 0}) async {
    final musicTracks = await AudioRepository.instance.getMusicOnlyTracks();
    if (musicTracks.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, musicTracks.length - 1);
    await loadPlaylist(musicTracks, safeIndex);
  }

  /// Skips to the next track in the playlist.
  Future<void> skipToNext() async {
    try {
      if (player.hasNext) {
        await player.seekToNext();
      } else if (_isAutoNextEnabled) {
        await _handleAutoNextAtEnd();
      }
    } catch (e) {
      debugPrint('AudioPlayerService: Error in skipToNext: $e');
    }
  }

  /// Skips to the previous track in the playlist.
  Future<void> skipToPrevious() async {
    try {
      if (player.hasPrevious) {
        await player.seekToPrevious();
      } else {
        await player.seek(Duration.zero);
      }
    } catch (e) {
      debugPrint('AudioPlayerService: Error in skipToPrevious: $e');
    }
  }

  /// Skips directly to a specific item index in the current queue.
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < currentPlaylist.length) {
      await player.seek(Duration.zero, index: index);
    }
  }

  /// Persists active playlist, index, and playback position to SQLite.
  Future<void> _persistCurrentQueue() async {
    try {
      if (currentPlaylist.isNotEmpty && player.currentIndex != null) {
        await AudioRepository.instance.saveQueue(
          tracks: currentPlaylist,
          currentIndex: player.currentIndex!,
          positionMs: player.position.inMilliseconds,
        );
      }
    } catch (e) {
      debugPrint('AudioPlayerService: Error persisting queue: $e');
    }
  }

  /// Restores persisted queue from previous app session.
  Future<void> restorePersistedQueue() async {
    try {
      final saved = await AudioRepository.instance.loadQueue();
      if (saved != null && saved.tracks.isNotEmpty) {
        // Red-team defense: enforce music-only on loaded queue
        final safeTracks = saved.tracks.where((t) => t.isMusic).toList();
        if (safeTracks.isEmpty) return;

        currentPlaylist = List.from(safeTracks);
        final safeIndex = saved.currentIndex.clamp(0, currentPlaylist.length - 1);
        final audioSources = currentPlaylist.map(_createAudioSource).toList();
        // ignore: deprecated_member_use
        _playlistSource = ConcatenatingAudioSource(children: audioSources);
        await player.setAudioSource(
          _playlistSource!,
          initialIndex: safeIndex,
          initialPosition: Duration(milliseconds: saved.positionMs),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AudioPlayerService: Error restoring queue: $e');
    }
  }

  /// Toggles favorite state with cross-instance synchronization and database persistence.
  Future<void> toggleFavorite(Track track) async {
    final newFav = !track.isFavorite;
    track.isFavorite = newFav;

    final cur = currentTrack;
    if ((cur?.id != null && cur!.id == track.id) ||
        (cur?.onlineId != null && cur!.onlineId == track.onlineId)) {
      cur.isFavorite = newFav;
    }

    for (final t in currentPlaylist) {
      if ((t.id != null && t.id == track.id) ||
          (t.onlineId != null && t.onlineId == track.onlineId)) {
        t.isFavorite = newFav;
      }
    }

    await AudioRepository.instance.toggleFavoriteTrack(track, newFav);
    notifyListeners();
  }

  // ───────────────────────── QUEUE HARDENING (P4.2) ─────────────────────────

  /// Adds a verified music track to the end of the active playback queue.
  Future<bool> addToQueue(Track track) async {
    if (!track.isMusic) {
      debugPrint('AudioPlayerService: Rejected non-music track from playback queue: ${track.title}');
      return false;
    }
    currentPlaylist.add(track);
    if (_playlistSource != null) {
      try {
        await _playlistSource!.add(_createAudioSource(track));
      } catch (e) {
        debugPrint('AudioPlayerService: Error adding to playlistSource: $e');
      }
    }
    await _persistCurrentQueue();
    notifyListeners();
    return true;
  }

  /// Inserts a verified music track as the next item to play in the active queue.
  Future<bool> insertNext(Track track) async {
    if (!track.isMusic) {
      debugPrint('AudioPlayerService: Rejected non-music track from playback queue: ${track.title}');
      return false;
    }
    final curIdx = player.currentIndex ?? (currentPlaylist.isNotEmpty ? 0 : -1);
    final insertIdx = (curIdx >= 0 && curIdx < currentPlaylist.length) ? curIdx + 1 : currentPlaylist.length;

    currentPlaylist.insert(insertIdx, track);
    if (_playlistSource != null) {
      try {
        final sourceIdx = insertIdx.clamp(0, _playlistSource!.length);
        await _playlistSource!.insert(sourceIdx, _createAudioSource(track));
      } catch (e) {
        debugPrint('AudioPlayerService: Error inserting into playlistSource: $e');
      }
    }
    await _persistCurrentQueue();
    notifyListeners();
    return true;
  }

  /// Removes an item at [index] from the active playback queue.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= currentPlaylist.length) return;
    if (currentPlaylist.length <= 1) {
      await player.stop();
      currentPlaylist.clear();
      await _persistCurrentQueue();
      notifyListeners();
      return;
    }

    currentPlaylist.removeAt(index);
    if (_playlistSource != null && index < _playlistSource!.length) {
      try {
        await _playlistSource!.removeAt(index);
      } catch (e) {
        debugPrint('AudioPlayerService: Error removing from playlistSource: $e');
      }
    }
    await _persistCurrentQueue();
    notifyListeners();
  }

  /// Reorders an item in the active playback queue from [oldIndex] to [newIndex].
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= currentPlaylist.length) return;
    if (newIndex < 0 || newIndex >= currentPlaylist.length) return;

    final item = currentPlaylist.removeAt(oldIndex);
    currentPlaylist.insert(newIndex, item);

    if (_playlistSource != null &&
        oldIndex < _playlistSource!.length &&
        newIndex < _playlistSource!.length) {
      try {
        await _playlistSource!.move(oldIndex, newIndex);
      } catch (e) {
        debugPrint('AudioPlayerService: Error moving in playlistSource: $e');
      }
    }
    await _persistCurrentQueue();
    notifyListeners();
  }

  /// Clears the playback queue except for currently playing track, or all if stopped.
  Future<void> clearQueue() async {
    final cur = currentTrack;
    if (cur != null) {
      currentPlaylist = [cur];
      final audioSources = [_createAudioSource(cur)];
      // ignore: deprecated_member_use
      _playlistSource = ConcatenatingAudioSource(children: audioSources);
      try {
        await player.setAudioSource(_playlistSource!, initialIndex: 0);
      } catch (e) {
        debugPrint('AudioPlayerService: Error setting audioSource in clearQueue: $e');
      }
      if (_isAutoNextEnabled && cur.onlineId != null) {
        _queuedOnlineIds.clear();
        _queuedOnlineIds.add(cur.onlineId!);
        _checkAndReplenishAutoNext();
      }
    } else {
      stopAutoNext();
      await player.stop();
      currentPlaylist.clear();
      _playlistSource = null;
    }
    await _persistCurrentQueue();
    notifyListeners();
  }


  /// Completely stops playback, clears the queue, releases the audio session,
  /// stops the Android foreground service, and dismisses the media notification.
  Future<void> stopAndReset() async {
    stopAutoNext();
    currentPlaylist.clear();
    testTrackOverride = null;
    _resolvingTrackIndex = null;
    _playlistSource = null;
    hasUserStartedPlayback = false;
    try {
      await player.stop();
      // Detach source so currentIndex becomes null → currentTrack == null
      // ignore: deprecated_member_use
      await player.setAudioSource(ConcatenatingAudioSource(children: []));
    } catch (e) {
      debugPrint('AudioPlayerService: Error stopping player in stopAndReset: $e');
    }
    try {
      await _audioHandler?.stop();
    } catch (e) {
      debugPrint('AudioPlayerService: Error stopping audioHandler: $e');
    }
    notifyListeners();
    await _persistCurrentQueue();
  }

  /// Explicit stop action wired to player controls and lifecycle events.
  Future<void> stopPlayback() => stopAndReset();


  /// Reorders queue item handling Flutter's ReorderableListView index shift.
  Future<void> reorderQueueItem(int oldIndex, int newIndex) async {
    int target = newIndex;
    if (oldIndex < newIndex) {
      target = newIndex - 1;
    }
    await reorderQueue(oldIndex, target);
  }

  /// Toggles shuffle mode on the underlying audio player.
  Future<void> toggleShuffle() async {
    final next = !player.shuffleModeEnabled;
    await player.setShuffleModeEnabled(next);
    notifyListeners();
  }

  /// Cycles loop mode: off -> all -> one -> off.
  Future<void> cycleLoopMode() async {
    final current = player.loopMode;
    final next = switch (current) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await player.setLoopMode(next);
    notifyListeners();
  }

  Future<void> _recoverFromLoadFailure(int failedIndex) async {
    if (_playlistSource == null) return;
    for (int i = failedIndex + 1; i < currentPlaylist.length; i++) {
      try {
        await player.seek(Duration.zero, index: i);
        await player.play();
        return;
      } catch (_) {
        continue;
      }
    }
  }

  AudioSource _createAudioSource(Track track) {
    final isOnline = track.filePath != null && track.filePath!.startsWith('http');
    final uri = isOnline
        ? Uri.parse(track.filePath!)
        : Uri.file(track.filePath ?? '');

    // Online (YouTube-sourced) tracks MUST send the same headers used when
    // the stream URL was fetched from YoutubeService, or YouTube's CDN
    // rejects the playback request with 403 — headers being logged
    // elsewhere for debugging was never enough; they have to be attached
    // to the AudioSource itself, which is what was missing before.
    return AudioSource.uri(
      uri,
      tag: track,
      headers: isOnline ? YoutubeService.playbackHeaders : null,
    );
  }

  // ───────────────────────── A-B Repeat methods ─────────────────────────
  void setAbPointA(Duration pos) {
    abPointA = pos;
    // We intentionally DO NOT clear abPointB here, so both markers can coexist.
    _abRepeatStreamCtrl.add(null);
  }

  void setAbPointB(Duration pos) {
    abPointB = pos;
    _abRepeatStreamCtrl.add(null);
  }

  void clearAbRepeat() {
    abPointA = null;
    abPointB = null;
    _abSeekInFlight = false;
    _abRepeatStreamCtrl.add(null);
  }

  // ───────────────────────── Sleep Timer ─────────────────────────
  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    if (duration.inSeconds == 0) {
      _sleepEndTime = null;
      _sleepTimerStreamCtrl.add(null);
      return;
    }
    _sleepEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (now.isAfter(_sleepEndTime!)) {
        player.pause();
        cancelSleepTimer();
      } else {
        _sleepTimerStreamCtrl.add(_sleepEndTime!.difference(now));
      }
    });
    _sleepTimerStreamCtrl.add(duration);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndTime = null;
    _sleepTimerStreamCtrl.add(null);
  }

  void setSleepTimerToEndOfSong() {
    _sleepTimer?.cancel();
    _sleepTimerStreamCtrl.add(const Duration(seconds: -1));
    StreamSubscription<ProcessingState>? sub;
    sub = player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        player.pause();
        cancelSleepTimer();
        sub?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _sleepTimerStreamCtrl.close();
    _abRepeatStreamCtrl.close();
    _audioBoostStreamCtrl.close();
    _deviceVolumeStreamCtrl.close();
    FlutterVolumeController.removeListener();
    EqualizerService.instance.release();
    player.dispose();
    super.dispose();
  }
}