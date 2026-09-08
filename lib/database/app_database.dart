// app_database.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static const String _databaseName = 'soundmind_ai.db';
  static const int _databaseVersion = 4;

  Database? _db;
  Completer<Database>? _initCompleter;
  bool _schemaEnsured = false;

  /// Visible for testing: inject an in-memory or mock database.
  @visibleForTesting
  set testDatabase(Database? db) {
    _db = db;
    _initCompleter = null;
    _schemaEnsured = false;
  }

  /// Visible for testing: invoke schema creation directly.
  @visibleForTesting
  Future<void> ensureSchemaForTesting(Database db) => _ensureSchema(db);

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;

    // Prevent concurrent openDatabase calls from competing or deadlocking for the SQLite file lock
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    final completer = Completer<Database>();
    _initCompleter = completer;

    try {
      final db = await _initDatabase();
      _db = db;
      completer.complete(db);
      return db;
    } catch (e) {
      completer.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        // WAL (Write-Ahead Logging) returns a row with the mode name ('wal'),
        // Android SQLiteDatabase requires rawQuery for PRAGMAs that return results.
        await db.rawQuery('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA busy_timeout = 5000;');
      },
      onCreate: (db, version) async {
        await _ensureSchema(db);
        _schemaEnsured = true;
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
        _schemaEnsured = true;
      },
      onOpen: (db) async {
        // Run schema verification once per process if not already run in onCreate/onUpgrade
        if (!_schemaEnsured) {
          await _ensureSchema(db);
          _schemaEnsured = true;
        }
      },
    );
  }

  /// Ensures all required tables, columns, and indexes exist in SQLite.
  /// Self-heals partial or upgraded databases idempotently without data loss.
  Future<void> _ensureSchema(Database db) async {
    // 1. Tracks Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
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

    // Inspect columns in tracks table to repair any legacy schema versions
    final columnInfo = await db.rawQuery('PRAGMA table_info(tracks)');
    final existingColumns = columnInfo.map((row) => row['name'] as String).toSet();

    Future<void> addColumnIfMissing(String colName, String colType) async {
      if (!existingColumns.contains(colName)) {
        try {
          await db.execute('ALTER TABLE tracks ADD COLUMN $colName $colType');
        } catch (e) {
          debugPrint('AppDatabase: Notice on adding column $colName: $e');
        }
      }
    }

    await addColumnIfMissing('track_number', 'INTEGER');
    await addColumnIfMissing('album_artist', 'TEXT');
    await addColumnIfMissing('is_downloaded', 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing('art_url', 'TEXT');
    await addColumnIfMissing('last_scanned', 'INTEGER');
    await addColumnIfMissing('online_id', 'TEXT');

    // Indexes for high performance querying on 10,000+ files
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_path ON tracks(file_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_online_id ON tracks(online_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_is_music ON tracks(is_music, confidence)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_category ON tracks(audio_category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_favorite ON tracks(is_favorite)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_history ON tracks(last_played)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_folder ON tracks(folder_path)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album)');

    // 2. Folder Exclusions Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folder_exclusions (
        folder_path TEXT PRIMARY KEY,
        date_excluded INTEGER,
        is_excluded INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 3. Persisted Playback Queue Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS persisted_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id INTEGER,
        file_path TEXT,
        queue_order INTEGER NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0,
        position_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 4. Custom Playlists Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 5. Playlist Tracks Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        track_id INTEGER NOT NULL,
        track_order INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_playlist_tracks ON playlist_tracks(playlist_id, track_order)');
  }

  /// Runs database integrity check and optimization.
  Future<bool> checkAndOptimizeDatabase() async {
    final db = await database;
    final integrityResult = await db.rawQuery('PRAGMA integrity_check');
    final isOk = integrityResult.isNotEmpty && integrityResult.first.values.first == 'ok';
    if (isOk) {
      await db.execute('ANALYZE');
      await db.execute('VACUUM');
    }
    return isOk;
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _initCompleter = null;
      _schemaEnsured = false;
    }
  }
}
