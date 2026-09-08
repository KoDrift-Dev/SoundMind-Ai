import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Gentle weightless zero-gravity floating drift widget.
/// Gives elements a simulated floating physics feel without degrading scroll performance.
class ZeroGravityDrift extends StatefulWidget {
  const ZeroGravityDrift({
    super.key,
    required this.child,
    this.maxOffset = 4.0,
    this.duration = const Duration(milliseconds: 3200),
    this.enabled = true,
  });

  final Widget child;
  final double maxOffset;
  final Duration duration;
  final bool enabled;

  @override
  State<ZeroGravityDrift> createState() => _ZeroGravityDriftState();
}

class _ZeroGravityDriftState extends State<ZeroGravityDrift>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ZeroGravityDrift oldWidget) {
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
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final val = math.sin(_controller.value * math.pi);
          return Transform.translate(
            offset: Offset(0, -widget.maxOffset * val),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
