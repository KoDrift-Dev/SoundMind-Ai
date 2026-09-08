// track.dart
import 'audio_category.dart';
import '../classifier/classification_result.dart';

class Track {
  final int? id;
  final String? onlineId;
  String? filePath;
  final String? fileName;
  final String title;
  final String artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final String? albumArtist;
  final String artUrl;
  final int? duration;
  final int? fileSize;
  final int? bitrate;
  final String? mimeType;
  final String? extension;
  final String? folderPath;
  final int? dateAdded;
  final int? dateModified;
  final int? lastScanned;

  // Online Resolution State
  bool isResolving;
  String? resolutionError;

  // Classification & Safety
  bool isMusic;
  AudioCategory audioCategory;
  double confidence;
  ClassificationSource classificationSource;
  bool userOverride;

  // State & User Interactions
  int playCount;
  DateTime? lastPlayed;
  bool isFavorite;
  bool isDownloaded;

  /// Convenience getter matching older size field
  int? get size => fileSize;

  Track({
    this.id,
    this.onlineId,
    this.filePath,
    String? fileName,
    required this.title,
    required this.artist,
    this.album,
    this.genre,
    this.year,
    this.trackNumber,
    this.albumArtist,
    this.artUrl = '',
    this.duration,
    int? size,
    int? fileSize,
    this.bitrate,
    this.mimeType,
    String? extension,
    String? folderPath,
    this.dateAdded,
    this.dateModified,
    this.lastScanned,
    bool? isMusic,
    this.audioCategory = AudioCategory.unknown,
    this.confidence = 0.0,
    this.classificationSource = ClassificationSource.heuristic,
    this.userOverride = false,
    this.isResolving = false,
    this.resolutionError,
    this.playCount = 0,
    this.lastPlayed,
    this.isFavorite = false,
    this.isDownloaded = false,
  })  : fileSize = fileSize ?? size,
        fileName = fileName ?? _extractFileName(filePath),
        extension = extension ?? _extractExtension(filePath),
        folderPath = folderPath ?? _extractFolderPath(filePath),
        isMusic = (userOverride == true)
            ? (isMusic ?? true)
            : ((isMusic ?? (audioCategory == AudioCategory.music && confidence >= 0.75)) &&
                audioCategory != AudioCategory.recording &&
                audioCategory != AudioCategory.voiceNote &&
                audioCategory != AudioCategory.messagingAudio &&
                audioCategory != AudioCategory.ringtone &&
                audioCategory != AudioCategory.notification &&
                audioCategory != AudioCategory.podcast &&
                audioCategory != AudioCategory.audiobook &&
                audioCategory != AudioCategory.soundEffect &&
                (audioCategory == AudioCategory.music ? confidence >= 0.75 : true));

  static String _extractFileName(String? path) {
    if (path == null || path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').last;
  }

  static String _extractExtension(String? path) {
    if (path == null || !path.contains('.')) return '';
    return path.split('.').last.toLowerCase();
  }

  static String _extractFolderPath(String? path) {
    if (path == null || path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.length > 1) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
    return '';
  }

  Track copyWith({
    int? id,
    String? onlineId,
    String? filePath,
    String? fileName,
    String? title,
    String? artist,
    String? album,
    String? genre,
    int? year,
    int? trackNumber,
    String? albumArtist,
    String? artUrl,
    int? duration,
    int? fileSize,
    int? bitrate,
    String? mimeType,
    String? extension,
    String? folderPath,
    int? dateAdded,
    int? dateModified,
    int? lastScanned,
    bool? isMusic,
    AudioCategory? audioCategory,
    double? confidence,
    ClassificationSource? classificationSource,
    bool? userOverride,
    bool? isResolving,
    String? resolutionError,
    int? playCount,
    DateTime? lastPlayed,
    bool? isFavorite,
    bool? isDownloaded,
  }) {
    return Track(
      id: id ?? this.id,
      onlineId: onlineId ?? this.onlineId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      albumArtist: albumArtist ?? this.albumArtist,
      artUrl: artUrl ?? this.artUrl,
      duration: duration ?? this.duration,
      fileSize: fileSize ?? this.fileSize,
      bitrate: bitrate ?? this.bitrate,
      mimeType: mimeType ?? this.mimeType,
      extension: extension ?? this.extension,
      folderPath: folderPath ?? this.folderPath,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      lastScanned: lastScanned ?? this.lastScanned,
      isMusic: isMusic ?? this.isMusic,
      audioCategory: audioCategory ?? this.audioCategory,
      confidence: confidence ?? this.confidence,
      classificationSource: classificationSource ?? this.classificationSource,
      userOverride: userOverride ?? this.userOverride,
      isResolving: isResolving ?? this.isResolving,
      resolutionError: resolutionError ?? this.resolutionError,
      playCount: playCount ?? this.playCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      isFavorite: isFavorite ?? this.isFavorite,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }

  /// Converts Track to database row map.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (onlineId != null) 'online_id': onlineId,
      'file_path': filePath,
      'file_name': fileName,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'year': year,
      'track_number': trackNumber,
      'album_artist': albumArtist,
      'duration': duration,
      'file_size': fileSize,
      'bitrate': bitrate,
      'mime_type': mimeType,
      'extension': extension,
      'folder_path': folderPath,
      'date_added': dateAdded,
      'date_modified': dateModified,
      'last_scanned': lastScanned ?? DateTime.now().millisecondsSinceEpoch,
      'is_music': isMusic ? 1 : 0,
      'audio_category': audioCategory.dbValue,
      'confidence': confidence,
      'classification_source': classificationSource.dbValue,
      'user_override': userOverride ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'play_count': playCount,
      'last_played': lastPlayed?.millisecondsSinceEpoch,
      'is_downloaded': isDownloaded ? 1 : 0,
      'art_url': artUrl,
    };
  }

