import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'track_artwork.dart';

/// Floating draggable music circle (bubble) that keeps music playing when
/// the mini-player is collapsed.
///
/// Features:
/// - Drag anywhere on screen, smoothly snapping to left or right edge on release.
/// - Tap to open [PlayerScreen].
/// - Double tap to restore standard MiniPlayer pill.
/// - When dragging, an animated "✕ Stop & Dismiss" cross zone appears at bottom center.
///   Dropping the bubble onto the cross stops music completely everywhere.
class FloatingMusicBubble extends StatefulWidget {
  final Color accentColor;
  final VoidCallback onOpenPlayer;
  final VoidCallback onDismiss;
  final VoidCallback? onRestoreMiniPlayer;

  const FloatingMusicBubble({
    super.key,
    required this.accentColor,
    required this.onOpenPlayer,
    required this.onDismiss,
    this.onRestoreMiniPlayer,
  });

  @override
  State<FloatingMusicBubble> createState() => _FloatingMusicBubbleState();
}

class _FloatingMusicBubbleState extends State<FloatingMusicBubble>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _snapController;
  late final AnimationController _crossAnimController;

  Animation<Offset>? _snapAnimation;

  static const double _bubbleSize = 64.0;
  static const double _crossZoneSize = 64.0;

  Offset _position = Offset.zero;
  bool _initializedPosition = false;
  bool _isDragging = false;
  bool _isOverCross = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _crossAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() {
          _position = _snapAnimation!.value;
        });
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _snapController.dispose();
    _crossAnimController.dispose();
    super.dispose();
  }

  void _initPositionIfNeeded(Size screenSize, EdgeInsets padding) {
    if (_initializedPosition) return;
    _initializedPosition = true;
    // Start on the right edge above the bottom nav bar
    _position = Offset(
      screenSize.width - _bubbleSize - 16.0,
      screenSize.height - padding.bottom - 170.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    _initPositionIfNeeded(screenSize, padding);

    return ListenableBuilder(
      listenable: AudioPlayerService.instance,
      builder: (context, _) {
        final track = AudioPlayerService.instance.currentTrack;
        if (track == null) {
          return const SizedBox.shrink();
        }

        final crossCenter = Offset(
          screenSize.width / 2,
          screenSize.height - padding.bottom - 60.0,
        );

        final bubbleCenter = Offset(
          _position.dx + _bubbleSize / 2,
          _position.dy + _bubbleSize / 2,
        );

        final distToCross = (bubbleCenter - crossCenter).distance;
        final isOverCross = _isDragging && distToCross < 75.0;

        if (isOverCross != _isOverCross) {
          _isOverCross = isOverCross;
          if (isOverCross) {
            HapticFeedback.selectionClick();
          }
        }

        return Stack(
          children: [
            // ── Dismiss Cross Zone (Drop Target) ──
            if (_isDragging || _crossAnimController.value > 0.01)
              _buildDismissCrossZone(crossCenter, isOverCross),

            // ── Draggable Floating Bubble ──
            Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onOpenPlayer();
                },
                onDoubleTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onRestoreMiniPlayer?.call();
                },
                onPanStart: (details) {
                  _snapController.stop();
                  setState(() => _isDragging = true);
                  _crossAnimController.forward();
                },
                onPanUpdate: (details) {
                  setState(() {
                    final double newX = (_position.dx + details.delta.dx).clamp(
                      8.0,
                      screenSize.width - _bubbleSize - 8.0,
                    );
                    final double newY = (_position.dy + details.delta.dy).clamp(
                      padding.top + 8.0,
                      screenSize.height - padding.bottom - _bubbleSize - 8.0,
                    );
                    _position = Offset(newX, newY);
                  });
                },
                onPanEnd: (details) async {
                  setState(() => _isDragging = false);
                  _crossAnimController.reverse();

                  if (isOverCross) {
                    // Dropped on cross: STOP MUSIC COMPLETELY & DISMISS
                    HapticFeedback.heavyImpact();
                    await AudioPlayerService.instance.stopAndReset();
                    widget.onDismiss();
                  } else {
                    // Snap to nearest screen edge (left or right)
                    _snapToEdge(screenSize, padding);
                  }
                },
                onPanCancel: () {
                  setState(() => _isDragging = false);
                  _crossAnimController.reverse();
                  _snapToEdge(screenSize, padding);
                },
                child: _buildBubbleContent(track, isOverCross),
              ),
            ),
          ],
        );
      },
    );
  }

  void _snapToEdge(Size screenSize, EdgeInsets padding) {
    final double midX = screenSize.width / 2;
    final double targetX = (_position.dx + _bubbleSize / 2 < midX)
        ? 14.0
        : screenSize.width - _bubbleSize - 14.0;

    final double targetY = _position.dy.clamp(
      padding.top + 20.0,
      screenSize.height - padding.bottom - _bubbleSize - 90.0,
    );

    _snapAnimation = Tween<Offset>(
      begin: _position,
      end: Offset(targetX, targetY),
    ).animate(CurvedAnimation(
      parent: _snapController,
      curve: Curves.easeOutBack,
    ));

    _snapController.forward(from: 0.0);
  }

  Widget _buildDismissCrossZone(Offset crossCenter, bool isTargeted) {
    return AnimatedBuilder(
      animation: _crossAnimController,
      builder: (context, _) {
        final scale = _crossAnimController.value;
        final targetScale = isTargeted ? 1.25 : 1.0;

        return Positioned(
          left: crossCenter.dx - (_crossZoneSize * targetScale) / 2,
          top: crossCenter.dy - (_crossZoneSize * targetScale) / 2,
          child: Opacity(
            opacity: (scale * (isTargeted ? 1.0 : 0.85)).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale * targetScale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _crossZoneSize,
                    height: _crossZoneSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: isTargeted
                            ? [
                                const Color(0xFFFF1744),
                                const Color(0xFFB71C1C),
                              ]
                            : [
                                const Color(0xFF334155).withValues(alpha: 0.9),
                                const Color(0xFF0F172A).withValues(alpha: 0.95),
                              ],
                      ),
                      border: Border.all(
                        color: isTargeted
                            ? Colors.white
                            : const Color(0xFFFF2E7E).withValues(alpha: 0.6),
                        width: isTargeted ? 2.5 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isTargeted
                              ? const Color(0xFFFF1744).withValues(alpha: 0.65)
                              : Colors.black.withValues(alpha: 0.4),
                          blurRadius: isTargeted ? 24 : 12,
                          spreadRadius: isTargeted ? 4 : 1,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        Icons.close_rounded,
                        size: isTargeted ? 32 : 26,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isTargeted ? 'Release to Stop' : 'Drop to Stop',
                      style: TextStyle(
                        color: isTargeted ? const Color(0xFFFF5252) : Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBubbleContent(Track track, bool isOverCross) {
    return AnimatedScale(
      scale: isOverCross ? 0.85 : (_isDragging ? 1.08 : 1.0),
      duration: const Duration(milliseconds: 140),
      child: Container(
        width: _bubbleSize,
        height: _bubbleSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: isOverCross
                  ? const Color(0xFFFF1744).withValues(alpha: 0.6)
                  : widget.accentColor.withValues(alpha: 0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: const Color(0xFFFF2E7E).withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: -2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rotating outer neon ring
            AnimatedBuilder(
              animation: _rotationController,
              builder: (context, _) {
                return Transform.rotate(
                  angle: _rotationController.value * 2 * math.pi,
                  child: Container(
                    width: _bubbleSize,
                    height: _bubbleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(
                        colors: isOverCross
                            ? [
                                const Color(0xFFFF1744),
                                Colors.white,
                                const Color(0xFFFF1744),
                              ]
                            : [
                                widget.accentColor,
                                const Color(0xFFFF2E7E),
                                const Color(0xFF9933FF),
                                widget.accentColor,
                              ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Inner Disc Background
            Container(
              width: _bubbleSize - 5,
              height: _bubbleSize - 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0D121F),
              ),
            ),

            // Vinyl / Artwork Circle
            ClipOval(
              child: SizedBox(
                width: _bubbleSize - 8,
                height: _bubbleSize - 8,
                child: TrackArtwork(
                  track: track,
                  width: _bubbleSize - 8,
                  height: _bubbleSize - 8,
                  borderRadius: (_bubbleSize - 8) / 2,
                  showShadow: false,
                ),
              ),
            ),

            // Subtle dark vinyl center spindle overlay
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.65),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.2,
                ),
              ),
              child: Center(
                child: StreamBuilder<bool>(
                  stream: AudioPlayerService.instance.player.playingStream,
                  initialData: AudioPlayerService.instance.player.playing,
                  builder: (context, playingSnap) {
                    final isPlaying = playingSnap.data ?? false;
                    return Icon(
                      isPlaying ? Icons.music_note_rounded : Icons.pause_rounded,
                      size: 11,
                      color: Colors.white,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
