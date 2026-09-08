// playlist_detail_screen.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../widgets/track_artwork.dart';

/// Full screen interface for managing a single custom playlist:
/// - Rename playlist
/// - Delete playlist
/// - Reorder songs via drag-and-drop
/// - Remove individual songs
/// - Play safe music-only queue
class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  final Color accentColor;
  final void Function(List<Track> playlist, int index) onPlaySelected;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.accentColor,
    required this.onPlaySelected,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final AudioRepository _repo = AudioRepository.instance;
  late Playlist _currentPlaylist;
  List<Track> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    if (_currentPlaylist.id == null) return;
    final tracks = await _repo.getPlaylistTracks(_currentPlaylist.id!, musicOnly: false);
    if (mounted) {
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    }
  }

  Future<void> _renamePlaylist() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _currentPlaylist.name);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(color: widget.accentColor.withValues(alpha: isDark ? 0.3 : 0.4)),
            ),
            title: Text(
              'Rename Playlist',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.accentColor)),
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
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (confirmed == true && controller.text.trim().isNotEmpty && _currentPlaylist.id != null) {
        final newName = controller.text.trim();
        await _repo.renamePlaylist(_currentPlaylist.id!, newName);
        setState(() {
          _currentPlaylist = _currentPlaylist.copyWith(name: newName);
        });
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deletePlaylist() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Text(
            'Delete Playlist?',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete "${_currentPlaylist.name}"? The audio files will remain on your device.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && _currentPlaylist.id != null) {
      await _repo.deletePlaylist(_currentPlaylist.id!);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, item);
    });

    if (_currentPlaylist.id != null) {
      final orderedIds = _tracks.map((t) => t.id).whereType<int>().toList();
      await _repo.reorderPlaylistTracks(_currentPlaylist.id!, orderedIds);
    }
  }

  Future<void> _removeTrack(Track track) async {
    if (_currentPlaylist.id == null || track.id == null) return;
    await _repo.removeTrackFromPlaylist(_currentPlaylist.id!, track.id!);
    setState(() {
      _tracks.removeWhere((t) => t.id == track.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${track.title}" from playlist'),
          backgroundColor: AppColors.voidOverlay,
        ),
      );
    }
  }

  Future<void> _playPlaylist({int startIndex = 0}) async {
    if (_currentPlaylist.id == null) return;
    // Music-only safety enforcement:
    // Only verified music tracks will be passed to playback queue
    final verifiedMusic = await _repo.getPlaylistTracks(_currentPlaylist.id!, musicOnly: true);
    if (!mounted) return;
    if (verifiedMusic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Playlist contains no verified music tracks for safe playback.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // Adjust start index if needed
    final selectedTrack = (startIndex < _tracks.length) ? _tracks[startIndex] : _tracks.first;
    int playIdx = verifiedMusic.indexWhere((t) => t.id == selectedTrack.id);
    if (playIdx < 0) playIdx = 0;

    widget.onPlaySelected(verifiedMusic, playIdx);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
    final mutedTextColor = isDark ? Colors.white38 : Colors.black38;
    final dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF030712) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentPlaylist.name,
          style: TextStyle(
            fontFamily: AppTypography.displayFont,
            fontSize: 18,
            color: primaryTextColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_rounded, color: secondaryTextColor),
            tooltip: 'Rename Playlist',
            onPressed: _renamePlaylist,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: 'Delete Playlist',
            onPressed: _deletePlaylist,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music_rounded, size: 64, color: isDark ? Colors.white24 : Colors.black26),
                      const SizedBox(height: 16),
                      Text(
                        'This playlist is empty',
                        style: TextStyle(color: secondaryTextColor, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add songs using the 3 dots menu on any track.',
                        style: TextStyle(color: mutedTextColor, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header action bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_tracks.length} ${_tracks.length == 1 ? "track" : "tracks"}',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 14),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.accentColor,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 22),
                            label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () => _playPlaylist(startIndex: 0),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _tracks.length,
                        onReorderItem: _onReorder,
                        itemBuilder: (context, index) {
                          final track = _tracks[index];
                          return ListTile(
                            key: ValueKey(track.id ?? track.filePath ?? '$index'),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: TrackArtwork(
                              track: track,
                              width: 44,
                              height: 44,
                              borderRadius: AppRadius.sm,
                              showShadow: false,
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              '${track.artist} • ${track.audioCategory.displayName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: track.isMusic ? (isDark ? Colors.white54 : Colors.black54) : Colors.amber.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove_circle_outline_rounded, color: isDark ? Colors.white38 : Colors.black45, size: 20),
                                  tooltip: 'Remove from playlist',
                                  onPressed: () => _removeTrack(track),
                                ),
                                Icon(Icons.drag_handle_rounded, color: isDark ? Colors.white24 : Colors.black26, size: 22),
                              ],
                            ),
                            onTap: () => _playPlaylist(startIndex: index),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
