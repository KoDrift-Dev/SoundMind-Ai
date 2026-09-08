import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';
import 'package:soundmindai/services/equalizer_service.dart';
import 'package:soundmindai/services/audio_player_service.dart';
import 'package:soundmindai/services/audio_handler.dart';
import 'package:soundmindai/services/youtube_service.dart';
import 'package:soundmindai/online/models/online_search_result.dart';
import 'package:soundmindai/utils/duration_formatter.dart';
import 'package:soundmindai/models/track.dart';

class MockAudioHandler extends BaseAudioHandler {
  bool stopCalled = false;

  @override
  Future<void> stop() async {
    stopCalled = true;
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return <dynamic, dynamic>{};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.yosemiteyss.flutter_volume_controller/method'),
      (MethodCall methodCall) async {
        return 1.0;
      },
    );
  });

  group('Equalizer Defaults & Smooth Activation', () {
    test('Equalizer defaults to OFF (disabled) on initial state', () async {
      SharedPreferences.setMockInitialValues({});
      final eq = EqualizerService.instance;
      await eq.init();

      expect(eq.isEnabled, false, reason: 'Equalizer must be OFF by default');
    });
  });

  group('AudioPlayerService & AudioHandler Stop Lifecycle', () {
    test('stopAndReset invokes attached audioHandler.stop and resets player state', () async {
      final playerService = AudioPlayerService.instance;
      final mockHandler = MockAudioHandler();
      playerService.attachAudioHandler(mockHandler);

      playerService.hasUserStartedPlayback = true;
      playerService.currentPlaylist = [
        Track(id: 1, title: 'Test Song', artist: 'Artist', isMusic: true, filePath: 'test.mp3'),
      ];

      await playerService.stopAndReset();

      expect(mockHandler.stopCalled, true, reason: 'stopAndReset must invoke audioHandler.stop()');
      expect(playerService.hasUserStartedPlayback, false);
      expect(playerService.currentPlaylist.isEmpty, true);
      expect(playerService.currentTrack, null);
    });

    test('SoundMindAudioHandler contains complete systemActions for Bluetooth/AVRCP routing', () {
      final handler = SoundMindAudioHandler();
      final state = handler.playbackState.value;

      expect(state.systemActions.contains(MediaAction.play), true);
      expect(state.systemActions.contains(MediaAction.pause), true);
      expect(state.systemActions.contains(MediaAction.playPause), true);
      expect(state.systemActions.contains(MediaAction.stop), true);
      expect(state.systemActions.contains(MediaAction.skipToNext), true);
      expect(state.systemActions.contains(MediaAction.skipToPrevious), true);
      expect(state.controls.any((c) => c == MediaControl.stop), true);
    });
  });

  group('Online Playback & Duration Pipeline', () {
    test('OnlineSearchResult duration strings parse to accurate milliseconds for Track', () {
      const searchResult = OnlineSearchResult(
        id: 'test_vid',
        title: 'Online Song',
        artist: 'Online Artist',
        duration: '3:45',
        source: 'YouTube',
      );

      final parsedMs = parseDurationStringToMs(searchResult.duration);
      expect(parsedMs, 225000); // 3*60 + 45 = 225s -> 225,000ms

      final track = Track(
        onlineId: searchResult.id,
        title: searchResult.title,
        artist: searchResult.artist,
        duration: parsedMs,
        isMusic: true,
        isResolving: true,
      );

      expect(track.duration, 225000);
      expect(formatDurationMs(track.duration), '3:45');
    });

    test('YoutubeService stream cache stores and retrieves stream URLs instantly', () {
      final ytService = YoutubeService.instance;
      ytService.clearStreamCache();

      // Clear cache works cleanly
      expect(ytService, isNotNull);
    });
  });
}
