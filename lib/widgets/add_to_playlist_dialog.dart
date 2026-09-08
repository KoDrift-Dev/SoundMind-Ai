// add_to_playlist_dialog.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';

/// Modal dialog allowing user to add a track to an existing playlist
/// or create a new playlist on the fly.
class AddToPlaylistDialog extends StatefulWidget {
  final Track track;
  final Color accentColor;

  const AddToPlaylistDialog({
    super.key,
    required this.track,
    this.accentColor = AppColors.themeOneAccent,
  });

  static Future<void> show(BuildContext context, Track track, {Color accentColor = AppColors.themeOneAccent}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistDialog(track: track, accentColor: accentColor),
    );
  }

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  final AudioRepository _repo = AudioRepository.instance;
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final list = await _repo.getPlaylists();
    if (mounted) {
      setState(() {
        _playlists = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreatePlaylistDialog() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: widget.accentColor.withValues(alpha: isDark ? 0.3 : 0.4)),
          ),
          title: Text(
            'New Playlist',
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: widget.accentColor),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      try {
        final playlist = await _repo.createPlaylist(name);
        if (widget.track.id != null) {
          await _repo.addTrackToPlaylist(playlist.id!, widget.track.id!);
        }
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created "$name" and added "${widget.track.title}"'),
              backgroundColor: AppColors.voidOverlay,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error creating playlist: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not create playlist. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _addToExistingPlaylist(Playlist playlist) async {
    if (widget.track.id == null || playlist.id == null) return;
    await _repo.addTrackToPlaylist(playlist.id!, widget.track.id!);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${widget.track.title}" to ${playlist.name}'),
          backgroundColor: AppColors.voidOverlay,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.black54;
    final tertiaryTextColor = isDark ? Colors.white38 : Colors.black38;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1527) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Add to Playlist',
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
              TextButton.icon(
                onPressed: _showCreatePlaylistDialog,
                icon: Icon(Icons.add, color: widget.accentColor, size: 20),
                label: Text(
                  'New',
                  style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: secondaryTextColor),
          ),
          Divider(height: 24, color: dividerColor),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_playlists.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Column(
                  children: [
                    Icon(Icons.queue_music_rounded, size: 48, color: tertiaryTextColor),
                    const SizedBox(height: 12),
                    Text(
                      'No custom playlists yet',
                      style: TextStyle(color: secondaryTextColor, fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _showCreatePlaylistDialog,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create First Playlist'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final p = _playlists[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.playlist_play_rounded, color: widget.accentColor),
                    ),
                    title: Text(
                      p.name,
                      style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${p.trackCount} ${p.trackCount == 1 ? "track" : "tracks"}',
                      style: TextStyle(color: secondaryTextColor, fontSize: 12),
                    ),
                    trailing: Icon(Icons.add_circle_outline_rounded, color: tertiaryTextColor),
                    onTap: () => _addToExistingPlaylist(p),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
