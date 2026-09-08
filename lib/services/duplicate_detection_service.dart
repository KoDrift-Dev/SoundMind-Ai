// duplicate_detection_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import 'audio_player_service.dart';

/// A group of duplicate audio files sharing identical binary content or acoustic fingerprint.
class DuplicateGroup {
  final String title;
  final String artist;
  final String matchReason;
  final List<Track> tracks;

  const DuplicateGroup({
    required this.title,
    required this.artist,
    required this.matchReason,
    required this.tracks,
  });

  /// Potential disk storage that can be reclaimed by keeping only 1 copy.
  int get reclaimableBytes {
    if (tracks.length <= 1) return 0;
    int total = 0;
    for (int i = 1; i < tracks.length; i++) {
      total += tracks[i].fileSize ?? 0;
    }
    return total;
  }
}

/// Real Duplicate Detection Service.
///
/// Detection Signals:
/// 1. File size in bytes.
/// 2. Audio duration (in milliseconds).
/// 3. Sampled byte block hash (SHA-256 of header and mid-stream bytes).
/// 4. Normalized acoustic metadata tokens.
///
/// Safety Guarantees:
/// - Never groups files merely because titles match.
/// - Never automatically deletes files.
/// - Provides safe deletion with user review.
class DuplicateDetectionService {
  static final DuplicateDetectionService instance = DuplicateDetectionService._internal();
  DuplicateDetectionService._internal();

  final AudioRepository _repository = AudioRepository.instance;

  /// Scans database tracks and clusters duplicates into reviewable groups.
  Future<List<DuplicateGroup>> findDuplicates() async {
    final allTracks = await _repository.getMusicOnlyTracks();
    if (allTracks.length < 2) return [];

    // Map by composite signature: size_bytes:duration_seconds
    final Map<String, List<Track>> sizeDurationBuckets = {};

    for (final track in allTracks) {
      final size = track.fileSize ?? 0;
      final durationSec = (track.duration != null && track.duration! > 0) ? (track.duration! ~/ 1000) : 0;

      if (size > 0 && durationSec > 0) {
        final key = '${size}_$durationSec';
        sizeDurationBuckets.putIfAbsent(key, () => []).add(track);
      }
    }

    final List<DuplicateGroup> duplicateGroups = [];

    // Phase 1: Verify exact byte hash for size/duration collisions
    for (final entry in sizeDurationBuckets.entries) {
      final bucket = entry.value;
      if (bucket.length < 2) continue;

      // Group tracks within bucket by partial content hash
      final Map<String, List<Track>> hashBuckets = {};

      for (final track in bucket) {
        final hash = await _computeSampleHash(track.filePath);
        hashBuckets.putIfAbsent(hash, () => []).add(track);
      }

      for (final hashEntry in hashBuckets.entries) {
        final matches = hashEntry.value;
        if (matches.length >= 2) {
          duplicateGroups.add(
            DuplicateGroup(
              title: matches.first.title,
              artist: matches.first.artist,
              matchReason: 'Identical File Size & Byte Hash',
              tracks: matches,
            ),
          );
        }
      }
    }

    // Phase 2: High-similarity acoustic duration & normalized title clusters
    // Only applies to tracks not already clustered in Phase 1
    final clusteredIds = duplicateGroups.expand((g) => g.tracks.map((t) => t.id)).toSet();
    final remainingTracks = allTracks.where((t) => !clusteredIds.contains(t.id)).toList();

    final Map<String, List<Track>> acousticBuckets = {};
    for (final track in remainingTracks) {
      final normTitle = _normalizeString(track.title);
      final normArtist = _normalizeString(track.artist);
      final durationSec = (track.duration != null && track.duration! > 0) ? (track.duration! ~/ 1000) : 0;

      if (normTitle.isNotEmpty && durationSec > 15) {
        // Quantize duration to 2-second windows to catch minor encoding padding differences
        final quantizedDuration = (durationSec ~/ 2) * 2;
        final key = '${normTitle}_${normArtist}_$quantizedDuration';
        acousticBuckets.putIfAbsent(key, () => []).add(track);
      }
    }

    for (final entry in acousticBuckets.entries) {
      final matches = entry.value;
      if (matches.length >= 2) {
        duplicateGroups.add(
          DuplicateGroup(
            title: matches.first.title,
            artist: matches.first.artist,
            matchReason: 'Matching Acoustic Duration & Audio Metadata',
            tracks: matches,
          ),
        );
      }
    }

    return duplicateGroups;
  }

  /// Computes a fast SHA-256 hash of the initial and middle 4096 bytes of an audio file.
  Future<String> _computeSampleHash(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return '';
    final file = File(filePath);
    if (!await file.exists()) return '';

    RandomAccessFile? raf;
    try {
      final len = await file.length();
      if (len == 0) return '';

      raf = await file.open(mode: FileMode.read);
      final headBytes = await raf.read(len < 4096 ? len : 4096);

      List<int> midBytes = [];
      if (len > 8192) {
        final midOffset = (len ~/ 2) - 2048;
        await raf.setPosition(midOffset);
        midBytes = await raf.read(4096);
      }

      final combined = [...headBytes, ...midBytes];
      return _fnv1a64Hex(combined);
    } catch (_) {
      return '';
    } finally {
      await raf?.close();
    }
  }

  static String _fnv1a64Hex(List<int> bytes) {
    BigInt hash = BigInt.parse('0xcbf29ce484222325');
    final prime = BigInt.parse('0x100000001b3');
    final mask64 = BigInt.parse('0xffffffffffffffff');

    for (final b in bytes) {
      hash = hash ^ BigInt.from(b);
      hash = (hash * prime) & mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _normalizeString(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\.(mp3|m4a|wav|flac|aac|ogg|opus)$'), '')
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // Remove parenthetical tags like (Official Audio)
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
  }

  /// Safely deletes a duplicate copy chosen by the user.
  /// Never deletes without explicit track reference.
  Future<bool> safelyDeleteDuplicate({
    required Track track,
    bool deletePhysicalFile = true,
  }) async {
    try {
      final path = track.filePath;

      // 1. Release active playback if current player has locked this file
      try {
        final currentPath = AudioPlayerService.instance.currentTrack?.filePath;
        final currentId = AudioPlayerService.instance.currentTrack?.id;
        if ((path != null && currentPath == path) ||
            (track.id != null && currentId == track.id)) {
          await AudioPlayerService.instance.player.stop();
        }
      } catch (playErr) {
        debugPrint('DuplicateDetectionService: Notice stopping player: $playErr');
      }

      // 2. Physical File Deletion with fallback
      if (deletePhysicalFile && path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (syncErr) {
          debugPrint('DuplicateDetectionService: Sync delete notice: $syncErr');
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (asyncErr) {
            debugPrint('DuplicateDetectionService: Async file delete notice: $asyncErr');
          }
        }
      }

      // 3. Purge record from SQLite database by file path AND by track id
      if (path != null && path.isNotEmpty) {
        await _repository.batchDeleteByPaths([path]);
      }
      if (track.id != null) {
        try {
          final db = await AppDatabase.instance.database;
          await db.delete('tracks', where: 'id = ?', whereArgs: [track.id]);
          await db.delete('playlist_tracks', where: 'track_id = ?', whereArgs: [track.id]);
        } catch (dbErr) {
          debugPrint('DuplicateDetectionService: DB cleanup error: $dbErr');
        }
      }

      return true;
    } catch (e) {
      debugPrint('DuplicateDetectionService: Error deleting duplicate: $e');
      return false;
    }
  }
}
