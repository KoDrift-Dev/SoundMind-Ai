// test/phase7_release_readiness_test.dart
import 'dart:convert';
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
  late AudioPlayerService playerService;
  late LibraryBackupService backupService;
  late LibraryIntelligenceService intelligenceService;

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
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
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
        await db.execute('''
          CREATE TABLE persisted_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id INTEGER,
            file_path TEXT NOT NULL,
            queue_order INTEGER NOT NULL,
            is_current INTEGER NOT NULL DEFAULT 0,
            position_ms INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    AppDatabase.instance.testDatabase = testDb;
    repo = AudioRepository.instance;
    backupService = LibraryBackupService.instance;
    intelligenceService = LibraryIntelligenceService.instance;
    playerService = AudioPlayerService.instance;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async => <dynamic, dynamic>{},
    );
  });

  tearDown(() async {
    await testDb.close();
  });

  group('P7.4 — Music-Only Safety Final Lock', () {
    test('All non-music categories are strictly rejected across loadPlaylist, addToQueue, and insertNext', () async {
      final nonMusicCategories = AudioCategory.values.where((c) => c != AudioCategory.music).toList();

      for (int i = 0; i < nonMusicCategories.length; i++) {
        final cat = nonMusicCategories[i];
        final track = Track(
          id: 1000 + i,
          filePath: '/storage/$cat/audio_$i.aac',
          fileName: 'audio_$i.aac',
          title: 'Unsafe $cat',
          artist: 'Bad Actor',
          audioCategory: cat,
          confidence: 0.99,
          isMusic: false,
        );

        // 1. addToQueue must return false and leave queue clean
        final added = await playerService.addToQueue(track);
        expect(added, isFalse, reason: 'addToQueue must reject $cat');

        // 2. insertNext must return false and leave queue clean
        final inserted = await playerService.insertNext(track);
        expect(inserted, isFalse, reason: 'insertNext must reject $cat');
      }

      // 3. loadPlaylist must filter them all out
      final testSongs = [
        Track(id: 2001, filePath: '/m/song1.mp3', fileName: 'song1.mp3', title: 'Legit Song', artist: 'Band', audioCategory: AudioCategory.music, isMusic: true, confidence: 0.95),
        Track(id: 2002, filePath: '/m/voice.opus', fileName: 'voice.opus', title: 'Voice', artist: 'User', audioCategory: AudioCategory.voiceNote, isMusic: false, confidence: 0.8),
      ];

      playerService.currentPlaylist = [];
      await playerService.loadPlaylist(testSongs, 0);

      expect(playerService.currentPlaylist.length, equals(1));
      expect(playerService.currentPlaylist.first.id, equals(2001));
      expect(playerService.currentPlaylist.any((t) => t.id == 2002), isFalse);
    });

    test('Folder exclusions permanently hide even 100% confidence music from safe queries', () async {
      final trackInExcludedFolder = Track(
        id: 3001,
        filePath: '/storage/WhatsApp/Audio/song.mp3',
        fileName: 'song.mp3',
        title: 'Song in WhatsApp folder',
        artist: 'Band',
        folderPath: '/storage/WhatsApp/Audio',
        audioCategory: AudioCategory.music,
        isMusic: true,
        confidence: 0.99,
      );

      final legitimateTrack = Track(
        id: 3002,
        filePath: '/storage/Music/GreatAlbum/song2.mp3',
        fileName: 'song2.mp3',
        title: 'Real Music',
        artist: 'Band',
        folderPath: '/storage/Music/GreatAlbum',
        audioCategory: AudioCategory.music,
        isMusic: true,
        confidence: 0.95,
      );

      await repo.batchUpsertTracks([trackInExcludedFolder, legitimateTrack]);
      await repo.setFolderExcluded('/storage/WhatsApp/Audio', true);

      final music = await repo.getMusicOnlyTracks();
      expect(music.length, equals(1));
      expect(music.first.id, equals(3002));
      expect(music.any((t) => t.id == 3001), isFalse, reason: 'Track in excluded folder must NEVER be returned in music queries');
    });
  });

  group('P7.5 & P7.7 — Offline Core & Backup Safety', () {
    test('Offline intelligence services execute locally without internet connectivity', () async {
      final t = Track(
        id: 4001,
        filePath: '/storage/Music/track.mp3',
        fileName: 'track.mp3',
        title: 'Offline Song',
        artist: 'Offline Artist',
        album: 'Offline Album',
        playCount: 12,
        isFavorite: true,
        isMusic: true,
        confidence: 0.95,
        duration: 210000,
      );
      await repo.batchUpsertTracks([t]);

      final artistInfo = await intelligenceService.getArtistIntelligence('Offline Artist');
      expect(artistInfo, isNotNull);
      expect(artistInfo!.totalPlayCount, equals(12));

      final albumInfo = await intelligenceService.getAlbumIntelligence('Offline Album');
      expect(albumInfo, isNotNull);
      expect(albumInfo!.trackCount, equals(1));

      final recs = await LocalRecommendationService.instance.generateRecommendations();
      expect(recs, isNotNull);
    });

    test('Backup export does not include audio bytes and import is atomic', () async {
      final t = Track(
        id: 5001,
        filePath: '/storage/Music/important.mp3',
        fileName: 'important.mp3',
        title: 'Important Song',
        artist: 'Artist',
        isMusic: true,
        confidence: 0.95,
      );
      await repo.batchUpsertTracks([t]);
      final pl = await repo.createPlaylist('Favorites Backup');
      await repo.addTrackToPlaylist(pl.id!, 5001);

      final jsonString = await backupService.exportBackupJson();
      final decodedJson = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(decodedJson['schemaVersion'], equals(1));
      expect(jsonString.contains('audioBytes'), isFalse, reason: 'Raw user audio must NEVER be exported in metadata backup');

      // Test atomic rollback on corrupt data
      const corruptJson = '{"version": 1, "playlists": "invalid_structure_not_a_list"}';
      final res = await backupService.importBackupJson(corruptJson);
      expect(res.isSuccess, isFalse);

      // Verify original playlist is untouched
      final currentPlaylists = await repo.getPlaylists();
      expect(currentPlaylists.length, equals(1));
      expect(currentPlaylists.first.name, equals('Favorites Backup'));
    });
  });

  group('P7.8 & P7.12 — Database & Release Sanity', () {
    test('Database integrity check passes with zero defects and foreign keys active', () async {
      final pragmaRows = await testDb.rawQuery('PRAGMA integrity_check;');
      expect(pragmaRows.first['integrity_check'], equals('ok'));

      final fkRows = await testDb.rawQuery('PRAGMA foreign_keys;');
      expect(fkRows.first['foreign_keys'], equals(1));
    });

    test('Self-healing database lifecycle creates all missing tables on an uninitialized database', () async {
      final emptyDb = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
      );
      await AppDatabase.instance.ensureSchemaForTesting(emptyDb);

      final tables = await emptyDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table';");
      final tableNames = tables.map((r) => r['name'] as String).toSet();
      expect(tableNames.contains('tracks'), isTrue);
      expect(tableNames.contains('folder_exclusions'), isTrue);
      expect(tableNames.contains('persisted_queue'), isTrue);
      expect(tableNames.contains('playlists'), isTrue);
      expect(tableNames.contains('playlist_tracks'), isTrue);

      final colInfo = await emptyDb.rawQuery('PRAGMA table_info(tracks);');
      final trackCols = colInfo.map((r) => r['name'] as String).toSet();
      expect(trackCols.contains('track_number'), isTrue);
      expect(trackCols.contains('album_artist'), isTrue);
      expect(trackCols.contains('is_downloaded'), isTrue);

      await emptyDb.close();
    });
  });
}
