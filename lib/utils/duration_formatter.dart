/// Shared duration formatting utilities for SoundMind.
///
/// Ensures consistent 'm:ss' and 'h:mm:ss' duration display across the app,
/// eliminating raw number displays (e.g. "213", "135") and handling clips over 1 hour.
library;

/// Formats a [Duration] into 'm:ss' or 'h:mm:ss'.
String formatDuration(Duration? d) {
  if (d == null || d.inSeconds <= 0) return '0:00';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Formats milliseconds [ms] (as stored in local [Track.duration]) into 'm:ss' or 'h:mm:ss'.
String formatDurationMs(int? ms, {String placeholder = '--:--'}) {
  if (ms == null || ms <= 0) return placeholder;
  return formatDuration(Duration(milliseconds: ms));
}

/// Formats seconds [sec] into 'm:ss' or 'h:mm:ss'.
String formatDurationSeconds(int? sec, {String placeholder = '--:--'}) {
  if (sec == null || sec <= 0) return placeholder;
  return formatDuration(Duration(seconds: sec));
}

/// Formats a string that may be a raw number of seconds (e.g. "213"),
/// raw milliseconds, or already partially formatted (e.g. "83:45", "3:33").
String formatDurationString(String? str, {String placeholder = '--:--'}) {
  if (str == null || str.trim().isEmpty) return placeholder;
  final clean = str.trim();

  // Case 1: Already contains colon (e.g. "83:45" or "1:23:45" or "3:33")
  if (clean.contains(':')) {
    final parts = clean.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null) {
        return formatDuration(Duration(minutes: m, seconds: s));
      }
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = int.tryParse(parts[2]);
      if (h != null && m != null && s != null) {
        return formatDuration(Duration(hours: h, minutes: m, seconds: s));
      }
    }
    return clean;
  }

  // Case 2: Pure numeric string (e.g. "213" or "213000")
  final numVal = int.tryParse(clean);
  if (numVal != null && numVal > 0) {
    // If greater than 10,000, treat as milliseconds, otherwise seconds
    if (numVal > 10000) {
      return formatDurationMs(numVal, placeholder: placeholder);
    } else {
      return formatDurationSeconds(numVal, placeholder: placeholder);
    }
  }

  return clean;
}

/// Parses a duration string (e.g. "4:41", "1:23:45", "213") into milliseconds.
int? parseDurationStringToMs(String? str) {
  if (str == null || str.trim().isEmpty) return null;
  final clean = str.trim();

  // Case 1: Contains colon (e.g. "4:41" or "1:23:45")
  if (clean.contains(':')) {
    final parts = clean.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null) {
        return (m * 60 + s) * 1000;
      }
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = int.tryParse(parts[2]);
      if (h != null && m != null && s != null) {
        return (h * 3600 + m * 60 + s) * 1000;
      }
    }
    return null;
  }

  // Case 2: Pure numeric string
  final numVal = int.tryParse(clean);
  if (numVal != null && numVal > 0) {
    // If greater than 10,000, treat as milliseconds, otherwise seconds
    if (numVal > 10000) {
      return numVal;
    } else {
      return numVal * 1000;
    }
  }

  return null;
}

/// Versatile helper accepting [Duration], [int], or [String].
String formatDurationAny(dynamic input, {String placeholder = '--:--'}) {
  if (input == null) return placeholder;
  if (input is Duration) return formatDuration(input);
  if (input is int) return formatDurationMs(input, placeholder: placeholder);
  if (input is String) return formatDurationString(input, placeholder: placeholder);
  return placeholder;
}
