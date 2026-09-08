// audio_scanner_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../classifier/audio_classifier.dart';
import '../classifier/classification_result.dart';
import '../classifier/hybrid_audio_classifier.dart';
import '../models/audio_category.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../utils/song_heuristics.dart';
import 'notification_service.dart';

/// Progress state emitted during device audio scanning.
class ScanProgress {
  final int totalCount;
  final int scannedCount;
  final int classifiedMusicCount;
  final int classifiedOtherCount;
  final String currentFilePath;
  final bool isScanning;
  final String? error;

  const ScanProgress({
    this.totalCount = 0,
    this.scannedCount = 0,
    this.classifiedMusicCount = 0,
    this.classifiedOtherCount = 0,
    this.currentFilePath = '',
    this.isScanning = false,
    this.error,
  });

  double get percentage => totalCount > 0 ? (scannedCount / totalCount).clamp(0.0, 1.0) : 0.0;
}

/// Standalone candidate model passed into background isolate for batch classification.
class _CandidateData {
  final int? id;
  final String filePath;
  final String fileName;
  final String title;
  final String artist;
  final String? album;
  final String? genre;
  final int? duration;
  final int? fileSize;
  final int? dateAdded;
  final int? dateModified;
  final bool userOverride;
  final AudioCategory audioCategory;
  final bool isFavorite;
  final int playCount;
  final DateTime? lastPlayed;

  const _CandidateData({
    this.id,
    required this.filePath,
    required this.fileName,
    required this.title,
    required this.artist,
    this.album,
    this.genre,
    this.duration,
    this.fileSize,
    this.dateAdded,
    this.dateModified,
    required this.userOverride,
    required this.audioCategory,
    required this.isFavorite,
    required this.playCount,
    this.lastPlayed,
  });

  Track toTrack() {
    return Track(
      id: id,
      filePath: filePath,
      fileName: fileName,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      duration: duration,
      fileSize: fileSize,
      dateAdded: dateAdded,
      dateModified: dateModified,
      lastScanned: DateTime.now().millisecondsSinceEpoch,
      isDownloaded: false,
      userOverride: userOverride,
      audioCategory: audioCategory,
      isFavorite: isFavorite,
      playCount: playCount,
      lastPlayed: lastPlayed,
    );
  }
}

/// Top-level isolate worker for batch audio classification.
/// Running this in an isolate keeps the UI thread buttery smooth and bounds memory usage.
Future<List<Map<String, dynamic>>> _classifyBatchIsolateWorker(List<Map<String, dynamic>> rawBatch) async {
  final classifier = HybridAudioClassifier();
  final results = <Map<String, dynamic>>[];

  for (final raw in rawBatch) {
    try {
      final candidate = _CandidateData(
        id: raw['id'] as int?,
        filePath: raw['filePath'] as String,
        fileName: raw['fileName'] as String,
        title: raw['title'] as String,
        artist: raw['artist'] as String,
        album: raw['album'] as String?,
        genre: raw['genre'] as String?,
        duration: raw['duration'] as int?,
        fileSize: raw['fileSize'] as int?,
        dateAdded: raw['dateAdded'] as int?,
        dateModified: raw['dateModified'] as int?,
        userOverride: (raw['userOverride'] as bool?) ?? false,
        audioCategory: AudioCategory.fromDbValue(raw['audioCategory'] as String?),
        isFavorite: (raw['isFavorite'] as bool?) ?? false,
        playCount: (raw['playCount'] as int?) ?? 0,
        lastPlayed: raw['lastPlayed'] != null ? DateTime.fromMillisecondsSinceEpoch(raw['lastPlayed'] as int) : null,
      );

      final trackCandidate = candidate.toTrack();

      // Classify deterministically
      final classification = await classifier.classify(trackCandidate);

      // Layered junk heuristic filter
      final bool isJunk = !trackCandidate.userOverride && isJunkTrack(trackCandidate);
      final bool effectiveIsMusic = classification.isMusic && !isJunk;
      final effectiveCategory = (isJunk && classification.category == AudioCategory.music)
          ? AudioCategory.recording
          : classification.category;

      final classifiedTrack = trackCandidate.copyWith(
        audioCategory: effectiveCategory,
        confidence: isJunk ? 0.90 : classification.confidence,
        classificationSource: isJunk ? ClassificationSource.heuristic : classification.source,
        isMusic: effectiveIsMusic,
      );

      results.add(classifiedTrack.toMap());
    } catch (e) {
      // Safe isolation: single corrupt file metadata never terminates isolate or scan
      debugPrint('IsolateWorker: Skipped corrupt file during classification: $e');
    }
  }

  return results;
}

