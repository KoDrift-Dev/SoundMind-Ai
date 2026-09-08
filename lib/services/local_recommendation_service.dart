// local_recommendation_service.dart
import '../models/track.dart';
import '../repositories/audio_repository.dart';

/// Recommendation model capturing offline user affinity and recommendations.
class RecommendationBatch {
  final List<Track> dailyMix;
  final List<Track> forgottenGems;
  final List<Track> heavyRotation;
  final Map<String, int> topGenres;
  final Map<String, int> topArtists;

  const RecommendationBatch({
    this.dailyMix = const [],
    this.forgottenGems = const [],
    this.heavyRotation = const [],
    this.topGenres = const {},
    this.topArtists = const {},
  });
}

/// Offline-first, privacy-preserving recommendation engine using local playback signals.
class LocalRecommendationService {
  LocalRecommendationService._internal();
  static final LocalRecommendationService instance = LocalRecommendationService._internal();

  final AudioRepository _repository = AudioRepository.instance;

  /// Generates a complete personalized recommendation batch strictly from local listening data.
  Future<RecommendationBatch> generateRecommendations() async {
    final allMusic = await _repository.getMusicOnlyTracks();
    if (allMusic.isEmpty) {
      return const RecommendationBatch();
    }

    final history = await _repository.getRecentlyPlayed(limit: 100);

    // 1. Calculate Genre and Artist Affinities
    final genreAffinities = <String, int>{};
    final artistAffinities = <String, int>{};

    for (final track in history) {
      final weight = (track.playCount > 0 ? track.playCount : 1) + (track.isFavorite ? 3 : 0);

      if (track.genre != null && track.genre!.isNotEmpty) {
        genreAffinities[track.genre!] = (genreAffinities[track.genre!] ?? 0) + weight;
      }
      if (track.artist.isNotEmpty && track.artist != 'Unknown Artist') {
        artistAffinities[track.artist] = (artistAffinities[track.artist] ?? 0) + weight;
      }
    }

    // 2. Heavy Rotation: Tracks with play count in top 15% or playCount >= 5
    final heavyRotation = allMusic.where((t) => t.playCount >= 5).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));

    // 3. Forgotten Gems: Favorited or played >= 3 times, but not played in last 14 days
    final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14));
    final forgottenGems = allMusic.where((t) {
      final playedBefore = t.lastPlayed != null && t.lastPlayed!.isBefore(fourteenDaysAgo);
      final hasAffinity = t.isFavorite || t.playCount >= 3;
      return playedBefore && hasAffinity;
    }).toList()
      ..sort((a, b) => (b.lastPlayed ?? DateTime(2000)).compareTo(a.lastPlayed ?? DateTime(2000)));

    // 4. Daily Smart Mix: Blends top artists, favorite genres, and unexplored music
    final topGenreNames = genreAffinities.keys.take(3).toSet();
    final topArtistNames = artistAffinities.keys.take(5).toSet();

    final scoredTracks = allMusic.map((track) {
      double score = 0.0;
      if (topArtistNames.contains(track.artist)) score += 40.0;
      if (topGenreNames.contains(track.genre)) score += 25.0;
      if (track.isFavorite) score += 20.0;
      if (track.confidence >= 0.85) score += 10.0;
      // Bonus for unplayed or rarely played tracks from favored artists
      if (track.playCount == 0 && topArtistNames.contains(track.artist)) score += 15.0;

      return MapEntry(track, score);
    }).toList();

    scoredTracks.sort((a, b) => b.value.compareTo(a.value));
    final dailyMix = scoredTracks.take(25).map((e) => e.key).toList();

    return RecommendationBatch(
      dailyMix: dailyMix,
      forgottenGems: forgottenGems.take(20).toList(),
      heavyRotation: heavyRotation.take(20).toList(),
      topGenres: genreAffinities,
      topArtists: artistAffinities,
    );
  }
}
