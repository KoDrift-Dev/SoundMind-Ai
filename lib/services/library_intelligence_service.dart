// library_intelligence_service.dart
import '../database/app_database.dart';
import '../models/track.dart';

/// Detailed intelligence statistics for a specific artist.
class ArtistIntelligence {
  final String artistName;
  final int trackCount;
  final int totalPlayCount;
  final int favoriteCount;
  final List<Track> topTracks;

  const ArtistIntelligence({
    required this.artistName,
    required this.trackCount,
    required this.totalPlayCount,
    required this.favoriteCount,
    required this.topTracks,
  });
}

/// Detailed intelligence statistics for an album.
class AlbumIntelligence {
  final String albumName;
  final String artistName;
  final int trackCount;
  final int totalDurationMs;
  final int totalPlayCount;
  final int favoriteCount;
  final List<Track> tracks;

  const AlbumIntelligence({
    required this.albumName,
    required this.artistName,
    required this.trackCount,
    required this.totalDurationMs,
    required this.totalPlayCount,
    required this.favoriteCount,
    required this.tracks,
  });
}

/// Composable advanced smart filter presets.
enum AdvancedSmartRule {
  highConfidenceRecentlyAdded,
  recentlyPlayedNotFavorites,
  longFavorites,
  neverPlayedHighConfidence,
  mostPlayedArtist;

  String get displayName {
    switch (this) {
      case AdvancedSmartRule.highConfidenceRecentlyAdded:
        return 'High Confidence Fresh';
      case AdvancedSmartRule.recentlyPlayedNotFavorites:
        return 'Recent Non-Favorites';
      case AdvancedSmartRule.longFavorites:
        return 'Extended Favorites';
      case AdvancedSmartRule.neverPlayedHighConfidence:
        return 'Unplayed Verified Gems';
      case AdvancedSmartRule.mostPlayedArtist:
        return 'Top Artist Deep Dive';
    }
  }

  String get description {
    switch (this) {
      case AdvancedSmartRule.highConfidenceRecentlyAdded:
        return 'Recently indexed with >=85% certainty';
      case AdvancedSmartRule.recentlyPlayedNotFavorites:
        return 'Played recently but not yet favorited';
      case AdvancedSmartRule.longFavorites:
        return 'Favorited tracks exceeding 5 minutes';
      case AdvancedSmartRule.neverPlayedHighConfidence:
        return 'Untouched music with pristine AI scoring';
      case AdvancedSmartRule.mostPlayedArtist:
        return 'Tracks by your most frequented artist';
    }
  }
}

/// Service computing local database intelligence without external network calls.
class LibraryIntelligenceService {
  LibraryIntelligenceService._internal();
  static final LibraryIntelligenceService instance = LibraryIntelligenceService._internal();

  final AppDatabase _dbManager = AppDatabase.instance;

  /// Computes artist intelligence from real SQLite rows.
  Future<ArtistIntelligence?> getArtistIntelligence(String artistName) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      'tracks',
      where: 'artist = ? AND ((is_music = 1 AND confidence >= 0.75) OR (user_override = 1 AND is_music = 1))',
      whereArgs: [artistName],
      orderBy: 'play_count DESC',
    );

    if (rows.isEmpty) return null;

    final tracks = rows.map((r) => Track.fromMap(r)).toList();
    int totalPlays = 0;
    int favs = 0;

    for (final t in tracks) {
      totalPlays += t.playCount;
      if (t.isFavorite) favs++;
    }

    return ArtistIntelligence(
      artistName: artistName,
      trackCount: tracks.length,
      totalPlayCount: totalPlays,
      favoriteCount: favs,
      topTracks: tracks.take(5).toList(),
    );
  }

  /// Computes album intelligence from real SQLite rows.
  Future<AlbumIntelligence?> getAlbumIntelligence(String albumName) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      'tracks',
      where: 'album = ? AND ((is_music = 1 AND confidence >= 0.75) OR (user_override = 1 AND is_music = 1))',
      whereArgs: [albumName],
      orderBy: 'track_number ASC, title ASC',
    );

    if (rows.isEmpty) return null;

    final tracks = rows.map((r) => Track.fromMap(r)).toList();
    int duration = 0;
    int totalPlays = 0;
    int favs = 0;

    for (final t in tracks) {
      duration += (t.duration ?? 0);
      totalPlays += t.playCount;
      if (t.isFavorite) favs++;
    }

    return AlbumIntelligence(
      albumName: albumName,
      artistName: tracks.first.artist,
      trackCount: tracks.length,
      totalDurationMs: duration,
      totalPlayCount: totalPlays,
      favoriteCount: favs,
      tracks: tracks,
    );
  }

  /// Queries composable advanced smart playlist tracks adhering strictly to Music-Only safety.
  Future<List<Track>> getAdvancedSmartPlaylist(AdvancedSmartRule rule, {int limit = 50}) async {
    final db = await _dbManager.database;
    const baseWhere = '((is_music = 1 AND confidence >= 0.75) OR (user_override = 1 AND is_music = 1)) AND (folder_path IS NULL OR folder_path NOT IN (SELECT folder_path FROM folder_exclusions WHERE is_excluded = 1))';

    String condition;
    String orderBy;

    switch (rule) {
      case AdvancedSmartRule.highConfidenceRecentlyAdded:
        condition = '$baseWhere AND confidence >= 0.85';
        orderBy = 'date_added DESC, id DESC';
        break;

      case AdvancedSmartRule.recentlyPlayedNotFavorites:
        condition = '$baseWhere AND last_played IS NOT NULL AND is_favorite = 0';
        orderBy = 'last_played DESC';
        break;

      case AdvancedSmartRule.longFavorites:
        condition = '$baseWhere AND is_favorite = 1 AND duration >= 300000';
        orderBy = 'play_count DESC';
        break;

      case AdvancedSmartRule.neverPlayedHighConfidence:
        condition = '$baseWhere AND (play_count = 0 OR last_played IS NULL) AND confidence >= 0.85';
        orderBy = 'title ASC';
        break;

      case AdvancedSmartRule.mostPlayedArtist:
        // Identify top artist first
        final topArtistRow = await db.rawQuery('''
          SELECT artist, SUM(play_count) as total_plays
          FROM tracks
          WHERE $baseWhere AND artist != 'Unknown Artist'
          GROUP BY artist
          ORDER BY total_plays DESC
          LIMIT 1
        ''');

        if (topArtistRow.isEmpty) return [];
        final topArtist = topArtistRow.first['artist'] as String;
        condition = '$baseWhere AND artist = ?';
        final rows = await db.query('tracks', where: condition, whereArgs: [topArtist], orderBy: 'play_count DESC', limit: limit);
        return rows.map((r) => Track.fromMap(r)).toList();
    }

    final rows = await db.query(
      'tracks',
      where: condition,
      orderBy: orderBy,
      limit: limit,
    );

    return rows.map((r) => Track.fromMap(r)).toList();
  }
}
