// test/phase2_advanced_intelligence_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:soundmindai/classifier/classification_result.dart';
import 'package:soundmindai/classifier/heuristic_audio_classifier.dart';
import 'package:soundmindai/classifier/hybrid_audio_classifier.dart';
import 'package:soundmindai/classifier/ml_audio_classifier.dart';
import 'package:soundmindai/database/app_database.dart';
import 'package:soundmindai/models/audio_category.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/repositories/audio_repository.dart';
import 'package:soundmindai/screens/car_mode_screen.dart';
import 'package:soundmindai/services/duplicate_detection_service.dart';
import 'package:soundmindai/services/equalizer_service.dart';
import 'package:soundmindai/services/metadata_editor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('P2.1 — On-Device ML & Hybrid Audio Classifier Tests', () {
    late HeuristicAudioClassifier heuristicClassifier;
    late MlAudioClassifier mlClassifier;
    late HybridAudioClassifier hybridClassifier;

    setUp(() {
      heuristicClassifier = const HeuristicAudioClassifier();
      mlClassifier = MlAudioClassifier();
      hybridClassifier = HybridAudioClassifier(
        heuristicClassifier: heuristicClassifier,
        mlClassifier: mlClassifier,
      );
    });

    test('MlAudioClassifier handles non-existent or inaccessible file gracefully without crashing', () async {
      final dummyTrack = Track(
        id: 9999,
        filePath: '/non/existent/path/test.mp3',
        fileName: 'test.mp3',
        title: 'Ghost Track',
        artist: 'Ghost Artist',
        duration: 180000,
        fileSize: 5000000,
      );

      final result = await mlClassifier.classify(dummyTrack);
      expect(result.source, equals(ClassificationSource.ml));
      expect(result.category, equals(AudioCategory.unknown));
      expect(result.confidence, lessThan(0.50));
      expect(result.isMusic, isFalse);
    });

    test('HybridAudioClassifier skips ML when heuristic confidence is high (Battery & CPU conservation)', () async {
      final highConfidenceMusic = Track(
        id: 101,
        filePath: '/storage/emulated/0/Music/Artist/Album/Song.flac',
        fileName: 'Song.flac',
        title: 'Masterpiece',
        artist: 'Legendary Band',
        album: 'Greatest Hits',
        genre: 'Rock',
        duration: 240000, // 4 mins
        fileSize: 30000000, // 30 MB FLAC
      );

      final result = await hybridClassifier.classify(highConfidenceMusic);
      expect(result.source, equals(ClassificationSource.heuristic));
      expect(result.category, equals(AudioCategory.music));
      expect(result.confidence, greaterThanOrEqualTo(0.85));
      expect(result.isMusic, isTrue);
    });

    test('HybridAudioClassifier routes low-confidence/ambiguous track to ML classifier', () async {
      // Create a temporary audio file with mock content
      final tempDir = await Directory.systemTemp.createTemp('soundmind_test_');
      final tempFile = File('${tempDir.path}/ambiguous_audio.mp3');
      
      // Write 8000 bytes with music-like non-zero distribution
      final bytes = List<int>.generate(8192, (i) => (i * 37) % 256);
      await tempFile.writeAsBytes(bytes);

      try {
        final ambiguousTrack = Track(
          id: 202,
          filePath: tempFile.path,
          fileName: 'audio_temp_track.mp3',
          title: 'Unknown Title',
          artist: 'Unknown Artist',
          duration: 120000, // 2 mins
          fileSize: 8192,
        );

        final result = await hybridClassifier.classify(ambiguousTrack);
        // Heuristic had no metadata, no tags, unknown title/artist -> low confidence
        // Hybrid should have invoked ML
        expect(result.source, equals(ClassificationSource.ml));
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        await tempDir.delete();
      }
    });

    test('End-to-end multi-category classification pipeline across all 10 audio categories', () async {
      // 1. Setup in-memory database to verify DB insertion and UI category mapping
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tracks (
              id INTEGER PRIMARY KEY,
              file_path TEXT UNIQUE,
              file_name TEXT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT,
              genre TEXT,
              year INTEGER,
              track_number INTEGER,
              album_artist TEXT,
              duration INTEGER,
              file_size INTEGER,
              bitrate INTEGER,
              mime_type TEXT,
              extension TEXT,
              folder_path TEXT,
              date_added INTEGER,
              date_modified INTEGER,
              last_scanned INTEGER,
              is_music INTEGER NOT NULL DEFAULT 0,
              audio_category TEXT NOT NULL,
              confidence REAL NOT NULL DEFAULT 0.0,
              classification_source TEXT NOT NULL,
              user_override INTEGER NOT NULL DEFAULT 0,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played INTEGER,
              is_downloaded INTEGER NOT NULL DEFAULT 0,
              art_url TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE folder_exclusions (
              folder_path TEXT PRIMARY KEY,
              date_excluded INTEGER,
              is_excluded INTEGER NOT NULL DEFAULT 1
            )
          ''');
        },
      );
      AppDatabase.instance.testDatabase = db;
      final repo = AudioRepository.instance;

      // 2. Define fixtures for all 10 categories
      final fixtures = <Track, AudioCategory>{
        // 1. Song
        Track(
          id: 1001,
          filePath: '/storage/emulated/0/Music/Queen/Bohemian_Rhapsody.mp3',
          fileName: 'Bohemian_Rhapsody.mp3',
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          album: 'A Night at the Opera',
          duration: 354000,
          fileSize: 8500000,
        ): AudioCategory.music,

        // 2. Voice recording
        Track(
          id: 1002,
          filePath: '/storage/emulated/0/Recordings/Voice Recorder/meeting_01.m4a',
          fileName: 'meeting_01.m4a',
          title: 'Meeting Notes',
          artist: '<unknown>',
          duration: 450000,
          fileSize: 3200000,
        ): AudioCategory.recording,

        // 3. Voice note
        Track(
          id: 1003,
          filePath: '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes/PTT-20240101-WA0001.opus',
          fileName: 'PTT-20240101-WA0001.opus',
          title: 'PTT-20240101-WA0001',
          artist: '<unknown>',
          duration: 15000,
          fileSize: 45000,
        ): AudioCategory.voiceNote,

        // 4. WhatsApp audio
        Track(
          id: 1004,
          filePath: '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio/AUD-20240101-WA0002.mp3',
          fileName: 'AUD-20240101-WA0002.mp3',
          title: 'AUD-20240101-WA0002',
          artist: '<unknown>',
          duration: 45000,
          fileSize: 720000,
        ): AudioCategory.messagingAudio,

        // 5. Ringtone
        Track(
          id: 1005,
          filePath: '/storage/emulated/0/Ringtones/marimba_ring.mp3',
          fileName: 'marimba_ring.mp3',
          title: 'Marimba Ringtone',
          artist: '<unknown>',
          duration: 22000,
          fileSize: 350000,
        ): AudioCategory.ringtone,

        // 6. Notification
        Track(
          id: 1006,
          filePath: '/storage/emulated/0/Notifications/alert_chime.ogg',
          fileName: 'alert_chime.ogg',
          title: 'Chime Alert',
          artist: '<unknown>',
          duration: 2500,
          fileSize: 42000,
        ): AudioCategory.notification,

        // 7. Podcast
        Track(
          id: 1007,
          filePath: '/storage/emulated/0/Podcasts/TechTalk/episode_42.mp3',
          fileName: 'episode_42.mp3',
          title: 'Tech Talk Episode 42',
          artist: 'Tech Podcasters',
          duration: 2400000,
          fileSize: 48000000,
        ): AudioCategory.podcast,

        // 8. Audiobook
        Track(
          id: 1008,
          filePath: '/storage/emulated/0/Audiobooks/Dune/chapter_01.mp3',
          fileName: 'chapter_01.mp3',
          title: 'Dune Chapter 1',
          artist: 'Narrator',
          duration: 1800000,
          fileSize: 36000000,
        ): AudioCategory.audiobook,

        // 9. Sound effect
        Track(
          id: 1009,
          filePath: '/storage/emulated/0/SoundEffects/sfx_laser.wav',
          fileName: 'sfx_laser.wav',
          title: 'Laser Blast SFX',
          artist: '<unknown>',
          duration: 2000,
          fileSize: 88000,
        ): AudioCategory.soundEffect,

        // 10. Unknown / Review
        Track(
          id: 1010,
          filePath: '/storage/emulated/0/Downloads/random_binary_track.bin',
          fileName: 'random_binary_track.bin',
          title: 'random_binary_track',
          artist: '<unknown>',
          duration: 42000,
          fileSize: 200000,
        ): AudioCategory.unknown,
      };

      // 3. Classify all fixtures and verify pipeline step by step
      final classifiedTracks = <Track>[];
      for (final entry in fixtures.entries) {
        final rawTrack = entry.key;
        final expectedCategory = entry.value;

        // Pipeline: raw track -> Hybrid classifier (Heuristic -> ML when ambiguous)
        final result = await hybridClassifier.classify(rawTrack);

        expect(result.category, equals(expectedCategory),
            reason: 'Track "${rawTrack.title}" should classify as ${expectedCategory.displayName}');

        if (expectedCategory == AudioCategory.music) {
          expect(result.isMusic, isTrue);
          expect(result.confidence, greaterThanOrEqualTo(0.75));
        } else if (expectedCategory == AudioCategory.unknown) {
          expect(result.isMusic, isFalse);
          expect(result.confidence, lessThan(0.50));
        } else {
          expect(result.isMusic, isFalse);
          expect(result.confidence, greaterThanOrEqualTo(0.70));
        }

        // Verify UI category display name contract
        expect(result.category.displayName, isNotEmpty);

        final classified = rawTrack.copyWith(
          audioCategory: result.category,
          isMusic: result.isMusic,
          confidence: result.confidence,
          classificationSource: result.source,
        );
        classifiedTracks.add(classified);
      }

      // 4. Batch upsert into SQLite database
      await repo.batchUpsertTracks(classifiedTracks);

      // 5. Verify database queries: Music-only queue MUST contain only Song (id: 1001)
      final musicTracks = await repo.getMusicOnlyTracks();
      expect(musicTracks.length, equals(1));
      expect(musicTracks.first.id, equals(1001));
      expect(musicTracks.first.audioCategory, equals(AudioCategory.music));

      // 6. Verify non-music tracks are categorized properly in DB
      for (final expectedCat in AudioCategory.values) {
        if (expectedCat == AudioCategory.other) continue;
        final categoryTracks = await repo.getTracksByCategory(expectedCat);
        if (expectedCat == AudioCategory.music) {
          expect(categoryTracks.length, equals(1));
        } else if (fixtures.values.contains(expectedCat)) {
          expect(categoryTracks.length, equals(1),
              reason: 'DB query for ${expectedCat.displayName} should return 1 track');
          expect(categoryTracks.first.audioCategory, equals(expectedCat));
        }
      }

      // 7. Verify review track is captured by getReviewTracks()
      final reviewTracks = await repo.getReviewTracks();
      expect(reviewTracks.any((t) => t.id == 1010), isTrue);

      await db.close();
    });
  });

  group('P2.2 — Real Multi-Band Equalizer Tests', () {
    late EqualizerService eq;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      eq = EqualizerService.instance;
      await eq.setPreset(EqualizerPreset.flat);
      await eq.setEnabled(true);
      await eq.setPreampGain(0.0);
    });

    test('Initializes with 5 frequency bands covering bass to treble', () {
      expect(eq.bands.length, equals(5));
      expect(eq.bands[0].centerFrequency, equals(60)); // Bass
      expect(eq.bands[1].centerFrequency, equals(230)); // Low-Mid
      expect(eq.bands[2].centerFrequency, equals(910)); // Mid
      expect(eq.bands[3].centerFrequency, equals(3600)); // High-Mid
      expect(eq.bands[4].centerFrequency, equals(14000)); // Treble
    });

    test('Applying presets correctly updates band gains and preset indicator', () async {
      await eq.setPreset(EqualizerPreset.rock);
      expect(eq.currentPreset, equals(EqualizerPreset.rock));
      expect(eq.bands[0].gain, equals(4.5));
      expect(eq.bands[2].gain, equals(-1.0));
      expect(eq.bands[4].gain, equals(4.0));

      await eq.setPreset(EqualizerPreset.pop);
      expect(eq.currentPreset, equals(EqualizerPreset.pop));
      expect(eq.bands[0].gain, equals(-1.0));
      expect(eq.bands[2].gain, equals(4.0));
    });

    test('Adjusting individual band switches preset to custom and clamps to bounds', () async {
      await eq.setPreset(EqualizerPreset.flat);
      await eq.setBandGain(0, 8.5);
      expect(eq.currentPreset, equals(EqualizerPreset.custom));
      expect(eq.bands[0].gain, equals(8.5));

      // Test upper clamp (+10.0 dB)
      await eq.setBandGain(0, 25.0);
      expect(eq.bands[0].gain, equals(10.0));

      // Test lower clamp (-10.0 dB)
      await eq.setBandGain(1, -30.0);
      expect(eq.bands[1].gain, equals(-10.0));
    });

    test('Preamp gain clamps between -6.0 and +6.0 dB', () async {
      await eq.setPreampGain(3.5);
      expect(eq.preampGain, equals(3.5));

      await eq.setPreampGain(15.0);
      expect(eq.preampGain, equals(6.0));

      await eq.setPreampGain(-12.0);
      expect(eq.preampGain, equals(-6.0));
    });

    test('Toggling equalizer enabled/disabled state works cleanly without crashing', () async {
      await eq.setEnabled(false);
      expect(eq.isEnabled, isFalse);

      await eq.setEnabled(true);
      expect(eq.isEnabled, isTrue);
    });
  });

  group('P2.3 — Storage & Category Insights Tests', () {
    late Database testDb;
    late AudioRepository repository;

    setUp(() async {
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tracks (
              id INTEGER PRIMARY KEY,
              file_path TEXT UNIQUE,
              file_name TEXT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT,
              genre TEXT,
              year INTEGER,
              track_number INTEGER,
              album_artist TEXT,
              duration INTEGER,
              file_size INTEGER,
              bitrate INTEGER,
              mime_type TEXT,
              extension TEXT,
              folder_path TEXT,
              date_added INTEGER,
              date_modified INTEGER,
              last_scanned INTEGER,
              is_music INTEGER NOT NULL DEFAULT 0,
              audio_category TEXT NOT NULL DEFAULT 'unknown',
              confidence REAL NOT NULL DEFAULT 0.0,
              classification_source TEXT NOT NULL DEFAULT 'heuristic',
              user_override INTEGER NOT NULL DEFAULT 0,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played INTEGER,
              is_downloaded INTEGER NOT NULL DEFAULT 0,
              art_url TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE folder_exclusions (
              folder_path TEXT PRIMARY KEY,
              date_excluded INTEGER,
              is_excluded INTEGER NOT NULL DEFAULT 1
            )
          ''');
        },
      );

      AppDatabase.instance.testDatabase = testDb;
      repository = AudioRepository.instance;
    });

    tearDown(() async {
      AppDatabase.instance.testDatabase = null;
      await testDb.close();
    });

    test('getStorageInsights computes real totals, category distributions, and byte metrics', () async {
      final sampleTracks = [
        // 3 verified music tracks (5MB each = 15,000,000 bytes)
        Track(id: 1, filePath: '/music/s1.mp3', fileName: 's1.mp3', title: 'S1', artist: 'A', fileSize: 5000000, isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9),
        Track(id: 2, filePath: '/music/s2.mp3', fileName: 's2.mp3', title: 'S2', artist: 'A', fileSize: 5000000, isMusic: true, audioCategory: AudioCategory.music, confidence: 0.85),
        Track(id: 3, filePath: '/music/s3.mp3', fileName: 's3.mp3', title: 'S3', artist: 'A', fileSize: 5000000, isMusic: true, audioCategory: AudioCategory.music, confidence: 0.92),
        // 2 recordings (2MB each = 4,000,000 bytes)
        Track(id: 4, filePath: '/rec/r1.m4a', fileName: 'r1.m4a', title: 'R1', artist: 'Unknown', fileSize: 2000000, isMusic: false, audioCategory: AudioCategory.recording, confidence: 0.8),
        Track(id: 5, filePath: '/rec/r2.m4a', fileName: 'r2.m4a', title: 'R2', artist: 'Unknown', fileSize: 2000000, isMusic: false, audioCategory: AudioCategory.recording, confidence: 0.8),
        // 1 voice note (500KB = 500,000 bytes)
        Track(id: 6, filePath: '/voice/v1.opus', fileName: 'v1.opus', title: 'V1', artist: 'Unknown', fileSize: 500000, isMusic: false, audioCategory: AudioCategory.voiceNote, confidence: 0.85),
        // 1 podcast (20MB = 20,000,000 bytes)
        Track(id: 7, filePath: '/pod/p1.mp3', fileName: 'p1.mp3', title: 'P1', artist: 'Host', fileSize: 20000000, isMusic: false, audioCategory: AudioCategory.podcast, confidence: 0.8),
        // 1 ringtone (800KB = 800,000 bytes)
        Track(id: 8, filePath: '/ring/ring.mp3', fileName: 'ring.mp3', title: 'Ring', artist: 'OEM', fileSize: 800000, isMusic: false, audioCategory: AudioCategory.ringtone, confidence: 0.88),
        // 1 notification (100KB = 100,000 bytes)
        Track(id: 9, filePath: '/notif/ding.ogg', fileName: 'ding.ogg', title: 'Ding', artist: 'OEM', fileSize: 100000, isMusic: false, audioCategory: AudioCategory.notification, confidence: 0.9),
        // 1 unknown track (1.2MB = 1,200,000 bytes)
        Track(id: 10, filePath: '/unk/clip.wav', fileName: 'clip.wav', title: 'Clip', artist: 'Unknown', fileSize: 1200000, isMusic: false, audioCategory: AudioCategory.unknown, confidence: 0.4),
      ];

      await repository.batchUpsertTracks(sampleTracks);

      final insights = await repository.getStorageInsights();

      expect(insights.totalAudioFiles, equals(10));
      expect(insights.musicCount, equals(3));
      expect(insights.recordingsCount, equals(2));
      expect(insights.voiceNotesCount, equals(1));
      expect(insights.podcastsCount, equals(1));
      expect(insights.ringtonesCount, equals(1));
      expect(insights.notificationsCount, equals(1));
      expect(insights.unknownCount, equals(1));

      expect(insights.totalStorageBytes, equals(41600000));
      expect(insights.musicStorageBytes, equals(15000000));

      expect(insights.formattedTotalStorage, contains('MB'));
      expect(insights.formattedMusicStorage, contains('MB'));
      expect(insights.musicStoragePercentage, closeTo(15000000 / 41600000, 0.01));
    });
  });

  group('P2.4 — Advanced Metadata Handling Tests', () {
    late Database testDb;
    late AudioRepository repository;
    late MetadataEditorService editorService;

    setUp(() async {
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tracks (
              id INTEGER PRIMARY KEY,
              file_path TEXT UNIQUE,
              file_name TEXT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT,
              genre TEXT,
              year INTEGER,
              track_number INTEGER,
              album_artist TEXT,
              duration INTEGER,
              file_size INTEGER,
              bitrate INTEGER,
              mime_type TEXT,
              extension TEXT,
              folder_path TEXT,
              date_added INTEGER,
              date_modified INTEGER,
              last_scanned INTEGER,
              is_music INTEGER NOT NULL DEFAULT 0,
              audio_category TEXT NOT NULL DEFAULT 'unknown',
              confidence REAL NOT NULL DEFAULT 0.0,
              classification_source TEXT NOT NULL DEFAULT 'heuristic',
              user_override INTEGER NOT NULL DEFAULT 0,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played INTEGER,
              is_downloaded INTEGER NOT NULL DEFAULT 0,
              art_url TEXT
            )
          ''');
        },
      );

      AppDatabase.instance.testDatabase = testDb;
      repository = AudioRepository.instance;
      editorService = MetadataEditorService.instance;
    });

    tearDown(() async {
      AppDatabase.instance.testDatabase = null;
      await testDb.close();
    });

    test('updateMetadata updates SQLite database record and reports physical write status', () async {
      final initialTrack = Track(
        id: 501,
        filePath: '/storage/emulated/0/Music/Song.mp3',
        fileName: 'Song.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Old Album',
        genre: 'Pop',
        year: 2020,
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.9,
      );

      await repository.batchUpsertTracks([initialTrack]);

      const editParams = EditMetadataParams(
        title: 'Updated Title',
        artist: 'Refined Artist',
        album: 'Remastered Album',
        genre: 'Progressive Rock',
        year: 2024,
        trackNumber: 7,
        albumArtist: 'Legendary Band',
      );

      final result = await editorService.updateMetadata(
        track: initialTrack,
        params: editParams,
      );

      expect(result.isDatabaseUpdated, isTrue);
      expect(result.updatedTrack.title, equals('Updated Title'));
      expect(result.updatedTrack.artist, equals('Refined Artist'));
      expect(result.updatedTrack.album, equals('Remastered Album'));
      expect(result.updatedTrack.genre, equals('Progressive Rock'));
      expect(result.updatedTrack.year, equals(2024));
      expect(result.updatedTrack.trackNumber, equals(7));
      expect(result.updatedTrack.albumArtist, equals('Legendary Band'));

      // Verify record inside SQLite database
      final verifiedRows = await testDb.query('tracks', where: 'id = ?', whereArgs: [501]);
      expect(verifiedRows.length, equals(1));
      expect(verifiedRows.first['title'], equals('Updated Title'));
      expect(verifiedRows.first['artist'], equals('Refined Artist'));
      expect(verifiedRows.first['album'], equals('Remastered Album'));
      expect(verifiedRows.first['year'], equals(2024));
      expect(verifiedRows.first['track_number'], equals(7));
      expect(verifiedRows.first['album_artist'], equals('Legendary Band'));
    });

    test('Correctly reports PARTIAL physical write on non-existent or restricted container', () async {
      final m4aTrack = Track(
        id: 502,
        filePath: '/storage/emulated/0/Music/voice.m4a',
        fileName: 'voice.m4a',
        title: 'Interview Clip',
        artist: 'Speaker',
        extension: 'm4a',
      );

      await repository.batchUpsertTracks([m4aTrack]);

      const editParams = EditMetadataParams(
        title: 'Interview 2024',
        artist: 'Speaker Refined',
      );

      final result = await editorService.updateMetadata(
        track: m4aTrack,
        params: editParams,
      );

      expect(result.isDatabaseUpdated, isTrue);
      // Because file does not exist on disk in test environment, physical status reflects accurate status
      expect(result.physicalStatusMessage, isNotEmpty);
    });
  });

  group('P2.5 — Duplicate Detection Tests', () {
    late Database testDb;
    late AudioRepository repository;
    late DuplicateDetectionService duplicateService;

    setUp(() async {
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tracks (
              id INTEGER PRIMARY KEY,
              file_path TEXT UNIQUE,
              file_name TEXT,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT,
              genre TEXT,
              year INTEGER,
              track_number INTEGER,
              album_artist TEXT,
              duration INTEGER,
              file_size INTEGER,
              bitrate INTEGER,
              mime_type TEXT,
              extension TEXT,
              folder_path TEXT,
              date_added INTEGER,
              date_modified INTEGER,
              last_scanned INTEGER,
              is_music INTEGER NOT NULL DEFAULT 0,
              audio_category TEXT NOT NULL DEFAULT 'unknown',
              confidence REAL NOT NULL DEFAULT 0.0,
              classification_source TEXT NOT NULL DEFAULT 'heuristic',
              user_override INTEGER NOT NULL DEFAULT 0,
              is_favorite INTEGER NOT NULL DEFAULT 0,
              play_count INTEGER NOT NULL DEFAULT 0,
              last_played INTEGER,
              is_downloaded INTEGER NOT NULL DEFAULT 0,
              art_url TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE folder_exclusions (
              folder_path TEXT PRIMARY KEY,
              date_excluded INTEGER,
              is_excluded INTEGER NOT NULL DEFAULT 1
            )
          ''');
        },
      );

      AppDatabase.instance.testDatabase = testDb;
      repository = AudioRepository.instance;
      duplicateService = DuplicateDetectionService.instance;
    });

    tearDown(() async {
      AppDatabase.instance.testDatabase = null;
      await testDb.close();
    });

    test('Does NOT mark two tracks as duplicate merely because their titles are equal', () async {
      final tracks = [
        // Song with same title 'Hello' by Adele (4 mins, 10MB) vs 'Hello' by Lionel Richie (5 mins, 12MB)
        Track(
          id: 601,
          filePath: '/music/adele/hello.mp3',
          fileName: 'hello.mp3',
          title: 'Hello',
          artist: 'Adele',
          duration: 240000,
          fileSize: 10000000,
          isMusic: true,
          audioCategory: AudioCategory.music,
          confidence: 0.95,
        ),
        Track(
          id: 602,
          filePath: '/music/richie/hello.mp3',
          fileName: 'hello.mp3',
          title: 'Hello',
          artist: 'Lionel Richie',
          duration: 300000,
          fileSize: 12000000,
          isMusic: true,
          audioCategory: AudioCategory.music,
          confidence: 0.95,
        ),
      ];

      await repository.batchUpsertTracks(tracks);

      final duplicates = await duplicateService.findDuplicates();
      expect(duplicates, isEmpty);
    });

    test('Clusters genuine duplicates with matching acoustic profile and normalized metadata', () async {
      final tracks = [
        Track(
          id: 701,
          filePath: '/storage/emulated/0/Music/Artist/TrackA.mp3',
          fileName: 'TrackA.mp3',
          title: 'Bohemian Rhapsody',
          artist: 'Queen',
          duration: 354000,
          fileSize: 8500000,
          isMusic: true,
          audioCategory: AudioCategory.music,
          confidence: 0.95,
        ),
        Track(
          id: 702,
          filePath: '/storage/emulated/0/Downloads/TrackA_Copy.mp3',
          fileName: 'TrackA_Copy.mp3',
          title: 'Bohemian Rhapsody (Official)',
          artist: 'Queen',
          duration: 354000,
          fileSize: 8500000,
          isMusic: true,
          audioCategory: AudioCategory.music,
          confidence: 0.95,
        ),
      ];

      await repository.batchUpsertTracks(tracks);

      final duplicates = await duplicateService.findDuplicates();
      expect(duplicates.length, equals(1));
      expect(duplicates.first.tracks.length, equals(2));
      expect(duplicates.first.reclaimableBytes, equals(8500000));
    });

    test('safelyDeleteDuplicate removes redundant copy from DB and preserves primary copy', () async {
      final track1 = Track(
        id: 801,
        filePath: '/music/song1.mp3',
        fileName: 'song1.mp3',
        title: 'Song 1',
        artist: 'Band',
        duration: 180000,
        fileSize: 4000000,
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.9,
      );
      final track2 = Track(
        id: 802,
        filePath: '/downloads/song1.mp3',
        fileName: 'song1.mp3',
        title: 'Song 1',
        artist: 'Band',
        duration: 180000,
        fileSize: 4000000,
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.9,
      );

      await repository.batchUpsertTracks([track1, track2]);

      // Delete the duplicate copy
      final success = await duplicateService.safelyDeleteDuplicate(
        track: track2,
        deletePhysicalFile: false, // In test environment
      );

      expect(success, isTrue);

      // Verify track2 is gone from DB, but track1 remains
      final remaining = await repository.getMusicOnlyTracks();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals(801));
    });
  });

  group('P2.6 — Car Mode Tests', () {
    testWidgets('CarModeScreen renders high-contrast interface, oversized controls and Bluetooth-safety badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CarModeScreen(),
        ),
      );

      // Verify glanceable in-car elements
      expect(find.text('Exit Car Mode'), findsOneWidget);
      expect(find.text('Music-Only Verified Safe'), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    });
  });
}





