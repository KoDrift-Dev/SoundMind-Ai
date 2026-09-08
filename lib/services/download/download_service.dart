import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../user_preferences_service.dart';
import '../youtube_service.dart';
import 'download_models.dart';
import 'download_notification_service.dart';

/// Robust singleton service for streaming, resuming, and converting online audio tracks.
class DownloadService {
  DownloadService._internal();
  static final DownloadService instance = DownloadService._internal();

  static const int maxConcurrentDownloads = 3;

  static const Map<String, String> _playbackHeaders = {
    'User-Agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    'Origin': 'https://www.youtube.com',
  };

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.stream,
      followRedirects: true,
      headers: _playbackHeaders,
    ),
  );

  final YoutubeService _youtubeService = YoutubeService();

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, int> _retryCounts = {};

  final StreamController<DownloadTask> _taskUpdateController =
      StreamController<DownloadTask>.broadcast();
  final StreamController<List<DownloadTask>> _allTasksController =
      StreamController<List<DownloadTask>>.broadcast();

  Directory? _downloadsDir;
  Directory? _tempDir;
  File? _metadataFile;

  bool _initialized = false;
  Timer? _saveDebounceTimer;
  DateTime _lastProgressSave = DateTime.now();

  // ─── Initialization & Recovery ───

  /// Resolves the active download directory according to user preferences.
  Future<Directory> _resolveDownloadsDirectory() async {
    final choice = UserPreferencesService.instance.downloadFolderChoice;
    final customPath = UserPreferencesService.instance.customDownloadPath;

    Directory? targetDir;

    if (choice == 'custom' && customPath.trim().isNotEmpty) {
      targetDir = Directory(customPath.trim());
    } else if (choice == 'music') {
      targetDir = Directory('/storage/emulated/0/Music/SoundMind');
    }

    // Default: Public Downloads directory on device internal storage (/storage/emulated/0/Download/SoundMind)
    targetDir ??= Directory('/storage/emulated/0/Download/SoundMind');

    try {
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    } catch (e) {
      debugPrint('DownloadService: Could not access $targetDir ($e). Falling back to app document folder.');
      final docDir = await getApplicationDocumentsDirectory();
      final fallbackDir = Directory(p.join(docDir.path, 'downloads'));
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      return fallbackDir;
    }
  }

  /// Refreshes the download directory when settings change.
  Future<void> refreshDownloadsDirectory() async {
    _downloadsDir = await _resolveDownloadsDirectory();
    debugPrint('DownloadService: Download directory updated to ${_downloadsDir?.path}');
  }

  /// Initializes directories and recovers any incomplete downloads from previous app runs.
  Future<void> init() async {
    if (_initialized) return;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      _downloadsDir = await _resolveDownloadsDirectory();

      _tempDir = await getTemporaryDirectory();
      _metadataFile = File(p.join(docDir.path, 'downloads_metadata.json'));

      await _loadAndRecoverTasks();
      await _cleanupOrphanedTempFiles();
      _initialized = true;
      debugPrint('DownloadService: Initialized with ${_tasks.length} tasks at ${_downloadsDir?.path}.');
    } catch (e, st) {
      debugPrint('DownloadService: Initialization error: $e\n$st');
    }
  }

  Future<void> _loadAndRecoverTasks() async {
    if (_metadataFile == null || !await _metadataFile!.exists()) return;

    try {
      final jsonStr = await _metadataFile!.readAsString();
      if (jsonStr.trim().isEmpty) return;

      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final task = DownloadTask.fromMap(item);

            // Recovery Check: If app was killed mid-download/queued, mark as paused
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued) {
              task.status = DownloadStatus.paused;
              task.errorMessage = null;
            } else if (task.status == DownloadStatus.converting) {
              // Interrupted mid-conversion: clean up incomplete final file and intermediate temp file
              if (task.finalFilePath != null) {
                final f = File(task.finalFilePath!);
                if (await f.exists()) {
                  try {
                    await f.delete();
                  } catch (_) {}
                }
              }
              if (task.tempFilePath != null) {
                final tf = File(task.tempFilePath!);
                if (await tf.exists()) {
                  try {
                    await tf.delete();
                  } catch (_) {}
                }
              }
              task.status = DownloadStatus.failed;
              task.errorMessage = 'Download interrupted when app closed.';
              task.bytesDownloaded = 0;
              task.progress = 0.0;
            }

            // Verify partial file status on disk
            if (task.tempFilePath != null) {
              final tempFile = File(task.tempFilePath!);
              if (task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.cancelled) {
                // Remove leftover temp file for terminal failed or cancelled tasks
                if (await tempFile.exists()) {
                  try {
                    await tempFile.delete();
                  } catch (_) {}
                }
                task.bytesDownloaded = 0;
                task.progress = 0.0;
              } else if (await tempFile.exists()) {
                task.bytesDownloaded = await tempFile.length();
                if (task.totalBytes != null && task.totalBytes! > 0) {
                  task.progress =
                      (task.bytesDownloaded / task.totalBytes!).clamp(0.0, 1.0);
                }
              } else {
                task.bytesDownloaded = 0;
                task.progress = 0.0;
              }
            }

            _tasks[task.videoId] = task;
          }
        }
      }
      _notifyAll();
    } catch (e) {
      debugPrint('DownloadService: Error reading metadata: $e');
    }
  }

  /// Scans the temporary directory for orphaned download files older than 24 hours
  /// with no matching active or paused DownloadTask record, and safely deletes them.
  Future<void> _cleanupOrphanedTempFiles() async {
    try {
      final activeOrPausedPaths = _tasks.values
          .where((t) =>
              t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.converting ||
              t.status == DownloadStatus.paused ||
              t.status == DownloadStatus.queued)
          .map((t) => t.tempFilePath)
          .whereType<String>()
          .toSet();

      final now = DateTime.now();

      // Clean temp directory
      if (_tempDir != null && await _tempDir!.exists()) {
        final entities = _tempDir!.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is File) {
            final name = p.basename(entity.path);
            final isDownloadTemp = name.endsWith('.download.tmp') ||
                name.endsWith('.tmp') ||
                name.contains('.download.');
            if (isDownloadTemp && !activeOrPausedPaths.contains(entity.path)) {
              try {
                final stat = await entity.stat();
                final ageHours = now.difference(stat.modified).inHours;
                if (ageHours >= 24) {
                  await entity.delete();
                  debugPrint(
                    'DownloadService: Cleaned up orphaned temp file (${ageHours}h old): ${entity.path}',
                  );
                }
              } catch (e) {
                debugPrint('DownloadService: Error inspecting/deleting temp file ${entity.path}: $e');
              }
            }
          }
        }
      }

      // Clean any orphaned .tmp in download folder as well
      if (_downloadsDir != null && await _downloadsDir!.exists()) {
        final dlEntities = _downloadsDir!.listSync(followLinks: false);
        for (final entity in dlEntities) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.endsWith('.tmp') || name.contains('.download.')) {
              if (!activeOrPausedPaths.contains(entity.path)) {
                try {
                  final stat = await entity.stat();
                  if (now.difference(stat.modified).inHours >= 24) {
                    await entity.delete();
                    debugPrint(
                      'DownloadService: Cleaned up orphaned temp file in downloads: ${entity.path}',
                    );
                  }
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DownloadService: Error in _cleanupOrphanedTempFiles: $e');
    }
  }

  // ─── Public API ───

  /// Picks the lowest muxed stream that satisfies the requested audio tier.
  Future<MuxedStreamInfo?> pickMuxedStreamForTier(
    String videoId,
    String qualityTier,
  ) async {
    try {
      final qualities = await _youtubeService.getAvailableQualities(videoId);
      if (qualities.isEmpty) {
        return await _youtubeService.getFreshStreamForQuality(videoId, 0);
      }

      // Sort ascending by bitrate
      final sorted = qualities.toList()
        ..sort((a, b) => a.bitrate.compareTo(b.bitrate));

      final tier = qualityTier.toLowerCase().trim();
      if (tier == DownloadQualityTier.low) {
        // Pick lowest muxed stream (saves data & time)
        return sorted.first;
      } else if (tier == DownloadQualityTier.medium) {
        // Pick middle tier muxed stream
        final midIndex = (sorted.length / 2).floor();
        return sorted[midIndex];
      } else {
        // High tier: pick highest available muxed stream
        return sorted.last;
      }
    } catch (e) {
      debugPrint('DownloadService: Error picking stream for tier $qualityTier: $e');
      return await _youtubeService.getFreshStreamForQuality(videoId, 0);
    }
  }

  /// Starts or queues an online track download.
  Future<DownloadTask> startDownload({
    required String videoId,
    required String title,
    required String artist,
    String qualityTier = DownloadQualityTier.high,
    required String outputFormat, // 'm4a' | 'mp3' | 'wav'
    int? durationSeconds,
    MuxedStreamInfo? selectedQuality,
    int? mp3BitrateKbps,
  }) async {
    await init();

    final cleanFormat = outputFormat.toLowerCase().trim();
    final validFormat =
        (cleanFormat == 'mp3' || cleanFormat == 'wav') ? cleanFormat : 'm4a';

    // If task already exists and is downloading or completed
    final existing = _tasks[videoId];
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        return existing;
      }
      if (existing.isActive || existing.status == DownloadStatus.queued) {
        return existing;
      }
      if (existing.canResume) {
        resumeDownload(videoId);
        return _tasks[videoId]!;
      }
    }

    final chosenStream = selectedQuality ??
        await pickMuxedStreamForTier(videoId, qualityTier);

    final sanitizedTitle = _sanitizeFileName(title);
    final tempPath = p.join(_tempDir!.path, '$videoId.download.tmp');
    final finalPath =
        p.join(_downloadsDir!.path, '$sanitizedTitle-$videoId.$validFormat');

    final targetKbps = DownloadQualityTier.getBitrateKbps(qualityTier);
    final estimatedBytes = durationSeconds != null
        ? DownloadTask.estimateBytes(
            qualityTier: qualityTier,
            format: validFormat,
            durationSeconds: durationSeconds,
          )
        : null;

    final task = DownloadTask(
      videoId: videoId,
      title: title,
      artist: artist,
      outputFormat: validFormat,
      qualityTier: qualityTier,
      qualityTag: chosenStream?.tag ?? 0,
      qualityBitrate:
          chosenStream?.bitrate.bitsPerSecond ?? (targetKbps * 1000),
      mp3BitrateKbps: mp3BitrateKbps ?? targetKbps,
      durationSeconds: durationSeconds,
      estimatedBytes: estimatedBytes,
      status: DownloadStatus.queued,
      progress: 0.0,
      bytesDownloaded: 0,
      totalBytes: chosenStream?.size.totalBytes,
      tempFilePath: tempPath,
      finalFilePath: finalPath,
      streamUrl: chosenStream?.url.toString(),
    );

    _tasks[videoId] = task;
    _retryCounts[videoId] = 0;
    _saveMetadataImmediate();
    _notify(task);
    _processQueue();

    return task;
  }

  /// Pauses an active or queued download.
  void pauseDownload(String videoId) {
    final task = _tasks[videoId];
    if (task == null) return;

    if (task.status == DownloadStatus.downloading) {
      _cancelTokens[videoId]?.cancel('paused_by_user');
      _cancelTokens.remove(videoId);
      task.status = DownloadStatus.paused;
      _saveMetadataImmediate();
      _notify(task);
      _processQueue();
    } else if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      _saveMetadataImmediate();
      _notify(task);
      _processQueue();
    }
  }

  /// Resumes a paused or failed download.
  void resumeDownload(String videoId) {
    final task = _tasks[videoId];
    if (task == null || !task.canResume) return;

    task.errorMessage = null;
    task.status = DownloadStatus.queued;
    _retryCounts[videoId] = 0;
    _saveMetadataImmediate();
    _notify(task);
    _processQueue();
  }

  /// Retries a failed or cancelled download task.
  Future<void> retryDownload(String videoId) async {
    final task = _tasks[videoId];
    if (task == null) return;

    task.errorMessage = null;
    task.status = DownloadStatus.queued;
    task.progress = 0.0;
    task.bytesDownloaded = 0;
    _retryCounts[videoId] = 0;
    _saveMetadataImmediate();
    _notify(task);
    _processQueue();
  }

  /// Cancels a download and cleans up its temporary and partial files.
  void cancelDownload(String videoId) {
    final task = _tasks[videoId];
    if (task == null) return;

    _cancelTokens[videoId]?.cancel('cancelled_by_user');
    _cancelTokens.remove(videoId);
    _retryCounts.remove(videoId);

    // Clean up partial temp file
    if (task.tempFilePath != null) {
      final tempFile = File(task.tempFilePath!);
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }

    // Clean up partial final file if cancelled mid-conversion
    if (task.finalFilePath != null) {
      final finalFile = File(task.finalFilePath!);
      if (finalFile.existsSync()) {
        try {
          finalFile.deleteSync();
        } catch (_) {}
      }
    }

    task.status = DownloadStatus.cancelled;
    task.bytesDownloaded = 0;
    task.progress = 0.0;
    _saveMetadataImmediate();
    _notify(task);
    _processQueue();
  }

  /// Observes updates for a specific download task.
  Stream<DownloadTask> watchDownload(String videoId) {
    return _taskUpdateController.stream
        .where((task) => task.videoId == videoId);
  }

  /// Observes all download tasks.
  Stream<List<DownloadTask>> watchAllDownloads() {
    return _allTasksController.stream;
  }

  /// Gets the current state of a task.
  DownloadTask? getTask(String videoId) => _tasks[videoId];

  /// Gets all tracked download tasks.
  List<DownloadTask> getAllTasks() => _tasks.values.toList();

  // ─── Queue Execution ───

  void _processQueue() {
    final activeCount = _tasks.values
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.converting)
        .length;

    if (activeCount >= maxConcurrentDownloads) return;

    final queuedTasks = _tasks.values
        .where((t) => t.status == DownloadStatus.queued)
        .toList();

    for (final task in queuedTasks) {
      final currentActive = _tasks.values
          .where((t) =>
              t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.converting)
          .length;
      if (currentActive >= maxConcurrentDownloads) break;

      _executeDownload(task);
    }
  }

  Future<void> _executeDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    _notify(task);
    _saveMetadataImmediate();

    final cancelToken = CancelToken();
    _cancelTokens[task.videoId] = cancelToken;

    final tempFile = File(task.tempFilePath!);
    RandomAccessFile? raf;

    try {
      // 1. Determine existing byte offset
      int startByte = 0;
      if (await tempFile.exists()) {
        startByte = await tempFile.length();
      }

      // 2. Refresh Stream URL & Verify Content-Length
      String? currentUrl = task.streamUrl;
      int? expectedTotal = task.totalBytes;

      // If URL is missing, or if we are resuming/retrying, obtain fresh stream info
      if (currentUrl == null || (_retryCounts[task.videoId] ?? 0) > 0) {
        debugPrint('DownloadService: Fetching fresh stream URL for ${task.videoId}...');
        final freshStream = await _youtubeService.getFreshStreamForQuality(
          task.videoId,
          task.qualityTag,
        );

        if (freshStream != null) {
          final newTotal = freshStream.size.totalBytes;
          currentUrl = freshStream.url.toString();
          task.streamUrl = currentUrl;

          // CONTENT-LENGTH VERIFICATION BEFORE RESUME:
          // If the refreshed stream URL size does not match the original totalBytes,
          // resume is unsafe (stream encoding differs). Truncate and restart from scratch!
          if (expectedTotal != null &&
              expectedTotal > 0 &&
              newTotal != expectedTotal &&
              startByte > 0) {
            debugPrint(
              'DownloadService: Content-Length mismatch ($newTotal vs $expectedTotal). Restarting from scratch.',
            );
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            startByte = 0;
            task.bytesDownloaded = 0;
            expectedTotal = newTotal;
            task.totalBytes = newTotal;
          } else {
            expectedTotal = newTotal;
            task.totalBytes = newTotal;
          }
        }
      }

      if (currentUrl == null) {
        throw Exception('Stream URL unavailable. Video may be restricted.');
      }

      // 3. Prepare headers for Range request
      final options = Options(
        headers: {
          ..._playbackHeaders,
          if (startByte > 0) 'Range': 'bytes=$startByte-',
        },
        responseType: ResponseType.stream,
        validateStatus: (status) =>
            status != null && (status == 200 || status == 206),
      );

      final response = await _dio.get<ResponseBody>(
        currentUrl,
        options: options,
        cancelToken: cancelToken,
      );

      final isPartial = response.statusCode == 206;

      // Further verify Content-Range if returned
      if (isPartial) {
        final contentRange = response.headers.value('content-range');
        if (contentRange != null && contentRange.contains('/')) {
          final totalFromHeader =
              int.tryParse(contentRange.split('/').last.trim());
          if (totalFromHeader != null &&
              expectedTotal != null &&
              totalFromHeader != expectedTotal) {
            debugPrint(
              'DownloadService: Content-Range total ($totalFromHeader) != expected ($expectedTotal). Restarting.',
            );
            response.data?.stream.drain();
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            task.bytesDownloaded = 0;
            task.totalBytes = totalFromHeader;
            _executeDownload(task);
            return;
          }
        }
        raf = await tempFile.open(mode: FileMode.append);
      } else {
        // Server returned 200 (Full content, not partial) -> write from start
        if (startByte > 0) {
          debugPrint('DownloadService: Server returned 200 instead of 206. Resetting from byte 0.');
        }
        startByte = 0;
        task.bytesDownloaded = 0;
        final lenStr = response.headers.value('content-length');
        if (lenStr != null) {
          task.totalBytes = int.tryParse(lenStr) ?? task.totalBytes;
        }
        raf = await tempFile.open(mode: FileMode.write);
      }

      task.bytesDownloaded = startByte;

      // 4. Stream response to disk incrementally
      await for (final chunk in response.data!.stream) {
        if (cancelToken.isCancelled) break;
        await raf.writeFrom(chunk);
        task.bytesDownloaded += chunk.length;

        if (task.totalBytes != null && task.totalBytes! > 0) {
          task.progress =
              (task.bytesDownloaded / task.totalBytes!).clamp(0.0, 1.0);
        }

        _notify(task);
        _maybeSaveProgress();
      }

      await raf.close();
      raf = null;

      if (cancelToken.isCancelled) return;

      // 5. Download complete -> Perform format conversion or finalization
      _cancelTokens.remove(task.videoId);
      _retryCounts.remove(task.videoId);

      await _finalizeOrConvert(task);
    } catch (e, stack) {
      if (raf != null) {
        try {
          await raf.close();
        } catch (_) {}
      }

      if (cancelToken.isCancelled) {
        debugPrint('DownloadService: Download cancelled/paused for ${task.videoId}');
        return;
      }

      // Check if transient error and retry with exponential backoff
      final retryCount = _retryCounts[task.videoId] ?? 0;
      final isForbidden = e is DioException &&
          (e.response?.statusCode == 403 || e.response?.statusCode == 416);

      if (isForbidden) {
        // Clear cached URL to force refresh on next attempt
        task.streamUrl = null;
      }

      if (retryCount < 3) {
        _retryCounts[task.videoId] = retryCount + 1;
        final backoffSecs = [2, 5, 10][retryCount];
        debugPrint(
          'DownloadService: Transient error ($e). Retrying in ${backoffSecs}s (attempt ${retryCount + 1}/3)...',
        );

        await Future.delayed(Duration(seconds: backoffSecs));
        if (task.status == DownloadStatus.downloading) {
          _executeDownload(task);
          return;
        }
      }

      // Definitive failure
      _cancelTokens.remove(task.videoId);
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      task.status = DownloadStatus.failed;
      task.errorMessage = _getUserFriendlyError(e);

      // Clean up partial temp file when retries exhausted
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      task.bytesDownloaded = 0;
      task.progress = 0.0;

      _saveMetadataImmediate();
      _notify(task);
      _processQueue();
    }
  }

  // ─── Format Conversion & Finalization ───

  Future<int> _detectSourceAudioBitrateKbps(String tempPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(tempPath);
      final mediaInfo = session.getMediaInformation();
      if (mediaInfo != null) {
        final streams = mediaInfo.getStreams();
        for (final stream in streams) {
          final type = stream.getType();
          if (type?.toLowerCase() == 'audio') {
            final bitrateStr = stream.getBitrate();
            if (bitrateStr != null) {
              final bitrateBps = int.tryParse(bitrateStr);
              if (bitrateBps != null && bitrateBps > 0) {
                final kbps = (bitrateBps / 1000).round();
                debugPrint('DownloadService: Detected source audio bitrate: ${kbps}kbps');
                return kbps;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DownloadService: ffprobe inspection error: $e');
    }
    // Default fallback if ffprobe cannot read stream bitrate
    return 128;
  }

  String _buildFfmpegCommand({
    required DownloadTask task,
    required String tempPath,
    required String finalPath,
    required int sourceAudioBitrateKbps,
  }) {
    final requestedKbps =
        DownloadQualityTier.getBitrateKbps(task.qualityTier);
    // Never allow selecting a target bitrate HIGHER than the source muxed stream's actual audio bitrate
    final targetKbps = (requestedKbps > sourceAudioBitrateKbps)
        ? sourceAudioBitrateKbps
        : requestedKbps;

    final format = task.outputFormat.toLowerCase().trim();

    if (format == 'mp3') {
      return '-y -i "$tempPath" -vn -c:a libmp3lame -b:a ${targetKbps}k "$finalPath"';
    } else if (format == 'wav') {
      return '-y -i "$tempPath" -vn -c:a pcm_s16le "$finalPath"';
    } else {
      // M4A:
      // If targetKbps >= sourceAudioBitrateKbps: fast stream copy, no re-encode, strips video
      // If lower bitrate than source requested (common for Low 64k): re-encode audio at target bitrate
      if (targetKbps >= sourceAudioBitrateKbps) {
        return '-y -i "$tempPath" -vn -c:a copy "$finalPath"';
      } else {
        return '-y -i "$tempPath" -vn -c:a aac -b:a ${targetKbps}k "$finalPath"';
      }
    }
  }

  Future<void> _finalizeOrConvert(DownloadTask task) async {
    final tempFile = File(task.tempFilePath!);
    if (!await tempFile.exists()) {
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Downloaded temp file missing.';
      _saveMetadataImmediate();
      _notify(task);
      _processQueue();
      return;
    }

    final finalFile = File(task.finalFilePath!);

    // ALWAYS run FFmpeg to strip video track (-vn) across EVERY format (M4A, MP3, WAV)
    task.status = DownloadStatus.converting;
    _notify(task);
    _saveMetadataImmediate();

    try {
      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      // 1. Detect source audio bitrate via ffprobe
      final sourceBitrateKbps =
          await _detectSourceAudioBitrateKbps(task.tempFilePath!);

      // 2. Build FFmpeg command with video-stripping and bitrate control
      final ffmpegCommand = _buildFfmpegCommand(
        task: task,
        tempPath: task.tempFilePath!,
        finalPath: task.finalFilePath!,
        sourceAudioBitrateKbps: sourceBitrateKbps,
      );

      debugPrint('DownloadService: Executing FFmpeg: $ffmpegCommand');
      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        if (await finalFile.exists() && await finalFile.length() > 0) {
          // Success: delete intermediate temp file
          try {
            await tempFile.delete();
          } catch (_) {}

          task.totalBytes = await finalFile.length();
          task.bytesDownloaded = task.totalBytes!;
          task.status = DownloadStatus.completed;
          task.progress = 1.0;
          task.errorMessage = null;
          debugPrint(
            'DownloadService: Audio finalized (${task.outputFormat}, ${task.totalBytes} bytes): ${task.finalFilePath}',
          );
          DownloadNotificationService.instance.showCompleted(task);
        } else {
          throw Exception('Output file was not created by FFmpeg.');
        }
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint(
          'DownloadService: FFmpeg failed (code: $returnCode). Logs: $logs',
        );
        throw Exception('FFmpeg process returned error code $returnCode');
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('DownloadService: Conversion/finalization error: $e');
      // Clean up corrupt/partial final output file
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }
      // Clean up intermediate temp file on conversion failure
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      task.bytesDownloaded = 0;
      task.progress = 0.0;
      task.status = DownloadStatus.failed;
      task.errorMessage = 'Audio conversion failed. Tap to retry.';
      DownloadNotificationService.instance.showFailed(task);
    }

    _saveMetadataImmediate();
    _notify(task);
    _processQueue();
  }

  /// Removes a task from the download list without deleting the audio file on disk.
  Future<void> removeTaskFromList(String videoId) async {
    final task = _tasks[videoId];
    cancelDownload(videoId);
    if (task != null && task.tempFilePath != null) {
      try {
        final tempFile = File(task.tempFilePath!);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
    _tasks.remove(videoId);
    await _saveMetadataImmediate();
    _notifyAll();
  }

  /// Deletes a task from the list and deletes its file from device storage.
  Future<void> deleteTaskAndFile(String videoId) async {
    final task = _tasks[videoId];
    cancelDownload(videoId);
    if (task != null) {
      if (task.finalFilePath != null) {
        try {
          final file = File(task.finalFilePath!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('DownloadService: Error deleting final file: $e');
        }
      }
      if (task.tempFilePath != null) {
        try {
          final tempFile = File(task.tempFilePath!);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          debugPrint('DownloadService: Error deleting temp file: $e');
        }
      }
    }
    _tasks.remove(videoId);
    await _saveMetadataImmediate();
    _notifyAll();
  }

  // ─── Helpers & Persistence ───

  void _notify(DownloadTask task) {
    if (!_taskUpdateController.isClosed) {
      _taskUpdateController.add(task);
    }
    _notifyAll();
  }

  void _notifyAll() {
    final allList = _tasks.values.toList();
    if (!_allTasksController.isClosed) {
      _allTasksController.add(allList);
    }

    final active = allList
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.converting)
        .toList();
    DownloadNotificationService.instance.showOrUpdateProgress(active);
  }

  void _maybeSaveProgress() {
    final now = DateTime.now();
    if (now.difference(_lastProgressSave).inSeconds >= 2) {
      _lastProgressSave = now;
      _debounceSaveMetadata();
    }
  }

  void _debounceSaveMetadata() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 1500), () {
      _saveMetadataImmediate();
    });
  }

  Future<void> _saveMetadataImmediate() async {
    if (_metadataFile == null) return;
    try {
      final list = _tasks.values.map((t) => t.toMap()).toList();
      await _metadataFile!.writeAsString(jsonEncode(list), flush: true);
    } catch (e) {
      debugPrint('DownloadService: Error saving metadata: $e');
    }
  }

  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _getUserFriendlyError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out. Check your internet connection.';
        case DioExceptionType.connectionError:
          return 'No internet connection.';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 403 || code == 410) {
            return 'This track is temporarily unavailable from source.';
          }
          return 'Server error ($code). Tap to retry.';
        default:
          return 'Download interrupted. Tap to retry.';
      }
    }
    return 'Download failed. Tap to retry.';
  }

  void dispose() {
    _saveDebounceTimer?.cancel();
    _taskUpdateController.close();
    _allTasksController.close();
    _dio.close();
    _youtubeService.dispose();
  }
}
