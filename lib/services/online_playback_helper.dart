import 'package:flutter/material.dart';

import 'audio_player_service.dart';
import 'notification_service.dart';
import '../models/track.dart';
import '../online/models/online_search_result.dart';
import '../utils/duration_formatter.dart';
import 'youtube_service.dart';

export '../core/theme/online_theme.dart';

class OnlinePlaybackHelper {
  /// Instantly transitions to the PlayerScreen with a pending resolving track,
  /// resolving the YouTube audio stream URL in the background.
  static Future<bool> playOnlineTrack(
    BuildContext context,
    OnlineSearchResult track,
    YoutubeService youtubeService,
    void Function(List<Track> playlist, int index) onPlaySelected,
    Color snackbarColor, {
    VoidCallback? onSuccess,
  }) async {
    // 1. Build a pending Track with isResolving: true so the Player screen can render immediately
    final durationMs = parseDurationStringToMs(track.duration);
    final pendingTrack = Track(
      onlineId: track.id,
      filePath: null,
      title: track.title,
      artist: track.artist,
      album: track.album,
      artUrl: track.thumbnailUrl ?? '',
      duration: durationMs,
      isMusic: true,
      isResolving: true,
    );

    // 2. Dispatch immediately to player engine & trigger tab navigation
    onPlaySelected([pendingTrack], 0);
    onSuccess?.call();

    // 3. Resolve audio stream URL asynchronously in the background
    debugPrint('OnlinePlaybackHelper: Resolving stream URL for video ${track.id} in background');
    youtubeService.getAudioStreamUrl(track.id).then((streamUrl) {
      if (streamUrl != null && streamUrl.isNotEmpty) {
        AudioPlayerService.instance.hydratePendingTrack(streamUrl);
      } else {
        AudioPlayerService.instance.markPendingTrackFailed('Unable to load stream');
        NotificationService.instance.addError(
          'Streaming Unavailable',
          'Could not stream "${track.title}". Please try another track.',
        );
      }
    }).catchError((e) {
      debugPrint('OnlinePlaybackHelper: Error resolving stream: $e');
      AudioPlayerService.instance.markPendingTrackFailed('Failed to load stream');
      NotificationService.instance.addError(
        'Streaming Error',
        'Network error while streaming "${track.title}".',
      );
    });

    return true;
  }
}
