import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_typography.dart';
import '../models/track.dart';
import '../online/models/online_search_result.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_player_service.dart';
import '../services/online_playback_helper.dart';
import '../services/youtube_service.dart';
import '../utils/duration_formatter.dart';
import 'track_artwork.dart';
import '../services/download/online_download_helper.dart';

/// Represents a single action within the forward-compatible track options menu.
/// Adding new actions (e.g. Download) in the future requires adding a single item
/// to the actions array in [TrackActionMenu].
class TrackMenuAction {
  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context) onExecute;
  final bool isVisible;
  final Color? iconColor;

  const TrackMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onExecute,
    this.isVisible = true,
    this.iconColor,
  });
}

/// Unified forward-compatible track action bottom sheet.
class TrackActionMenu extends StatefulWidget {
  final Track? localTrack;
  final OnlineSearchResult? onlineTrack;
  final Color accentColor;

  const TrackActionMenu._({
    required this.localTrack,
    required this.onlineTrack,
    required this.accentColor,
  });

  /// Shows the track options menu for a local track or online search result.
  static Future<void> show(
    BuildContext context, {
    Track? localTrack,
    OnlineSearchResult? onlineTrack,
    required Color accentColor,
  }) {
    assert(
      localTrack != null || onlineTrack != null,
      'Either localTrack or onlineTrack must be provided',
    );
    HapticFeedback.lightImpact();

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TrackActionMenu._(
        localTrack: localTrack,
        onlineTrack: onlineTrack,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<TrackActionMenu> createState() => _TrackActionMenuState();
}

class _TrackActionMenuState extends State<TrackActionMenu> {
  bool _isFav = false;

  bool get isOnline =>
      widget.onlineTrack != null ||
      (widget.localTrack?.filePath?.startsWith('http') ?? false);

  String get title =>
      widget.onlineTrack?.title ?? widget.localTrack?.title ?? 'Unknown Track';
  String get artist =>
      widget.onlineTrack?.artist ??
      widget.localTrack?.artist ??
      'Unknown Artist';
  String? get thumbnailUrl =>
      widget.onlineTrack?.thumbnailUrl ?? widget.localTrack?.artUrl;

  @override
  void initState() {
    super.initState();
    _isFav = widget.localTrack?.isFavorite ?? false;
    if (widget.onlineTrack != null) {
      SharedPreferences.getInstance().then((prefs) {
        final favs = prefs.getStringList('online_favorites') ?? [];
        if (mounted && favs.contains(widget.onlineTrack!.id)) {
          setState(() => _isFav = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeAccent = isOnline ? OnlineTheme.accent(isDark) : widget.accentColor;

    // ── Forward-Compatible Actions Array ──
    final actions = <TrackMenuAction>[
      TrackMenuAction(
        id: 'play',
        label: 'Play',
        icon: Icons.play_arrow_rounded,
        onExecute: (ctx) => _handlePlay(ctx, themeAccent),
      ),
      TrackMenuAction(
        id: 'add_to_queue',
        label: 'Add to Queue',
        icon: Icons.queue_music_rounded,
        onExecute: (ctx) => _handleAddToQueue(ctx, themeAccent),
      ),
      TrackMenuAction(
        id: 'favorite',
        label: _isFav ? 'Remove from Favorites' : 'Add to Favorites',
        icon: _isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        iconColor: _isFav ? const Color(0xFFFF2E7E) : null,
        onExecute: (ctx) => _handleToggleFavorite(ctx, _isFav),
      ),
      if (isOnline && widget.onlineTrack != null)
        TrackMenuAction(
          id: 'download',
          label: 'Download Track',
          icon: Icons.download_rounded,
          iconColor: themeAccent,
          onExecute: (ctx) => _handleDownload(ctx, themeAccent),
        ),
      TrackMenuAction(
        id: 'share',
        label: 'Share',
        icon: Icons.share_rounded,
        onExecute: (ctx) => _handleShare(ctx),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131826) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header: Artwork + Track Details + Source Badge
          Row(
            children: [
              _buildArtwork(isDark, themeAccent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 13,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Source Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: themeAccent.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: themeAccent.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOnline ? Icons.cloud_rounded : Icons.phone_android_rounded,
                      size: 13,
                      color: themeAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'Online' : 'Device',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: themeAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 8),

          // Actions List
          ...actions.where((a) => a.isVisible).map(
                (action) => _buildActionTile(context, action, isDark, themeAccent),
              ),
        ],
      ),
    );
  }

  Widget _buildArtwork(bool isDark, Color themeAccent) {
    if (widget.localTrack != null &&
        (widget.localTrack?.filePath == null ||
            !widget.localTrack!.filePath!.startsWith('http'))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TrackArtwork(
          track: widget.localTrack!,
          width: 52,
          height: 52,
          borderRadius: 12,
          showShadow: false,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        color: themeAccent.withValues(alpha: 0.15),
        child: thumbnailUrl != null && thumbnailUrl!.isNotEmpty
            ? Image.network(
                thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.music_note_rounded,
                  color: themeAccent,
                  size: 24,
                ),
              )
            : Icon(Icons.music_note_rounded, color: themeAccent, size: 24),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    TrackMenuAction action,
    bool isDark,
    Color themeAccent,
  ) {
    return InkWell(
      onTap: () async {
        Navigator.of(context).pop();
        await action.onExecute(context);
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (action.iconColor ?? themeAccent).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                action.icon,
                size: 18,
                color: action.iconColor ??
                    (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action Handlers ──

  Future<void> _handlePlay(BuildContext context, Color themeAccent) async {
    if (widget.localTrack != null) {
      await AudioPlayerService.instance.loadPlaylist([widget.localTrack!], 0);
      return;
    }

    if (widget.onlineTrack != null) {
      await OnlinePlaybackHelper.playOnlineTrack(
        context,
        widget.onlineTrack!,
        YoutubeService(),
        (playlist, idx) {},
        themeAccent,
      );
    }
  }

  Future<void> _handleAddToQueue(
      BuildContext context, Color themeAccent) async {
    final messenger = ScaffoldMessenger.of(context);
    final trackToAdd =
        await _resolveTrackForQueue(context, messenger, themeAccent);
    if (trackToAdd != null) {
      final success = await AudioPlayerService.instance.addToQueue(trackToAdd);
      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Added to queue: ${trackToAdd.title}'),
            duration: const Duration(seconds: 2),
            backgroundColor: themeAccent,
          ),
        );
      }
    }
  }

  Future<Track?> _resolveTrackForQueue(
    BuildContext context,
    ScaffoldMessengerState messenger,
    Color themeAccent,
  ) async {
    if (widget.localTrack != null &&
        (widget.localTrack?.filePath == null ||
            !widget.localTrack!.filePath!.startsWith('http'))) {
      return widget.localTrack;
    }

    if (widget.localTrack != null &&
        widget.localTrack!.filePath != null &&
        widget.localTrack!.filePath!.startsWith('http')) {
      return widget.localTrack;
    }

    if (widget.onlineTrack != null) {
      messenger.showSnackBar(
        SnackBar(
          content:
              Text('Resolving audio stream for "${widget.onlineTrack!.title}"...'),
          duration: const Duration(seconds: 2),
          backgroundColor: themeAccent,
        ),
      );

      final yt = YoutubeService();
      try {
        final streamUrl = await yt.getAudioStreamUrl(widget.onlineTrack!.id);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          return Track(
            filePath: streamUrl,
            title: widget.onlineTrack!.title,
            artist: widget.onlineTrack!.artist,
            album: widget.onlineTrack!.album,
            artUrl: widget.onlineTrack!.thumbnailUrl ?? '',
            isMusic: true,
            isResolving: false,
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Unable to resolve stream for this track.'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to load audio stream.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
          ),
        );
      } finally {
        yt.dispose();
      }
    }
    return null;
  }

  Future<void> _handleShare(BuildContext context) async {
    try {
      if (isOnline && widget.onlineTrack != null) {
        final shareUrl = 'https://youtu.be/${widget.onlineTrack!.id}';
        final text =
            '${widget.onlineTrack!.title} - ${widget.onlineTrack!.artist}\n$shareUrl';
        await Share.share(text);
        return;
      }

      if (widget.localTrack != null) {
        final text =
            '${widget.localTrack!.title} by ${widget.localTrack!.artist}';
        if (widget.localTrack!.filePath != null &&
            widget.localTrack!.filePath!.isNotEmpty &&
            !widget.localTrack!.filePath!.startsWith('http')) {
          final file = File(widget.localTrack!.filePath!);
          if (await file.exists()) {
            await Share.shareXFiles([XFile(widget.localTrack!.filePath!)],
                text: text);
            return;
          }
        }
        await Share.share(text);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not share track.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleToggleFavorite(
      BuildContext context, bool currentFav) async {
    try {
      if (widget.localTrack != null) {
        await AudioPlayerService.instance.toggleFavorite(widget.localTrack!);
        if (mounted) {
          setState(() => _isFav = !currentFav);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !currentFav ? 'Added to Favorites' : 'Removed from Favorites',
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: widget.accentColor,
            ),
          );
        }
        return;
      }

      if (widget.onlineTrack != null) {
        final onlineTrack = widget.onlineTrack!;
        final newFav = !currentFav;
        final trackObj = Track(
          onlineId: onlineTrack.id,
          filePath: 'online:${onlineTrack.id}',
          title: onlineTrack.title,
          artist: onlineTrack.artist,
          album: onlineTrack.album ?? 'Online Stream',
          artUrl: onlineTrack.thumbnailUrl ?? '',
          duration: parseDurationStringToMs(onlineTrack.duration),
          isMusic: true,
          isFavorite: newFav,
        );
        await AudioRepository.instance.toggleFavoriteTrack(trackObj, newFav);

        final prefs = await SharedPreferences.getInstance();
        final favs = prefs.getStringList('online_favorites') ?? [];
        final id = onlineTrack.id;
        if (newFav) {
          if (!favs.contains(id)) favs.add(id);
        } else {
          favs.remove(id);
        }
        await prefs.setStringList('online_favorites', favs);
        if (mounted) {
          setState(() => _isFav = newFav);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newFav ? 'Added to Favorites' : 'Removed from Favorites',
              ),
              duration: const Duration(seconds: 2),
              backgroundColor: widget.accentColor,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update favorites. Please try again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleDownload(BuildContext context, Color themeAccent) async {
    await OnlineDownloadHelper.openDownloadSheet(
      context,
      accentColor: themeAccent,
      explicitOnlineTrack: widget.onlineTrack,
      currentTrack: widget.localTrack,
      sourceCaller: 'TrackActionMenu(3-Dot Menu)',
    );
  }
}
