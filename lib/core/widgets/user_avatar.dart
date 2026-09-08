import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/music_avatar_painter.dart';

export '../../widgets/music_avatar_painter.dart';

class AvatarPreset {
  final String id;
  final String label;
  final IconData icon;
  final List<Color> colors;

  const AvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.colors,
  });
}

const List<AvatarPreset> kAvatarPresets = [
  AvatarPreset(
    id: 'headphones',
    label: 'Headphones',
    icon: Icons.headphones_rounded,
    colors: [Color(0xFF38BDF8), Color(0xFF1D4ED8)],
  ),
  AvatarPreset(
    id: 'music',
    label: 'Melody',
    icon: Icons.music_note_rounded,
    colors: [Color(0xFFA855F7), Color(0xFF6366F1)],
  ),
  AvatarPreset(
    id: 'dj',
    label: 'DJ Vinyl',
    icon: Icons.album_rounded,
    colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
  ),
  AvatarPreset(
    id: 'mic',
    label: 'Vocalist',
    icon: Icons.mic_rounded,
    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
  ),
  AvatarPreset(
    id: 'wave',
    label: 'Frequency',
    icon: Icons.graphic_eq_rounded,
    colors: [Color(0xFF10B981), Color(0xFF06B6D4)],
  ),
  AvatarPreset(
    id: 'star',
    label: 'Superstar',
    icon: Icons.star_rounded,
    colors: [Color(0xFFFBBF24), Color(0xFFD97706)],
  ),
  AvatarPreset(
    id: 'fire',
    label: 'Fire Beats',
    icon: Icons.local_fire_department_rounded,
    colors: [Color(0xFFFF5722), Color(0xFFE91E63)],
  ),
  AvatarPreset(
    id: 'ai',
    label: 'SoundMind AI',
    icon: Icons.auto_awesome_rounded,
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  ),
];

class UserAvatar extends StatelessWidget {
  final double size;
  final bool isDark;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    this.size = 40,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPreferencesService.instance,
      builder: (context, _) {
        final avatarType = UserPreferencesService.instance.avatarType;
        final avatarValue = UserPreferencesService.instance.avatarValue;

        Widget content;

        if (avatarType == 'file' && avatarValue.isNotEmpty) {
          final file = File(avatarValue);
          if (file.existsSync()) {
            content = Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildFallbackPreset('music_cyber_blue'),
            );
          } else {
            content = _buildFallbackPreset('music_cyber_blue');
          }
        } else {
          content = _buildFallbackPreset(avatarValue);
        }

        final container = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0xFF0F172A))
                    .withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(child: content),
        );

        if (onTap != null) {
          return GestureDetector(onTap: onTap, child: container);
        }
        return container;
      },
    );
  }

  Widget _buildFallbackPreset(String presetId) {
    final config = resolveAvatarConfig(presetId);

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: isDark
              ? const [Color(0xFF1E293B), Color(0xFF0B0F19)]
              : const [Color(0xFF334155), Color(0xFF0F172A)],
          center: Alignment.topCenter,
          radius: 0.9,
        ),
      ),
      child: Center(
        child: MusicAvatar.fromConfig(
          config,
          size: size,
        ),
      ),
    );
  }
}
