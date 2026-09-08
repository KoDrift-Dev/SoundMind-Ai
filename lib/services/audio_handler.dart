// audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_player_service.dart';
import '../models/track.dart';

/// Bridges the app's single AudioPlayerService/just_audio player to
/// audio_service, which is what actually provides:
///  - the media-style notification (artwork, title, artist, prev/play/next/stop)
///  - lock-screen controls + timeline
///  - MediaSession metadata/playback-state for Android Auto/Wear/Assistant
///  - Bluetooth and wired-headset button routing (play/pause/next/prev/stop)
///
/// Observes AudioPlayerService.instance and registers itself as the single
/// audio handler for transport and lifecycle synchronization.
class SoundMindAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayerService _service = AudioPlayerService.instance;

  SoundMindAudioHandler() {
    _service.attachAudioHandler(this);
    try {
      playbackState.add(_transformEvent(_player.playbackEvent));
    } catch (_) {}
    _listenForPlaybackEvents();
    _listenForCurrentTrack();
    _listenForSequence();
  }

  AudioPlayer get _player => _service.player;

  void _listenForPlaybackEvents() {
    _player.playbackEventStream.listen((event) {
      playbackState.add(_transformEvent(event));
    }, onError: (Object e, StackTrace st) {
      // Never let a stream error silently kill notification updates.
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
      ));
    });

    _player.playingStream.listen((playing) {
      playbackState.add(playbackState.value.copyWith(playing: playing));
    });
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.setRepeatMode,
        MediaAction.setShuffleMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
      shuffleMode: _player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[_player.loopMode]!,
    );
  }

  void _listenForCurrentTrack() {
    _player.currentIndexStream.listen((index) {
      if (index == null) {
        mediaItem.add(null);
        return;
      }
      final playlist = _service.currentPlaylist;
      if (index < 0 || index >= playlist.length) {
        mediaItem.add(null);
        return;
      }
      mediaItem.add(_mediaItemFor(playlist[index]));
    });
  }

  void _listenForSequence() {
    _player.sequenceStateStream.listen((state) {
      queue.add(_service.currentPlaylist.map(_mediaItemFor).toList());
    });
  }

  MediaItem _mediaItemFor(Track track) {
    Uri? artUri;
    final art = track.artUrl;
    if (art.isNotEmpty) {
      artUri = art.startsWith('http') ? Uri.tryParse(art) : Uri.file(art);
    } else if (track.id != null && track.id! > 0) {
      // Android standard MediaStore content URI for album art
      artUri = Uri.parse('content://media/external/audio/media/${track.id}/albumart');
    }
    return MediaItem(
      id: track.filePath ?? track.id.toString(),
      title: track.title,
      artist: track.artist,
      album: track.album,
      artUri: artUri,
      duration: track.duration != null ? Duration(milliseconds: track.duration!) : null,
    );
  }

  // ───────────────────────── Transport controls ─────────────────────────
  // These are invoked from the notification, lock screen, Android Auto,
  // Bluetooth headset buttons, and wired-headset buttons alike.

  @override
  Future<void> play() {
    if (_service.currentTrack == null ||
        _player.processingState == ProcessingState.idle) {
      return Future.value();
    }
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
      controls: const [],
    ));
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // When the user closes/swipes away the app from Recents,
    // completely tear down the foreground service and MediaSession to prevent
    // zombie playback upon Bluetooth reconnection or button press.
    await stop();
    await super.onTaskRemoved();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _service.skipToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _service.currentPlaylist.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(shuffleMode != AudioServiceShuffleMode.none);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    };
    await _player.setLoopMode(mode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  /// Double/triple-click on some Bluetooth earbuds arrives as repeated
  /// MEDIA_BUTTON events; audio_service coalesces single vs double clicks
  /// for us and calls these overrides.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (_service.currentTrack == null ||
        _player.processingState == ProcessingState.idle) {
      return;
    }
    switch (button) {
      case MediaButton.media:
        _player.playing ? await pause() : await play();
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }
}