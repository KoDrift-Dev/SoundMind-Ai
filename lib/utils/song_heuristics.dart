import '../models/track.dart';

/// Heuristic junk audio detector for SoundMind AI.
///
/// Rules:
/// 1. File name or title contains 6 or more digit characters (0-9)
///    (e.g., WhatsApp audio `AUD-20230501-WA0001`, system call logs `REC_20240102143000`, etc.).
/// 2. Audio duration is less than 2 minutes (< 120,000 ms) or greater than 60 minutes (> 3,600,000 ms).
/// 3. Name, title, or metadata matches typical voice recordings, phone calls, or notification junk.
bool isJunkTrack(Track track) {
  final String name = track.fileName ??
      (track.filePath != null && track.filePath!.isNotEmpty
          ? track.filePath!.split(RegExp(r'[/\\]')).last
          : track.title);

  // 1. Any file with 6 or more digits in name or title is categorized as junk
  final nameDigits = name.replaceAll(RegExp(r'[^0-9]'), '');
  if (nameDigits.length >= 6) {
    return true;
  }

  final titleDigits = track.title.replaceAll(RegExp(r'[^0-9]'), '');
  if (titleDigits.length >= 6) {
    return true;
  }

  // 2. Scan name and title for voice notes, recordings, or notification sound keywords
  final lowerName = name.toLowerCase();
  final lowerTitle = track.title.toLowerCase();
  const junkKeywords = [
    'aud-',
    'ptt-',
    'rec_',
    'recording',
    'voice note',
    'voice_note',
    'voicerecorder',
    'call_rec',
    'call recording',
    'whatsapp audio',
    'telegram audio',
    'ringtone',
    'notification',
    'alarm_sound',
    'ui_sound',
  ];

  for (final keyword in junkKeywords) {
    if (lowerName.contains(keyword) || lowerTitle.contains(keyword)) {
      return true;
    }
  }

  // 3. Duration heuristics:
  final dur = track.duration ?? 0;
  // Exclude audio shorter than 2 minutes (120,000 ms)
  if (dur < 120000) {
    return true;
  }

  // Exclude audio longer than 60 minutes (3,600,000 ms)
  if (dur > 3600000) {
    return true;
  }

  return false;
}
