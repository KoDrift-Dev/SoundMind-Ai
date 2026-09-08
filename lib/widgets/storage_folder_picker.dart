import 'dart:io';
import 'package:flutter/material.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';

class StorageFolderPicker extends StatefulWidget {
  final String initialPath;
  final Color accentColor;

  const StorageFolderPicker({
    super.key,
    required this.initialPath,
    required this.accentColor,
  });

  static Future<String?> show(BuildContext context, {String? initialPath, required Color accentColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (ctx) => StorageFolderPicker(
        initialPath: initialPath ?? '/storage/emulated/0',
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<StorageFolderPicker> createState() => _StorageFolderPickerState();
}

class _StorageFolderPickerState extends State<StorageFolderPicker> {
  late Directory _currentDir;
  List<Directory> _subDirs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final candidate = Directory(widget.initialPath);
    if (candidate.existsSync()) {
      _currentDir = candidate;
    } else {
      _currentDir = Directory('/storage/emulated/0');
      if (!_currentDir.existsSync()) {
        _currentDir = Directory.current;
      }
    }
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() => _isLoading = true);
    final dirs = <Directory>[];
    try {
      await for (final entity in _currentDir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (!name.startsWith('.')) {
            dirs.add(entity);
          }
        }
      }
      dirs.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    } catch (_) {}

    if (mounted) {
      setState(() {
        _subDirs = dirs;
        _isLoading = false;
      });
    }
  }

  void _navigateUp() {
    final parent = _currentDir.parent;
    if (parent.path != _currentDir.path && parent.existsSync()) {
      _currentDir = parent;
      _loadDirectories();
    }
  }

  void _navigateTo(Directory dir) {
    _currentDir = dir;
    _loadDirectories();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                Icon(Icons.folder_open_rounded, color: widget.accentColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Select Folder',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const Spacer(),
                if (_currentDir.path != '/storage/emulated/0' && _currentDir.parent.path != _currentDir.path)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    tooltip: 'Parent Folder',
                    color: primaryTextColor,
                    onPressed: _navigateUp,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Current path badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                ),
              ),
              child: Text(
                _currentDir.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: secondaryTextColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Subdirectories list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _subDirs.isEmpty
                      ? Center(
                          child: Text(
                            'No subfolders here.\nYou can select this folder below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: secondaryTextColor, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _subDirs.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, index) {
                            final dir = _subDirs[index];
                            final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              leading: Icon(
                                Icons.folder_rounded,
                                color: widget.accentColor.withValues(alpha: 0.85),
                                size: 22,
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: primaryTextColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: secondaryTextColor,
                                size: 18,
                              ),
                              onTap: () => _navigateTo(dir),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 10),
            // Select button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text(
                  'Select This Folder',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context, _currentDir.path),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
