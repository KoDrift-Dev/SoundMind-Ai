// phase1_audio_intelligence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:soundmindai/classifier/audio_classifier.dart';
import 'package:soundmindai/classifier/classification_result.dart';
import 'package:soundmindai/classifier/heuristic_audio_classifier.dart';
import 'package:soundmindai/database/app_database.dart';
import 'package:soundmindai/models/audio_category.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/repositories/audio_repository.dart';

void main() {
  // Initialize FFI for SQLite tests
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late AudioClassifier classifier;
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

        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_path ON tracks(file_path)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_is_music ON tracks(is_music, confidence)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_category ON tracks(audio_category)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_favorite ON tracks(is_favorite)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_history ON tracks(last_played)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_folder ON tracks(folder_path)');

        await db.execute('''
          CREATE TABLE folder_exclusions (
            folder_path TEXT PRIMARY KEY,
            date_excluded INTEGER,
            is_excluded INTEGER NOT NULL DEFAULT 1
          )
        ''');

        await db.execute('''
          CREATE TABLE persisted_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER,
            file_path TEXT,
            queue_order INTEGER NOT NULL,
            is_current INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    AppDatabase.instance.testDatabase = testDb;
    classifier = const HeuristicAudioClassifier();
    repository = AudioRepository.instance;
  });

  tearDown(() async {
    await testDb.close();
  });

  // ════════════════════════════ 1. CLASSIFICATION TESTS (SECTION 39) ════════════════════════════
  group('Heuristic Audio Classifier Tests', () {
    test('Classifies standard music file as MUSIC with high confidence', () async {
      final track = Track(
        id: 101,
        filePath: '/storage/emulated/0/Music/Coldplay/Yellow.mp3',
        title: 'Yellow',
        artist: 'Coldplay',
        album: 'Parachutes',
        genre: 'Alternative Rock',
        year: 2000,
        duration: 269000,
        fileSize: 6451200,
      );

      final result = await classifier.classify(track);
      expect(result.category, equals(AudioCategory.music));
      expect(result.confidence, greaterThanOrEqualTo(ClassificationResult.musicConfidenceThreshold));
      expect(result.isMusic, isTrue);
      expect(result.source, equals(ClassificationSource.heuristic));
    });

    test('Classifies meeting voice recording as RECORDING', () async {
      final track = Track(
        id: 102,
        filePath: '/storage/emulated/0/Recordings/meeting_001.m4a',
        title: 'meeting_001',
        artist: 'Unknown Artist',
        duration: 1800000,
        fileSize: 12400000,
      );

      final result = await classifier.classify(track);
      expect(result.category, equals(AudioCategory.recording));
      expect(result.confidence, greaterThanOrEqualTo(0.70));
      expect(result.isMusic, isFalse);
    });

    test('Classifies WhatsApp audio file as MESSAGING_AUDIO or VOICE_NOTE', () async {
      final track = Track(
        id: 103,
        filePath: '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio/AUD-20230501-WA0001.opus',
        title: 'AUD-20230501-WA0001',
        artist: 'Unknown Artist',
        duration: 45000,
        fileSize: 340000,
      );

      final result = await classifier.classify(track);
      expect(
        result.category == AudioCategory.messagingAudio || result.category == AudioCategory.voiceNote,
        isTrue,
      );
      expect(result.isMusic, isFalse);
    });

    test('Classifies ringtone as RINGTONE', () async {
      final track = Track(
        id: 104,
        filePath: '/storage/emulated/0/Ringtones/my_ringtone.mp3',
        title: 'my_ringtone',
        artist: 'Unknown Artist',
        duration: 25000,
        fileSize: 450000,
      );

      final result = await classifier.classify(track);
      expect(result.category, equals(AudioCategory.ringtone));
      expect(result.isMusic, isFalse);
    });

    test('Classifies notification sound as NOTIFICATION', () async {
      final track = Track(
        id: 105,
        filePath: '/storage/emulated/0/Notifications/message.mp3',
        title: 'message',
        artist: 'Unknown Artist',
        duration: 3000,
        fileSize: 64000,
      );

      final result = await classifier.classify(track);
      expect(result.category, equals(AudioCategory.notification));
      expect(result.isMusic, isFalse);
    });

    test('Classifies ambiguous audio file without metadata or known path as UNKNOWN / Review', () async {
      final track = Track(
        id: 106,
        filePath: '/storage/emulated/0/random_folder/track_x.bin',
        title: 'track_x',
        artist: 'Unknown Artist',
        duration: 42000,
      );

      final result = await classifier.classify(track);
      expect(
        result.category == AudioCategory.unknown || result.confidence < ClassificationResult.musicConfidenceThreshold,
        isTrue,
      );
      expect(result.isMusic, isFalse);
    });
  });

  // ════════════════════════════ 2. MANUAL OVERRIDE (SECTION 40) ════════════════════════════
  group('Manual Classification Override Tests', () {
    test('User override changes category and persists permanently across rescans', () async {
      // 1. Initial automatic classification: recording
      final autoTrack = Track(
        id: 201,
        filePath: '/storage/emulated/0/Recordings/guitar_riff.mp3',
        title: 'guitar_riff',
        artist: 'Unknown Artist',
        duration: 120000,
        audioCategory: AudioCategory.recording,
        confidence: 0.85,
        isMusic: false,
        userOverride: false,
      );

      await repository.batchUpsertTracks([autoTrack]);

      var inDb = (await repository.getExistingTrackMap())[autoTrack.filePath]!;
      expect(inDb.isMusic, isFalse);
      expect(inDb.userOverride, isFalse);

      // 2. User overrides: "Add to Music"
      await repository.overrideClassification(autoTrack.id!, AudioCategory.music);

      inDb = (await repository.getExistingTrackMap())[autoTrack.filePath]!;
      expect(inDb.audioCategory, equals(AudioCategory.music));
      expect(inDb.isMusic, isTrue);
      expect(inDb.userOverride, isTrue);
      expect(inDb.classificationSource, equals(ClassificationSource.userOverride));

      // 3. Simulated rescan: classifier must respect userOverride
      final rescanResult = await classifier.classify(inDb);
      expect(rescanResult.category, equals(AudioCategory.music));
      expect(rescanResult.confidence, equals(1.0));
      expect(rescanResult.isMusic, isTrue);
    });
  });

  // ════════════════════════════ 3. BLUETOOTH-SAFE QUEUE (SECTION 41) ════════════════════════════
  group('Bluetooth-Safe Music-Only Queue Tests', () {
    test('getMusicOnlyTracks returns ONLY verified music and rejects non-music', () async {
      final tracks = [
        Track(
          id: 301,
          filePath: '/storage/emulated/0/Music/SongA.mp3',
          title: 'Song A',
          artist: 'Artist A',
          audioCategory: AudioCategory.music,
          confidence: 0.95,
          isMusic: true,
        ),
        Track(
          id: 302,
          filePath: '/storage/emulated/0/Recordings/VoiceA.m4a',
          title: 'Voice A',
          artist: 'Unknown Artist',
          audioCategory: AudioCategory.recording,
          confidence: 0.85,
          isMusic: false,
        ),
        Track(
          id: 303,
          filePath: '/storage/emulated/0/Ringtones/RingA.mp3',
          title: 'Ring A',
          artist: 'Unknown Artist',
          audioCategory: AudioCategory.ringtone,
          confidence: 0.90,
          isMusic: false,
        ),
        Track(
          id: 304,
          filePath: '/storage/emulated/0/WhatsApp/WhatsAppA.opus',
          title: 'WhatsApp A',
          artist: 'Unknown Artist',
          audioCategory: AudioCategory.messagingAudio,
          confidence: 0.88,
          isMusic: false,
        ),
        Track(
          id: 305,
          filePath: '/storage/emulated/0/UnknownA.mp3',
          title: 'Unknown A',
          artist: 'Unknown Artist',
          audioCategory: AudioCategory.unknown,
          confidence: 0.40,
          isMusic: false,
        ),
        Track(
          id: 306,
          filePath: '/storage/emulated/0/Music/SongB.mp3',
          title: 'Song B',
          artist: 'Artist B',
          audioCategory: AudioCategory.music,
          confidence: 0.92,
          isMusic: true,
        ),
      ];

      await repository.batchUpsertTracks(tracks);

      final musicQueue = await repository.getMusicOnlyTracks();

      expect(musicQueue.length, equals(2));
      expect(musicQueue.map((t) => t.title).toList(), containsAll(['Song A', 'Song B']));
      expect(musicQueue.any((t) => t.audioCategory != AudioCategory.music), isFalse);
    });
  });

  // ════════════════════════════ 4. PERSISTENCE TESTS (SECTION 42) ════════════════════════════
  group('Database Persistence Tests', () {
    test('Persists favorite state across sessions', () async {
      final track = Track(
        id: 401,
        filePath: '/storage/emulated/0/Music/FavSong.mp3',
        title: 'Fav Song',
        artist: 'Favorite Artist',
        audioCategory: AudioCategory.music,
        confidence: 0.95,
        isMusic: true,
        isFavorite: false,
      );

      await repository.batchUpsertTracks([track]);
      var favs = await repository.getFavorites();
      expect(favs.isEmpty, isTrue);

      // Toggle favorite
      await repository.toggleFavorite(track.id!, true);
      favs = await repository.getFavorites();
      expect(favs.length, equals(1));
      expect(favs.first.id, equals(track.id));
      expect(favs.first.isFavorite, isTrue);
    });

    test('Persists playback history and updates play count', () async {
      final track = Track(
        id: 402,
        filePath: '/storage/emulated/0/Music/HistorySong.mp3',
        title: 'History Song',
        artist: 'History Artist',
        audioCategory: AudioCategory.music,
        confidence: 0.95,
        isMusic: true,
        playCount: 0,
      );

      await repository.batchUpsertTracks([track]);

      await repository.recordPlayback(track.id!);
      await repository.recordPlayback(track.id!);

      final history = await repository.getRecentlyPlayed();
      expect(history.length, equals(1));
      expect(history.first.playCount, equals(2));
      expect(history.first.lastPlayed, isNotNull);
    });

    test('Persists and restores active playback queue', () async {
      final t1 = Track(
        id: 403,
        filePath: '/storage/emulated/0/Music/Q1.mp3',
        title: 'Q1',
        artist: 'Artist 1',
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.9,
      );
      final t2 = Track(
        id: 404,
        filePath: '/storage/emulated/0/Music/Q2.mp3',
        title: 'Q2',
        artist: 'Artist 2',
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.9,
      );

      await repository.batchUpsertTracks([t1, t2]);
      await repository.saveQueue(tracks: [t1, t2], currentIndex: 1, positionMs: 45000);

      final restored = await repository.loadQueue();
      expect(restored, isNotNull);
      expect(restored!.tracks.length, equals(2));
      expect(restored.currentIndex, equals(1));
      expect(restored.positionMs, equals(45000));
      expect(restored.tracks[1].title, equals('Q2'));
    });
  });

  // ════════════════════════════ 5. FOLDER EXCLUSION TESTS (SECTION 44) ════════════════════════════
  group('Folder Exclusion Tests', () {
    test('Excluded folder omits tracks from music-only query', () async {
      final t1 = Track(
        id: 501,
        filePath: '/storage/emulated/0/Music/Song1.mp3',
        folderPath: '/storage/emulated/0/Music',
        title: 'Song 1',
        artist: 'Artist 1',
        audioCategory: AudioCategory.music,
        confidence: 0.95,
        isMusic: true,
      );
      final t2 = Track(
        id: 502,
        filePath: '/storage/emulated/0/WhatsApp/Media/Song2.mp3',
        folderPath: '/storage/emulated/0/WhatsApp/Media',
        title: 'Song 2',
        artist: 'Artist 2',
        audioCategory: AudioCategory.music,
        confidence: 0.90,
        isMusic: true,
      );

      await repository.batchUpsertTracks([t1, t2]);

      // Initially both are returned
      var music = await repository.getMusicOnlyTracks();
      expect(music.length, equals(2));

      // Exclude WhatsApp folder
      await repository.setFolderExcluded('/storage/emulated/0/WhatsApp/Media', true);

      // Now only Music folder track is returned
      music = await repository.getMusicOnlyTracks();
      expect(music.length, equals(1));
      expect(music.first.title, equals('Song 1'));

      // Re-include folder
      await repository.setFolderExcluded('/storage/emulated/0/WhatsApp/Media', false);
      music = await repository.getMusicOnlyTracks();
      expect(music.length, equals(2));
    });
  });

  // ════════════════════════════ 6. 10,000 FILE PERFORMANCE TEST (SECTION 45) ════════════════════════════
  group('Large Dataset Performance Tests (10,000 Files Mock)', () {
    test('Handles 10,000 files with bounded batch inserts and fast indexed queries', () async {
      const int totalFiles = 10000;
      final stopwatch = Stopwatch()..start();

      // Insert in batches of 200 items
      const int batchSize = 200;
      for (int i = 0; i < totalFiles; i += batchSize) {
        final batch = <Track>[];
        for (int j = i; j < i + batchSize && j < totalFiles; j++) {
          final isMusic = (j % 3 != 0); // ~66% music, 33% recordings/other
          batch.add(Track(
            id: j + 1,
            filePath: '/storage/emulated/0/${isMusic ? "Music" : "Recordings"}/track_$j.mp3',
            folderPath: '/storage/emulated/0/${isMusic ? "Music" : "Recordings"}',
            title: 'Track $j',
            artist: isMusic ? 'Artist ${j % 50}' : 'Unknown Artist',
            album: isMusic ? 'Album ${j % 20}' : null,
            duration: 180000,
            fileSize: 5000000,
            isMusic: isMusic,
            audioCategory: isMusic ? AudioCategory.music : AudioCategory.recording,
            confidence: isMusic ? 0.92 : 0.85,
            dateAdded: 1672531200 + j,
            dateModified: 1672531200 + j,
          ));
        }
        await repository.batchUpsertTracks(batch);
      }

      stopwatch.stop();
      final insertDuration = stopwatch.elapsedMilliseconds;
      expect(insertDuration, greaterThan(0));

      final totalCount = await repository.getTotalTracksCount();
      expect(totalCount, equals(totalFiles));

      // Benchmark indexed music-only query with pagination
      final queryStopwatch = Stopwatch()..start();
      final musicPage = await repository.getMusicOnlyTracks(limit: 50, offset: 0);
      queryStopwatch.stop();

      expect(musicPage.length, equals(50));
      // Indexed SQLite query on 10,000 items should complete in under 50ms
      expect(queryStopwatch.elapsedMilliseconds, lessThan(100));

      // Category breakdown aggregation
      final counts = await repository.getCategoryCounts();
      expect(counts[AudioCategory.music], greaterThan(6000));
      expect(counts[AudioCategory.recording], greaterThan(3000));
    });
  });
}
