import 'dart:convert';
import '../../models/storage_insights.dart';

/// Fixed target quality tiers.
class DownloadQualityTier {
  static const String low = 'low';
  static const String medium = 'medium';
  static const String high = 'high';

  static const List<String> all = [low, medium, high];

  static int getBitrateKbps(String tier) {
    switch (tier.toLowerCase()) {
      case low:
        return 64;
      case medium:
        return 128;
      case high:
      default:
        return 192;
    }
  }

  static String getLabel(String tier) {
    switch (tier.toLowerCase()) {
      case low:
        return 'Low (64 kbps)';
      case medium:
        return 'Medium (128 kbps)';
      case high:
      default:
        return 'High (192 kbps)';
    }
  }
}

/// Status of an individual download task.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  converting,
  completed,
  failed,
  cancelled,
}

/// Represents a single audio download task with full metadata for persistence and resumability.
class DownloadTask {
  final String videoId;
  final String title;
  final String artist;
  final String outputFormat; // 'm4a' | 'mp3' | 'wav'
  final String qualityTier; // 'low' | 'medium' | 'high'
  final int qualityTag; // stream itag
  final int qualityBitrate; // stream bitrate in bps
  final int mp3BitrateKbps;
  final int? durationSeconds;
  final int? estimatedBytes;

  DownloadStatus status;
  double progress; // 0.0 to 1.0
  String? errorMessage;
  int bytesDownloaded;
  int? totalBytes;
  String? tempFilePath;
  String? finalFilePath;
  String? streamUrl;
  DateTime createdAt;
  DateTime updatedAt;

  DownloadTask({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.outputFormat,
    this.qualityTier = DownloadQualityTier.high,
    required this.qualityTag,
    required this.qualityBitrate,
    this.mp3BitrateKbps = 192,
    this.durationSeconds,
    this.estimatedBytes,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.tempFilePath,
    this.finalFilePath,
    this.streamUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Estimates file size in bytes before download starts.
  static int estimateBytes({
    required String qualityTier,
    required String format,
    required int durationSeconds,
  }) {
    if (durationSeconds <= 0) return 0;
    final fmt = format.toLowerCase().trim();
    if (fmt == 'wav') {
      // 44.1kHz, 16-bit, stereo = 44100 * 2 * 2 = 176400 bytes/sec
      return 176400 * durationSeconds;
    }
    final kbps = DownloadQualityTier.getBitrateKbps(qualityTier);
    return ((kbps * 1000 / 8) * durationSeconds).round();
  }

  String get formattedDownloadedSize =>
      StorageInsights.formatBytes(bytesDownloaded);

  String get formattedTotalSize {
    if (totalBytes != null && totalBytes! > 0) {
      return StorageInsights.formatBytes(totalBytes!);
    }
    if (estimatedBytes != null && estimatedBytes! > 0) {
      return '~${StorageInsights.formatBytes(estimatedBytes!)}';
    }
    return '--';
  }

  String get formattedEstimatedSize =>
      estimatedBytes != null && estimatedBytes! > 0
          ? '~${StorageInsights.formatBytes(estimatedBytes!)}'
          : '--';

  String get formattedProgress {
    final downloaded = StorageInsights.formatBytes(bytesDownloaded);
    final total = formattedTotalSize;
    return '$downloaded / $total';
  }

  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get canResume =>
      status == DownloadStatus.paused || status == DownloadStatus.failed;

  bool get isActive =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.converting;

  Map<String, dynamic> toMap() {
    return {
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'outputFormat': outputFormat,
      'qualityTier': qualityTier,
      'qualityTag': qualityTag,
      'qualityBitrate': qualityBitrate,
      'mp3BitrateKbps': mp3BitrateKbps,
      'durationSeconds': durationSeconds,
      'estimatedBytes': estimatedBytes,
      'status': status.name,
      'progress': progress,
      'errorMessage': errorMessage,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
      'tempFilePath': tempFilePath,
      'finalFilePath': finalFilePath,
      'streamUrl': streamUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      videoId: map['videoId'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String,
      outputFormat: (map['outputFormat'] as String?) ?? 'm4a',
      qualityTier:
          (map['qualityTier'] as String?) ?? DownloadQualityTier.high,
      qualityTag: (map['qualityTag'] as int?) ?? 0,
      qualityBitrate: (map['qualityBitrate'] as int?) ?? 0,
      mp3BitrateKbps: (map['mp3BitrateKbps'] as int?) ?? 192,
      durationSeconds: map['durationSeconds'] as int?,
      estimatedBytes: map['estimatedBytes'] as int?,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DownloadStatus.paused,
      ),
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: map['errorMessage'] as String?,
      bytesDownloaded: (map['bytesDownloaded'] as int?) ?? 0,
      totalBytes: map['totalBytes'] as int?,
      tempFilePath: map['tempFilePath'] as String?,
      finalFilePath: map['finalFilePath'] as String?,
      streamUrl: map['streamUrl'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DownloadTask.fromJson(String source) =>
      DownloadTask.fromMap(jsonDecode(source) as Map<String, dynamic>);

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
    int? bytesDownloaded,
    int? totalBytes,
    String? tempFilePath,
    String? finalFilePath,
    String? streamUrl,
    int? estimatedBytes,
  }) {
    return DownloadTask(
      videoId: videoId,
      title: title,
      artist: artist,
      outputFormat: outputFormat,
      qualityTier: qualityTier,
      qualityTag: qualityTag,
      qualityBitrate: qualityBitrate,
      mp3BitrateKbps: mp3BitrateKbps,
      durationSeconds: durationSeconds,
      estimatedBytes: estimatedBytes ?? this.estimatedBytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      finalFilePath: finalFilePath ?? this.finalFilePath,
      streamUrl: streamUrl ?? this.streamUrl,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
