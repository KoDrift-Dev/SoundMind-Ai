// online_models.dart

/// Represents an artist from an authorized online music service.
class OnlineArtist {
  final String id;
  final String name;
  final String? imageUrl;
  final String? bio;

  const OnlineArtist({
    required this.id,
    required this.name,
    this.imageUrl,
    this.bio,
  });
}

/// Represents an album from an authorized online music service.
class OnlineAlbum {
  final String id;
  final String title;
  final String artistName;
  final String? artistId;
  final String? coverUrl;
  final int? releaseYear;
  final int trackCount;

  const OnlineAlbum({
    required this.id,
    required this.title,
    required this.artistName,
    this.artistId,
    this.coverUrl,
    this.releaseYear,
    this.trackCount = 0,
  });
}

/// Represents a streamable / downloadable track from an authorized online provider.
class OnlineTrack {
  final String id;
  final String title;
  final String artistName;
  final String? albumName;
  final int durationSeconds;
  final String? streamUrl;
  final String? downloadUrl;
  final String? coverUrl;
  final String license; // e.g. "Creative Commons BY-SA", "Commercial License"

  const OnlineTrack({
    required this.id,
    required this.title,
    required this.artistName,
    this.albumName,
    required this.durationSeconds,
    this.streamUrl,
    this.downloadUrl,
    this.coverUrl,
    this.license = 'All Rights Reserved',
  });
}

/// Consolidated search results from an authorized online provider.
class OnlineSearchResult {
  final List<OnlineTrack> tracks;
  final List<OnlineAlbum> albums;
  final List<OnlineArtist> artists;

  const OnlineSearchResult({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });
}
