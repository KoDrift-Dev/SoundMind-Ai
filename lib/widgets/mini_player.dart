import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../core/constants/app_blur.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'track_artwork.dart';

/// Floating liquid glass mini-player pill shown above the bottom navigation bar.
///
/// Features:
/// 1. Close & Dismiss System:
///    - Top-right subtle animated '✕' close button with hover/tap scale effects.
///    - Immediately stops audio, resets player state, and smoothly unmounts.
///    - Multi-directional drag-to-dismiss gestures (downward `drag="y"` and horizontal `drag="x"`).
/// 2. Code-Based Animated Play/Pause Button:
///    - Pure code vector morphing between Play triangle and Pause double bars with rounded line caps.
///    - Responsive Dark Mode (glowing neon cyan/teal) and Light Mode (crisp contrast border & drop shadow).
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    required this.accentColor,
    required this.onTap,
    this.onConvertToFloating,
  });

  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback? onConvertToFloating;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> with TickerProviderStateMixin {
  late final AnimationController _dismissController;
  late final AnimationController _springController;

  Animation<Offset>? _dismissAnimation;
  Animation<Offset>? _springAnimation;

  Offset _dragOffset = Offset.zero;
  bool _isDismissing = false;
  Track? _cachedTrack;

  /// Set to true after user explicitly dismisses the player.
  /// Cleared automatically when a brand-new track starts playing.
  bool _dismissed = false;

  /// The last track ID we saw as "current" so we can detect a new track starting.
  int? _lastSeenTrackId;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _dismissController.addListener(() {
      if (mounted) setState(() {});
    });
    _springController.addListener(() {
      if (mounted) {
        setState(() {
          if (_springAnimation != null) {
            _dragOffset = _springAnimation!.value;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _dismissController.dispose();
    _springController.dispose();
    super.dispose();
  }

  /// Smoothly animates the player off-screen, converts to floating bubble or stops audio, and unmounts.
  Future<void> _triggerDismiss({required Offset targetOffset}) async {
    if (_isDismissing || _dismissed) return;
    setState(() => _isDismissing = true);

    if (widget.onConvertToFloating != null) {
      _dismissAnimation = Tween<Offset>(
        begin: _dragOffset,
        end: targetOffset,
      ).animate(CurvedAnimation(
        parent: _dismissController,
        curve: Curves.easeOutCubic,
      ));

      await _dismissController.forward(from: 0.0);

      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
          _isDismissing = false;
          _cachedTrack = null;
          _lastSeenTrackId = null;
          _dismissed = true;
        });
        _dismissController.reset();
      }
      widget.onConvertToFloating!();
      return;
    }

    // Terminate audio playback and reset player state immediately
    unawaited(AudioPlayerService.instance.stopAndReset());

    _dismissAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(CurvedAnimation(
      parent: _dismissController,
      curve: Curves.easeOutCubic,
    ));

    await _dismissController.forward(from: 0.0);

    if (mounted) {
      setState(() {
        _dragOffset = Offset.zero;
        _isDismissing = false;
        // Permanently clear the cached track so the widget stays hidden
        _cachedTrack = null;
        _lastSeenTrackId = null;
        _dismissed = true;
      });
      _dismissController.reset();
    }
  }

  /// Handles tap on the subtle top-right '✕' button.
  void _handleCloseTap() {
    HapticFeedback.lightImpact();
    _triggerDismiss(targetOffset: const Offset(0, 160));
  }

  // ──────────────────────── Gesture Drag Handling ────────────────────────

  void _onPanStart(DragStartDetails details) {
    if (_isDismissing) return;
    _springController.stop();
    _dragOffset = Offset.zero;
  }

  void _onPanUpdate(DragStartDetails? start, DragUpdateDetails details) {
    if (_isDismissing) return;
    setState(() {
      final double nextDx = _dragOffset.dx + details.delta.dx;
      double nextDy = _dragOffset.dy + details.delta.dy;
      // Damped elastic resistance when dragging upward
      if (nextDy < 0) {
        nextDy = nextDy * 0.25;
      }
      _dragOffset = Offset(nextDx, nextDy);
    });
  }

  void _onPanCancel() {
    if (_isDismissing) return;
    _springAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _springController,
      curve: Curves.easeOutCubic,
    ));
    _springController.forward(from: 0.0);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isDismissing) return;

    final velocity = details.velocity.pixelsPerSecond;
    final double dx = _dragOffset.dx;
    final double dy = _dragOffset.dy;

    // Multi-directional dismissal threshold check:
    // Downward swipe:
    final bool dismissDown = dy > 30 || (velocity.dy > 200 && dy > 8);
    // Horizontal swipe (left or right):
    final bool dismissHorizontal = dx.abs() > 35 || (velocity.dx.abs() > 200 && dx.abs() > 8);

    if (dismissDown) {
      final double targetY = dy + 180.0;
      _triggerDismiss(targetOffset: Offset(dx, targetY));
    } else if (dismissHorizontal) {
      final double direction = dx != 0 ? dx.sign : (velocity.dx >= 0 ? 1.0 : -1.0);
      _triggerDismiss(targetOffset: Offset(direction * 480, dy));
    } else {
      // Spring back to center
      _springAnimation = Tween<Offset>(
        begin: _dragOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _springController,
        curve: Curves.easeOutCubic,
      ));
      _springController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0B132B);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);
    final iconMutedColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF0B132B).withValues(alpha: 0.7);

    return ListenableBuilder(
      listenable: AudioPlayerService.instance,
      builder: (context, _) {
        final service = AudioPlayerService.instance;
        final Track? currentTrack = service.currentTrack;

        // If a brand-new track has started, lift the dismissed flag
        if (currentTrack != null && currentTrack.id != _lastSeenTrackId) {
          _dismissed = false;
          _lastSeenTrackId = currentTrack.id;
          _cachedTrack = currentTrack;
        } else if (currentTrack != null) {
          _cachedTrack = currentTrack;
        }

        // Stay hidden if dismissed or no track ever loaded
        if (_dismissed) return const SizedBox.shrink();

        final Track? displayTrack = currentTrack ?? _cachedTrack;
        if (displayTrack == null && !_isDismissing) {
          return const SizedBox.shrink();
        }

        // Compute current gesture / dismiss offset
        final Offset currentOffset = _isDismissing
            ? (_dismissAnimation?.value ?? _dragOffset)
            : _dragOffset;

        final double distance = currentOffset.distance;
        final double opacity = (1.0 - (distance / 200.0)).clamp(0.0, 1.0);
        final double scale = (1.0 - (distance / 1200.0)).clamp(0.88, 1.0);

        return RepaintBoundary(
          child: Transform.translate(
            offset: currentOffset,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isDismissing ? null : widget.onTap,
                  onPanStart: _onPanStart,
                  onPanUpdate: (details) => _onPanUpdate(null, details),
                  onPanEnd: _onPanEnd,
                  onPanCancel: _onPanCancel,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: AppBlur.glass3,
                          sigmaY: AppBlur.glass3,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0D1527).withValues(alpha: 0.85)
                                : Colors.white.withValues(alpha: 0.90),
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: isDark ? 0.38 : 0.42),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.45)
                                    : widget.accentColor.withValues(alpha: 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                                spreadRadius: -2,
                              ),
                              BoxShadow(
                                color: widget.accentColor.withValues(alpha: 0.20),
                                blurRadius: 18,
                                spreadRadius: -1,
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Progress bar at top edge
                                  _ProgressBar(
                                    service: service,
                                    accentColor: widget.accentColor,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 26, 10),
                                    child: Row(
                                      children: [
                                        // Artwork
                                        TrackArtwork(
                                          track: displayTrack!,
                                          width: 44,
                                          height: 44,
                                          borderRadius: AppRadius.sm,
                                          showShadow: false,
                                        ),
                                        const SizedBox(width: 12),

                                        // Track info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                displayTrack.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: primaryTextColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontFamily: AppTypography.uiFont,
                                                  fontSize: 13,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                displayTrack.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: subtitleColor,
                                                  fontFamily: AppTypography.uiFont,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Animated Play/Pause Button (pure code morphing)
                                        StreamBuilder<PlayerState>(
                                          stream: service.player.playerStateStream,
                                          builder: (context, stateSnap) {
                                            final bool playing = stateSnap.data?.playing ??
                                                service.player.playing;
                                            return AnimatedPlayPauseButton(
                                              isPlaying: playing,
                                              isDark: isDark,
                                              accentColor: widget.accentColor,
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                playing
                                                    ? service.player.pause()
                                                    : service.player.play();
                                              },
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 4),

                                        // Skip Next Button
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            service.skipToNext();
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: Icon(
                                              Icons.skip_next_rounded,
                                              color: iconMutedColor,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // Subtle animated '✕' close button at top-right corner
                              Positioned(
                                top: 6,
                                right: 6,
                                child: _CloseButton(
                                  isDark: isDark,
                                  onClose: _handleCloseTap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────── Animated '✕' Close Button ────────────────────────

class _CloseButton extends StatefulWidget {
  const _CloseButton({
    required this.isDark,
    required this.onClose,
  });

  final bool isDark;
  final VoidCallback onClose;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.88 : (_isHovered ? 1.15 : 1.0);

    final Color bgColor = widget.isDark
        ? Colors.white.withValues(alpha: _isHovered ? 0.20 : 0.08)
        : const Color(0xFF0F172A).withValues(alpha: _isHovered ? 0.12 : 0.06);

    final Color borderColor = widget.isDark
        ? Colors.white.withValues(alpha: _isHovered ? 0.32 : 0.14)
        : const Color(0xFF0F172A).withValues(alpha: _isHovered ? 0.22 : 0.10);

    final Color iconColor = widget.isDark
        ? Colors.white.withValues(alpha: _isHovered ? 1.0 : 0.70)
        : const Color(0xFF0F172A).withValues(alpha: _isHovered ? 1.0 : 0.70);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onClose();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: borderColor, width: 0.9),
            ),
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────── Animated Play/Pause Button ────────────────────────

/// Code-based dynamic animated Play/Pause toggle button.
///
/// Uses pure vector math with custom canvas drawing:
/// - Smooth morphing between Play triangle and Pause double bars with rounded line caps.
/// - Dark Mode: Glowing neon cyan/teal stroke/fill against dark backdrop.
/// - Light Mode: Crisp border and light palette with drop shadow.
class AnimatedPlayPauseButton extends StatefulWidget {
  const AnimatedPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
    this.size = 40.0,
  });

  final bool isPlaying;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;
  final double size;

  @override
  State<AnimatedPlayPauseButton> createState() => _AnimatedPlayPauseButtonState();
}

class _AnimatedPlayPauseButtonState extends State<AnimatedPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morphController;
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _morphController.forward();
      } else {
        _morphController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.90 : (_isHovered ? 1.08 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _morphController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _PlayPauseMorphPainter(
                    progress: _morphController.value,
                    isDark: widget.isDark,
                    accentColor: widget.accentColor,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseMorphPainter extends CustomPainter {
  _PlayPauseMorphPainter({
    required this.progress,
    required this.isDark,
    required this.accentColor,
  });

  /// 0.0 = Play triangle, 1.0 = Pause double bars.
  final double progress;
  final bool isDark;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width / 2) - 2.5;

    // ──────────────────────── 1. Outer Ring & Backdrop ────────────────────────

    if (isDark) {
      // Dark Mode: Glowing neon cyan/teal styling
      const Color neonCyan = Color(0xFF00F0FF);

      // Neon outer glow blur
      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..color = neonCyan.withValues(alpha: 0.50)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
      canvas.drawCircle(center, radius, glowPaint);

      // Dark translucent backdrop
      final Paint bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF091428).withValues(alpha: 0.82);
      canvas.drawCircle(center, radius, bgPaint);

      // Neon stroke ring with gradient
      final Paint ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader = LinearGradient(
          colors: [
            neonCyan,
            accentColor,
            const Color(0xFF00D2FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, ringPaint);
    } else {
      // Light Mode: Crisp contrast border and soft drop shadow
      final Path circlePath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.drawShadow(
        circlePath,
        accentColor.withValues(alpha: 0.28),
        4.0,
        true,
      );

      final Paint bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.96);
      canvas.drawCircle(center, radius, bgPaint);

      final Paint ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = accentColor.withValues(alpha: 0.88);
      canvas.drawCircle(center, radius, ringPaint);
    }

    // ──────────────────────── 2. Morphing Play ↔ Pause Geometry ────────────────────────

    final double t = progress.clamp(0.0, 1.0);

    // Geometry parameters:
    const double barHeight = 6.2;
    const double barWidth = 3.0;

    // Color definitions for the morphing strokes
    final Color strokeColor = isDark
        ? const Color(0xFF00F0FF)
        : accentColor;

    final Paint strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Subtle neon glow on the glyph strokes in dark mode
    if (isDark) {
      final Paint glyphGlowPaint = Paint()
        ..color = strokeColor.withValues(alpha: 0.55)
        ..strokeWidth = barWidth + 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);

      _drawMorphLines(canvas, center, t, barHeight, glyphGlowPaint);
    }

    // Draw the primary morphing strokes
    _drawMorphLines(canvas, center, t, barHeight, strokePaint);

    // When near Play state (t < 0.5), paint a soft glowing interior fill for the play triangle
    if (t < 0.45) {
      final double fillAlpha = (1.0 - (t / 0.45)).clamp(0.0, 1.0) * (isDark ? 0.35 : 0.22);
      final Paint fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = strokeColor.withValues(alpha: fillAlpha);

      final Path trianglePath = Path()
        ..moveTo(center.dx - 4.5, center.dy - barHeight)
        ..lineTo(center.dx + 7.5, center.dy)
        ..lineTo(center.dx - 4.5, center.dy + barHeight)
        ..close();

      canvas.drawPath(trianglePath, fillPaint);
    }
  }

  /// Draws the 3 morphing segments that transition between Play triangle and Pause double bars.
  void _drawMorphLines(
    Canvas canvas,
    Offset c,
    double t,
    double h,
    Paint paint,
  ) {
    // Left Base / Left Pause Bar:
    // In both Play and Pause, left bar is vertical at x = (c.dx - 4.5)
    final Offset p1 = Offset(c.dx - 4.5, c.dy - h);
    final Offset p2 = Offset(c.dx - 4.5, c.dy + h);
    canvas.drawLine(p1, p2, paint);

    // Top Segment (Top diagonal of Play -> Upper half of right Pause bar):
    // In Play (t=0): from (c.dx - 4.5, c.dy - h) to (c.dx + 7.5, c.dy)
    // In Pause (t=1): from (c.dx + 4.5, c.dy - h) to (c.dx + 4.5, c.dy)
    final double topStartX = lerpDouble(c.dx - 4.5, c.dx + 4.5, t)!;
    final double topEndX = lerpDouble(c.dx + 7.5, c.dx + 4.5, t)!;
    canvas.drawLine(
      Offset(topStartX, c.dy - h),
      Offset(topEndX, c.dy),
      paint,
    );

    // Bottom Segment (Bottom diagonal of Play -> Lower half of right Pause bar):
    // In Play (t=0): from (c.dx - 4.5, c.dy + h) to (c.dx + 7.5, c.dy)
    // In Pause (t=1): from (c.dx + 4.5, c.dy + h) to (c.dx + 4.5, c.dy)
    final double botStartX = lerpDouble(c.dx - 4.5, c.dx + 4.5, t)!;
    final double botEndX = lerpDouble(c.dx + 7.5, c.dx + 4.5, t)!;
    canvas.drawLine(
      Offset(botStartX, c.dy + h),
      Offset(botEndX, c.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayPauseMorphPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDark != isDark ||
        oldDelegate.accentColor != accentColor;
  }
}

// ──────────────────────── Progress Bar ────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.service,
    required this.accentColor,
  });

  final AudioPlayerService service;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: service.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final total = service.player.duration ?? Duration.zero;
        final double progress = total.inMilliseconds > 0
            ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: accentColor.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            minHeight: 2.5,
          ),
        );
      },
    );
  }
}