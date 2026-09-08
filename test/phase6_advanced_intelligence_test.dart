// test/phase6_advanced_intelligence_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:soundmindai/database/app_database.dart';
import 'package:soundmindai/models/audio_category.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/repositories/audio_repository.dart';
import 'package:soundmindai/services/audio_player_service.dart';
import 'package:soundmindai/services/library_backup_service.dart';
import 'package:soundmindai/services/library_intelligence_service.dart';
import 'package:soundmindai/services/local_recommendation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late AudioRepository repo;
  late LocalRecommendationService recService;
  late LibraryBackupService backupService;
  late LibraryIntelligenceService intelligenceService;
  late AudioPlayerService playerService;

  setUp(() async {
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
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
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_id INTEGER NOT NULL,
            track_id INTEGER NOT NULL,
            track_order INTEGER NOT NULL,
            FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
            FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
          )
        ''');
      },
    );

    AppDatabase.instance.testDatabase = testDb;
    repo = AudioRepository.instance;
    recService = LocalRecommendationService.instance;
    backupService = LibraryBackupService.instance;
    intelligenceService = LibraryIntelligenceService.instance;
    playerService = AudioPlayerService.instance;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return <dynamic, dynamic>{};
      },
    );
  });

  tearDown(() async {
    await testDb.close();
  });

  group('P6.1 — Local Recommendation Engine', () {
    test('generateRecommendations dynamically shifts when listening history changes', () async {
      final rockSong = Track(
        id: 101,
        filePath: '/m/rock.mp3',
        fileName: 'rock.mp3',
        title: 'Rock Anthem',
        artist: 'Queen',
        genre: 'Rock',
        playCount: 1,
        isMusic: true,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
      );
      final jazzSong = Track(
        id: 102,
        filePath: '/m/jazz.mp3',
        fileName: 'jazz.mp3',
        title: 'Smooth Jazz',
        artist: 'Miles',
        genre: 'Jazz',
        playCount: 1,
        isMusic: true,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
      );
      await repo.batchUpsertTracks([rockSong, jazzSong]);

      // Initially equal
      var recs = await recService.generateRecommendations();
      expect(recs.dailyMix.length, equals(2));

      // Heavily listen to Queen
      for (int i = 0; i < 5; i++) {
        await repo.recordPlayback(101);
      }
      await repo.toggleFavorite(101, true);

      // Regenerate recommendations
      recs = await recService.generateRecommendations();
      expect(recs.dailyMix.first.id, equals(101), reason: 'Daily mix must prioritize high affinity artist and genre');
      expect(recs.topArtists['Queen'], greaterThan(recs.topArtists['Miles'] ?? 0));
    });

    test('Gracefully handles empty library without exceptions', () async {
      final recs = await recService.generateRecommendations();
      expect(recs.dailyMix, isEmpty);
      expect(recs.forgottenGems, isEmpty);
      expect(recs.heavyRotation, isEmpty);
      expect(recs.topGenres, isEmpty);
    });
  });

  group('P6.2 & P6.10 — Library Backup & Schema Versioning', () {
    test('exportBackupJson produces valid JSON with schema version 1', () async {
      final playlist = await repo.createPlaylist('Export Test');
      final t1 = Track(id: 201, filePath: '/m/201.mp3', fileName: '201.mp3', title: 'T1', artist: 'A', isMusic: true, confidence: 0.95);
      await repo.batchUpsertTracks([t1]);
      await repo.addTrackToPlaylist(playlist.id!, 201);
      await repo.setFolderExcluded('/storage/rec', true);

      final json = await backupService.exportBackupJson();
      expect(json.contains('"version":1'), isTrue);
      expect(json.contains('Export Test'), isTrue);
      expect(json.contains('/storage/rec'), isTrue);
    });

    test('importBackupJson safely rejects unsupported future schema versions', () async {
      const futureJson = '''
      {
        "version": 99,
        "timestamp": "2030-01-01T00:00:00Z",
        "playlists": [],
        "favoritePaths": [],
        "classificationOverrides": [],
        "excludedFolders": []
      }
      ''';
      final result = await backupService.importBackupJson(futureJson);
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('Unsupported backup schema version (99)'));
    });
  });

  group('P6.3 — Backup Restore End-to-End & Transactional Rollback', () {
    test('12-step end-to-end backup, mutation, restore, and verification lifecycle', () async {
      // 1. Setup tracks
      final t1 = Track(id: 301, filePath: '/m/t1.mp3', fileName: 't1.mp3', title: 'Song 1', artist: 'Band', isMusic: true, confidence: 0.95);
      final t2 = Track(id: 302, filePath: '/m/t2.mp3', fileName: 't2.mp3', title: 'Song 2', artist: 'Band', isMusic: true, confidence: 0.95);
      await repo.batchUpsertTracks([t1, t2]);

      // 2. Add playlists and state
      final pl = await repo.createPlaylist('Roadtrip Mix');
      await repo.addTrackToPlaylist(pl.id!, 301);
      await repo.addTrackToPlaylist(pl.id!, 302);
      await repo.toggleFavorite(301, true);
      await repo.overrideClassification(302, AudioCategory.music);
      await repo.setFolderExcluded('/storage/temp', true);

      // 3. Export backup
      final backup = await backupService.exportBackupJson();

      // 4. Mutate/Delete state
      await repo.deletePlaylist(pl.id!);
      await repo.toggleFavorite(301, false);
      await repo.resetOverride(302);
      await repo.setFolderExcluded('/storage/temp', false);

      expect(await repo.getPlaylists(), isEmpty);
      expect(await repo.getFavorites(), isEmpty);
      expect((await repo.getExcludedFolders()).contains('/storage/temp'), isFalse);

      // 5. Restore backup
      final importResult = await backupService.importBackupJson(backup);
      expect(importResult.isSuccess, isTrue);
      expect(importResult.restoredPlaylistsCount, equals(1));
      expect(importResult.restoredFavoritesCount, equals(1));
      expect(importResult.restoredOverridesCount, equals(1));
      expect(importResult.restoredExcludedFoldersCount, equals(1));

      // 6. Verify full recovery
      final restoredPlaylists = await repo.getPlaylists();
      expect(restoredPlaylists.length, equals(1));
      expect(restoredPlaylists.first.name, equals('Roadtrip Mix'));

      final restoredTracks = await repo.getPlaylistTracks(restoredPlaylists.first.id!);
      expect(restoredTracks.length, equals(2));

      final restoredFavs = await repo.getFavorites();
      expect(restoredFavs.any((t) => t.id == 301), isTrue);

      final restoredExclusions = await repo.getExcludedFolders();
      expect(restoredExclusions.contains('/storage/temp'), isTrue);
    });

    test('Deliberately corrupted JSON rollbacks cleanly without leaving partial state', () async {
      final originalTrack = Track(id: 401, filePath: '/m/orig.mp3', fileName: 'orig.mp3', title: 'Orig', artist: 'A', isMusic: true, confidence: 0.95, isFavorite: false);
      await repo.batchUpsertTracks([originalTrack]);

      const corruptedJson = '{"version": 1, "playlists": "invalid_structure_not_a_list"}';
      final result = await backupService.importBackupJson(corruptedJson);

      expect(result.isSuccess, isFalse);
      final checkTrack = (await repo.getMusicOnlyTracks()).firstWhere((t) => t.id == 401);
      expect(checkTrack.isFavorite, isFalse);
    });
  });

  group('P6.4 — Recommendation → Playback End-to-End Safety', () {
    test('Defense-in-depth: AudioPlayerService loadPlaylist blocks any non-music even if injected into recommendation', () async {
      final voiceNote = Track(
        id: 501,
        filePath: '/WhatsApp/ptt.opus',
        fileName: 'ptt.opus',
        title: 'Voice Note Hack',
        artist: 'Hacker',
        audioCategory: AudioCategory.voiceNote,
        confidence: 0.9,
      );
      final validSong = Track(
        id: 502,
        filePath: '/m/song.mp3',
        fileName: 'song.mp3',
        title: 'Valid Song',
        artist: 'Artist',
        audioCategory: AudioCategory.music,
        confidence: 0.95,
      );

      // Attempt to load recommendations containing non-music
      playerService.currentPlaylist = [];
      await playerService.loadPlaylist([voiceNote, validSong], 0);

      expect(playerService.currentPlaylist.length, equals(1));
      expect(playerService.currentPlaylist.first.id, equals(502));
      expect(playerService.currentPlaylist.any((t) => t.id == 501), isFalse);

      // Attempt addToQueue with non-music
      final added = await playerService.addToQueue(voiceNote);
      expect(added, isFalse);
      expect(playerService.currentPlaylist.any((t) => t.id == 501), isFalse);

      // Attempt insertNext with non-music
      final inserted = await playerService.insertNext(voiceNote);
      expect(inserted, isFalse);
      expect(playerService.currentPlaylist.any((t) => t.id == 501), isFalse);
    });
  });

  group('P6.7 — Library Intelligence', () {
    test('Artist and Album intelligence correctly aggregated from SQLite records', () async {
      final t1 = Track(id: 601, filePath: '/m/a1.mp3', fileName: 'a1.mp3', title: 'T1', artist: 'Beatles', album: 'Abbey Road', playCount: 10, isFavorite: true, isMusic: true, confidence: 0.95, duration: 180000);
      final t2 = Track(id: 602, filePath: '/m/a2.mp3', fileName: 'a2.mp3', title: 'T2', artist: 'Beatles', album: 'Abbey Road', playCount: 5, isFavorite: false, isMusic: true, confidence: 0.95, duration: 200000);
      final t3 = Track(id: 603, filePath: '/m/a3.mp3', fileName: 'a3.mp3', title: 'T3', artist: 'Beatles', album: 'Let It Be', playCount: 2, isFavorite: true, isMusic: true, confidence: 0.95, duration: 220000);
      await repo.batchUpsertTracks([t1, t2, t3]);

      // Artist stats
      final artistStats = await intelligenceService.getArtistIntelligence('Beatles');
      expect(artistStats, isNotNull);
      expect(artistStats!.trackCount, equals(3));
      expect(artistStats.totalPlayCount, equals(17));
      expect(artistStats.favoriteCount, equals(2));
      expect(artistStats.topTracks.first.id, equals(601));

      // Album stats
      final albumStats = await intelligenceService.getAlbumIntelligence('Abbey Road');
      expect(albumStats, isNotNull);
      expect(albumStats!.trackCount, equals(2));
      expect(albumStats.totalDurationMs, equals(380000));
      expect(albumStats.totalPlayCount, equals(15));
      expect(albumStats.favoriteCount, equals(1));
    });
  });

  group('P6.8 — Advanced Composable Smart Playlists', () {
    test('Advanced smart filters enforce composable rules and strict Music-Only safety', () async {
      final freshHighConf = Track(id: 701, filePath: '/m/f1.mp3', fileName: 'f1.mp3', title: 'Fresh', artist: 'Band A', isMusic: true, confidence: 0.95, dateAdded: 1700005000);
      final longFav = Track(id: 702, filePath: '/m/f2.mp3', fileName: 'f2.mp3', title: 'Long Fav', artist: 'Band B', isMusic: true, confidence: 0.90, isFavorite: true, duration: 360000);
      final unplayedHighConf = Track(id: 703, filePath: '/m/f3.mp3', fileName: 'f3.mp3', title: 'Unplayed', artist: 'Band C', isMusic: true, confidence: 0.92, playCount: 0);
      final recNotFav = Track(id: 704, filePath: '/m/f4.mp3', fileName: 'f4.mp3', title: 'Recent Not Fav', artist: 'Band D', isMusic: true, confidence: 0.88, isFavorite: false, lastPlayed: DateTime.now());
      final voiceTrap = Track(id: 705, filePath: '/w/trap.opus', fileName: 'trap.opus', title: 'Trap', artist: 'Band A', audioCategory: AudioCategory.voiceNote, confidence: 0.99, duration: 400000, isFavorite: true);

      await repo.batchUpsertTracks([freshHighConf, longFav, unplayedHighConf, recNotFav, voiceTrap]);

      // High Confidence Recently Added
      final q1 = await intelligenceService.getAdvancedSmartPlaylist(AdvancedSmartRule.highConfidenceRecentlyAdded);
      expect(q1.any((t) => t.id == 701), isTrue);
      expect(q1.any((t) => t.id == 705), isFalse);

      // Long Favorites
      final q2 = await intelligenceService.getAdvancedSmartPlaylist(AdvancedSmartRule.longFavorites);
      expect(q2.length, equals(1));
      expect(q2.first.id, equals(702));
      expect(q2.any((t) => t.id == 705), isFalse);

      // Never Played High Confidence
      final q3 = await intelligenceService.getAdvancedSmartPlaylist(AdvancedSmartRule.neverPlayedHighConfidence);
      expect(q3.any((t) => t.id == 703), isTrue);

      // Recently Played Not Favorites
      final q4 = await intelligenceService.getAdvancedSmartPlaylist(AdvancedSmartRule.recentlyPlayedNotFavorites);
      expect(q4.any((t) => t.id == 704), isTrue);
    });
  });
}
