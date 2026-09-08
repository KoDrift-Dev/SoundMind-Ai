import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/online_search_result.dart';
import '../../services/youtube_service.dart';

class OnlineAudioService extends ChangeNotifier {
  static final OnlineAudioService instance = OnlineAudioService._();
  OnlineAudioService._() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  
  OnlineSearchResult? _currentTrack;
  bool _isLoading = false;
  String? _error;

  OnlineSearchResult? get currentTrack => _currentTrack;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isPlaying => _player.playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  void _init() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _player.stop();
        _currentTrack = null;
        notifyListeners();
      }
    });
  }

  Future<void> playTrack(OnlineSearchResult track) async {
    if (track.previewUrl == null) {
      _error = 'No playable stream available for this track.';
      notifyListeners();
      return;
    }

    try {
      _isLoading = true;
      _error = null;
      _currentTrack = track;
      notifyListeners();

      // Use the SAME headers the androidSdkless client used to fetch the manifest.
      // YouTube's stream URLs are tied to the requesting User-Agent — mismatches = 403.
      debugPrint('OnlineAudioService: Playback starting with headers: ${YoutubeService.playbackHeaders}');

      await _player.setAudioSource(AudioSource.uri(
        Uri.parse(track.previewUrl!),
        headers: YoutubeService.playbackHeaders,
      ));
      await _player.play();
    } catch (e) {
      _error = 'Playback failed: $e';
      _currentTrack = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    await _player.play();
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
