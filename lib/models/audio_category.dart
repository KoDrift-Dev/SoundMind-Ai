// audio_category.dart
import 'package:flutter/material.dart';

/// Strongly-typed classification categories for audio files on device.
enum AudioCategory {
  music,
  recording,
  voiceNote,
  messagingAudio,
  podcast,
  audiobook,
  ringtone,
  notification,
  soundEffect,
  other,
  unknown;

  /// String serialization value for database persistence.
  String get dbValue => name;

  /// Converts a database string back to [AudioCategory].
  static AudioCategory fromDbValue(String? value) {
    if (value == null) return AudioCategory.unknown;
    return AudioCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == value.toLowerCase(),
      orElse: () => AudioCategory.unknown,
    );
  }

  /// Human-readable label for UI display.
  String get displayName {
    switch (this) {
      case AudioCategory.music:
        return 'Music';
      case AudioCategory.recording:
        return 'Recording';
      case AudioCategory.voiceNote:
        return 'Voice Note';
      case AudioCategory.messagingAudio:
        return 'Messaging Audio';
      case AudioCategory.podcast:
        return 'Podcast';
      case AudioCategory.audiobook:
        return 'Audiobook';
      case AudioCategory.ringtone:
        return 'Ringtone';
      case AudioCategory.notification:
        return 'Notification';
      case AudioCategory.soundEffect:
        return 'Sound Effect';
      case AudioCategory.other:
        return 'Other Audio';
      case AudioCategory.unknown:
        return 'Unknown / Review';
    }
  }

  /// Representative icon for each audio category.
  IconData get icon {
    switch (this) {
      case AudioCategory.music:
        return Icons.music_note_rounded;
      case AudioCategory.recording:
        return Icons.mic_rounded;
      case AudioCategory.voiceNote:
        return Icons.record_voice_over_rounded;
      case AudioCategory.messagingAudio:
        return Icons.chat_bubble_outline_rounded;
      case AudioCategory.podcast:
        return Icons.podcasts_rounded;
      case AudioCategory.audiobook:
        return Icons.auto_stories_rounded;
      case AudioCategory.ringtone:
        return Icons.ring_volume_rounded;
      case AudioCategory.notification:
        return Icons.notifications_active_rounded;
      case AudioCategory.soundEffect:
        return Icons.graphic_eq_rounded;
      case AudioCategory.other:
        return Icons.audiotrack_rounded;
      case AudioCategory.unknown:
        return Icons.help_outline_rounded;
    }
  }
}
