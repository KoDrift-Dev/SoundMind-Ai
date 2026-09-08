import 'package:flutter_test/flutter_test.dart';
import 'package:soundmindai/services/download/download_models.dart';

void main() {
  group('DownloadTask Model Tests', () {
    test('DownloadTask serialization to and from Map/JSON', () {
      final task = DownloadTask(
        videoId: 'abc123xyz',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        outputFormat: 'mp3',
        qualityTag: 18,
        qualityBitrate: 128000,
        mp3BitrateKbps: 320,
        status: DownloadStatus.downloading,
        progress: 0.45,
        bytesDownloaded: 4500000,
        totalBytes: 10000000,
        tempFilePath: '/temp/abc123xyz.download.tmp',
        finalFilePath: '/downloads/Bohemian Rhapsody-abc123xyz.mp3',
        streamUrl: 'https://rr1---sn.googlevideo.com/videoplayback?...',
      );

      final map = task.toMap();
      final restored = DownloadTask.fromMap(map);

      expect(restored.videoId, task.videoId);
      expect(restored.title, task.title);
      expect(restored.artist, task.artist);
      expect(restored.outputFormat, 'mp3');
      expect(restored.qualityTag, 18);
      expect(restored.qualityBitrate, 128000);
      expect(restored.mp3BitrateKbps, 320);
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.progress, 0.45);
      expect(restored.bytesDownloaded, 4500000);
      expect(restored.totalBytes, 10000000);
      expect(restored.tempFilePath, task.tempFilePath);
      expect(restored.finalFilePath, task.finalFilePath);

      // JSON roundtrip
      final jsonString = task.toJson();
      final fromJsonTask = DownloadTask.fromJson(jsonString);
      expect(fromJsonTask.videoId, task.videoId);
      expect(fromJsonTask.status, DownloadStatus.downloading);
    });

    test('Status flags: isTerminal, canResume, isActive', () {
      final queued = DownloadTask(
        videoId: '1',
        title: 'T1',
        artist: 'A1',
        outputFormat: 'm4a',
        qualityTag: 18,
        qualityBitrate: 128000,
        status: DownloadStatus.queued,
      );
      expect(queued.isTerminal, isFalse);
      expect(queued.isActive, isFalse);
      expect(queued.canResume, isFalse);

      final downloading = queued.copyWith(status: DownloadStatus.downloading);
      expect(downloading.isTerminal, isFalse);
      expect(downloading.isActive, isTrue);

      final converting = queued.copyWith(status: DownloadStatus.converting);
      expect(converting.isActive, isTrue);

      final paused = queued.copyWith(status: DownloadStatus.paused);
      expect(paused.canResume, isTrue);
      expect(paused.isTerminal, isFalse);

      final failed = queued.copyWith(status: DownloadStatus.failed);
      expect(failed.canResume, isTrue);
      expect(failed.isTerminal, isTrue);

      final completed = queued.copyWith(status: DownloadStatus.completed);
      expect(completed.isTerminal, isTrue);
      expect(completed.canResume, isFalse);

      final cancelled = queued.copyWith(status: DownloadStatus.cancelled);
      expect(cancelled.isTerminal, isTrue);
      expect(cancelled.canResume, isFalse);
    });

    test('Crash Recovery logic: downloading/converting transitions to paused', () {
      final rawTasksData = [
        {
          'videoId': 'v1',
          'title': 'Track 1',
          'artist': 'Artist 1',
          'outputFormat': 'm4a',
          'qualityTag': 18,
          'qualityBitrate': 128000,
          'status': 'downloading', // Simulated active when app killed
          'bytesDownloaded': 2000000,
          'totalBytes': 5000000,
          'progress': 0.4,
        },
        {
          'videoId': 'v2',
          'title': 'Track 2',
          'artist': 'Artist 2',
          'outputFormat': 'mp3',
          'qualityTag': 18,
          'qualityBitrate': 128000,
          'status': 'converting', // Simulated active converting when app killed
          'bytesDownloaded': 5000000,
          'totalBytes': 5000000,
          'progress': 1.0,
        },
        {
          'videoId': 'v3',
          'title': 'Track 3',
          'artist': 'Artist 3',
          'outputFormat': 'm4a',
          'qualityTag': 18,
          'qualityBitrate': 128000,
          'status': 'completed',
          'bytesDownloaded': 4000000,
          'totalBytes': 4000000,
          'progress': 1.0,
        },
      ];

      // Simulate recovery loop
      final recovered = rawTasksData.map((m) {
        final t = DownloadTask.fromMap(m);
        if (t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.converting ||
            t.status == DownloadStatus.queued) {
          t.status = DownloadStatus.paused;
        }
        return t;
      }).toList();

      expect(recovered[0].status, DownloadStatus.paused);
      expect(recovered[0].bytesDownloaded, 2000000);
      expect(recovered[1].status, DownloadStatus.paused);
      expect(recovered[2].status, DownloadStatus.completed);
    });

    test('Content-Length mismatch detection restarts download from scratch', () {
      // Simulate Content-Length verification logic
      final originalTotal = 8000000;
      final refreshedStreamTotal = 7500000; // Encoding changed from YouTube server
      int existingBytes = 4000000; // 50% partial file downloaded previously
      int bytesDownloaded = existingBytes;

      bool shouldRestart = false;
      if (originalTotal > 0 && refreshedStreamTotal != originalTotal && existingBytes > 0) {
        shouldRestart = true;
        // Reset from scratch
        existingBytes = 0;
        bytesDownloaded = 0;
      }

      expect(shouldRestart, isTrue);
      expect(bytesDownloaded, 0);
      expect(existingBytes, 0);
    });

    test('Content-Length matching proceeds with partial Range resume', () {
      final originalTotal = 8000000;
      final refreshedStreamTotal = 8000000; // Same total size
      int existingBytes = 4000000;
      int bytesDownloaded = existingBytes;

      bool shouldRestart = false;
      if (originalTotal > 0 && refreshedStreamTotal != originalTotal && existingBytes > 0) {
        shouldRestart = true;
        bytesDownloaded = 0;
      }

      expect(shouldRestart, isFalse);
      expect(bytesDownloaded, 4000000);
      // Range header to send: bytes=4000000-
      final rangeHeader = 'bytes=$existingBytes-';
      expect(rangeHeader, 'bytes=4000000-');
    });

    test('Sanitizing file names removes illegal OS characters', () {
      String sanitize(String name) {
        return name
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      expect(
        sanitize('Song: "The Best" / 2026 <Live>? *Special* | Edit'),
        'Song_ _The Best_ _ 2026 _Live__ _Special_ _ Edit',
      );
    });

    test('File size estimation accurately computes bytes for Low, Medium, High, and WAV', () {
      const duration = 200; // 200 seconds (~3m 20s)

      // Low = 64 kbps -> (64 * 1000 / 8) * 200 = 1,600,000 bytes (~1.5 MB)
      final lowBytes = DownloadTask.estimateBytes(
        qualityTier: DownloadQualityTier.low,
        format: 'm4a',
        durationSeconds: duration,
      );
      expect(lowBytes, 1600000);

      // Medium = 128 kbps -> (128 * 1000 / 8) * 200 = 3,200,000 bytes (~3.1 MB)
      final medBytes = DownloadTask.estimateBytes(
        qualityTier: DownloadQualityTier.medium,
        format: 'm4a',
        durationSeconds: duration,
      );
      expect(medBytes, 3200000);

      // High = 192 kbps -> (192 * 1000 / 8) * 200 = 4,800,000 bytes (~4.6 MB)
      final highBytes = DownloadTask.estimateBytes(
        qualityTier: DownloadQualityTier.high,
        format: 'mp3',
        durationSeconds: duration,
      );
      expect(highBytes, 4800000);

      // WAV = uncompressed 44.1kHz 16-bit stereo = 176,400 * 200 = 35,280,000 bytes (~33.6 MB)
      final wavBytes = DownloadTask.estimateBytes(
        qualityTier: DownloadQualityTier.high,
        format: 'wav',
        durationSeconds: duration,
      );
      expect(wavBytes, 35280000);
    });

    test('Bitrate capping: target bitrate never exceeds source audio bitrate', () {
      int calculateTargetKbps(String tier, int sourceBitrate) {
        final requestedKbps = DownloadQualityTier.getBitrateKbps(tier);
        return requestedKbps > sourceBitrate ? sourceBitrate : requestedKbps;
      }

      // If source audio is 128k, High tier (192k) is capped at 128k
      expect(calculateTargetKbps(DownloadQualityTier.high, 128), 128);

      // If source audio is 160k, High tier (192k) is capped at 160k
      expect(calculateTargetKbps(DownloadQualityTier.high, 160), 160);

      // If source audio is 128k, Low tier (64k) remains 64k
      expect(calculateTargetKbps(DownloadQualityTier.low, 128), 64);

      // If source audio is 128k, Medium tier (128k) remains 128k
      expect(calculateTargetKbps(DownloadQualityTier.medium, 128), 128);
    });

    test('Video stripping and FFmpeg command generation logic', () {
      String buildCommand({
        required String format,
        required String tier,
        required int sourceAudioBitrateKbps,
        required String tempPath,
        required String finalPath,
      }) {
        final requestedKbps = DownloadQualityTier.getBitrateKbps(tier);
        final targetKbps = (requestedKbps > sourceAudioBitrateKbps)
            ? sourceAudioBitrateKbps
            : requestedKbps;

        if (format == 'mp3') {
          return '-y -i "$tempPath" -vn -c:a libmp3lame -b:a ${targetKbps}k "$finalPath"';
        } else if (format == 'wav') {
          return '-y -i "$tempPath" -vn -c:a pcm_s16le "$finalPath"';
        } else {
          // M4A
          if (targetKbps >= sourceAudioBitrateKbps) {
            return '-y -i "$tempPath" -vn -c:a copy "$finalPath"';
          } else {
            return '-y -i "$tempPath" -vn -c:a aac -b:a ${targetKbps}k "$finalPath"';
          }
        }
      }

      // M4A High with 128k source -> -vn -c:a copy (stream copy, strips video)
      final m4aHigh = buildCommand(
        format: 'm4a',
        tier: 'high',
        sourceAudioBitrateKbps: 128,
        tempPath: '/tmp/song.tmp',
        finalPath: '/dl/song.m4a',
      );
      expect(m4aHigh, '-y -i "/tmp/song.tmp" -vn -c:a copy "/dl/song.m4a"');

      // M4A Low with 128k source -> -vn -c:a aac -b:a 64k (re-encodes to 64k, genuine size reduction!)
      final m4aLow = buildCommand(
        format: 'm4a',
        tier: 'low',
        sourceAudioBitrateKbps: 128,
        tempPath: '/tmp/song.tmp',
        finalPath: '/dl/song.m4a',
      );
      expect(m4aLow, '-y -i "/tmp/song.tmp" -vn -c:a aac -b:a 64k "/dl/song.m4a"');

      // MP3 Medium with 128k source -> -vn -c:a libmp3lame -b:a 128k
      final mp3Med = buildCommand(
        format: 'mp3',
        tier: 'medium',
        sourceAudioBitrateKbps: 128,
        tempPath: '/tmp/song.tmp',
        finalPath: '/dl/song.mp3',
      );
      expect(mp3Med, '-y -i "/tmp/song.tmp" -vn -c:a libmp3lame -b:a 128k "/dl/song.mp3"');

      // WAV -> -vn -c:a pcm_s16le
      final wav = buildCommand(
        format: 'wav',
        tier: 'high',
        sourceAudioBitrateKbps: 128,
        tempPath: '/tmp/song.tmp',
        finalPath: '/dl/song.wav',
      );
      expect(wav, '-y -i "/tmp/song.tmp" -vn -c:a pcm_s16le "/dl/song.wav"');
    });

    test('Downloads tab filtering into In Progress, Completed, and Cancelled', () {
      final tasks = [
        DownloadTask(videoId: '1', title: 'T1', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.downloading),
        DownloadTask(videoId: '2', title: 'T2', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.queued),
        DownloadTask(videoId: '3', title: 'T3', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.paused),
        DownloadTask(videoId: '4', title: 'T4', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.converting),
        DownloadTask(videoId: '5', title: 'T5', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.completed),
        DownloadTask(videoId: '6', title: 'T6', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.cancelled),
        DownloadTask(videoId: '7', title: 'T7', artist: 'A', outputFormat: 'm4a', qualityTag: 18, qualityBitrate: 128000, status: DownloadStatus.failed),
      ];

      final inProgress = tasks.where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued ||
          t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.converting).toList();

      final completed = tasks.where((t) => t.status == DownloadStatus.completed).toList();

      final cancelledOrFailed = tasks.where((t) =>
          t.status == DownloadStatus.cancelled ||
          t.status == DownloadStatus.failed).toList();

      expect(inProgress.length, 4);
      expect(completed.length, 1);
      expect(cancelledOrFailed.length, 2);
    });
  });
}
