import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../core/constants/app_assets.dart';
import '../core/constants/app_radius.dart';
import '../models/track.dart';

/// A global LRU-like artwork cache so QueryArtworkWidget bytes are never
/// re-fetched after the first load. Keyed by track.id.
class _ArtworkCache {
  _ArtworkCache._();
  static final _ArtworkCache instance = _ArtworkCache._();

  final Map<int, Uint8List?> _cache = {};

  Uint8List? get(int id) => _cache[id];
  void set(int id, Uint8List? bytes) {
    // Keep a reasonable cap to avoid unbounded memory growth
    if (_cache.length > 400) {
      _cache.remove(_cache.keys.first);
    }
    _cache[id] = bytes;
  }

  bool contains(int id) => _cache.containsKey(id);
}

/// Displays the album artwork for a [Track].
///
/// Artwork bytes are fetched exactly ONCE per track ID and stored in a
/// process-level cache — rebuilds / scrolls / state changes never cause
/// a re-fetch or flicker.
class TrackArtwork extends StatefulWidget {
  final Track track;
  final double width;
  final double height;
  final double borderRadius;
  final bool showShadow;
  final Widget? customFallback;

  const TrackArtwork({
    super.key,
    required this.track,
    this.width = 150,
    this.height = 150,
    this.borderRadius = AppRadius.artwork,
    this.showShadow = true,
    this.customFallback,
  });

  @override
  State<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<TrackArtwork>
    with AutomaticKeepAliveClientMixin {
  // null means "still loading", _loaded=true means we got a definitive answer
  Uint8List? _bytes;
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant TrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only re-fetch when the track ID actually changes
    if (oldWidget.track.id != widget.track.id) {
      _loaded = false;
      _bytes = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final id = widget.track.id;
    if (id == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }

    final cache = _ArtworkCache.instance;
    if (cache.contains(id)) {
      if (mounted) {
        setState(() {
          _bytes = cache.get(id);
          _loaded = true;
        });
      }
      return;
    }

    // Fetch once
    try {
      final bytes = await OnAudioQuery().queryArtwork(
        id,
        ArtworkType.AUDIO,
        quality: 70,
        size: 250,
      );
      cache.set(id, bytes);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loaded = true;
        });
      }
    } catch (_) {
      cache.set(id, null);
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    Widget content;
    if (!_loaded) {
      // Show a static placeholder while bytes load (no animation = no flicker)
      content = _Placeholder(
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius,
      );
    } else if (_bytes != null && _bytes!.isNotEmpty) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.memory(
          _bytes!,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          // gaplessPlayback prevents white flash between consecutive loads
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => widget.customFallback ??
              _Fallback(
                width: widget.width,
                height: widget.height,
                borderRadius: widget.borderRadius,
              ),
        ),
      );
    } else {
      content = widget.customFallback ??
          _Fallback(
            width: widget.width,
            height: widget.height,
            borderRadius: widget.borderRadius,
          );
    }

    if (!widget.showShadow) return RepaintBoundary(child: content);

    return RepaintBoundary(
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

// ─── Static placeholder (shown before artwork loads) ───

class _Placeholder extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _Placeholder({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: isDark ? const Color(0xFF1A2540) : const Color(0xFFE2E8F0),
      ),
    );
  }
}

// ─── Fallback when no artwork available ───

class _Fallback extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _Fallback({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconAsset = isDark ? AppAssets.darkIcon : AppAssets.lightIcon;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF162038), const Color(0xFF0A1020)]
              : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
        ),
      ),
      child: Center(
        child: Image.asset(
          iconAsset,
          width: width * 0.55,
          height: height * 0.55,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.music_note_rounded,
            color: isDark ? Colors.lightBlueAccent : Colors.blueAccent,
            size: width * 0.5,
          ),
        ),
      ),
    );
  }
}