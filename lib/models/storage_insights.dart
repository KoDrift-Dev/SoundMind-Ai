// storage_insights.dart
import 'audio_category.dart';

/// Real metrics and statistics computed from device audio scanned into SQLite.
class StorageInsights {
  final int totalAudioFiles;
  final int musicCount;
  final int recordingsCount;
  final int voiceNotesCount;
  final int podcastsCount;
  final int ringtonesCount;
  final int notificationsCount;
  final int unknownCount;
  final int soundEffectsCount;
  final int otherCount;
  final int totalStorageBytes;
  final int musicStorageBytes;

  const StorageInsights({
    required this.totalAudioFiles,
    required this.musicCount,
    required this.recordingsCount,
    required this.voiceNotesCount,
    required this.podcastsCount,
    required this.ringtonesCount,
    required this.notificationsCount,
    required this.unknownCount,
    this.soundEffectsCount = 0,
    this.otherCount = 0,
    required this.totalStorageBytes,
    required this.musicStorageBytes,
  });

  String get formattedTotalStorage => formatBytes(totalStorageBytes);
  String get formattedMusicStorage => formatBytes(musicStorageBytes);
  String get formattedNonMusicStorage => formatBytes(totalStorageBytes - musicStorageBytes);

  double get musicStoragePercentage =>
      totalStorageBytes > 0 ? (musicStorageBytes / totalStorageBytes).clamp(0.0, 1.0) : 0.0;

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Map<AudioCategory, int> toCategoryMap() {
    return {
      AudioCategory.music: musicCount,
      AudioCategory.recording: recordingsCount,
      AudioCategory.voiceNote: voiceNotesCount,
      AudioCategory.podcast: podcastsCount,
      AudioCategory.ringtone: ringtonesCount,
      AudioCategory.notification: notificationsCount,
      AudioCategory.soundEffect: soundEffectsCount,
      AudioCategory.unknown: unknownCount,
      AudioCategory.other: otherCount,
    };
  }
}