  /// Reconstructs Track from database row map.
  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as int?,
      onlineId: map['online_id'] as String?,
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      title: (map['title'] as String?)?.isNotEmpty == true ? map['title'] as String : 'Unknown Title',
      artist: (map['artist'] as String?)?.isNotEmpty == true ? map['artist'] as String : 'Unknown Artist',
      album: map['album'] as String?,
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      trackNumber: map['track_number'] as int?,
      albumArtist: map['album_artist'] as String?,
      duration: map['duration'] as int?,
      fileSize: map['file_size'] as int?,
      bitrate: map['bitrate'] as int?,
      mimeType: map['mime_type'] as String?,
      extension: map['extension'] as String?,
      folderPath: map['folder_path'] as String?,
      dateAdded: map['date_added'] as int?,
      dateModified: map['date_modified'] as int?,
      lastScanned: map['last_scanned'] as int?,
      isMusic: (map['is_music'] as int?) == 1,
      audioCategory: AudioCategory.fromDbValue(map['audio_category'] as String?),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      classificationSource: ClassificationSource.fromDbValue(map['classification_source'] as String?),
      userOverride: (map['user_override'] as int?) == 1,
      isFavorite: (map['is_favorite'] as int?) == 1,
      playCount: (map['play_count'] as int?) ?? 0,
      lastPlayed: map['last_played'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int)
          : null,
      isDownloaded: (map['is_downloaded'] as int?) == 1,
      artUrl: (map['art_url'] as String?) ?? '',
    );
  }
}

final List<Track> placeholderLibrary = [
  Track(
    id: 1,
    filePath: '/storage/emulated/0/Music/Synthetic Dreams/Neon Genesis.mp3',
    title: 'Neon Genesis',
    artist: 'Aurora Drift',
    album: 'Synthetic Dreams',
    artUrl: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?q=80&w=500&auto=format&fit=crop',
    duration: 248000,
    size: 5242880,
    dateAdded: 1672531200,
    isDownloaded: true,
    audioCategory: AudioCategory.music,
    confidence: 0.98,
    isMusic: true,
  ),
  Track(
    id: 2,
    filePath: '/storage/emulated/0/Music/Sufi Resurgence/Midnight Qalb.mp3',
    title: 'Midnight Qalb',
    artist: 'Nusrat Echoes',
    album: 'Sufi Resurgence',
    artUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?q=80&w=500&auto=format&fit=crop',
    duration: 320000,
    size: 7340032,
    dateAdded: 1672617600,
    isFavorite: true,
    audioCategory: AudioCategory.music,
    confidence: 0.96,
    isMusic: true,
  ),
  Track(
    id: 3,
    filePath: '/storage/emulated/0/Music/Sufi Resurgence/Sufi Static.mp3',
    title: 'Sufi Static',
    artist: 'Kaafi Sessions',
    album: 'Sufi Resurgence',
    artUrl: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?q=80&w=500&auto=format&fit=crop',
    duration: 190000,
    size: 4194304,
    dateAdded: 1672704000,
    audioCategory: AudioCategory.music,
    confidence: 0.95,
    isMusic: true,
  ),
  Track(
    id: 4,
    filePath: '/storage/emulated/0/Music/Live Acoustic/Studio 9.mp3',
    title: 'Studio 9',
    artist: 'Coke Sessions',
    album: 'Live Acoustic',
    artUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?q=80&w=500&auto=format&fit=crop',
    duration: 210000,
    size: 4718592,
    dateAdded: 1672790400,
    isDownloaded: true,
    audioCategory: AudioCategory.music,
    confidence: 0.92,
    isMusic: true,
  ),
  Track(
    id: 5,
    filePath: '/storage/emulated/0/Music/Morning Prayers/Fajr Reverie.mp3',
    title: 'Fajr Reverie',
    artist: 'Naat Collective',
    album: 'Morning Prayers',
    artUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?q=80&w=500&auto=format&fit=crop',
    duration: 280000,
    size: 6291456,
    dateAdded: 1672876800,
    isFavorite: true,
    audioCategory: AudioCategory.music,
    confidence: 0.95,
    isMusic: true,
  ),
];