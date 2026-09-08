import '../../models/track.dart';
import '../constants/app_strings.dart';
import 'folder_name_helper.dart';

/// Library grouping and ranking helpers extracted from the home screen.
abstract final class TrackCollectionHelper {
  static const int minTrackDurationMs = 60000;
  static const int minMusicDurationMs = 90000;
  static const int minCollectionSize = 3;
  static const int maxCategoryCount = 4;
  static const int maxRailCount = 15;

  static const List<String> junkFolderKeywords = [
    'notifications',
    'ringtones',
    'alarms',
    'phonerecord',
    'call',
    'voicenotes',
    'recordings',
  ];

  static final RegExp phoneNumberFolderPattern = RegExp(r'\d{7,}');

  static const List<String> priorityPathKeywords = [
    'music',
    'song',
    'download',
    'audio',
  ];

  /// Groups device tracks by parent folder with junk filtering applied.
  static Map<String, List<Track>> groupByFolder(List<Track> tracks) {
    final grouped = <String, List<Track>>{};

    for (final track in tracks) {
      if (track.duration == null || track.duration! < minTrackDurationMs) {
        continue;
      }

      final folderName = FolderNameHelper.fromFilePath(track.filePath);
      final lowerFolder = folderName.toLowerCase();

      if (junkFolderKeywords.any((junk) => lowerFolder.contains(junk))) {
        continue;
      }

      if (phoneNumberFolderPattern.hasMatch(lowerFolder)) {
        continue;
      }

      grouped.putIfAbsent(folderName, () => []).add(track);
    }

    grouped.removeWhere((_, value) => value.length < minCollectionSize);
    return grouped;
  }

  /// Returns top folder names sorted by track count.
  static List<String> topCategories(
    Map<String, List<Track>> grouped, {
    int limit = maxCategoryCount,
  }) {
    final sortedFolders = grouped.keys.toList()
      ..sort(
        (a, b) => grouped[b]!.length.compareTo(grouped[a]!.length),
      );

    return [AppStrings.allCategory, ...sortedFolders.take(limit)];
  }

  /// Heuristic ranking for the home "Popular Right Now" rail.
  static List<Track> intelligentRail(List<Track> sourceTracks) {
    if (sourceTracks.isEmpty) return [];

    if (sourceTracks.any((t) => t.playCount > 0)) {
      final sorted = List<Track>.from(sourceTracks)
        ..sort((a, b) => b.playCount.compareTo(a.playCount));
      return sorted.take(maxRailCount).toList();
    }

    var validMusicFiles = sourceTracks
        .where(
          (t) => t.duration != null && t.duration! >= minMusicDurationMs,
        )
        .toList();

    if (validMusicFiles.isEmpty) {
      validMusicFiles = List<Track>.from(sourceTracks);
    }

    final priorityFolders = validMusicFiles.where((t) {
      if (t.filePath == null) return false;
      final path = t.filePath!.toLowerCase();
      return priorityPathKeywords.any(path.contains);
    }).toList();

    if (priorityFolders.isNotEmpty) {
      priorityFolders.sort(
        (a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0),
      );
      return priorityFolders.take(maxRailCount).toList();
    }

    final sortedByLength = List<Track>.from(validMusicFiles)
      ..sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));

    return sortedByLength.take(maxRailCount).toList();
  }
}
