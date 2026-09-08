import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_blur.dart';
import '../constants/app_opacity.dart';
import '../constants/app_radius.dart';
import '../constants/app_typography.dart';

/// Glass input field with animated focus glow and clear button.
///
/// Drop-in for Search screen; also used wherever a text input is needed.
class SmTextField extends StatefulWidget {
  const SmTextField({
    super.key,
    required this.controller,
    required this.accentColor,
    this.focusNode,
    this.hint = '',
    this.prefixIcon,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.search,
    this.autofocus = false,
    this.isDark = true,
  });

  final TextEditingController controller;
  final Color accentColor;
  final FocusNode? focusNode;
  final String hint;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;
  final bool autofocus;
  final bool isDark;

  @override
  State<SmTextField> createState() => _SmTextFieldState();
}

class _SmTextFieldState extends State<SmTextField>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focus;
  late final AnimationController _glow;
  late final Animation<double> _glowAnim;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _glowAnim = CurvedAnimation(parent: _glow, curve: Curves.easeOut);
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focus.hasFocus);
    if (_focus.hasFocus) {
      _glow.forward();
    } else {
      _glow.reverse();
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha: 0.25 * _glowAnim.value),
                blurRadius: 18,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppBlur.glass2, sigmaY: AppBlur.glass2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF0B1730).withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _isFocused
                    ? widget.accentColor
                    : (widget.isDark
                        ? widget.accentColor.withValues(alpha: 0.35)
                        : const Color(0xFFCBD5E1)),
                width: _isFocused ? 1.5 : 1.0,
              ),
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: AppTypography.bodyM,
                color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                hintText: widget.hint,
                hintStyle: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: AppTypography.bodyM,
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: AppOpacity.textHint)
                      : const Color(0xFF64748B),
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: _isFocused
                            ? widget.accentColor
                            : (widget.isDark
                                ? widget.accentColor.withValues(alpha: 0.8)
                                : widget.accentColor),
                        size: 20,
                      )
                    : null,
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (_, val, _) {
                    if (val.text.isEmpty) return const SizedBox.shrink();
                    return GestureDetector(
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                        HapticFeedback.lightImpact();
                      },
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: AppOpacity.iconMuted)
                            : const Color(0xFF64748B),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
