// heuristic_audio_classifier.dart
import '../models/audio_category.dart';
import '../models/track.dart';
import 'audio_classifier.dart';
import 'classification_result.dart';

/// Production-grade deterministic audio classifier using weighted signals
/// from folder path, file name, metadata, and audio characteristics.
class HeuristicAudioClassifier implements AudioClassifier {
  const HeuristicAudioClassifier();

  @override
  Future<ClassificationResult> classify(Track track) async {
    // If the track already has a manual user override, respect it with maximum confidence
    if (track.userOverride) {
      return ClassificationResult(
        category: track.audioCategory,
        confidence: 1.0,
        source: ClassificationSource.userOverride,
        explanation: 'User manual classification override.',
      );
    }

    final path = (track.filePath ?? '').replaceAll('\\', '/').toLowerCase();
    final name = (track.fileName ?? '').toLowerCase();
    final artist = track.artist.trim().toLowerCase();
    final album = (track.album ?? '').trim().toLowerCase();
    final genre = (track.genre ?? '').trim().toLowerCase();
    final duration = track.duration ?? 0; // ms

    // Signal scoring maps
    final scores = <AudioCategory, double>{
      for (final cat in AudioCategory.values) cat: 0.0,
    };
    final reasons = <String>[];

    // ──────────────── 1. PATH / FOLDER SIGNALS ────────────────
    if (path.contains('/whatsapp/media/whatsapp voice notes') ||
        path.contains('/whatsapp voice notes') ||
        path.contains('/telegram/telegram voice')) {
      scores[AudioCategory.voiceNote] = (scores[AudioCategory.voiceNote] ?? 0) + 0.65;
      reasons.add('Messaging voice notes directory');
    } else if (path.contains('/whatsapp/media/whatsapp audio') ||
        path.contains('/whatsapp audio') ||
        path.contains('/telegram/telegram audio') ||
        path.contains('/viber') ||
        path.contains('/signal/media')) {
      scores[AudioCategory.messagingAudio] = (scores[AudioCategory.messagingAudio] ?? 0) + 0.60;
      reasons.add('Messaging media audio directory');
    }

    if (path.contains('/recordings') ||
        path.contains('/recorder') ||
        path.contains('/voice recorder') ||
        path.contains('/call recordings') ||
        path.contains('/callrecorder') ||
        path.contains('/phonerecord') ||
        path.contains('/sound recordings')) {
      scores[AudioCategory.recording] = (scores[AudioCategory.recording] ?? 0) + 0.60;
      reasons.add('Device voice/call recording directory');
    }

    if (path.contains('/ringtones') || path.contains('/ringtone')) {
      scores[AudioCategory.ringtone] = (scores[AudioCategory.ringtone] ?? 0) + 0.65;
      reasons.add('Ringtone directory');
    }

    if (path.contains('/notifications') || path.contains('/notification') || path.contains('/alerts')) {
      scores[AudioCategory.notification] = (scores[AudioCategory.notification] ?? 0) + 0.65;
      reasons.add('Notification directory');
    }

    if (path.contains('/podcasts') || path.contains('/podcast')) {
      scores[AudioCategory.podcast] = (scores[AudioCategory.podcast] ?? 0) + 0.60;
      reasons.add('Podcast directory');
    }

    if (path.contains('/audiobooks') || path.contains('/audiobook')) {
      scores[AudioCategory.audiobook] = (scores[AudioCategory.audiobook] ?? 0) + 0.60;
      reasons.add('Audiobook directory');
    }

    if (path.contains('/music') ||
        path.contains('/songs') ||
        path.contains('/albums') ||
        path.contains('/artist') ||
        path.contains('/itunes') ||
        path.contains('/spotify') ||
        path.contains('/soundtracks')) {
      scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.35;
      reasons.add('Music directory structure');
    }

    // ──────────────── 2. FILENAME PATTERNS ────────────────
    if (name.startsWith('aud-') || name.startsWith('ptt-') || name.contains('whatsapp') || name.contains('telegram')) {
      if (name.startsWith('ptt-') || name.contains('voice')) {
        scores[AudioCategory.voiceNote] = (scores[AudioCategory.voiceNote] ?? 0) + 0.45;
        reasons.add('Voice note prefix pattern');
      } else {
        scores[AudioCategory.messagingAudio] = (scores[AudioCategory.messagingAudio] ?? 0) + 0.40;
        reasons.add('Messaging audio prefix pattern');
      }
    }

    if (name.contains('voicenote') ||
        name.contains('voice_note') ||
        name.contains('voice-note') ||
        name.contains('voice memo') ||
        name.contains('audiomemo')) {
      scores[AudioCategory.voiceNote] = (scores[AudioCategory.voiceNote] ?? 0) + 0.45;
      reasons.add('Voice note keyword in filename');
    }

    if (name.contains('recording') ||
        name.contains('record_') ||
        name.contains('rec_') ||
        name.contains('meeting_') ||
        name.contains('call_') ||
        name.contains('lecture_') ||
        name.contains('screen_recording')) {
      scores[AudioCategory.recording] = (scores[AudioCategory.recording] ?? 0) + 0.40;
      reasons.add('Recording keyword in filename');
    }

    if (name.contains('ringtone') || name.contains('ring_') || name.contains('ring-')) {
      scores[AudioCategory.ringtone] = (scores[AudioCategory.ringtone] ?? 0) + 0.45;
      reasons.add('Ringtone keyword in filename');
    }

    if (name.contains('notification') ||
        name.contains('notif_') ||
        name.contains('alarm') ||
        name.contains('alert_') ||
        name.contains('beep') ||
        name.contains('chime')) {
      scores[AudioCategory.notification] = (scores[AudioCategory.notification] ?? 0) + 0.45;
      reasons.add('Notification keyword in filename');
    }

    if (name.contains('sound effect') ||
        name.contains('sound_effect') ||
        name.contains('sfx') ||
        name.contains('foley')) {
      scores[AudioCategory.soundEffect] = (scores[AudioCategory.soundEffect] ?? 0) + 0.50;
      reasons.add('Sound effect keyword in filename');
    }

    if (name.contains('podcast') || name.contains('episode') || name.contains('ep.')) {
      scores[AudioCategory.podcast] = (scores[AudioCategory.podcast] ?? 0) + 0.40;
      reasons.add('Podcast keyword in filename');
    }

    if (name.contains('chapter') || name.contains('audiobook')) {
      scores[AudioCategory.audiobook] = (scores[AudioCategory.audiobook] ?? 0) + 0.40;
      reasons.add('Audiobook keyword in filename');
    }

    if (name.contains('feat.') ||
        name.contains('ft.') ||
        name.contains('remix') ||
        name.contains('official') ||
        name.contains('acoustic') ||
        name.contains('instrumental') ||
        name.contains('original mix')) {
      scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.30;
      reasons.add('Musical title keyword');
    }

    // ──────────────── 3. METADATA SIGNALS ────────────────
    final bool hasValidArtist = artist.isNotEmpty &&
        artist != '<unknown>' &&
        artist != 'unknown artist' &&
        artist != 'unknown' &&
        artist != 'null';

    final bool hasValidAlbum = album.isNotEmpty &&
        album != '<unknown>' &&
        album != 'unknown album' &&
        album != 'unknown' &&
        album != 'null' &&
        album != name;

    if (hasValidArtist) {
      scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.35;
      reasons.add('Tagged artist metadata present');
    }

    if (hasValidAlbum) {
      scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.25;
      reasons.add('Tagged album metadata present');
    }

    if (track.year != null && track.year! > 1920 && track.year! <= DateTime.now().year + 1) {
      scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.15;
      reasons.add('Release year tagged');
    }

    if (genre.isNotEmpty && genre != '<unknown>') {
      final speechGenres = ['speech', 'vocal', 'podcast', 'audiobook', 'spoken word', 'audio drama', 'interview'];
      if (speechGenres.any(genre.contains)) {
        scores[AudioCategory.podcast] = (scores[AudioCategory.podcast] ?? 0) + 0.30;
        scores[AudioCategory.recording] = (scores[AudioCategory.recording] ?? 0) + 0.25;
        reasons.add('Speech genre metadata');
      } else {
        scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.25;
        reasons.add('Music genre tagged');
      }
    }

    // ──────────────── 4. DURATION SIGNALS ────────────────
    if (duration > 0) {
      if (duration < 6000) {
        // Less than 6s
        scores[AudioCategory.notification] = (scores[AudioCategory.notification] ?? 0) + 0.35;
        scores[AudioCategory.soundEffect] = (scores[AudioCategory.soundEffect] ?? 0) + 0.30;
        scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) - 0.40;
        reasons.add('Very short duration (< 6s)');
      } else if (duration < 35000) {
        // 6s - 35s
        scores[AudioCategory.ringtone] = (scores[AudioCategory.ringtone] ?? 0) + 0.30;
        scores[AudioCategory.notification] = (scores[AudioCategory.notification] ?? 0) + 0.20;
        scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) - 0.20;
        reasons.add('Short ringtone-like duration (< 35s)');
      } else if (duration >= 60000 && duration <= 600000) {
        // 1 to 10 minutes: Typical song duration
        scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) + 0.20;
        reasons.add('Typical song duration (1-10m)');
      } else if (duration > 1800000) {
        // > 30 minutes: Typical podcast / audiobook / meeting recording
        if (!hasValidArtist || !hasValidAlbum) {
          scores[AudioCategory.podcast] = (scores[AudioCategory.podcast] ?? 0) + 0.25;
          scores[AudioCategory.audiobook] = (scores[AudioCategory.audiobook] ?? 0) + 0.25;
          scores[AudioCategory.recording] = (scores[AudioCategory.recording] ?? 0) + 0.25;
          scores[AudioCategory.music] = (scores[AudioCategory.music] ?? 0) - 0.20;
          reasons.add('Long speech duration (> 30m) without music tags');
        }
      }
    }

    // ──────────────── 5. WINNER SELECTION & NORMALIZATION ────────────────
    AudioCategory bestCategory = AudioCategory.unknown;
    double highestScore = 0.0;

    for (final entry in scores.entries) {
      if (entry.key == AudioCategory.unknown) continue;
      if (entry.value > highestScore) {
        highestScore = entry.value;
        bestCategory = entry.key;
      }
    }

    // Normalize confidence between 0.0 and 1.0
    // A score of 0.85+ represents near certainty
    double normalizedConfidence = (highestScore / 1.0).clamp(0.0, 1.0);

    // If highest confidence is below review threshold (< 0.50), mark as Unknown / Review
    if (normalizedConfidence < ClassificationResult.reviewConfidenceThreshold) {
      return ClassificationResult(
        category: AudioCategory.unknown,
        confidence: normalizedConfidence,
        source: ClassificationSource.heuristic,
        explanation: reasons.isNotEmpty
            ? 'Ambiguous signals: ${reasons.join(', ')}'
            : 'Insufficient metadata and signals to determine category',
      );
    }

    return ClassificationResult(
      category: bestCategory,
      confidence: normalizedConfidence,
      source: ClassificationSource.heuristic,
      explanation: reasons.join('; '),
    );
  }
}
