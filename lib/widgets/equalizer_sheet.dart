// equalizer_sheet.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../screens/equalizer_screen.dart';
import 'equalizer_content.dart';

/// Equalizer Bottom Sheet accessible from the Player screen.
/// Hosts the shared [EqualizerContent] widget and supports both Light and Dark modes.
/// Single drag handle with ultra-responsive smooth downward drag dismissal.
class EqualizerSheet extends StatelessWidget {
  final Color accentColor;

  const EqualizerSheet({
    super.key,
    this.accentColor = AppColors.abyssAccent,
  });

  static Future<void> show(BuildContext context, {Color? accentColor}) {
    final effectiveAccent = accentColor ?? Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      showDragHandle: false, // Ensures NO duplicate system drag line
      backgroundColor: isDark ? const Color(0xFF090D16) : Colors.white,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (ctx) => EqualizerSheet(
        accentColor: effectiveAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final handleColor = isDark ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFCBD5E1);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF090D16) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Single Grabber Handle area with quick-close swipe gesture
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                // Immediately and smoothly dismiss when dragging downwards
                if (details.primaryDelta != null && details.primaryDelta! > 4) {
                  Navigator.of(context).pop();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 12, left: 20, right: 12, bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 32),
                    const Spacer(),
                    // The ONLY single grabber line
                    Container(
                      width: 42,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: handleColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Open Full Screen',
                      icon: Icon(Icons.open_in_full_rounded, color: iconColor, size: 18),
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EqualizerScreen(accentColor: accentColor),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Main Equalizer Controls
            Flexible(
              child: EqualizerContent(
                accentColor: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
