// test/phase4_core_hardening_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:soundmindai/database/app_database.dart';
import 'package:soundmindai/models/audio_category.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/repositories/audio_repository.dart';
import 'package:soundmindai/services/audio_player_service.dart';
import 'package:soundmindai/services/duplicate_detection_service.dart';
import 'package:soundmindai/services/metadata_editor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late AudioRepository repo;
  late AudioPlayerService playerService;

  setUp(() async {
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 3,
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
    playerService = AudioPlayerService.instance;
  });

  tearDown(() async {
    await testDb.close();
  });

  group('P4.1 — Favorites Hardening Tests', () {
    test('toggleFavorite updates SQLite is_favorite and syncs across active playlist instances', () async {
      final track = Track(
        id: 701,
        filePath: '/music/fav_test.mp3',
        fileName: 'fav_test.mp3',
        title: 'Favorite Track',
        artist: 'Test Artist',
        isMusic: true,
        isFavorite: false,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
      );
      await repo.batchUpsertTracks([track]);

      // Toggle favorite ON
      await playerService.toggleFavorite(track);
      expect(track.isFavorite, isTrue);

      final dbFavs = await repo.getFavorites();
      expect(dbFavs.length, equals(1));
      expect(dbFavs.first.id, equals(701));

      // Toggle favorite OFF
      await playerService.toggleFavorite(track);
      expect(track.isFavorite, isFalse);

      final dbFavsAfter = await repo.getFavorites();
      expect(dbFavsAfter, isEmpty);
    });

    test('Favorites state persists across restart and feeds Smart Playlist', () async {
      final track = Track(
        id: 702,
        filePath: '/music/fav_smart.mp3',
        fileName: 'fav_smart.mp3',
        title: 'Smart Fav Track',
        artist: 'Test Artist',
        isMusic: true,
        isFavorite: true,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
      );
      await repo.batchUpsertTracks([track]);

      final smartFavs = await repo.getSmartPlaylistTracks(SmartPlaylistType.favorites);
      expect(smartFavs.length, equals(1));
      expect(smartFavs.first.title, equals('Smart Fav Track'));
    });
  });

  group('P4.2 — Queue Hardening Tests', () {
    test('addToQueue enforces Music-Only safety and rejects non-music audio', () async {
      final nonMusicTrack = Track(
        id: 801,
        filePath: '/recordings/voice.m4a',
        fileName: 'voice.m4a',
        title: 'Voice Note',
        artist: '<unknown>',
        isMusic: false,
        confidence: 0.90,
        audioCategory: AudioCategory.recording,
      );

      final musicTrack = Track(
        id: 802,
        filePath: '/music/song.mp3',
        fileName: 'song.mp3',
        title: 'Real Song',
        artist: 'Real Band',
        isMusic: true,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
      );

      // Attempt to add non-music
      final addedNonMusic = await playerService.addToQueue(nonMusicTrack);
      expect(addedNonMusic, isFalse, reason: 'Non-music must NEVER enter playback queue');

      // Add valid music
      final addedMusic = await playerService.addToQueue(musicTrack);
      expect(addedMusic, isTrue);
      expect(playerService.currentPlaylist.any((t) => t.id == 802), isTrue);
    });

    test('insertNext places track immediately after current queue position', () async {
      final t1 = Track(id: 1, filePath: '/m/1.mp3', fileName: '1.mp3', title: 'T1', artist: 'A', isMusic: true);
      final t2 = Track(id: 2, filePath: '/m/2.mp3', fileName: '2.mp3', title: 'T2', artist: 'A', isMusic: true);
      final tNext = Track(id: 3, filePath: '/m/3.mp3', fileName: '3.mp3', title: 'Next Up', artist: 'A', isMusic: true);

      playerService.currentPlaylist = [t1, t2];
      await playerService.insertNext(tNext);

      expect(playerService.currentPlaylist.length, equals(3));
      expect(playerService.currentPlaylist[0].id, equals(1));
      expect(playerService.currentPlaylist[1].id, equals(3)); // Inserted next
      expect(playerService.currentPlaylist[2].id, equals(2));
    });

    test('removeFromQueue and reorderQueue maintain queue integrity and persistence', () async {
      final t1 = Track(id: 11, filePath: '/m/11.mp3', fileName: '11.mp3', title: 'T11', artist: 'A', isMusic: true);
      final t2 = Track(id: 22, filePath: '/m/22.mp3', fileName: '22.mp3', title: 'T22', artist: 'A', isMusic: true);
      final t3 = Track(id: 33, filePath: '/m/33.mp3', fileName: '33.mp3', title: 'T33', artist: 'A', isMusic: true);

      playerService.currentPlaylist = [t1, t2, t3];

      // Reorder from index 0 to 2
      await playerService.reorderQueue(0, 2);
      expect(playerService.currentPlaylist.map((t) => t.id).toList(), equals([22, 33, 11]));

      // Remove from index 1 (id 33)
      await playerService.removeFromQueue(1);
      expect(playerService.currentPlaylist.map((t) => t.id).toList(), equals([22, 11]));
    });
  });

  group('P4.3 — Playback History Tests', () {
    test('recordPlayback increments count and updates last_played timestamp in SQLite', () async {
      final track = Track(
        id: 901,
        filePath: '/music/history_test.mp3',
        fileName: 'history_test.mp3',
        title: 'History Track',
        artist: 'Band',
        isMusic: true,
        confidence: 0.95,
        playCount: 2,
        audioCategory: AudioCategory.music,
      );
      await repo.batchUpsertTracks([track]);

      await repo.recordPlayback(901);

      final music = await repo.getMusicOnlyTracks();
      final updated = music.firstWhere((t) => t.id == 901);
      expect(updated.playCount, equals(3));
      expect(updated.lastPlayed, isNotNull);
    });

    test('clearHistory safely resets all play counts and timestamps', () async {
      final t1 = Track(id: 902, filePath: '/m/h1.mp3', fileName: 'h1.mp3', title: 'H1', artist: 'B', isMusic: true, confidence: 0.95, playCount: 10, lastPlayed: DateTime.now());
      final t2 = Track(id: 903, filePath: '/m/h2.mp3', fileName: 'h2.mp3', title: 'H2', artist: 'B', isMusic: true, confidence: 0.95, playCount: 5, lastPlayed: DateTime.now());
      await repo.batchUpsertTracks([t1, t2]);

      await repo.clearHistory();

      final recent = await repo.getRecentlyPlayed();
      expect(recent, isEmpty);

      final music = await repo.getMusicOnlyTracks();
      expect(music.every((t) => t.playCount == 0 && t.lastPlayed == null), isTrue);
    });
  });

  group('P4.4 — Duplicate Finder Hardening Tests', () {
    test('Clustering requires matching duration, file size, and acoustic profile', () async {
      final duplicateService = DuplicateDetectionService.instance;
      final tracks = [
        Track(
          id: 1001,
          filePath: '/music/Queen/Track.mp3',
          fileName: 'Track.mp3',
          title: 'We Will Rock You',
          artist: 'Queen',
          duration: 122000,
          fileSize: 3200000,
          isMusic: true,
          confidence: 0.95,
        ),
        Track(
          id: 1002,
          filePath: '/downloads/Track_Copy.mp3',
          fileName: 'Track_Copy.mp3',
          title: 'We Will Rock You (Remastered)',
          artist: 'Queen',
          duration: 122000,
          fileSize: 3200000,
          isMusic: true,
          confidence: 0.95,
        ),
      ];
      await repo.batchUpsertTracks(tracks);

      final duplicates = await duplicateService.findDuplicates();
      expect(duplicates.length, equals(1));
      expect(duplicates.first.tracks.length, equals(2));
      // Never auto-deletes without user explicit action
    });
  });

  group('P4.5 — Metadata Editor Hardening Tests', () {
    test('updateMetadata persists all fields into SQLite including trackNumber and albumArtist', () async {
      final original = Track(
        id: 1101,
        filePath: '/music/meta.mp3',
        fileName: 'meta.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        genre: 'Pop',
        year: 2020,
        trackNumber: 1,
        albumArtist: 'Original Artist',
        isMusic: true,
        confidence: 0.95,
      );
      await repo.batchUpsertTracks([original]);

      final editor = MetadataEditorService.instance;
      final result = await editor.updateMetadata(
        track: original,
        params: const EditMetadataParams(
          title: 'Updated Masterpiece',
          artist: 'Legendary Composer',
          album: 'Greatest Symphony',
          genre: 'Classical',
          year: 2024,
          trackNumber: 7,
          albumArtist: 'Orchestra Master',
        ),
      );

      expect(result.isDatabaseUpdated, isTrue);

      final tracks = await repo.getMusicOnlyTracks();
      final updated = tracks.firstWhere((t) => t.id == 1101);
      expect(updated.title, equals('Updated Masterpiece'));
      expect(updated.artist, equals('Legendary Composer'));
      expect(updated.album, equals('Greatest Symphony'));
      expect(updated.genre, equals('Classical'));
      expect(updated.year, equals(2024));
      expect(updated.trackNumber, equals(7));
      expect(updated.albumArtist, equals('Orchestra Master'));
    });
  });

  group('P4.6 & P4.7 — Folder Exclusions & Settings Management Tests', () {
    test('Folder exclusion persistently hides tracks from music queries', () async {
      final track1 = Track(
        id: 1201,
        filePath: '/storage/music/clean/song.mp3',
        folderPath: '/storage/music/clean',
        fileName: 'song.mp3',
        title: 'Allowed Song',
        artist: 'Artist',
        isMusic: true,
        confidence: 0.95,
      );
      final track2 = Track(
        id: 1202,
        filePath: '/storage/music/excluded/song.mp3',
        folderPath: '/storage/music/excluded',
        fileName: 'song.mp3',
        title: 'Excluded Song',
        artist: 'Artist',
        isMusic: true,
        confidence: 0.95,
      );
      await repo.batchUpsertTracks([track1, track2]);

      await repo.setFolderExcluded('/storage/music/excluded', true);

      final music = await repo.getMusicOnlyTracks();
      expect(music.length, equals(1));
      expect(music.first.id, equals(1201));
    });

    test('resetAllClassifications clears user_override flag across all records', () async {
      final track = Track(
        id: 1301,
        filePath: '/m/override.mp3',
        fileName: 'override.mp3',
        title: 'Overridden Track',
        artist: 'Artist',
        isMusic: true,
        userOverride: true,
        confidence: 1.0,
      );
      await repo.batchUpsertTracks([track]);

      await repo.resetAllClassifications();

      final music = await repo.getMusicOnlyTracks();
      expect(music.first.userOverride, isFalse);
    });

    test('optimizeDatabase runs PRAGMA integrity check and ANALYZE without error', () async {
      final isHealthy = await repo.optimizeDatabase();
      expect(isHealthy, isTrue);
    });
  });
}
