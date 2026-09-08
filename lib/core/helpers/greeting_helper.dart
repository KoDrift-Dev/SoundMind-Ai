import '../constants/app_strings.dart';

/// Time-of-day greeting used on the home screen header.
abstract final class GreetingHelper {
  static String forCurrentTime([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;

    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';

    return 'Good Evening';
  }

  static String indexedMessage(int trackCount) {
    return 'Engine successfully indexed $trackCount local audio files.';
  }

  static String trackCountLabel(int count) => '$count ${AppStrings.tracksSuffix}';
}
