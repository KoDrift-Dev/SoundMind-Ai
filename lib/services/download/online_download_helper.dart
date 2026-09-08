import 'package:flutter/material.dart';
import '../../models/track.dart';
import '../../online/models/online_search_result.dart';
import '../../widgets/download_options_sheet.dart';

/// Single unified helper for opening download options from any screen
/// (3-dot menu, Player screen, etc.), ensuring videoId consistency.
class OnlineDownloadHelper {
  static Future<void> openDownloadSheet(
    BuildContext context, {
    required Color accentColor,
    Track? currentTrack,
    OnlineSearchResult? explicitOnlineTrack,
    required String sourceCaller,
  }) async {
    OnlineSearchResult? targetTrack;

    if (explicitOnlineTrack != null) {
      targetTrack = explicitOnlineTrack;
    } else if (currentTrack != null) {
      // Resolve videoId from track.onlineId
      String videoId = currentTrack.onlineId ?? '';

      // Fallback: Check if filePath contains video ID or query parameter
      if (videoId.isEmpty && currentTrack.filePath != null) {
        final uri = Uri.tryParse(currentTrack.filePath!);
        if (uri != null && uri.queryParameters.containsKey('id')) {
          videoId = uri.queryParameters['id']!;
        }
      }

      // If still empty, use a clean identifier
      if (videoId.isEmpty) {
        videoId = currentTrack.id?.toString() ?? '${currentTrack.title}_${currentTrack.artist}';
      }

      targetTrack = OnlineSearchResult(
        id: videoId,
        title: currentTrack.title,
        artist: currentTrack.artist,
        album: currentTrack.album,
        thumbnailUrl: currentTrack.artUrl,
        source: 'YouTube',
        previewUrl: currentTrack.filePath,
      );
    }

    if (targetTrack == null) {
      debugPrint('[$sourceCaller] Cannot start download: no track provided');
      return;
    }

    debugPrint(
      '[$sourceCaller] Triggering DownloadOptionsSheet -> videoId: "${targetTrack.id}", title: "${targetTrack.title}", artist: "${targetTrack.artist}"',
    );

    await DownloadOptionsSheet.show(
      context,
      track: targetTrack,
      accentColor: accentColor,
    );
  }
}
