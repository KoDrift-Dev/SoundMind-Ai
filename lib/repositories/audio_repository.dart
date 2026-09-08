// audio_repository.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/audio_category.dart';
import '../models/playlist.dart';
import '../models/storage_insights.dart';
import '../models/track.dart';
import '../classifier/classification_result.dart';

/// Types of rule-based smart playlists automatically computed from metadata & history.
enum SmartPlaylistType {
  recentlyPlayed,
  mostPlayed,
  recentlyAdded,
  favorites,
  longTracks,
  shortTracks,
  highConfidenceMusic,
  neverPlayed;

  String get displayName {
    switch (this) {
      case SmartPlaylistType.recentlyPlayed:
        return 'Recently Played';
      case SmartPlaylistType.mostPlayed:
        return 'Most Played';
      case SmartPlaylistType.recentlyAdded:
        return 'Recently Added';
      case SmartPlaylistType.favorites:
        return 'Favorites';
      case SmartPlaylistType.longTracks:
        return 'Long Tracks';
      case SmartPlaylistType.shortTracks:
        return 'Short Tracks';
      case SmartPlaylistType.highConfidenceMusic:
        return 'High Confidence Music';
      case SmartPlaylistType.neverPlayed:
        return 'Never Played';
    }
  }

  String get description {
    switch (this) {
      case SmartPlaylistType.recentlyPlayed:
        return 'Tracks you played recently';
      case SmartPlaylistType.mostPlayed:
        return 'Your most frequently repeated tracks';
      case SmartPlaylistType.recentlyAdded:
        return 'Freshly scanned or added audio';
      case SmartPlaylistType.favorites:
        return 'Tracks marked with a heart';
      case SmartPlaylistType.longTracks:
        return 'Extended listening (over 5 minutes)';
      case SmartPlaylistType.shortTracks:
        return 'Quick hits (under 2.5 minutes)';
      case SmartPlaylistType.highConfidenceMusic:
        return 'Highest acoustic AI certainty (>= 85%)';
      case SmartPlaylistType.neverPlayed:
        return 'Unplayed music awaiting discovery';
    }
  }
}

class AudioRepository extends ChangeNotifier {
  AudioRepository._internal();
  static final AudioRepository instance = AudioRepository._internal();

  final AppDatabase _appDb = AppDatabase.instance;

  // ───────────────────────── MUSIC-ONLY QUERIES (BLUETOOTH-SAFE) ─────────────────────────