/// Smart incremental scanner that discovers, classifies, and persists local audio files.
/// Features:
/// - Full multi-storage coverage (Internal storage, SD cards, and Download directories).
/// - Memory-bounded batching (100 items per batch committed directly to SQLite).
/// - Heavy classification offloaded to a background isolate via `compute()`.
/// - Individual file try/catch protection against corrupt files and out-of-bounds tags.
/// - Persistent scan checkpoints in SharedPreferences to safely recover from interruptions.
/// - Single UI notification upon completion to eliminate UI query churn during scanning.
class AudioScannerService extends ChangeNotifier {
  AudioScannerService._internal();
  static final AudioScannerService instance = AudioScannerService._internal();

  static const String _prefKeyCheckpoint = 'sm_scan_checkpoint';
  static const int _batchSize = 100;

  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioClassifier _classifier = HybridAudioClassifier();
  final AudioRepository _repository = AudioRepository.instance;

  ScanProgress _currentProgress = const ScanProgress();
  ScanProgress get currentProgress => _currentProgress;

  final StreamController<ScanProgress> _progressController = StreamController<ScanProgress>.broadcast();
  Stream<ScanProgress> get progressStream => _progressController.stream;

  bool get isScanning => _currentProgress.isScanning;

  /// Checks whether required audio/media permissions are already granted without prompting dialogs.
  Future<bool> checkPermissions() async {
    try {
      if (await Permission.audio.isGranted) return true;
    } catch (_) {}
    try {
      if (await Permission.storage.isGranted) return true;
    } catch (_) {}
    try {
      if (await _audioQuery.permissionsStatus()) return true;
    } catch (_) {}
    return false;
  }

  /// Requests required storage and media permissions for the device's Android version.
  Future<bool> requestPermissions() async {
    if (await checkPermissions()) {
      return true;
    }

    bool hasPermission = false;

    // Android 13+ (API 33+) requires READ_MEDIA_AUDIO via Permission.audio
    try {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        hasPermission = true;
      }
    } catch (_) {}

