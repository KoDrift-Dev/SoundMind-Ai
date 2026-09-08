import 'package:flutter/material.dart';

import '../constants/app_opacity.dart';
import '../constants/app_radius.dart';
import '../constants/app_typography.dart';
import 'glass_container.dart';

/// Button variant — controls visual style.
enum SmButtonVariant {
  primary,
  secondary,
  ghost,
  outline,
  destructive,
}

/// Full button system for SoundMind AI.
///
/// Supports: [primary], [secondary], [ghost], [outline], [destructive]
/// States: normal, pressed (scale), disabled, loading.
class SmButton extends StatefulWidget {
  const SmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SmButtonVariant.primary,
    this.accentColor,
    this.icon,
    this.loading = false,
    this.enabled = true,
    this.fullWidth = false,
    this.small = false,
  });

  /// Icon-only button
  const SmButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    this.variant = SmButtonVariant.ghost,
    this.accentColor,
    this.loading = false,
    this.enabled = true,
  })  : label = '',
        fullWidth = false,
        small = true;

  final String label;
  final VoidCallback? onPressed;
  final SmButtonVariant variant;
  final Color? accentColor;
  final IconData? icon;
  final bool loading;
  final bool enabled;
  final bool fullWidth;
  final bool small;

  @override
  State<SmButton> createState() => _SmButtonState();
}

class _SmButtonState extends State<SmButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _press;
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  bool get _isIconOnly => widget.label.isEmpty && widget.icon != null;

  @override
  Widget build(BuildContext context) {
    final bool canPress = widget.enabled && !widget.loading;
    final Color acc = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: canPress ? (_) => _press.reverse() : null,
        onTapUp: canPress
            ? (_) {
                _press.forward();
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: () => _press.forward(),
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: _buildBody(acc),
        ),
      ),
    );
  }

  Widget _buildBody(Color acc) {
    final double vPad = widget.small ? 8 : 13;
    final double hPad = _isIconOnly ? (widget.small ? 10 : 14) : (widget.small ? 14 : 20);

    final Widget content = _isIconOnly
        ? _buildIcon(acc)
        : _buildLabel(acc);

    switch (widget.variant) {
      case SmButtonVariant.primary:
        return Container(
          width: widget.fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          decoration: BoxDecoration(
            color: acc,
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: [
              BoxShadow(
                color: acc.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: content,
        );

      case SmButtonVariant.secondary:
        return GlassContainer(
          tier: GlassTier.primary,
          borderRadius: AppRadius.full,
          borderColor: acc.withValues(alpha: AppOpacity.glassBorderStrong),
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          width: widget.fullWidth ? double.infinity : null,
          child: content,
        );

      case SmButtonVariant.ghost:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          child: content,
        );

      case SmButtonVariant.outline:
        return Container(
          width: widget.fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: acc.withValues(alpha: 0.50), width: 1.5),
          ),
          child: content,
        );

      case SmButtonVariant.destructive:
        return Container(
          width: widget.fullWidth ? double.infinity : null,
          padding: EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
          decoration: BoxDecoration(
            color: const Color(0xFFF87171).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: const Color(0xFFF87171).withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: content,
        );
    }
  }

  Widget _buildLabel(Color acc) {
    final bool isPrimary = widget.variant == SmButtonVariant.primary;
    final Color fgColor = isPrimary ? Colors.black87 : acc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: fgColor,
            ),
          )
        else if (widget.icon != null) ...[
          Icon(widget.icon, size: 16, color: fgColor),
          const SizedBox(width: 6),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: AppTypography.labelL,
            fontWeight: FontWeight.w600,
            color: fgColor,
          ),
        ),
      ],
    );
  }

  Widget _buildIcon(Color acc) {
    final bool isPrimary = widget.variant == SmButtonVariant.primary;
    final Color fgColor = isPrimary ? Colors.black87 : acc;
    if (widget.loading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: fgColor),
      );
    }
    return Icon(widget.icon, size: widget.small ? 18 : 22, color: fgColor);
  }
}
