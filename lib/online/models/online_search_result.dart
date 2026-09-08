class OnlineSearchResult {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
  final String? duration;
  final String source;
  final String? previewUrl;

  const OnlineSearchResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
    this.duration,
    required this.source,
    this.previewUrl,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlineSearchResult &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'OnlineSearchResult(id: $id, title: $title, artist: $artist, source: $source)';
  }
}
