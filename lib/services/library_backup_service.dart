// library_backup_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/audio_category.dart';
import '../repositories/audio_repository.dart';

/// Structured metadata backup format.
class LibraryBackupPayload {
  final int version;
  final String timestamp;
  final List<Map<String, dynamic>> playlists;
  final List<String> favoritePaths;
  final List<Map<String, dynamic>> classificationOverrides;
  final List<String> excludedFolders;

  const LibraryBackupPayload({
    this.version = 1,
    required this.timestamp,
    this.playlists = const [],
    this.favoritePaths = const [],
    this.classificationOverrides = const [],
    this.excludedFolders = const [],
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'schemaVersion': version,
    'timestamp': timestamp,
    'playlists': playlists,
    'favoritePaths': favoritePaths,
    'classificationOverrides': classificationOverrides,
    'excludedFolders': excludedFolders,
  };

  factory LibraryBackupPayload.fromJson(Map<String, dynamic> json) {
    return LibraryBackupPayload(
      version: (json['schemaVersion'] ?? json['version']) as int? ?? 1,
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      playlists: (json['playlists'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      favoritePaths: (json['favoritePaths'] as List<dynamic>?)?.cast<String>() ?? [],
      classificationOverrides: (json['classificationOverrides'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      excludedFolders: (json['excludedFolders'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }
}

/// Result of an import operation.
class BackupImportResult {
  final bool isSuccess;
  final int restoredPlaylistsCount;
  final int restoredFavoritesCount;
  final int restoredOverridesCount;
  final int restoredExcludedFoldersCount;
  final String? error;

  const BackupImportResult({
    required this.isSuccess,
    this.restoredPlaylistsCount = 0,
    this.restoredFavoritesCount = 0,
    this.restoredOverridesCount = 0,
    this.restoredExcludedFoldersCount = 0,
    this.error,
  });
}

/// Service that securely exports and imports library metadata without touching physical files.
class LibraryBackupService {
  LibraryBackupService._internal();
  static final LibraryBackupService instance = LibraryBackupService._internal();

  final AudioRepository _repository = AudioRepository.instance;
  final AppDatabase _dbManager = AppDatabase.instance;

  /// Exports current library metadata to a JSON string.
  Future<String> exportBackupJson() async {
    final db = await _dbManager.database;

    // 1. Playlists & associated tracks
    final playlists = await _repository.getPlaylists();
    final playlistsData = <Map<String, dynamic>>[];

    for (final pl in playlists) {
      if (pl.id == null) continue;
      final tracks = await _repository.getPlaylistTracks(pl.id!, musicOnly: false);
      playlistsData.add({
        'name': pl.name,
        'createdAt': pl.createdAt,
        'updatedAt': pl.updatedAt,
        'trackPaths': tracks.map((t) => t.filePath).whereType<String>().toList(),
      });
    }

    // 2. Favorites
    final favRows = await db.query('tracks', columns: ['file_path'], where: 'is_favorite = 1');
    final favoritePaths = favRows.map((r) => r['file_path'] as String?).whereType<String>().toList();

    // 3. Classification overrides
    final overrideRows = await db.query(
      'tracks',
      columns: ['file_path', 'audio_category', 'is_music'],
      where: 'user_override = 1',
    );
    final overrides = overrideRows.map((r) => {
      'filePath': r['file_path'] as String,
      'category': r['audio_category'] as String,
      'isMusic': (r['is_music'] as int) == 1,
    }).toList();

    // 4. Excluded folders
    final excludedFolders = await _repository.getExcludedFolders();

    final payload = LibraryBackupPayload(
      timestamp: DateTime.now().toIso8601String(),
      playlists: playlistsData,
      favoritePaths: favoritePaths,
      classificationOverrides: overrides,
      excludedFolders: excludedFolders.toList(),
    );

    return jsonEncode(payload.toJson());
  }

  /// Restores metadata from a JSON string inside a single SQLite transaction.
  Future<BackupImportResult> importBackupJson(String jsonString) async {
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      final payload = LibraryBackupPayload.fromJson(decoded);

      if (payload.version > 1) {
        return BackupImportResult(
          isSuccess: false,
          error: 'Unsupported backup schema version (${payload.version}). Please update SoundMind to restore this backup.',
        );
      }

      final db = await _dbManager.database;

      int restoredPlaylists = 0;
      int restoredFavs = 0;
      int restoredOverrides = 0;
      int restoredExclusions = 0;

      await db.transaction((txn) async {
        // 1. Restore folder exclusions
        for (final folder in payload.excludedFolders) {
          await txn.insert(
            'folder_exclusions',
            {
              'folder_path': folder,
              'date_excluded': DateTime.now().millisecondsSinceEpoch,
              'is_excluded': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredExclusions++;
        }

        // 2. Restore favorites
        for (final path in payload.favoritePaths) {
          final count = await txn.update(
            'tracks',
            {'is_favorite': 1},
            where: 'file_path = ?',
            whereArgs: [path],
          );
          if (count > 0) restoredFavs++;
        }

        // 3. Restore user overrides
        for (final override in payload.classificationOverrides) {
          final path = override['filePath'] as String?;
          final categoryStr = override['category'] as String?;
          final isMusic = override['isMusic'] as bool? ?? true;
          if (path != null && categoryStr != null) {
            final category = AudioCategory.fromDbValue(categoryStr);
            final count = await txn.update(
              'tracks',
              {
                'audio_category': category.dbValue,
                'is_music': isMusic ? 1 : 0,
                'user_override': 1,
                'confidence': 1.0,
              },
              where: 'file_path = ?',
              whereArgs: [path],
            );
            if (count > 0) restoredOverrides++;
          }
        }

        // 4. Restore playlists
        for (final pl in payload.playlists) {
          final name = pl['name'] as String?;
          final trackPaths = (pl['trackPaths'] as List<dynamic>?)?.cast<String>() ?? [];
          if (name == null || name.isEmpty) continue;

          // Insert or get playlist
          int pId;
          final existing = await txn.query('playlists', where: 'name = ?', whereArgs: [name]);
          if (existing.isNotEmpty) {
            pId = existing.first['id'] as int;
          } else {
            pId = await txn.insert('playlists', {
              'name': name,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            });
          }

          // Add tracks by matching file_path
          for (final path in trackPaths) {
            final trackRow = await txn.query('tracks', where: 'file_path = ?', whereArgs: [path]);
            if (trackRow.isNotEmpty) {
              final trackId = trackRow.first['id'] as int;
              final maxOrderRow = await txn.rawQuery(
                'SELECT MAX(track_order) as m FROM playlist_tracks WHERE playlist_id = ?',
                [pId],
              );
              final nextOrder = ((maxOrderRow.first['m'] as int?) ?? -1) + 1;
              await txn.insert(
                'playlist_tracks',
                {
                  'playlist_id': pId,
                  'track_id': trackId,
                  'track_order': nextOrder,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
          restoredPlaylists++;
        }
      });

      return BackupImportResult(
        isSuccess: true,
        restoredPlaylistsCount: restoredPlaylists,
        restoredFavoritesCount: restoredFavs,
        restoredOverridesCount: restoredOverrides,
        restoredExcludedFoldersCount: restoredExclusions,
      );
    } catch (e) {
      debugPrint('LibraryBackupService: Import error: $e');
      return BackupImportResult(isSuccess: false, error: e.toString());
    }
  }

  /// Writes backup JSON to a file path.
  Future<File> writeBackupToFile(String filePath) async {
    final json = await exportBackupJson();
    final file = File(filePath);
    return await file.writeAsString(json);
  }
}
