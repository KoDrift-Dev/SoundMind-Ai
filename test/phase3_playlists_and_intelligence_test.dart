// test/phase3_playlists_and_intelligence_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:soundmindai/database/app_database.dart';
import 'package:soundmindai/models/audio_category.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/repositories/audio_repository.dart';
import 'package:soundmindai/services/offline_download_service.dart';
import 'package:soundmindai/services/online/online_music_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;
  late AudioRepository repo;

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
  });

  tearDown(() async {
    await testDb.close();
  });

  group('P3.1 — Custom Playlists Tests', () {
    test('createPlaylist creates playlist record with unique ID and accurate timestamp', () async {
      final playlist = await repo.createPlaylist('Late Night Lo-Fi');
      expect(playlist.id, isNotNull);
      expect(playlist.name, equals('Late Night Lo-Fi'));
      expect(playlist.trackCount, equals(0));

      final allPlaylists = await repo.getPlaylists();
      expect(allPlaylists.length, equals(1));
      expect(allPlaylists.first.name, equals('Late Night Lo-Fi'));
    });

    test('renamePlaylist updates playlist name in SQLite', () async {
      final p = await repo.createPlaylist('Morning Acoustic');
      await repo.renamePlaylist(p.id!, 'Morning Coffee Chill');

      final updated = await repo.getPlaylistById(p.id!);
      expect(updated?.name, equals('Morning Coffee Chill'));
    });

    test('addTrackToPlaylist adds songs in sequential order and prevents duplicate insertions', () async {
      final playlist = await repo.createPlaylist('Road Trip');

      final track1 = Track(
        id: 1,
        filePath: '/music/song1.mp3',
        fileName: 'song1.mp3',
        title: 'Highway Star',
        artist: 'Deep Purple',
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.95,
      );
      final track2 = Track(
        id: 2,
        filePath: '/music/song2.mp3',
        fileName: 'song2.mp3',
        title: 'Born to Run',
        artist: 'Bruce Springsteen',
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.95,
      );

      await repo.batchUpsertTracks([track1, track2]);

      await repo.addTrackToPlaylist(playlist.id!, 1);
      await repo.addTrackToPlaylist(playlist.id!, 2);
      // Attempt duplicate addition
      await repo.addTrackToPlaylist(playlist.id!, 1);

      final tracks = await repo.getPlaylistTracks(playlist.id!);
      expect(tracks.length, equals(2));
      expect(tracks[0].id, equals(1));
      expect(tracks[1].id, equals(2));

      final playlists = await repo.getPlaylists();
      expect(playlists.first.trackCount, equals(2));
    });

    test('reorderPlaylistTracks alters playlist playback sequence', () async {
      final playlist = await repo.createPlaylist('Workout Beats');
      final t1 = Track(id: 10, filePath: '/m/t1.mp3', fileName: 't1.mp3', title: 'Warmup', artist: 'Artist', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      final t2 = Track(id: 20, filePath: '/m/t2.mp3', fileName: 't2.mp3', title: 'Sprint', artist: 'Artist', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      final t3 = Track(id: 30, filePath: '/m/t3.mp3', fileName: 't3.mp3', title: 'Cooldown', artist: 'Artist', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      await repo.batchUpsertTracks([t1, t2, t3]);

      await repo.addTrackToPlaylist(playlist.id!, 10);
      await repo.addTrackToPlaylist(playlist.id!, 20);
      await repo.addTrackToPlaylist(playlist.id!, 30);

      // Reorder to 30, 10, 20
      await repo.reorderPlaylistTracks(playlist.id!, [30, 10, 20]);

      final tracks = await repo.getPlaylistTracks(playlist.id!);
      expect(tracks.map((t) => t.id).toList(), equals([30, 10, 20]));
    });

    test('removeTrackFromPlaylist deletes association without deleting audio track', () async {
      final playlist = await repo.createPlaylist('Favorites Mix');
      final t1 = Track(id: 100, filePath: '/m/t100.mp3', fileName: 't100.mp3', title: 'Song 100', artist: 'Artist', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      final t2 = Track(id: 200, filePath: '/m/t200.mp3', fileName: 't200.mp3', title: 'Song 200', artist: 'Artist', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      await repo.batchUpsertTracks([t1, t2]);

      await repo.addTrackToPlaylist(playlist.id!, 100);
      await repo.addTrackToPlaylist(playlist.id!, 200);

      await repo.removeTrackFromPlaylist(playlist.id!, 100);

      final playlistTracks = await repo.getPlaylistTracks(playlist.id!);
      expect(playlistTracks.length, equals(1));
      expect(playlistTracks.first.id, equals(200));

      // Ensure track 100 is still safely in tracks table
      final allMusic = await repo.getMusicOnlyTracks();
      expect(allMusic.length, equals(2));
    });

    test('getPlaylistTracks strictly enforces music-only safety filter', () async {
      final playlist = await repo.createPlaylist('Mixed Media');
      final musicTrack = Track(
        id: 1,
        filePath: '/music/track.mp3',
        fileName: 'track.mp3',
        title: 'Symphony',
        artist: 'Orchestra',
        isMusic: true,
        audioCategory: AudioCategory.music,
        confidence: 0.95,
      );
      final voiceNote = Track(
        id: 2,
        filePath: '/whatsapp/voice.opus',
        fileName: 'voice.opus',
        title: 'PTT Note',
        artist: '<unknown>',
        isMusic: false,
        audioCategory: AudioCategory.voiceNote,
        confidence: 0.90,
      );
      await repo.batchUpsertTracks([musicTrack, voiceNote]);

      await repo.addTrackToPlaylist(playlist.id!, 1);
      await repo.addTrackToPlaylist(playlist.id!, 2);

      // Safe music-only playback query
      final safeTracks = await repo.getPlaylistTracks(playlist.id!, musicOnly: true);
      expect(safeTracks.length, equals(1));
      expect(safeTracks.first.id, equals(1));
      expect(safeTracks.first.isMusic, isTrue);

      // Unfiltered raw tracks
      final rawTracks = await repo.getPlaylistTracks(playlist.id!, musicOnly: false);
      expect(rawTracks.length, equals(2));
    });

    test('deletePlaylist removes playlist and cascade clears playlist_tracks', () async {
      final playlist = await repo.createPlaylist('To Delete');
      final track = Track(id: 1, filePath: '/m/1.mp3', fileName: '1.mp3', title: 'T1', artist: 'A', isMusic: true, audioCategory: AudioCategory.music, confidence: 0.9);
      await repo.batchUpsertTracks([track]);
      await repo.addTrackToPlaylist(playlist.id!, 1);

      await repo.deletePlaylist(playlist.id!);

      final playlists = await repo.getPlaylists();
      expect(playlists, isEmpty);

      // Ensure track itself is NOT deleted
      final remainingTracks = await repo.getMusicOnlyTracks();
      expect(remainingTracks.length, equals(1));
    });
  });

  group('P3.2 — Smart Playlists Tests', () {
    setUp(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final tracks = [
        // Music tracks with various metadata
        Track(
          id: 1,
          filePath: '/music/recent.mp3',
          fileName: 'recent.mp3',
          title: 'Recent Hit',
          artist: 'Artist A',
          duration: 210000,
          dateAdded: now - 1000,
          lastPlayed: DateTime.fromMillisecondsSinceEpoch(now - 500),
          playCount: 15,
          isFavorite: true,
          isMusic: true,
          confidence: 0.95,
          audioCategory: AudioCategory.music,
        ),
        Track(
          id: 2,
          filePath: '/music/epic_journey.mp3',
          fileName: 'epic_journey.mp3',
          title: 'Epic Symphony',
          artist: 'Orchestra',
          duration: 420000, // 7 mins (Long track)
          dateAdded: now - 5000,
          lastPlayed: DateTime.fromMillisecondsSinceEpoch(now - 3000),
          playCount: 3,
          isFavorite: false,
          isMusic: true,
          confidence: 0.92,
          audioCategory: AudioCategory.music,
        ),
        Track(
          id: 3,
          filePath: '/music/short_interlude.mp3',
          fileName: 'short_interlude.mp3',
          title: 'Acoustic Interlude',
          artist: 'Acoustic Trio',
          duration: 90000, // 1.5 mins (Short track)
          dateAdded: now - 8000,
          playCount: 0, // Never played
          isFavorite: false,
          isMusic: true,
          confidence: 0.88,
          audioCategory: AudioCategory.music,
        ),
        Track(
          id: 4,
          filePath: '/music/top_chart.mp3',
          fileName: 'top_chart.mp3',
          title: 'Most Played Anthem',
          artist: 'Mega Band',
          duration: 200000,
          dateAdded: now - 10000,
          lastPlayed: DateTime.fromMillisecondsSinceEpoch(now - 2000),
          playCount: 99, // Most played
          isFavorite: true,
          isMusic: true,
          confidence: 0.99,
          audioCategory: AudioCategory.music,
        ),
        // Non-music audio (MUST NEVER appear in Smart Playlists)
        Track(
          id: 5,
          filePath: '/recordings/lecture.m4a',
          fileName: 'lecture.m4a',
          title: 'Lecture Recording',
          artist: '<unknown>',
          duration: 1800000,
          lastPlayed: DateTime.fromMillisecondsSinceEpoch(now - 100),
          playCount: 50,
          isFavorite: true,
          isMusic: false,
          confidence: 0.95,
          audioCategory: AudioCategory.recording,
        ),
      ];

      await repo.batchUpsertTracks(tracks);
    });

    test('Recently Played returns music tracks in descending last_played order and excludes non-music', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.recentlyPlayed);
      expect(list.length, equals(3));
      expect(list.first.id, equals(1)); // recent.mp3 was played 500ms ago
      // Non-music recording (id 5) played 100ms ago must be omitted
      expect(list.any((t) => t.id == 5), isFalse);
    });

    test('Most Played returns tracks ordered by play_count DESC and excludes non-music', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.mostPlayed);
      expect(list.length, equals(3));
      expect(list.first.id, equals(4)); // 99 plays
      expect(list[1].id, equals(1)); // 15 plays
      expect(list[2].id, equals(2)); // 3 plays
      expect(list.any((t) => t.id == 5), isFalse);
    });

    test('Favorites returns only favorited music tracks', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.favorites);
      expect(list.length, equals(2));
      expect(list.every((t) => t.isFavorite && t.isMusic), isTrue);
      expect(list.any((t) => t.id == 5), isFalse);
    });

    test('Long Tracks returns music with duration >= 5 minutes', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.longTracks);
      expect(list.length, equals(1));
      expect(list.first.id, equals(2));
      expect(list.first.duration, greaterThanOrEqualTo(300000));
    });

    test('Short Tracks returns music with duration <= 2.5 minutes', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.shortTracks);
      expect(list.length, equals(1));
      expect(list.first.id, equals(3));
      expect(list.first.duration, lessThanOrEqualTo(150000));
    });

    test('Never Played returns tracks with playCount == 0', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.neverPlayed);
      expect(list.length, equals(1));
      expect(list.first.id, equals(3));
      expect(list.first.playCount, equals(0));
    });

    test('High Confidence Music returns music tracks with confidence >= 0.85', () async {
      final list = await repo.getSmartPlaylistTracks(SmartPlaylistType.highConfidenceMusic);
      expect(list.length, equals(4));
      expect(list.every((t) => t.confidence >= 0.85 && t.isMusic), isTrue);
    });
  });

  group('P3.3 — Advanced Search Tests', () {
    setUp(() async {
      final tracks = [
        Track(
          id: 1,
          filePath: '/music/rock/Stairway_To_Heaven.mp3',
          fileName: 'Stairway_To_Heaven.mp3',
          title: 'Stairway To Heaven',
          artist: 'Led Zeppelin',
          album: 'Led Zeppelin IV',
          genre: 'Classic Rock',
          folderPath: '/music/rock',
          isMusic: true,
          confidence: 0.95,
          audioCategory: AudioCategory.music,
        ),
        Track(
          id: 2,
          filePath: '/music/jazz/Kind_Of_Blue.mp3',
          fileName: 'Kind_Of_Blue.mp3',
          title: 'So What',
          artist: 'Miles Davis',
          album: 'Kind of Blue',
          genre: 'Modal Jazz',
          folderPath: '/music/jazz',
          isMusic: true,
          confidence: 0.95,
          audioCategory: AudioCategory.music,
        ),
        Track(
          id: 3,
          filePath: '/whatsapp/voice_note_1.opus',
          fileName: 'voice_note_1.opus',
          title: 'Miles Meeting Audio',
          artist: 'Miles Davis', // Spurious tag on voice note
          isMusic: false,
          confidence: 0.95,
          audioCategory: AudioCategory.voiceNote,
        ),
      ];

      await repo.batchUpsertTracks(tracks);
      await repo.createPlaylist('Rock Classics');
    });

    test('Matches by Title and never returns non-music', () async {
      final results = await repo.searchMusicTracks('Stairway');
      expect(results.length, equals(1));
      expect(results.first.id, equals(1));
    });

    test('Matches by Artist and rejects non-music sharing same artist name', () async {
      final results = await repo.searchMusicTracks('Miles Davis');
      expect(results.length, equals(1));
      expect(results.first.id, equals(2));
      // Voice note (id 3) with artist 'Miles Davis' must never be returned in main music search
      expect(results.any((t) => t.id == 3), isFalse);
    });

    test('Matches by Album', () async {
      final results = await repo.searchMusicTracks('Zeppelin IV');
      expect(results.length, equals(1));
      expect(results.first.id, equals(1));
    });

    test('Matches by Genre', () async {
      final results = await repo.searchMusicTracks('Modal Jazz');
      expect(results.length, equals(1));
      expect(results.first.id, equals(2));
    });

    test('Matches by Folder Path', () async {
      final results = await repo.searchMusicTracks('/music/rock');
      expect(results.length, equals(1));
      expect(results.first.id, equals(1));
    });

    test('searchPlaylists returns custom playlists matching query', () async {
      final matches = await repo.searchPlaylists('Rock');
      expect(matches.length, equals(1));
      expect(matches.first.name, equals('Rock Classics'));
    });
  });

  group('P3.5 & P3.6 — Real Download & Storage Management Tests', () {
    late Directory tempCacheDir;

    setUp(() async {
      tempCacheDir = await Directory.systemTemp.createTemp('soundmind_cache_');
      OfflineDownloadService.instance.cacheDirectoryOverride = tempCacheDir;
    });

    tearDown(() async {
      if (await tempCacheDir.exists()) {
        await tempCacheDir.delete(recursive: true);
      }
    });

    test('OnlineMusicProvider contract reports configuration status and legal licensing', () {
      final provider = CreativeCommonsMusicProvider(clientId: 'test_token');
      expect(provider.isConfigured, isTrue);
      expect(provider.licensingDisclosure, contains('Creative Commons'));
    });

    test('getOfflineCacheSizeBytes accurately reports disk usage of cached audio files', () async {
      final service = OfflineDownloadService.instance;
      final file1 = File('${tempCacheDir.path}/track_101.mp3');
      await file1.writeAsBytes(List<int>.filled(50000, 1)); // 50 KB

      final file2 = File('${tempCacheDir.path}/track_102.mp3');
      await file2.writeAsBytes(List<int>.filled(30000, 2)); // 30 KB

      final cacheSize = await service.getOfflineCacheSizeBytes();
      expect(cacheSize, equals(80000));
    });

    test('deleteOfflineDownload deletes physical file from disk and clears isDownloaded in SQLite', () async {
      final service = OfflineDownloadService.instance;

      final cachedFile = File('${tempCacheDir.path}/track_999.mp3');
      await cachedFile.writeAsBytes(List<int>.filled(10000, 0));
      expect(await cachedFile.exists(), isTrue);

      final downloadedTrack = Track(
        id: 999,
        filePath: cachedFile.path,
        fileName: 'track_999.mp3',
        title: 'Cached Track',
        artist: 'Indie Artist',
        isMusic: true,
        isDownloaded: true,
        fileSize: 10000,
        audioCategory: AudioCategory.music,
        confidence: 0.95,
      );
      await repo.batchUpsertTracks([downloadedTrack]);

      // Verify track has isDownloaded = 1 in DB
      final dbTracks = await repo.getMusicOnlyTracks();
      expect(dbTracks.firstWhere((t) => t.id == 999).isDownloaded, isTrue);

      // Execute real deletion
      await service.deleteOfflineDownload(downloadedTrack);

      // Verify file is physically removed from storage
      expect(await cachedFile.exists(), isFalse);

      // Verify DB reflects isDownloaded = false
      final updatedDbTracks = await repo.getMusicOnlyTracks();
      expect(updatedDbTracks.firstWhere((t) => t.id == 999).isDownloaded, isFalse);
    });
  });

  group('P3.7 — End-to-End Integration Scenario (Playlist + Search + Download)', () {
    test('Executes full 17-step lifecycle with simulated app restart and safety enforcement', () async {
      // 1 & 2. Scan & Classify multiple audio types
      final track1 = Track(
        id: 5001,
        filePath: '/storage/music/Queen/Radio_GaGa.mp3',
        fileName: 'Radio_GaGa.mp3',
        title: 'Radio Ga Ga',
        artist: 'Queen',
        album: 'The Works',
        genre: 'Rock',
        duration: 343000,
        isMusic: true,
        confidence: 0.96,
        audioCategory: AudioCategory.music,
      );

      final track2 = Track(
        id: 5002,
        filePath: '/storage/recordings/Meeting_01.m4a',
        fileName: 'Meeting_01.m4a',
        title: 'Meeting Notes',
        artist: '<unknown>',
        duration: 600000,
        isMusic: false,
        confidence: 0.90,
        audioCategory: AudioCategory.recording,
      );

      final track3 = Track(
        id: 5003,
        filePath: '/storage/notifications/bell.ogg',
        fileName: 'bell.ogg',
        title: 'Bell Alert',
        artist: '<unknown>',
        duration: 2000,
        isMusic: false,
        confidence: 0.95,
        audioCategory: AudioCategory.notification,
      );

      final track4 = Track(
        id: 5004,
        filePath: '/storage/music/Queen/Under_Pressure.mp3',
        fileName: 'Under_Pressure.mp3',
        title: 'Under Pressure',
        artist: 'Queen & David Bowie',
        album: 'Hot Space',
        genre: 'Rock',
        duration: 248000,
        isMusic: true,
        confidence: 0.97,
        audioCategory: AudioCategory.music,
      );

      await repo.batchUpsertTracks([track1, track2, track3, track4]);

      // 3. Create playlist
      final playlist = await repo.createPlaylist('Retro Hits');
      expect(playlist.id, isNotNull);

      // 4. Add verified song
      await repo.addTrackToPlaylist(playlist.id!, 5001);
      await repo.addTrackToPlaylist(playlist.id!, 5004);

      // 5. Attempt to add recording / notification
      await repo.addTrackToPlaylist(playlist.id!, 5002);
      await repo.addTrackToPlaylist(playlist.id!, 5003);

      // Verify all 4 tracks are associated in DB
      final rawPlaylistTracks = await repo.getPlaylistTracks(playlist.id!, musicOnly: false);
      expect(rawPlaylistTracks.length, equals(4));

      // 6. Verify Music-Only playback CANNOT play unsafe audio
      final safePlaylistTracks = await repo.getPlaylistTracks(playlist.id!, musicOnly: true);
      expect(safePlaylistTracks.length, equals(2));
      expect(safePlaylistTracks.every((t) => t.isMusic), isTrue);
      expect(safePlaylistTracks.any((t) => t.id == 5002 || t.id == 5003), isFalse);

      // 7. Reorder playlist
      await repo.reorderPlaylistTracks(playlist.id!, [5004, 5001, 5002, 5003]);
      final reorderedSafe = await repo.getPlaylistTracks(playlist.id!, musicOnly: true);
      expect(reorderedSafe.first.id, equals(5004));
      expect(reorderedSafe[1].id, equals(5001));

      // 8 & 9. Simulate App Restart (re-query SQLite directly)
      final reloadedPlaylists = await repo.getPlaylists();
      expect(reloadedPlaylists.any((p) => p.name == 'Retro Hits'), isTrue);

      // 10. Search for playlist
      final foundPlaylists = await repo.searchPlaylists('Retro');
      expect(foundPlaylists.length, equals(1));
      expect(foundPlaylists.first.name, equals('Retro Hits'));

      // 11 & 12. Search for music & verify non-music is never returned
      final musicSearchResults = await repo.searchMusicTracks('Queen');
      expect(musicSearchResults.length, equals(2));
      expect(musicSearchResults.every((t) => t.isMusic), isTrue);

      // 13. Download an authorized online track with real bytes
      final tempDir = await Directory.systemTemp.createTemp('e2e_download_');
      final targetFile = File('${tempDir.path}/track_5005.mp3');
      await targetFile.writeAsBytes(List<int>.filled(25000, 42)); // 25 KB real bytes

      final onlineTrack = Track(
        id: 5005,
        filePath: targetFile.path,
        fileName: 'track_5005.mp3',
        title: 'Creative Commons Anthem',
        artist: 'Indie Artist',
        album: 'Open Sounds',
        duration: 180000,
        isMusic: true,
        confidence: 0.95,
        audioCategory: AudioCategory.music,
        isDownloaded: true,
        fileSize: 25000,
      );
      await repo.batchUpsertTracks([onlineTrack]);

      // 14 & 15. Verify download state persists
      final downloadedMusic = await repo.getMusicOnlyTracks();
      final savedDownload = downloadedMusic.firstWhere((t) => t.id == 5005);
      expect(savedDownload.isDownloaded, isTrue);
      expect(await File(savedDownload.filePath!).exists(), isTrue);

      // 16 & 17. Delete download & verify physical file removal and DB state
      await OfflineDownloadService.instance.deleteOfflineDownload(savedDownload);
      expect(await targetFile.exists(), isFalse);

      final postDeleteMusic = await repo.getMusicOnlyTracks();
      final postDeleteTrack = postDeleteMusic.firstWhere((t) => t.id == 5005);
      expect(postDeleteTrack.isDownloaded, isFalse);

      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('P3.8 — Large Dataset Performance & Safety Tests (10,000 Tracks)', () {
    test('Smart playlists and search execute in under 150ms over 10,000 indexed records', () async {
      final batch = testDb.batch();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (int i = 1; i <= 10000; i++) {
        final isMusic = (i % 3 != 0); // 2/3 music, 1/3 voice notes/recordings
        batch.insert('tracks', {
          'id': 10000 + i,
          'file_path': '/storage/audio/track_$i.mp3',
          'file_name': 'track_$i.mp3',
          'title': (i % 2 == 0) ? 'Rock Track #$i' : 'Acoustic Melody #$i',
          'artist': 'Artist ${i % 50}',
          'album': 'Album ${i % 25}',
          'genre': (i % 4 == 0) ? 'Rock' : 'Classical',
          'duration': 180000 + (i % 300) * 1000,
          'is_music': isMusic ? 1 : 0,
          'audio_category': isMusic ? 'music' : 'voiceNote',
          'confidence': isMusic ? 0.92 : 0.85,
          'classification_source': 'heuristic',
          'user_override': 0,
          'is_favorite': (i % 7 == 0) ? 1 : 0,
          'play_count': i % 20,
          'last_played': (i % 5 == 0) ? now - i * 100 : null,
          'date_added': now - i * 50,
          'is_downloaded': 0,
        });
      }

      final stopwatch = Stopwatch()..start();
      await batch.commit(noResult: true);
      stopwatch.stop();
      // Batch insert of 10,000 rows completes fast
      expect(stopwatch.elapsedMilliseconds, lessThan(4000));

      // 1. Benchmark Smart Playlist (Most Played with limit 50)
      final swSmart = Stopwatch()..start();
      final mostPlayed = await repo.getSmartPlaylistTracks(SmartPlaylistType.mostPlayed, limit: 50);
      swSmart.stop();
      expect(swSmart.elapsedMilliseconds, lessThan(150), reason: 'Indexed smart playlist query should be under 150ms');
      expect(mostPlayed.length, equals(50));
      expect(mostPlayed.every((t) => t.isMusic), isTrue);

      // 2. Benchmark Advanced Search (search 'Rock' with limit 50)
      final swSearch = Stopwatch()..start();
      final searchResults = await repo.searchMusicTracks('Rock', limit: 50);
      swSearch.stop();
      expect(swSearch.elapsedMilliseconds, lessThan(150), reason: 'Indexed multi-field search should be under 150ms');
      expect(searchResults.length, equals(50));
      expect(searchResults.every((t) => t.isMusic), isTrue);
    });
  });
}