    // Android 12 and below (API <= 32) requires READ_EXTERNAL_STORAGE via Permission.storage
    if (!hasPermission) {
      try {
        final storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted) {
          hasPermission = true;
        }
      } catch (_) {}
    }

    // Fallback check on OnAudioQuery permission handler
    if (!hasPermission) {
      try {
        hasPermission = await _audioQuery.permissionsStatus();
        if (!hasPermission) {
          hasPermission = await _audioQuery.permissionsRequest();
        }
      } catch (_) {}
    }

    if (!hasPermission) {
      NotificationService.instance.add(
        'Permission Required',
        'Audio media access is needed to index your songs. Please grant permission in App Settings.',
        type: 'error',
      );
    }
    return hasPermission;
  }

  /// Discovers audio files across all mounted storage volumes (SD card, Internal, Downloads)
  /// that may not yet be indexed by MediaStore.
  Future<List<File>> _discoverAdditionalStorageFiles(Set<String> knownPaths) async {
    final extraFiles = <File>[];
    if (!Platform.isAndroid) return extraFiles;

    const audioExtensions = {
      '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma'
    };

    final volumeRoots = <String>{};

    // 1. Primary internal storage root
    const internalPath = '/storage/emulated/0';
    if (await Directory(internalPath).exists()) {
      volumeRoots.add(internalPath);
    }

    // 2. Discover removable SD card volumes from getExternalStorageDirectories()
    try {
      final appDirs = await getExternalStorageDirectories();
      if (appDirs != null) {
        for (final dir in appDirs) {
          final pNorm = dir.path.replaceAll('\\', '/');
          final androidIdx = pNorm.indexOf('/Android/');
          if (androidIdx != -1) {
            volumeRoots.add(pNorm.substring(0, androidIdx));
          }
        }
      }
    } catch (_) {}

    // 3. Inspect /storage directory entries for mounted SD cards (e.g. /storage/XXXX-XXXX)
    try {
      final storageDir = Directory('/storage');
      if (await storageDir.exists()) {
        final entries = storageDir.listSync(followLinks: false);
        for (final entry in entries) {
          if (entry is Directory) {
            final name = p.basename(entry.path);
            if (name != 'self' && name != 'emulated' && name != 'knox' && !name.startsWith('.')) {
              volumeRoots.add(entry.path);
            }
          }
        }
      }
    } catch (_) {}

    // Target subdirectories that typically hold music and downloaded songs
    const scanFolders = [
      'Music',
      'Download',
      'Downloads',
      'Audio',
      'Podcasts',
      'Audiobooks',
      'Recordings',
      'Ringtones',
      'Notifications',
    ];

    for (final root in volumeRoots) {
      for (final folder in scanFolders) {
        try {
          final dir = Directory(p.join(root, folder));
          if (await dir.exists()) {
            _crawlDirectory(dir, audioExtensions, knownPaths, extraFiles, maxDepth: 4);
          }
        } catch (_) {}
      }
    }

    return extraFiles;
  }

  void _crawlDirectory(
    Directory dir,
    Set<String> extensions,
    Set<String> knownPaths,
    List<File> result, {
    required int maxDepth,
    int currentDepth = 0,
  }) {
    if (currentDepth > maxDepth) return;

    try {
      final entries = dir.listSync(followLinks: false);
      for (final entry in entries) {
        try {
          if (entry is File) {
            final ext = p.extension(entry.path).toLowerCase();
            if (extensions.contains(ext)) {
              final normPath = entry.path.replaceAll('\\', '/');
              if (!knownPaths.contains(normPath)) {
                result.add(entry);
                knownPaths.add(normPath);
              }
            }
          } else if (entry is Directory) {
            final name = p.basename(entry.path);
            if (!name.startsWith('.') && name != 'Android') {
              _crawlDirectory(
                entry,
                extensions,
                knownPaths,
                result,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1,
              );
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void>? _activeScanFuture;

  /// Runs the full smart incremental audio scan.
  /// If a scan is already running, returns the existing active scan Future.
  Future<void> scan({bool isRescan = false}) {
    if (_activeScanFuture != null) {
      return _activeScanFuture!;
    }
    final future = _performScan(isRescan: isRescan).whenComplete(() {
      _activeScanFuture = null;
    });
    _activeScanFuture = future;
    return future;
  }

  Future<void> _performScan({bool isRescan = false}) async {
    final hasPerm = await requestPermissions();
    if (!hasPerm) {
      _updateProgress(const ScanProgress(isScanning: false, error: 'Permission denied'));
      return;
    }

    _updateProgress(const ScanProgress(isScanning: true));

    final prefs = await SharedPreferences.getInstance();

    // Check for previous interrupted scan checkpoint
    int checkpointStartIndex = 0;
    try {
      final checkpointJson = prefs.getString(_prefKeyCheckpoint);
      if (checkpointJson != null && !isRescan) {
        final Map<String, dynamic> cp = jsonDecode(checkpointJson);
        checkpointStartIndex = (cp['scannedCount'] as num?)?.toInt() ?? 0;
        debugPrint('AudioScannerService: Detected previous incomplete scan at index $checkpointStartIndex. Resuming...');
      }
    } catch (_) {
      checkpointStartIndex = 0;
    }

    try {
      // 1. Query Android MediaStore songs via OnAudioQuery
      List<SongModel> songs = [];
      try {
        songs = await _audioQuery.querySongs(
          ignoreCase: true,
          orderType: OrderType.ASC_OR_SMALLER,
          sortType: null,
          uriType: UriType.EXTERNAL,
        );
      } catch (e) {
        debugPrint('AudioScannerService: querySongs returned error: $e');
        songs = [];
      }

      final activePathsOnDevice = <String>{};
      final Set<String> knownPaths = {};

      for (final s in songs) {
        if (s.data.isNotEmpty) {
          final norm = s.data.replaceAll('\\', '/');
          activePathsOnDevice.add(norm);
          knownPaths.add(norm);
        }
      }

      // 2. Discover physical storage files across all volumes (SD card + Download folder)
      // that MediaStore may not have indexed
      final additionalFiles = await _discoverAdditionalStorageFiles(knownPaths);
      for (final f in additionalFiles) {
        activePathsOnDevice.add(f.path.replaceAll('\\', '/'));
      }

      final totalDiscovered = songs.length + additionalFiles.length;
      final existingTrackMap = await _repository.getExistingTrackMap();
      final excludedFolders = await _repository.getExcludedFolders();

      int scannedCount = 0;
      int musicCount = 0;
      int otherCount = 0;

      final pendingBatchCandidates = <Map<String, dynamic>>[];
      final directUpsertBatch = <Track>[];

      // Helper to flush direct (already classified/cached) tracks
      Future<void> flushDirectBatch() async {
        if (directUpsertBatch.isNotEmpty) {
          await _repository.batchUpsertTracks(List.from(directUpsertBatch), notify: false);
          directUpsertBatch.clear();
          // Yield to event loop to allow UI read queries to run without lock starvation
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      // Helper to process and flush candidate batch through background isolate
      Future<void> flushIsolateBatch() async {
        if (pendingBatchCandidates.isEmpty) return;

        List<Map<String, dynamic>> classifiedMaps = [];
        try {
          classifiedMaps = await compute<List<Map<String, dynamic>>, List<Map<String, dynamic>>>(
            _classifyBatchIsolateWorker,
            List<Map<String, dynamic>>.from(pendingBatchCandidates),
          );
        } catch (e) {
          debugPrint('AudioScannerService: compute isolate batch failed, falling back inline: $e');
          // Inline fallback if isolate instantiation fails
          for (final raw in pendingBatchCandidates) {
            try {
              final track = Track(
                id: raw['id'] as int?,
                filePath: raw['filePath'] as String,
                fileName: raw['fileName'] as String,
                title: raw['title'] as String,
                artist: raw['artist'] as String,
                album: raw['album'] as String?,
                genre: raw['genre'] as String?,
                duration: raw['duration'] as int?,
                fileSize: raw['fileSize'] as int?,
                dateAdded: raw['dateAdded'] as int?,
                dateModified: raw['dateModified'] as int?,
                userOverride: (raw['userOverride'] as bool?) ?? false,
                audioCategory: AudioCategory.fromDbValue(raw['audioCategory'] as String?),
              );
              final classification = await _classifier.classify(track);
              final bool isJunk = !track.userOverride && isJunkTrack(track);
              final bool effectiveIsMusic = classification.isMusic && !isJunk;
              final effectiveCategory = (isJunk && classification.category == AudioCategory.music)
                  ? AudioCategory.recording
                  : classification.category;

              final classified = track.copyWith(
                audioCategory: effectiveCategory,
                confidence: isJunk ? 0.90 : classification.confidence,
                classificationSource: isJunk ? ClassificationSource.heuristic : classification.source,
                isMusic: effectiveIsMusic,
              );
              classifiedMaps.add(classified.toMap());
            } catch (_) {}
          }
        }

        final tracksToSave = classifiedMaps.map((m) => Track.fromMap(m)).toList();
        for (final t in tracksToSave) {
          if (t.isMusic) {
            musicCount++;
          } else {
            otherCount++;
          }
        }

        await _repository.batchUpsertTracks(tracksToSave, notify: false);
        pendingBatchCandidates.clear();
        // Yield to event loop to allow UI read queries to run without lock starvation
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Save progress checkpoint to SharedPreferences
        await prefs.setString(_prefKeyCheckpoint, jsonEncode({
          'scannedCount': scannedCount,
          'musicCount': musicCount,
          'otherCount': otherCount,
          'totalDiscovered': totalDiscovered,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));

        _updateProgress(ScanProgress(
          totalCount: totalDiscovered,
          scannedCount: scannedCount,
          classifiedMusicCount: musicCount,
          classifiedOtherCount: otherCount,
          isScanning: true,
        ));
      }

      // ─── Process MediaStore songs ───
      for (final song in songs) {
        try {
          final filePath = song.data.replaceAll('\\', '/');

          // Check if folder is excluded
          final folder = _extractFolder(filePath);
          if (excludedFolders.contains(folder)) {
            scannedCount++;
            continue;
          }

          final existing = existingTrackMap[filePath];
          final fileModified = song.dateModified;
          final fileSize = song.size;

          // INCREMENTAL CHECK:
          // If file is already in DB and unchanged, bypass re-classification
          if (existing != null &&
              existing.dateModified != null &&
              fileModified != null &&
              existing.dateModified == fileModified &&
              existing.fileSize == fileSize) {
            if (existing.isMusic && !existing.userOverride && isJunkTrack(existing)) {
              final corrected = existing.copyWith(
                isMusic: false,
                audioCategory: AudioCategory.recording,
                classificationSource: ClassificationSource.heuristic,
              );
              directUpsertBatch.add(corrected);
              otherCount++;
            } else {
              if (existing.isMusic) {
                musicCount++;
              } else {
                otherCount++;
              }
            }
            scannedCount++;

            if (directUpsertBatch.length >= _batchSize) {
              await flushDirectBatch();
            }
            continue;
          }

          // Queue candidate for isolate batch classification
          pendingBatchCandidates.add({
            'id': song.id,
            'filePath': filePath,
            'fileName': song.displayName,
            'title': song.title.isNotEmpty
                ? song.title
                : (song.displayNameWOExt.isNotEmpty ? song.displayNameWOExt : 'Unknown Title'),
            'artist': (song.artist != null && song.artist!.isNotEmpty) ? song.artist! : 'Unknown Artist',
            'album': song.album,
            'genre': song.genre,
            'duration': song.duration,
            'fileSize': song.size,
            'dateAdded': song.dateAdded,
            'dateModified': song.dateModified,
            'userOverride': existing?.userOverride ?? false,
            'audioCategory': existing?.userOverride == true ? existing!.audioCategory.dbValue : null,
            'isFavorite': existing?.isFavorite ?? false,
            'playCount': existing?.playCount ?? 0,
            'lastPlayed': existing?.lastPlayed?.millisecondsSinceEpoch,
          });

          scannedCount++;

          if (pendingBatchCandidates.length >= _batchSize) {
            await flushDirectBatch();
            await flushIsolateBatch();
          }
        } catch (e) {
          debugPrint('AudioScanner: Error queueing MediaStore song ${song.data}: $e');
          scannedCount++;
        }
      }

      // ─── Process additional physical files (SD card, Download folder) ───
      for (final file in additionalFiles) {
        try {
          final filePath = file.path.replaceAll('\\', '/');

          final folder = _extractFolder(filePath);
          if (excludedFolders.contains(folder)) {
            scannedCount++;
            continue;
          }

          final stat = await file.stat();
          final fileSize = stat.size;
          final dateModified = stat.modified.millisecondsSinceEpoch;
          final fileName = p.basename(filePath);
          final title = p.basenameWithoutExtension(filePath);

          final existing = existingTrackMap[filePath];
          if (existing != null &&
              existing.fileSize == fileSize &&
              existing.dateModified != null &&
              (existing.dateModified! - dateModified).abs() < 5000) {
            if (existing.isMusic) {
              musicCount++;
            } else {
              otherCount++;
            }
            scannedCount++;
            continue;
          }

          pendingBatchCandidates.add({
            'id': null,
            'filePath': filePath,
            'fileName': fileName,
            'title': title.isNotEmpty ? title : 'Unknown Title',
            'artist': 'Unknown Artist',
            'album': null,
            'genre': null,
            'duration': null,
            'fileSize': fileSize,
            'dateAdded': stat.changed.millisecondsSinceEpoch,
            'dateModified': dateModified,
            'userOverride': existing?.userOverride ?? false,
            'audioCategory': existing?.userOverride == true ? existing!.audioCategory.dbValue : null,
            'isFavorite': existing?.isFavorite ?? false,
            'playCount': existing?.playCount ?? 0,
            'lastPlayed': existing?.lastPlayed?.millisecondsSinceEpoch,
          });

          scannedCount++;

          if (pendingBatchCandidates.length >= _batchSize) {
            await flushDirectBatch();
            await flushIsolateBatch();
          }
        } catch (e) {
          debugPrint('AudioScanner: Error queueing physical file ${file.path}: $e');
          scannedCount++;
        }
      }

      // Flush any remaining tracks
      await flushDirectBatch();
      await flushIsolateBatch();

      // Clean up deleted files from database
      final deletedPaths = existingTrackMap.keys.where((p) => !activePathsOnDevice.contains(p)).toList();
      if (deletedPaths.isNotEmpty) {
        await _repository.batchDeleteByPaths(deletedPaths);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Clear checkpoint on successful completion
      await prefs.remove(_prefKeyCheckpoint);

      // Single UI notification when scan completes to prevent query churn
      _repository.notifyListeners();

      _updateProgress(ScanProgress(
        totalCount: totalDiscovered,
        scannedCount: scannedCount,
        classifiedMusicCount: musicCount,
        classifiedOtherCount: otherCount,
        isScanning: false,
      ));

      NotificationService.instance.add(
        'Library Scan Complete',
        'Discovered $totalDiscovered files across all storage: $musicCount Music, $otherCount Other.',
        type: 'system',
      );
    } catch (e) {
      debugPrint('AudioScannerService: Scan error: $e');
      _updateProgress(ScanProgress(isScanning: false, error: e.toString()));
    }
  }

  void _updateProgress(ScanProgress progress) {
    _currentProgress = progress;
    _progressController.add(progress);
    notifyListeners();
  }

  String _extractFolder(String? path) {
    if (path == null || path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.length > 1) {
      return parts.sublist(0, parts.length - 1).join('/');
    }
    return '';
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}
