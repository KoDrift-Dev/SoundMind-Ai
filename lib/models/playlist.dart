// playlist.dart
import 'track.dart';

/// Represents a custom user-curated playlist.
class Playlist {
  final int? id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int trackCount;
  final List<Track>? tracks;

  const Playlist({
    this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.trackCount = 0,
    this.tracks,
  });

  Playlist copyWith({
    int? id,
    String? name,
    int? createdAt,
    int? updatedAt,
    int? trackCount,
    List<Track>? tracks,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trackCount: trackCount ?? this.trackCount,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map, {int trackCount = 0, List<Track>? tracks}) {
    return Playlist(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: (map['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      trackCount: (map['track_count'] as int?) ?? trackCount,
      tracks: tracks,
    );
  }
}
