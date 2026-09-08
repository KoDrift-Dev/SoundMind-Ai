import 'dart:io';
import 'package:flutter/material.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../core/widgets/user_avatar.dart';
import '../services/user_preferences_service.dart';

class AvatarPickerSheet extends StatefulWidget {
  final Color accentColor;

  const AvatarPickerSheet({super.key, required this.accentColor});

  static Future<void> show(BuildContext context, {required Color accentColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (ctx) => AvatarPickerSheet(accentColor: accentColor),
    );
  }

  @override
  State<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<AvatarPickerSheet> {
  bool _isBrowsingStorage = false;
  List<File> _storageImages = [];
  bool _isLoadingImages = false;

  Future<void> _scanStorageImages() async {
    setState(() {
      _isBrowsingStorage = true;
      _isLoadingImages = true;
    });

    final foundImages = <File>[];
    final candidateDirs = [
      Directory('/storage/emulated/0/DCIM/Camera'),
      Directory('/storage/emulated/0/Pictures'),
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/DCIM'),
    ];

    for (final dir in candidateDirs) {
      if (dir.existsSync()) {
        try {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final lower = entity.path.toLowerCase();
              if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
                foundImages.add(entity);
                if (foundImages.length >= 60) break;
              }
            }
          }
        } catch (_) {}
      }
      if (foundImages.length >= 60) break;
    }

    if (mounted) {
      setState(() {
        _storageImages = foundImages;
        _isLoadingImages = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final currentAvatarType = UserPreferencesService.instance.avatarType;
    final currentAvatarValue = UserPreferencesService.instance.avatarValue;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Icon(Icons.face_rounded, color: widget.accentColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  _isBrowsingStorage ? 'Select Photo from Memory' : 'Choose Your Avatar',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const Spacer(),
                if (_isBrowsingStorage)
                  TextButton(
                    onPressed: () => setState(() => _isBrowsingStorage = false),
                    child: Text('Presets', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_isBrowsingStorage) ...[
              // Preset Grid
              Expanded(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: kMusicAvatarPresets.length,
                  itemBuilder: (context, index) {
                    final preset = kMusicAvatarPresets[index];
                    final resolvedCurrent = resolveAvatarConfig(currentAvatarValue);
                    final isSelected = currentAvatarType == 'preset' &&
                        (currentAvatarValue == preset.id || resolvedCurrent.id == preset.id);

                    return GestureDetector(
                      onTap: () async {
                        await UserPreferencesService.instance.setPresetAvatar(preset.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: isDark
                                    ? const [Color(0xFF1E293B), Color(0xFF0B0F19)]
                                    : const [Color(0xFF334155), Color(0xFF0F172A)],
                                center: Alignment.topCenter,
                                radius: 0.9,
                              ),
                              border: Border.all(
                                color: isSelected ? widget.accentColor : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                                width: isSelected ? 2.6 : 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: widget.accentColor.withValues(alpha: 0.5),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipOval(
                                  child: MusicAvatar.fromConfig(
                                    preset,
                                    size: 58,
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    right: 1,
                                    bottom: 1,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: widget.accentColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preset.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 10.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? widget.accentColor : secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Memory / Custom Photo Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text(
                    'Select Photo from Storage / Memory',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryTextColor,
                    side: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _scanStorageImages,
                ),
              ),
            ] else ...[
              // Storage Images Grid
              Expanded(
                child: _isLoadingImages
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _storageImages.isEmpty
                        ? Center(
                            child: Text(
                              'No photos found in standard folders.\n(DCIM, Pictures, Download)',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: secondaryTextColor, fontSize: 13),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemCount: _storageImages.length,
                            itemBuilder: (context, index) {
                              final file = _storageImages[index];
                              return GestureDetector(
                                onTap: () async {
                                  await UserPreferencesService.instance.setFileAvatar(file.path);
                                  if (context.mounted) Navigator.pop(context);
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
