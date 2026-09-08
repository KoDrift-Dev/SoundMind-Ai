// offline_download_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';

enum DownloadStatus {
  idle,
  downloading,
  paused,
  completed,
  failed,
  cancelled;
}

class DownloadProgress {
  final String taskId;
  final int bytesDownloaded;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final DownloadStatus status;
  final String? errorMessage;

  const DownloadProgress({
    required this.taskId,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.progress,
    required this.status,
    this.errorMessage,
  });

  DownloadProgress copyWith({
    int? bytesDownloaded,
    int? totalBytes,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    return DownloadProgress(
      taskId: taskId,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Production service managing real audio file downloads, offline disk storage,
/// pause/resume with byte ranges, progress tracking, and storage cleanup.
class OfflineDownloadService {
  OfflineDownloadService._internal();
  static final OfflineDownloadService instance = OfflineDownloadService._internal();

  final AudioRepository _repo = AudioRepository.instance;
  final Map<String, _ActiveDownloadTask> _activeTasks = {};
  final StreamController<DownloadProgress> _progressController = StreamController<DownloadProgress>.broadcast();

  Stream<DownloadProgress> get progressStream => _progressController.stream;

  Directory? _cacheDirOverride;

  /// Visible for testing: inject custom directory for unit tests.
  @visibleForTesting
  set cacheDirectoryOverride(Directory? dir) => _cacheDirOverride = dir;

  Future<Directory> get _offlineDirectory async {
    if (_cacheDirOverride != null) return _cacheDirOverride!;
    final appDocDir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory(p.join(appDocDir.path, 'offline_audio'));
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir;
  }

  /// Starts downloading an authorized audio file to local disk.
  Future<void> startDownload({
    required Track track,
    required Uri sourceUri,
  }) async {
    final taskId = track.id?.toString() ?? track.title;
    if (_activeTasks.containsKey(taskId) && _activeTasks[taskId]!.status == DownloadStatus.downloading) {
      return; // Already downloading
    }

    final offlineDir = await _offlineDirectory;
    final fileExtension = p.extension(sourceUri.path).isNotEmpty ? p.extension(sourceUri.path) : '.mp3';
    final targetFile = File(p.join(offlineDir.path, 'track_${track.id ?? DateTime.now().millisecondsSinceEpoch}$fileExtension'));

    final task = _ActiveDownloadTask(
      taskId: taskId,
      track: track,
      sourceUri: sourceUri,
      targetFile: targetFile,
    );

    _activeTasks[taskId] = task;
    _runTask(task);
  }

  /// Pauses an active download.
  void pauseDownload(String taskId) {
    final task = _activeTasks[taskId];
    if (task != null && task.status == DownloadStatus.downloading) {
      task.isPaused = true;
      task.httpClient?.close(force: true);
      task.status = DownloadStatus.paused;
      _emitProgress(task);
    }
  }

  /// Resumes a paused download with HTTP Range header.
  void resumeDownload(String taskId) {
    final task = _activeTasks[taskId];
    if (task != null && task.status == DownloadStatus.paused) {
      task.isPaused = false;
      task.status = DownloadStatus.downloading;
      _runTask(task);
    }
  }

  /// Cancels an active or paused download and deletes partial bytes.
  Future<void> cancelDownload(String taskId) async {
    final task = _activeTasks[taskId];
    if (task != null) {
      task.isCancelled = true;
      task.httpClient?.close(force: true);
      task.status = DownloadStatus.cancelled;
      _emitProgress(task);

      if (await task.targetFile.exists()) {
        try {
          await task.targetFile.delete();
        } catch (_) {}
      }
      _activeTasks.remove(taskId);
    }
  }

  /// Internal download execution loop.
  Future<void> _runTask(_ActiveDownloadTask task) async {
    task.status = DownloadStatus.downloading;
    _emitProgress(task);

    HttpClient? client;
    IOSink? sink;

    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      task.httpClient = client;

      final request = await client.getUrl(task.sourceUri);

      // Check existing partial bytes for resuming
      int existingBytes = 0;
      if (await task.targetFile.exists()) {
        existingBytes = await task.targetFile.length();
        if (existingBytes > 0) {
          request.headers.add(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
          task.downloadedBytes = existingBytes;
        }
      }

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Download failed with status: ${response.statusCode}');
      }

      final contentLength = response.contentLength;
      if (contentLength != -1) {
        task.totalBytes = existingBytes + contentLength;
      }

      sink = task.targetFile.openWrite(mode: FileMode.append);

      await for (final chunk in response) {
        if (task.isPaused || task.isCancelled) break;

        sink.add(chunk);
        task.downloadedBytes += chunk.length;

        final double prog = (task.totalBytes > 0) ? (task.downloadedBytes / task.totalBytes).clamp(0.0, 1.0) : 0.0;
        task.progress = prog;
        _emitProgress(task);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (task.isCancelled) return;

      if (!task.isPaused) {
        // Download complete: verify physical file exists and update SQLite
        final verifiedExists = await task.targetFile.exists();
        final actualLength = verifiedExists ? await task.targetFile.length() : 0;

        if (verifiedExists && actualLength > 0) {
          task.status = DownloadStatus.completed;
          task.progress = 1.0;
          _emitProgress(task);

          // Update SQLite record with real local offline path and is_downloaded = 1
          final updatedTrack = task.track.copyWith(
            filePath: task.targetFile.path,
            isDownloaded: true,
            fileSize: actualLength,
          );
          await _repo.updateTrackMetadata(updatedTrack);
        } else {
          task.status = DownloadStatus.failed;
          task.errorMessage = 'Downloaded file could not be verified on disk';
          _emitProgress(task);
        }
      }
    } catch (e) {
      if (!task.isPaused && !task.isCancelled) {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
        _emitProgress(task);
      }
    } finally {
      await sink?.close();
      client?.close(force: true);
      task.httpClient = null;
    }
  }

  void _emitProgress(_ActiveDownloadTask task) {
    if (_progressController.isClosed) return;
    _progressController.add(DownloadProgress(
      taskId: task.taskId,
      bytesDownloaded: task.downloadedBytes,
      totalBytes: task.totalBytes,
      progress: task.progress,
      status: task.status,
      errorMessage: task.errorMessage,
    ));
  }

  /// Calculates real disk bytes consumed by offline cache directory.
  Future<int> getOfflineCacheSizeBytes() async {
    final dir = await _offlineDirectory;
    if (!await dir.exists()) return 0;

    int totalBytes = 0;
    try {
      await for (final entity in dir.list(recursive: false, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  /// Physically deletes a downloaded file from disk and updates SQLite record.
  Future<bool> deleteOfflineDownload(Track track) async {
    final filePath = track.filePath;
    if (filePath != null && filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    // Update database record to reflect removal of offline copy
    final updated = track.copyWith(isDownloaded: false);
    await _repo.updateTrackMetadata(updated);
    return true;
  }

  void dispose() {
    _progressController.close();
  }
}

class _ActiveDownloadTask {
  final String taskId;
  final Track track;
  final Uri sourceUri;
  final File targetFile;

  int downloadedBytes = 0;
  int totalBytes = 0;
  double progress = 0.0;
  DownloadStatus status = DownloadStatus.idle;
  String? errorMessage;

  bool isPaused = false;
  bool isCancelled = false;
  HttpClient? httpClient;

  _ActiveDownloadTask({
    required this.taskId,
    required this.track,
    required this.sourceUri,
    required this.targetFile,
  });
}
