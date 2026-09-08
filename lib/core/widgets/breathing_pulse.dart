import 'package:flutter/material.dart';

/// Subtle breathing / pulse scale micro-animation widget for icons and brand avatars.
class BreathingPulse extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double beginScale;
  final double endScale;
  final bool enabled;

  const BreathingPulse({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2000),
    this.beginScale = 0.95,
    this.endScale = 1.05,
    this.enabled = true,
  });

  @override
  State<BreathingPulse> createState() => _BreathingPulseState();
}

class _BreathingPulseState extends State<BreathingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(
      begin: widget.beginScale,
      end: widget.endScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BreathingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return RepaintBoundary(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