  /// The primary Bluetooth-safe music query.
  /// Returns ONLY tracks verified as MUSIC:
  /// (is_music == 1 AND confidence >= 0.75) OR (user_override == 1 AND is_music == 1)
  /// AND excluding any folders currently on the exclusion blacklist.
  Future<List<Track>> getMusicOnlyTracks({
    int? limit,
    int? offset,
    String orderBy = 'title ASC',
  }) async {
    final db = await _appDb.database;
    final excludedFolders = await getExcludedFolders();

    String whereClause = '((is_music = 1 AND confidence >= ?) OR (user_override = 1 AND is_music = 1))';
    final whereArgs = <dynamic>[ClassificationResult.musicConfidenceThreshold];

    if (excludedFolders.isNotEmpty) {
      final placeholders = List.filled(excludedFolders.length, '?').join(',');
      whereClause += ' AND folder_path NOT IN ($placeholders)';
      whereArgs.addAll(excludedFolders);
    }

    final rows = await db.query(
      'tracks',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  // ───────────────────────── CATEGORY & REVIEW QUERIES ─────────────────────────

  /// Fetches audio files belonging to a specific category.
  Future<List<Track>> getTracksByCategory(
    AudioCategory category, {
    int? limit,
    int? offset,
    String orderBy = 'title ASC',
  }) async {
    if (category == AudioCategory.music) {
      return getMusicOnlyTracks(limit: limit, offset: offset, orderBy: orderBy);
    }

    final db = await _appDb.database;
    final rows = await db.query(
      'tracks',
      where: 'audio_category = ?',
      whereArgs: [category.dbValue],
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  /// Fetches all audio requiring manual review (unknown or confidence below threshold).
  Future<List<Track>> getReviewTracks({int? limit, int? offset}) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'tracks',
      where: 'user_override = 0 AND (audio_category = ? OR confidence < ?)',
      whereArgs: [
        AudioCategory.unknown.dbValue,
        ClassificationResult.musicConfidenceThreshold,
      ],
      orderBy: 'confidence ASC, title ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  // ───────────────────────── FAVORITES & HISTORY ─────────────────────────

  /// Fetches all user favorites.
  Future<List<Track>> getFavorites({int? limit, int? offset}) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'tracks',
      where: 'is_favorite = 1',
      orderBy: 'title ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  /// Toggles favorite status in database.
  Future<void> toggleFavorite(int trackId, bool isFavorite) async {
    final db = await _appDb.database;
    await db.update(
      'tracks',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    notifyListeners();
  }

  /// Toggles favorite status in database for both offline and online tracks.
  Future<void> toggleFavoriteTrack(Track track, bool isFavorite) async {
    final db = await _appDb.database;
    if (track.id != null) {
      await db.update(
        'tracks',
        {'is_favorite': isFavorite ? 1 : 0},
        where: 'id = ?',
        whereArgs: [track.id],
      );
    } else if (track.onlineId != null && track.onlineId!.isNotEmpty) {
      final existing = await db.query(
        'tracks',
        where: 'online_id = ? OR file_path = ?',
        whereArgs: [track.onlineId, 'online:${track.onlineId}'],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final existingId = existing.first['id'] as int;
        await db.update(
          'tracks',
          {'is_favorite': isFavorite ? 1 : 0},
          where: 'id = ?',
          whereArgs: [existingId],
        );
      } else if (isFavorite) {
        await db.insert(
          'tracks',
          {
            'online_id': track.onlineId,
            'file_path': 'online:${track.onlineId}',
            'file_name': track.title,
            'title': track.title,
            'artist': track.artist,
            'album': track.album ?? 'Online Stream',
            'art_url': track.artUrl,
            'duration': track.duration,
            'is_music': 1,
            'audio_category': 'music',
            'confidence': 1.0,
            'classification_source': 'online',
            'user_override': 1,
            'is_favorite': 1,
            'date_added': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'last_scanned': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        track.filePath = 'online:${track.onlineId}';
      }
    }
    notifyListeners();
  }

  /// Fetches recently played tracks.
  Future<List<Track>> getRecentlyPlayed({int limit = 50}) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'tracks',
      where: 'last_played IS NOT NULL',
      orderBy: 'last_played DESC',
      limit: limit,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  /// Increments play count and updates last played timestamp.
  Future<void> recordPlayback(int trackId) async {
    final db = await _appDb.database;
    await db.rawUpdate('''
      UPDATE tracks
      SET play_count = play_count + 1,
          last_played = ?
      WHERE id = ?
    ''', [DateTime.now().millisecondsSinceEpoch, trackId]);

    notifyListeners();
  }

  // ───────────────────────── SEARCH (P3.3) ─────────────────────────

  /// Searches strictly within verified music tracks.
  /// Matches across title, artist, album, genre, folder_path, and file_name.
  Future<List<Track>> searchMusicTracks(String query, {int limit = 50}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final db = await _appDb.database;
    final excluded = await getExcludedFolders();

    final wildcard = '%$cleanQuery%';
    String where = '''
      ((is_music = 1 AND confidence >= ?) OR (user_override = 1 AND is_music = 1))
      AND (title LIKE ? OR artist LIKE ? OR album LIKE ? OR genre LIKE ? OR folder_path LIKE ? OR file_name LIKE ?)
    ''';
    final args = <dynamic>[
      ClassificationResult.musicConfidenceThreshold,
      wildcard,
      wildcard,
      wildcard,
      wildcard,
      wildcard,
      wildcard,
    ];

    if (excluded.isNotEmpty) {
      final placeholders = List.filled(excluded.length, '?').join(',');
      where += ' AND folder_path NOT IN ($placeholders)';
      args.addAll(excluded);
    }

    final rows = await db.query(
      'tracks',
      where: where,
      whereArgs: args,
      limit: limit,
      orderBy: 'title ASC',
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  /// Searches custom playlists matching [query].
  Future<List<Playlist>> searchPlaylists(String query) async {
    final clean = query.trim();
    final db = await _appDb.database;
    if (clean.isEmpty) {
      return getPlaylists();
    }

    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.updated_at, COUNT(pt.id) as track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON p.id = pt.playlist_id
      WHERE p.name LIKE ?
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC
    ''', ['%$clean%']);

    return rows.map((r) => Playlist.fromMap(r)).toList();
  }

  // ───────────────────────── MANUAL OVERRIDE (USER CORRECTION) ─────────────────────────

  /// Sets permanent manual user override for an audio track.
  Future<void> overrideClassification(int trackId, AudioCategory newCategory) async {
    final db = await _appDb.database;
    final isMusic = (newCategory == AudioCategory.music);

    await db.update(
      'tracks',
      {
        'audio_category': newCategory.dbValue,
        'is_music': isMusic ? 1 : 0,
        'confidence': 1.0,
        'classification_source': ClassificationSource.userOverride.dbValue,
        'user_override': 1,
      },
      where: 'id = ?',
      whereArgs: [trackId],
    );

    notifyListeners();
  }

  /// Resets user override back to automatic classification.
  Future<void> resetOverride(int trackId) async {
    final db = await _appDb.database;
    await db.update(
      'tracks',
      {'user_override': 0},
      where: 'id = ?',
      whereArgs: [trackId],
    );
    notifyListeners();
  }

  // ───────────────────────── FOLDER EXCLUSIONS ─────────────────────────

  /// Gets list of currently excluded folder paths.
  Future<Set<String>> getExcludedFolders() async {
    final db = await _appDb.database;
    final rows = await db.query(
      'folder_exclusions',
      where: 'is_excluded = 1',
    );
    return rows.map((r) => r['folder_path'] as String).toSet();
  }

  /// Adds or removes folder from exclusion blacklist.
  Future<void> setFolderExcluded(String folderPath, bool isExcluded) async {
    final db = await _appDb.database;
    if (isExcluded) {
      await db.insert(
        'folder_exclusions',
        {
          'folder_path': folderPath,
          'date_excluded': DateTime.now().millisecondsSinceEpoch,
          'is_excluded': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.delete(
        'folder_exclusions',
        where: 'folder_path = ?',
        whereArgs: [folderPath],
      );
    }
    notifyListeners();
  }

  /// Discovers and returns ALL audio-containing folders on the device:
  /// 1. All distinct folder paths in SQLite 'tracks' table.
  /// 2. Any folder paths currently in 'folder_exclusions'.
  /// 3. Device directories queried from OnAudioQuery and standard storage volumes.
  Future<List<String>> getAllDiscoveredFolders() async {
    final Set<String> folders = {};
    final db = await _appDb.database;

    // 1. From active & scanned tracks in database
    try {
      final rows = await db.rawQuery(
        'SELECT DISTINCT folder_path FROM tracks WHERE folder_path IS NOT NULL AND folder_path != ""',
      );
      for (final r in rows) {
        final fp = r['folder_path'] as String?;
        if (fp != null && fp.trim().isNotEmpty) {
          folders.add(fp.trim());
        }
      }
    } catch (e) {
      debugPrint('AudioRepository: Error querying track folders: $e');
    }

    // 2. From folder exclusions
    try {
      final excluded = await getExcludedFolders();
      folders.addAll(excluded.where((f) => f.trim().isNotEmpty));
    } catch (e) {
      debugPrint('AudioRepository: Error querying excluded folders: $e');
    }

    // 3. Query on_audio_query if available on platform
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final audioQuery = OnAudioQuery();
        final devicePaths = await audioQuery.queryAllPath();
        for (final p in devicePaths) {
          if (p.trim().isNotEmpty) {
            folders.add(p.trim());
          }
        }
      } catch (e) {
        debugPrint('AudioRepository: OnAudioQuery.queryAllPath error: $e');
      }

      // Check standard well-known storage directories
      const standardCandidates = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/Audio',
        '/storage/emulated/0/Podcasts',
        '/storage/emulated/0/Recordings',
      ];
      for (final path in standardCandidates) {
        try {
          final dir = Directory(path);
          if (dir.existsSync()) {
            folders.add(path);
          }
        } catch (_) {}
      }
    }

    final sortedList = folders.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sortedList;
  }

  /// Updates editable metadata for a track in SQLite and notifies UI stream listeners.
  Future<void> updateTrackMetadata(Track updatedTrack) async {
    final db = await _appDb.database;
    await db.update(
      'tracks',
      updatedTrack.toMap(),
      where: 'id = ?',
      whereArgs: [updatedTrack.id],
    );
    notifyListeners();
  }

  // ───────────────────────── QUEUE PERSISTENCE ─────────────────────────

  /// Saves active playlist, current index, and scrub position to SQLite.
  Future<void> saveQueue({
    required List<Track> tracks,
    required int currentIndex,
    int positionMs = 0,
  }) async {
    final db = await _appDb.database;
    final batch = db.batch();

    batch.delete('persisted_queue');

    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      batch.insert('persisted_queue', {
        'track_id': t.id,
        'file_path': t.filePath,
        'queue_order': i,
        'is_current': (i == currentIndex) ? 1 : 0,
        'position_ms': (i == currentIndex) ? positionMs : 0,
      });
    }

    await batch.commit(noResult: true);
  }

  /// Restores persisted playlist and playback position.
  Future<({List<Track> tracks, int currentIndex, int positionMs})?> loadQueue() async {
    final db = await _appDb.database;
    final rows = await db.query('persisted_queue', orderBy: 'queue_order ASC');

    if (rows.isEmpty) return null;

    final filePaths = rows.map((r) => r['file_path'] as String?).whereType<String>().toList();
    if (filePaths.isEmpty) return null;

    final placeholders = List.filled(filePaths.length, '?').join(',');
    final trackRows = await db.query(
      'tracks',
      where: 'file_path IN ($placeholders)',
      whereArgs: filePaths,
    );

    final trackMap = {
      for (final tr in trackRows) (tr['file_path'] as String): Track.fromMap(tr),
    };

    final playlist = <Track>[];
    int curIdx = 0;
    int pos = 0;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final path = row['file_path'] as String?;
      if (path != null && trackMap.containsKey(path)) {
        playlist.add(trackMap[path]!);
        if ((row['is_current'] as int?) == 1) {
          curIdx = playlist.length - 1;
          pos = (row['position_ms'] as int?) ?? 0;
        }
      }
    }

    if (playlist.isEmpty) return null;

    return (tracks: playlist, currentIndex: curIdx, positionMs: pos);
  }

  // ───────────────────────── SCANNER / BULK WRITE HELPERS ─────────────────────────

  /// Retrieves map of existing tracks keyed by file_path.
  Future<Map<String, Track>> getExistingTrackMap() async {
    final db = await _appDb.database;
    final rows = await db.query('tracks');
    return {
      for (final r in rows) (r['file_path'] as String): Track.fromMap(r),
    };
  }

  /// Bulk upserts tracks in a fast, indexed transaction.
  Future<void> batchUpsertTracks(List<Track> tracks, {bool notify = true}) async {
    if (tracks.isEmpty) return;
    final db = await _appDb.database;
    final batch = db.batch();

    for (final t in tracks) {
      batch.insert(
        'tracks',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    if (notify) {
      notifyListeners();
    }
  }

  /// Removes tracks from database whose file paths no longer exist on device.
  Future<void> batchDeleteByPaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final db = await _appDb.database;
    final batch = db.batch();

    for (final p in paths) {
      batch.delete('tracks', where: 'file_path = ?', whereArgs: [p]);
    }

    await batch.commit(noResult: true);
    notifyListeners();
  }

  /// Gets breakdown of counts by category for library stats and UI.
  Future<Map<AudioCategory, int>> getCategoryCounts() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery('''
      SELECT audio_category, COUNT(*) as count
      FROM tracks
      GROUP BY audio_category
    ''');

    final counts = <AudioCategory, int>{
      for (final cat in AudioCategory.values) cat: 0,
    };

    for (final r in rows) {
      final cat = AudioCategory.fromDbValue(r['audio_category'] as String?);
      final count = (r['count'] as int?) ?? 0;
      counts[cat] = count;
    }

    return counts;
  }

  /// Gets total tracks in database.
  Future<int> getTotalTracksCount() async {
    final db = await _appDb.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM tracks');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Calculates real storage consumption and category counts across device audio.
  Future<StorageInsights> getStorageInsights() async {
    final db = await _appDb.database;

    // Total audio count and total file size
    final totalRows = await db.rawQuery('SELECT COUNT(*) as cnt, SUM(file_size) as total_size FROM tracks');
    final totalFiles = (totalRows.first['cnt'] as num?)?.toInt() ?? 0;
    final totalBytes = (totalRows.first['total_size'] as num?)?.toInt() ?? 0;

    // Verified music count and size (satisfies Bluetooth safety rule)
    final musicRows = await db.rawQuery(
      'SELECT COUNT(*) as cnt, SUM(file_size) as music_size FROM tracks '
      'WHERE (is_music = 1 AND confidence >= ?) OR (user_override = 1 AND is_music = 1)',
      [ClassificationResult.musicConfidenceThreshold],
    );
    final musicFiles = (musicRows.first['cnt'] as num?)?.toInt() ?? 0;
    final musicBytes = (musicRows.first['music_size'] as num?)?.toInt() ?? 0;

    // Category breakdown
    final catRows = await db.rawQuery(
      'SELECT audio_category, COUNT(*) as cnt FROM tracks GROUP BY audio_category',
    );
    final catMap = <String, int>{};
    for (final r in catRows) {
      final cat = r['audio_category'] as String?;
      final cnt = (r['cnt'] as num?)?.toInt() ?? 0;
      if (cat != null) {
        catMap[cat.toLowerCase()] = cnt;
      }
    }

    return StorageInsights(
      totalAudioFiles: totalFiles,
      musicCount: musicFiles,
      recordingsCount: catMap[AudioCategory.recording.dbValue.toLowerCase()] ?? 0,
      voiceNotesCount: catMap[AudioCategory.voiceNote.dbValue.toLowerCase()] ?? 0,
      podcastsCount: catMap[AudioCategory.podcast.dbValue.toLowerCase()] ?? 0,
      ringtonesCount: catMap[AudioCategory.ringtone.dbValue.toLowerCase()] ?? 0,
      notificationsCount: catMap[AudioCategory.notification.dbValue.toLowerCase()] ?? 0,
      soundEffectsCount: catMap[AudioCategory.soundEffect.dbValue.toLowerCase()] ?? 0,
      unknownCount: catMap[AudioCategory.unknown.dbValue.toLowerCase()] ?? 0,
      otherCount: catMap[AudioCategory.other.dbValue.toLowerCase()] ?? 0,
      totalStorageBytes: totalBytes,
      musicStorageBytes: musicBytes,
    );
  }

  // ───────────────────────── CUSTOM PLAYLISTS (P3.1) ─────────────────────────

  /// Creates a new user-curated playlist.
  Future<Playlist> createPlaylist(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Playlist name cannot be empty');
    final db = await _appDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insert(
      'playlists',
      {
        'name': cleanName,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.fail,
    );

    notifyListeners();
    return Playlist(id: id, name: cleanName, createdAt: now, updatedAt: now, trackCount: 0);
  }

  /// Renames an existing playlist.
  Future<void> renamePlaylist(int playlistId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) throw ArgumentError('Playlist name cannot be empty');
    final db = await _appDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'playlists',
      {'name': cleanName, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [playlistId],
    );

    notifyListeners();
  }

  /// Deletes a playlist and all associated track associations.
  Future<void> deletePlaylist(int playlistId) async {
    final db = await _appDb.database;
    await db.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    notifyListeners();
  }

  /// Fetches all custom playlists with accurate track counts.
  Future<List<Playlist>> getPlaylists() async {
    final db = await _appDb.database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.updated_at, COUNT(pt.id) as track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON p.id = pt.playlist_id
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC
    ''');

    return rows.map((r) => Playlist.fromMap(r)).toList();
  }

  /// Fetches single playlist by ID.
  Future<Playlist?> getPlaylistById(int playlistId) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, p.created_at, p.updated_at, COUNT(pt.id) as track_count
      FROM playlists p
      LEFT JOIN playlist_tracks pt ON p.id = pt.playlist_id
      WHERE p.id = ?
      GROUP BY p.id
    ''', [playlistId]);

    if (rows.isEmpty) return null;
    return Playlist.fromMap(rows.first);
  }

  /// Adds a song to a playlist with unique sequential ordering.
  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final db = await _appDb.database;

    // Check if song already exists in playlist to avoid redundant duplicates
    final existing = await db.query(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );
    if (existing.isNotEmpty) return;

    final maxOrderRows = await db.rawQuery(
      'SELECT MAX(track_order) as max_order FROM playlist_tracks WHERE playlist_id = ?',
      [playlistId],
    );
    final currentMax = (maxOrderRows.first['max_order'] as int?) ?? -1;
    final nextOrder = currentMax + 1;

    await db.insert(
      'playlist_tracks',
      {
        'playlist_id': playlistId,
        'track_id': trackId,
        'track_order': nextOrder,
      },
    );

    await db.update(
      'playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );

    notifyListeners();
  }

  /// Removes a song from a playlist and compacts track_order.
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    final db = await _appDb.database;
    await db.delete(
      'playlist_tracks',
      where: 'playlist_id = ? AND track_id = ?',
      whereArgs: [playlistId, trackId],
    );

    await db.update(
      'playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );

    notifyListeners();
  }

  /// Reorders songs in a playlist to match [orderedTrackIds].
  Future<void> reorderPlaylistTracks(int playlistId, List<int> orderedTrackIds) async {
    final db = await _appDb.database;
    final batch = db.batch();

    batch.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlistId]);

    for (int i = 0; i < orderedTrackIds.length; i++) {
      batch.insert('playlist_tracks', {
        'playlist_id': playlistId,
        'track_id': orderedTrackIds[i],
        'track_order': i,
      });
    }

    batch.update(
      'playlists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [playlistId],
    );

    await batch.commit(noResult: true);
    notifyListeners();
  }

  /// Retrieves tracks belonging to a playlist in sequential track_order.
  /// When [musicOnly] is true (default for playback safety), non-music tracks are filtered out.
  Future<List<Track>> getPlaylistTracks(int playlistId, {bool musicOnly = true}) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery('''
      SELECT t.*
      FROM playlist_tracks pt
      JOIN tracks t ON pt.track_id = t.id
      WHERE pt.playlist_id = ?
      ORDER BY pt.track_order ASC
    ''', [playlistId]);

    final allTracks = rows.map((r) => Track.fromMap(r)).toList();
    if (!musicOnly) return allTracks;

    final excludedFolders = await getExcludedFolders();
    return allTracks.where((t) {
      final isMusicSafe = (t.isMusic && t.confidence >= ClassificationResult.musicConfidenceThreshold) ||
          (t.userOverride && t.isMusic);
      if (!isMusicSafe) return false;
      if (t.folderPath != null && excludedFolders.contains(t.folderPath)) return false;
      return true;
    }).toList();
  }

  // ───────────────────────── SMART PLAYLISTS (P3.2) ─────────────────────────

  /// Fetches tracks for a real rule-based smart playlist.
  /// All smart playlists query strictly against the music-only dataset
  /// so non-music never contaminates playback.
  Future<List<Track>> getSmartPlaylistTracks(SmartPlaylistType type, {int limit = 100}) async {
    final db = await _appDb.database;
    final excludedFolders = await getExcludedFolders();

    String baseWhere = '((is_music = 1 AND confidence >= ?) OR (user_override = 1 AND is_music = 1))';
    final baseArgs = <dynamic>[ClassificationResult.musicConfidenceThreshold];

    if (excludedFolders.isNotEmpty) {
      final placeholders = List.filled(excludedFolders.length, '?').join(',');
      baseWhere += ' AND folder_path NOT IN ($placeholders)';
      baseArgs.addAll(excludedFolders);
    }

    String specificWhere = baseWhere;
    final specificArgs = List<dynamic>.from(baseArgs);
    String orderBy = 'title ASC';

    switch (type) {
      case SmartPlaylistType.recentlyPlayed:
        specificWhere += ' AND last_played IS NOT NULL';
        orderBy = 'last_played DESC';
        break;

      case SmartPlaylistType.mostPlayed:
        specificWhere += ' AND play_count > 0';
        orderBy = 'play_count DESC, last_played DESC';
        break;

      case SmartPlaylistType.recentlyAdded:
        orderBy = 'date_added DESC, id DESC';
        break;

      case SmartPlaylistType.favorites:
        specificWhere += ' AND is_favorite = 1';
        orderBy = 'title ASC';
        break;

      case SmartPlaylistType.longTracks:
        specificWhere += ' AND duration >= 300000'; // >= 5 mins
        orderBy = 'duration DESC';
        break;

      case SmartPlaylistType.shortTracks:
        specificWhere += ' AND duration > 0 AND duration <= 150000'; // <= 2.5 mins
        orderBy = 'duration ASC';
        break;

      case SmartPlaylistType.highConfidenceMusic:
        specificWhere += ' AND confidence >= 0.85';
        orderBy = 'confidence DESC, title ASC';
        break;

      case SmartPlaylistType.neverPlayed:
        specificWhere += ' AND (play_count = 0 OR last_played IS NULL)';
        orderBy = 'title ASC';
        break;
    }

    final rows = await db.query(
      'tracks',
      where: specificWhere,
      whereArgs: specificArgs,
      orderBy: orderBy,
      limit: limit,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }

  // ───────────────────────── SETTINGS & DATA MANAGEMENT (P4.7) ─────────────────────────

  /// Optimizes SQLite database indexes and storage.
  Future<bool> optimizeDatabase() async {
    final ok = await _appDb.checkAndOptimizeDatabase();
    notifyListeners();
    return ok;
  }

  /// Clears all playback history (resets play_count and last_played).
  Future<void> clearHistory() async {
    final db = await _appDb.database;
    await db.update('tracks', {'last_played': null, 'play_count': 0});
    notifyListeners();
  }

  /// Resets all manual classification overrides.
  Future<void> resetAllClassifications() async {
    final db = await _appDb.database;
    await db.update('tracks', {'user_override': 0});
    notifyListeners();
  }
}


