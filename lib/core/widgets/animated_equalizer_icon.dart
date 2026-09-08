import 'package:flutter/material.dart';

/// Auto-looping 3-bar animated equalizer icon widget rendered purely via Flutter animations.
class AnimatedEqualizerIcon extends StatefulWidget {
  final Color color;
  final double size;

  const AnimatedEqualizerIcon({
    super.key,
    required this.color,
    this.size = 18.0,
  });

  @override
  State<AnimatedEqualizerIcon> createState() => _AnimatedEqualizerIconState();
}

class _AnimatedEqualizerIconState extends State<AnimatedEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return SizedBox(
          height: widget.size,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 3,
                height: (widget.size * 0.4) + (_ctrl.value * (widget.size * 0.55)),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 2.5),
              Container(
                width: 3,
                height: (widget.size * 0.9) - (_ctrl.value * (widget.size * 0.45)),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 2.5),
              Container(
                width: 3,
                height: (widget.size * 0.35) + (_ctrl.value * (widget.size * 0.65)),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
