import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/section_accents.dart';
import '../core/widgets/themed_icon.dart';
import '../models/storage_insights.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_scanner_service.dart';
import '../services/download/download_models.dart';
import '../services/download/download_service.dart';
import '../services/library_backup_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/duplicate_review_sheet.dart';
import '../widgets/genre_selector_grid.dart';
import '../widgets/storage_insights_sheet.dart';
import '../widgets/storage_folder_picker.dart';
import '../widgets/avatar_picker_sheet.dart';
import '../core/widgets/user_avatar.dart';
import 'car_mode_screen.dart';
import 'equalizer_screen.dart';
import 'welcome_onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.accentColor,
    required this.isThemeOne,
    required this.onThemeToggle,
  });

  final Color accentColor;
  final bool isThemeOne;
  final ValueChanged<bool> onThemeToggle;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Color get accentColor => widget.accentColor;
  bool get isThemeOne => widget.isThemeOne;
  ValueChanged<bool> get onThemeToggle => widget.onThemeToggle;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(List<String?> terms) {
    if (_searchQuery.trim().isEmpty) return true;
    final q = _searchQuery.toLowerCase().trim();
    return terms.any((t) => t != null && t.toLowerCase().contains(q));
  }

  // ──────────────────────── Profile Dialog ────────────────────────
  void _showEditNameDialog(BuildContext context) {
    final textController = TextEditingController(
      text: UserPreferencesService.instance.userName,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isThemeOne ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: accentColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        title: Text(
          'Edit Your Name',
          style: TextStyle(
            fontFamily: AppTypography.displayFont,
            fontSize: 20,
            color: isThemeOne ? Colors.white : const Color(0xFF0B132B),
          ),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(
            color: isThemeOne ? Colors.white : const Color(0xFF0B132B),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Enter your name',
            hintStyle: TextStyle(
              color: isThemeOne ? Colors.white38 : const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: isThemeOne
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor.withValues(alpha: 0.5)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: isThemeOne ? Colors.white60 : const Color(0xFF475569)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                UserPreferencesService.instance.setUserName(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ──────────────────────── Download Quality Dialog ────────────────────────
  void _showDownloadQualityDialog(BuildContext context, bool isDark) {
    final prefs = UserPreferencesService.instance;
    String selected = prefs.defaultDownloadQuality;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: accentColor.withValues(alpha: 0.35), width: 1.2),
          ),
          title: Text(
            'Default Download Quality',
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0B132B),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('High (192 kbps)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Highest fidelity, recommended for music lovers', style: TextStyle(fontSize: 12)),
                value: DownloadQualityTier.high,
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Medium (128 kbps)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Balanced standard quality and compact file size', style: TextStyle(fontSize: 12)),
                value: DownloadQualityTier.medium,
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Low (64 kbps)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Ultra compact storage, great for limited bandwidth', style: TextStyle(fontSize: 12)),
                value: DownloadQualityTier.low,
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: () async {
                await prefs.setDefaultDownloadQuality(selected);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Default download quality set to ${DownloadQualityTier.getLabel(selected)}'),
                      backgroundColor: accentColor,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── Download Format Dialog ────────────────────────
  void _showDownloadFormatDialog(BuildContext context, bool isDark) {
    final prefs = UserPreferencesService.instance;
    String selected = prefs.defaultDownloadFormat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: accentColor.withValues(alpha: 0.35), width: 1.2),
          ),
          title: Text(
            'Default Download Format',
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0B132B),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('M4A (Default AAC)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Native audio container, high efficiency & tag support', style: TextStyle(fontSize: 12)),
                value: 'm4a',
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('MP3 (Standard Audio)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Maximum legacy compatibility with all external players', style: TextStyle(fontSize: 12)),
                value: 'mp3',
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('WAV (Uncompressed PCM)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Lossless raw audio waveforms, larger file footprint', style: TextStyle(fontSize: 12)),
                value: 'wav',
                groupValue: selected,
                activeColor: accentColor,
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
              onPressed: () async {
                await prefs.setDefaultDownloadFormat(selected);
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Default download format set to ${selected.toUpperCase()}'),
                      backgroundColor: accentColor,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── Cache Management Dialog ────────────────────────
  void _showCacheManagementDialog(BuildContext context, bool isDark) async {
    int cacheBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            cacheBytes += await entity.length();
          }
        }
      }
    } catch (_) {}

    if (!context.mounted) return;

    final String cacheFormatted = StorageInsights.formatBytes(cacheBytes);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: accentColor.withValues(alpha: 0.35), width: 1.2),
          ),
          title: Row(
            children: [
              Icon(Icons.cleaning_services_rounded, color: accentColor),
              const SizedBox(width: 8),
              Text(
                'Storage & Cache Manager',
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0B132B),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Temporary cache and stream buffers currently occupy:',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'App Cache Footprint',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      cacheFormatted,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Clearing cache safely removes temporary download chunks and transient audio streams. Your completed library downloads and playlists are never removed.',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('Clear Cache'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                int freedBytes = 0;
                try {
                  final tempDir = await getTemporaryDirectory();
                  if (await tempDir.exists()) {
                    await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
                      if (entity is File) {
                        try {
                          final len = await entity.length();
                          await entity.delete();
                          freedBytes += len;
                        } catch (_) {}
                      }
                    }
                  }
                } catch (_) {}

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cleared ${StorageInsights.formatBytes(freedBytes)} of cached temp files.'),
                      backgroundColor: accentColor,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── About SoundMind Dialog ────────────────────────
  void _showAboutDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: accentColor.withValues(alpha: 0.35), width: 1.2),
        ),
        title: Row(
          children: [
            ThemedIcon(size: 28, accentColor: accentColor, showGlow: true),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SoundMind AI',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0B132B),
                  ),
                ),
                Text(
                  'Version 1.0.0 (Release)',
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 11,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Intelligent Local & Online Music Player powered by AI audio classification, high-fidelity offline downloads, and heuristic junk filtering.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Dual-Tier Audio Classification (Heuristic & AI)', style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 4),
                  Text('• Resumable FFmpeg High-Fidelity Audio Engine', style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 4),
                  Text('• Unified Download History & Offline Playback', style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 4),
                  Text('• Glassmorphism Design System & Equalizer', style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '© 2026 SoundMind AI Team. Built with Flutter & FFmpeg.',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showLicensePage(
                context: context,
                applicationName: 'SoundMind AI',
                applicationVersion: '1.0.0',
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ThemedIcon(size: 40, accentColor: accentColor, showGlow: false),
                ),
              );
            },
            child: Text('View Licenses', style: TextStyle(color: accentColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ──────────────────────── Export Backup Dialog ────────────────────────
  void _showExportBackupDialog(BuildContext context, Color accentColor, bool isDark) async {
    try {
      final json = await LibraryBackupService.instance.exportBackupJson();
      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Row(
            children: [
              Icon(Icons.backup_rounded, color: accentColor),
              const SizedBox(width: 8),
              const Text('Library Backup Export', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your playlists, favorites, custom classification overrides, and folder exclusions have been compiled into portable JSON format. No raw audio files are exported.'),
            const SizedBox(height: 12),
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.black45 : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy JSON'),
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup copied to clipboard!'), backgroundColor: AppColors.voidOverlay),
                );
              }
            },
          ),
        ],
      ),
    );
    } catch (e) {
      debugPrint('Error exporting backup: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export backup. Please try again.')),
        );
      }
    }
  }

  // ──────────────────────── Optimize Database Dialog ────────────────────────
  void _showOptimizeDatabaseDialog(BuildContext context, Color accentColor, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Row(
          children: [
            Icon(Icons.health_and_safety_rounded, color: accentColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Optimize Library Database',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  fontFamily: AppTypography.displayFont,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About Database Optimization:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 10),
            _buildOptBenefitRow(
              Icons.verified_outlined,
              'Integrity Check',
              'Scans SQLite database files for corrupted pages, broken B-tree indexes, and missing references.',
              accentColor,
              isDark,
            ),
            const SizedBox(height: 8),
            _buildOptBenefitRow(
              Icons.bolt_rounded,
              'Query Speed Tuning (ANALYZE)',
              'Updates table statistics so music searches, artist sorting, and playlist loading execute instantly.',
              accentColor,
              isDark,
            ),
            const SizedBox(height: 8),
            _buildOptBenefitRow(
              Icons.cleaning_services_rounded,
              'Storage Reclaim (VACUUM)',
              'Defragments physical storage, frees space left by deleted tracks, and rebuilds database pages.',
              accentColor,
              isDark,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '100% Safe: Your music files, favorites, playlists, and settings remain untouched.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.speed_rounded, size: 16),
            label: const Text('Optimize Now', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: accentColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Optimizing library database...'),
                    backgroundColor: AppColors.voidOverlay,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
              final ok = await AudioRepository.instance.optimizeDatabase();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Database optimized, defragmented & verified healthy!'
                        : 'Database optimization completed'),
                    backgroundColor: AppColors.voidOverlay,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptBenefitRow(
    IconData icon,
    String title,
    String description,
    Color accentColor,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accentColor, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────── Import Backup Dialog ────────────────────────
  void _showImportBackupDialog(BuildContext context, Color accentColor, bool isDark) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Row(
          children: [
            Icon(Icons.restore_page_rounded, color: accentColor),
            const SizedBox(width: 8),
            const Text('Import Library Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste your exported SoundMind JSON backup below. This will safely restore your playlists, favorites, and overrides inside a protected database transaction.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Paste backup JSON here...',
                filled: true,
                fillColor: isDark ? Colors.black45 : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              final result = await LibraryBackupService.instance.importBackupJson(text);
              if (context.mounted) {
                if (result.isSuccess) {
                  showDialog(
                    context: context,
                    builder: (alertCtx) => AlertDialog(
                      backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      title: const Text('Backup Restored Successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
                      content: Text('Restored:\n• ${result.restoredPlaylistsCount} Playlists\n• ${result.restoredFavoritesCount} Favorites\n• ${result.restoredOverridesCount} Category Overrides\n• ${result.restoredExcludedFoldersCount} Folder Exclusions'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(alertCtx), child: const Text('OK')),
                      ],
                    ),
                  );
                } else {
                  final errorMsg = result.error != null && result.error!.contains('FormatException')
                      ? 'Invalid backup data format. Please verify the JSON.'
                      : (result.error ?? 'Unable to import backup.');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Import Failed: $errorMsg'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  // ──────────────────────── Download Storage Location ────────────────────────
  void _showDownloadLocationDialog(
      BuildContext context, Color accentColor, bool isDark) {
    final prefs = UserPreferencesService.instance;
    String selectedChoice = prefs.downloadFolderChoice;
    final customPathController =
        TextEditingController(text: prefs.customDownloadPath);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          title: Text(
            'Download Storage Location',
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0B132B),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Public Downloads Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('/storage/emulated/0/Download/SoundMind', style: TextStyle(fontSize: 11)),
                value: 'default',
                groupValue: selectedChoice,
                activeColor: accentColor,
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedChoice = val);
                },
              ),
              RadioListTile<String>(
                title: const Text('Public Music Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('/storage/emulated/0/Music/SoundMind', style: TextStyle(fontSize: 11)),
                value: 'music',
                groupValue: selectedChoice,
                activeColor: accentColor,
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedChoice = val);
                },
              ),
              RadioListTile<String>(
                title: const Text('Custom Folder Path', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('Pick any folder from internal storage', style: TextStyle(fontSize: 11)),
                value: 'custom',
                groupValue: selectedChoice,
                activeColor: accentColor,
                onChanged: (val) async {
                  if (val != null) {
                    setDialogState(() => selectedChoice = val);
                    final picked = await StorageFolderPicker.show(
                      context,
                      accentColor: accentColor,
                      initialPath: customPathController.text.trim().isNotEmpty
                          ? customPathController.text.trim()
                          : null,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        customPathController.text = picked;
                      });
                    }
                  }
                },
              ),
              if (selectedChoice == 'custom')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await StorageFolderPicker.show(
                        context,
                        accentColor: accentColor,
                        initialPath: customPathController.text.trim().isNotEmpty
                            ? customPathController.text.trim()
                            : null,
                      );
                      if (picked != null) {
                        setDialogState(() {
                          customPathController.text = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: isDark ? 0.15 : 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_open_rounded, color: accentColor, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              customPathController.text.trim().isEmpty
                                  ? 'Tap to browse phone storage...'
                                  : customPathController.text.trim(),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Browse',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await prefs.setDownloadFolderChoice(selectedChoice);
                if (selectedChoice == 'custom') {
                  await prefs.setCustomDownloadPath(customPathController.text.trim());
                }
                await DownloadService.instance.refreshDownloadsDirectory();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Download storage location updated.'),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── Storage Folders Dialog ────────────────────────
  void _showManageFoldersDialog(BuildContext context, Color accentColor, bool isDark) async {
    final allFolders = await AudioRepository.instance.getAllDiscoveredFolders();
    final excluded = await AudioRepository.instance.getExcludedFolders();

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manage Storage Folders',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All discovered device music folders. Toggle off to exclude from library.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: allFolders.length > 5 ? 360 : null,
                child: allFolders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No audio folders discovered yet. Run a library scan first.',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: allFolders.length,
                        itemBuilder: (context, index) {
                          final folder = allFolders[index];
                          final isExcluded = excluded.contains(folder);
                          final parts = folder.replaceAll('\\', '/').split('/');
                          final folderName = parts.isNotEmpty ? parts.last : folder;

                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              folderName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              folder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                                fontSize: 11,
                              ),
                            ),
                            value: !isExcluded,
                            activeThumbColor: accentColor,
                            onChanged: (included) async {
                              final shouldExclude = !included;
                              await AudioRepository.instance.setFolderExcluded(folder, shouldExclude);
                              setDialogState(() {
                                if (shouldExclude) {
                                  excluded.add(folder);
                                } else {
                                  excluded.remove(folder);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAccent = SectionAccents.settings(isDark);
    final baseColor = isDark ? const Color(0xFF070B14) : const Color(0xFFF1F5F9);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      color: baseColor,
      child: SafeArea(
        top: true,
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page Header
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsTitle,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Preferences, audio, storage & system controls',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: _searchQuery.isNotEmpty
                          ? effectiveAccent.withValues(alpha: 0.5)
                          : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search settings...',
                      hintStyle: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 14,
                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: _searchQuery.isNotEmpty
                            ? effectiveAccent
                            : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              color: isDark ? Colors.white54 : Colors.black45,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),

              // ── Profile ──────────────────────────────────────────────
              ListenableBuilder(
                listenable: UserPreferencesService.instance,
                builder: (context, _) {
                  final name = UserPreferencesService.instance.userName;
                  final avatarMatch = _matches(['Profile', 'Profile Avatar', 'Change']);
                  final nameMatch = _matches(['Profile', 'User Name', name]);
                  if (!avatarMatch && !nameMatch) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsSectionHeader(title: 'Profile', accentColor: effectiveAccent),
                      _SettingsGroupCard(
                        isDark: isDark,
                        children: [
                          if (avatarMatch)
                            _SettingsRow(
                              leadingWidget: UserAvatar(size: 30, isDark: isDark),
                              label: 'Profile Avatar',
                              value: 'Change',
                              accentColor: effectiveAccent,
                              showDivider: nameMatch,
                              onTap: () => AvatarPickerSheet.show(context, accentColor: effectiveAccent),
                            ),
                          if (nameMatch)
                            _SettingsRow(
                              icon: Icons.person_rounded,
                              label: 'User Name',
                              value: name,
                              accentColor: effectiveAccent,
                              showDivider: false,
                              onTap: () => _showEditNameDialog(context),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // ── Appearance ───────────────────────────────────────────
              if (_matches(['Appearance', 'Theme', 'Theme Mode', 'Dark Mode', 'Light Mode'])) ...[
                _SettingsSectionHeader(title: 'Appearance', accentColor: effectiveAccent),
                _CompactThemeToggle(
                  isThemeOne: isThemeOne,
                  onToggle: onThemeToggle,
                  accentColor: effectiveAccent,
                  isDark: isDark,
                ),
              ],

              // ── Music Preferences & Audio ────────────────────────────
              Builder(
                builder: (context) {
                  final prefMatch = _matches(['Music Preferences & Audio', 'Music Preferences', 'Preferred Genres', 'Update initial genre recommendations', 'Genres', 'Preferences', 'Audio']);
                  final eqMatch = _matches(['Music Preferences & Audio', 'Equalizer & Bass Boost', 'Configure', '10-band EQ', 'bass boost', 'Equalizer']);
                  final carMatch = _matches(['Music Preferences & Audio', 'Car Mode', 'Driving Interface', 'Launch']);
                  final welcomeMatch = _matches(['Music Preferences & Audio', 'Replay Welcome Intro', 'Onboarding', 'View']);
                  if (!prefMatch && !eqMatch && !carMatch && !welcomeMatch) return const SizedBox.shrink();

                  final rows = <Widget>[];
                  if (prefMatch) {
                    rows.add(_CompactMusicPreferencesRow(
                      accentColor: effectiveAccent,
                      isDark: isDark,
                    ));
                  }
                  if (eqMatch) {
                    rows.add(_SettingsRow(
                      icon: Icons.equalizer_rounded,
                      label: 'Equalizer & Bass Boost',
                      value: 'Configure',
                      accentColor: effectiveAccent,
                      showDivider: carMatch || welcomeMatch,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EqualizerScreen(accentColor: effectiveAccent),
                        ),
                      ),
                    ));
                  }
                  if (carMatch) {
                    rows.add(_SettingsRow(
                      icon: Icons.directions_car_rounded,
                      label: 'Car Mode',
                      value: 'Launch',
                      accentColor: effectiveAccent,
                      showDivider: welcomeMatch,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CarModeScreen(accentColor: effectiveAccent),
                        ),
                      ),
                    ));
                  }
                  if (welcomeMatch) {
                    rows.add(_SettingsRow(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Replay Welcome Intro',
                      value: 'View',
                      accentColor: effectiveAccent,
                      showDivider: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WelcomeOnboardingScreen(),
                        ),
                      ),
                    ));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsSectionHeader(title: 'Music Preferences & Audio', accentColor: effectiveAccent),
                      _SettingsGroupCard(
                        isDark: isDark,
                        children: rows,
                      ),
                    ],
                  );
                },
              ),

              // ── Downloads & Audio Quality ────────────────────────────
              ListenableBuilder(
                listenable: UserPreferencesService.instance,
                builder: (context, _) {
                  final quality = UserPreferencesService.instance.defaultDownloadQuality;
                  final format = UserPreferencesService.instance.defaultDownloadFormat;
                  final choice = UserPreferencesService.instance.downloadFolderChoice;
                  final custom = UserPreferencesService.instance.customDownloadPath;
                  final String locationLabel;
                  if (choice == 'music') {
                    locationLabel = 'Public Music';
                  } else if (choice == 'custom' && custom.isNotEmpty) {
                    locationLabel = 'Custom';
                  } else {
                    locationLabel = 'Public Downloads';
                  }

                  final qualMatch = _matches(['Downloads & Audio Quality', 'Default Quality', DownloadQualityTier.getLabel(quality), 'Quality', 'Streaming']);
                  final fmtMatch = _matches(['Downloads & Audio Quality', 'Default Format', format, 'M4A', 'MP3', 'WAV', 'Format']);
                  final locMatch = _matches(['Downloads & Audio Quality', 'Storage Location', locationLabel, 'Downloads', 'Path']);
                  if (!qualMatch && !fmtMatch && !locMatch) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsSectionHeader(title: 'Downloads & Audio Quality', accentColor: effectiveAccent),
                      _SettingsGroupCard(
                        isDark: isDark,
                        children: [
                          if (qualMatch)
                            _SettingsRow(
                              icon: Icons.graphic_eq_rounded,
                              label: 'Default Quality',
                              value: DownloadQualityTier.getLabel(quality),
                              accentColor: effectiveAccent,
                              showDivider: fmtMatch || locMatch,
                              onTap: () => _showDownloadQualityDialog(context, isDark),
                            ),
                          if (fmtMatch)
                            _SettingsRow(
                              icon: Icons.audio_file_rounded,
                              label: 'Default Format',
                              value: format == 'm4a' ? 'M4A (AAC)' : format == 'mp3' ? 'MP3' : 'WAV',
                              accentColor: effectiveAccent,
                              showDivider: locMatch,
                              onTap: () => _showDownloadFormatDialog(context, isDark),
                            ),
                          if (locMatch)
                            _SettingsRow(
                              icon: Icons.folder_special_rounded,
                              label: 'Storage Location',
                              value: locationLabel,
                              accentColor: effectiveAccent,
                              showDivider: false,
                              onTap: () => _showDownloadLocationDialog(context, effectiveAccent, isDark),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // ── Storage & Cache ──────────────────────────────────────
              Builder(
                builder: (context) {
                  final cacheMatch = _matches(['Storage & Cache', 'Storage & Cache Manager', 'Manage', 'Cache']);
                  final insightsMatch = _matches(['Storage & Cache', 'Category & Storage Insights', 'Insights', 'Breakdown']);
                  final dupMatch = _matches(['Storage & Cache', 'Duplicate Audio Cleaner', 'Scan', 'Duplicates']);
                  final foldersMatch = _matches(['Storage & Cache', 'Manage Storage Folders', 'Folders', 'Configure', 'Storage']);
                  if (!cacheMatch && !insightsMatch && !dupMatch && !foldersMatch) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsSectionHeader(title: 'Storage & Cache', accentColor: effectiveAccent),
                      _SettingsGroupCard(
                        isDark: isDark,
                        children: [
                          if (cacheMatch)
                            _SettingsRow(
                              icon: Icons.cleaning_services_rounded,
                              label: 'Storage & Cache Manager',
                              value: 'Manage',
                              accentColor: effectiveAccent,
                              showDivider: insightsMatch || dupMatch || foldersMatch,
                              onTap: () => _showCacheManagementDialog(context, isDark),
                            ),
                          if (insightsMatch)
                            _SettingsRow(
                              icon: Icons.pie_chart_outline_rounded,
                              label: 'Category & Storage Insights',
                              value: 'Insights',
                              accentColor: effectiveAccent,
                              showDivider: dupMatch || foldersMatch,
                              onTap: () => StorageInsightsSheet.show(context, accentColor: effectiveAccent),
                            ),
                          if (dupMatch)
                            _SettingsRow(
                              icon: Icons.copy_all_rounded,
                              label: 'Duplicate Audio Cleaner',
                              value: 'Scan',
                              accentColor: effectiveAccent,
                              showDivider: foldersMatch,
                              onTap: () => DuplicateReviewSheet.show(context, accentColor: effectiveAccent),
                            ),
                          if (foldersMatch)
                            _SettingsRow(
                              icon: Icons.folder_open_rounded,
                              label: 'Manage Storage Folders',
                              value: 'Configure',
                              accentColor: effectiveAccent,
                              showDivider: false,
                              onTap: () => _showManageFoldersDialog(context, effectiveAccent, isDark),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // ── Library & Database ───────────────────────────────────
              Builder(
                builder: (context) {
                  final rescanMatch = _matches(['Library & Database', 'Rescan Local Audio', 'Scan', 'Library']);
                  final resetMatch = _matches(['Library & Database', 'Reset Classification Overrides', 'Overrides', 'Reset']);
                  final optMatch = _matches(['Library & Database', 'Optimize Library Database', 'Optimize', 'Database']);
                  final exportMatch = _matches(['Library & Database', 'Export Library Backup', 'JSON', 'Backup']);
                  final importMatch = _matches(['Library & Database', 'Import Library Backup', 'Restore', 'Backup']);
                  final historyMatch = _matches(['Library & Database', 'Clear Playback History', 'History', 'Clear']);
                  if (!rescanMatch && !resetMatch && !optMatch && !exportMatch && !importMatch && !historyMatch) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SettingsSectionHeader(title: 'Library & Database', accentColor: effectiveAccent),
                      _SettingsGroupCard(
                        isDark: isDark,
                        children: [
                          if (rescanMatch)
                            _SettingsRow(
                              icon: Icons.refresh_rounded,
                              label: 'Rescan Local Audio',
                              value: 'Scan',
                              accentColor: effectiveAccent,
                              showDivider: resetMatch || optMatch || exportMatch || importMatch || historyMatch,
                              onTap: () async {
                                final scanner = AudioScannerService.instance;
                                final perm = await scanner.requestPermissions();
                                if (perm) {
                                  scanner.scan(isRescan: true);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Starting local audio rescan...'), backgroundColor: AppColors.voidOverlay),
                                    );
                                  }
                                }
                              },
                            ),
                          if (resetMatch)
                            _SettingsRow(
                              icon: Icons.restore_rounded,
                              label: 'Reset Classification Overrides',
                              value: 'Reset',
                              accentColor: effectiveAccent,
                              showDivider: optMatch || exportMatch || importMatch || historyMatch,
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                    title: const Text('Reset Classification Overrides?', style: TextStyle(fontWeight: FontWeight.bold)),
                                    content: const Text('This will clear manual user categories and restore automatic AI classification.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: effectiveAccent, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Reset'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await AudioRepository.instance.resetAllClassifications();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Classification overrides reset'), backgroundColor: AppColors.voidOverlay),
                                    );
                                  }
                                }
                              },
                            ),
                          if (optMatch)
                            _SettingsRow(
                              icon: Icons.health_and_safety_outlined,
                              label: 'Optimize Library Database',
                              value: 'Optimize',
                              accentColor: effectiveAccent,
                              showDivider: exportMatch || importMatch || historyMatch,
                              onTap: () => _showOptimizeDatabaseDialog(context, effectiveAccent, isDark),
                            ),
                          if (exportMatch)
                            _SettingsRow(
                              icon: Icons.file_upload_outlined,
                              label: 'Export Library Backup',
                              value: 'JSON',
                              accentColor: effectiveAccent,
                              showDivider: importMatch || historyMatch,
                              onTap: () => _showExportBackupDialog(context, effectiveAccent, isDark),
                            ),
                          if (importMatch)
                            _SettingsRow(
                              icon: Icons.file_download_outlined,
                              label: 'Import Library Backup',
                              value: 'Restore',
                              accentColor: effectiveAccent,
                              showDivider: historyMatch,
                              onTap: () => _showImportBackupDialog(context, effectiveAccent, isDark),
                            ),
                          if (historyMatch)
                            _SettingsRow(
                              icon: Icons.history_toggle_off_rounded,
                              label: 'Clear Playback History',
                              value: 'Clear',
                              accentColor: effectiveAccent,
                              showDivider: false,
                              onTap: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                                    title: const Text('Clear Playback History?', style: TextStyle(fontWeight: FontWeight.bold)),
                                    content: const Text('This will reset your play counts and last played history. Your music files remain intact.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Clear'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await AudioRepository.instance.clearHistory();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Playback history cleared'), backgroundColor: AppColors.voidOverlay),
                                    );
                                  }
                                }
                              },
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // ── System & Permissions ─────────────────────────────────
              if (_matches(['System & Permissions', 'System App Permissions', 'OS Settings', 'Permissions'])) ...[
                _SettingsSectionHeader(title: 'System & Permissions', accentColor: effectiveAccent),
                _SettingsGroupCard(
                  isDark: isDark,
                  children: [
                    _SettingsRow(
                      icon: Icons.security_rounded,
                      label: 'System App Permissions',
                      value: 'OS Settings',
                      accentColor: effectiveAccent,
                      showDivider: false,
                      onTap: () async => await openAppSettings(),
                    ),
                  ],
                ),
              ],

              // ── About ────────────────────────────────────────────────
              if (_matches(['About', 'About SoundMind AI', 'v1.0.0', 'Version', 'App Info', 'Licenses'])) ...[
                _SettingsSectionHeader(title: 'About', accentColor: effectiveAccent),
                _SettingsGroupCard(
                  isDark: isDark,
                  children: [
                    _SettingsRow(
                      icon: Icons.info_outline_rounded,
                      label: 'About SoundMind AI',
                      value: 'v1.0.0',
                      accentColor: effectiveAccent,
                      showDivider: false,
                      onTap: () => _showAboutDialog(context, isDark),
                    ),
                  ],
                ),
              ],

              // Empty State
              Builder(
                builder: (context) {
                  if (_searchQuery.trim().isEmpty) return const SizedBox.shrink();
                  final hasAnyMatch = _matches([
                    'Profile', 'Profile Avatar', 'User Name',
                    'Appearance', 'Theme', 'Theme Mode', 'Dark Mode', 'Light Mode',
                    'Music Preferences & Audio', 'Music Preferences', 'Equalizer & Bass Boost', 'Car Mode', 'Replay Welcome Intro',
                    'Downloads & Audio Quality', 'Default Quality', 'Default Format', 'Storage Location',
                    'Storage & Cache', 'Storage & Cache Manager', 'Category & Storage Insights', 'Duplicate Audio Cleaner', 'Manage Storage Folders',
                    'Library & Database', 'Rescan Local Audio', 'Reset Classification Overrides', 'Optimize Library Database', 'Export Library Backup', 'Import Library Backup', 'Clear Playback History',
                    'System & Permissions', 'System App Permissions',
                    'About', 'About SoundMind AI',
                  ]);
                  if (hasAnyMatch) return const SizedBox.shrink();

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: subtitleColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No matching settings found',
                            style: TextStyle(
                              fontFamily: AppTypography.displayFont,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try searching for "equalizer", "storage", "theme", or "backup"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 13,
                              color: subtitleColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            label: const Text('Clear Search'),
                            style: TextButton.styleFrom(
                              foregroundColor: effectiveAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Generous bottom clearance ensuring the About card floats safely above the mini player
              const SizedBox(height: 180),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────── Section Header ────────────────────────
class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({
    required this.title,
    required this.accentColor,
  });

  final String title;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 20),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 11,
            margin: const EdgeInsets.only(right: 7),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTypography.uiFont,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────── Group Card ────────────────────────
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({
    required this.children,
    required this.isDark,
  });

  final List<Widget> children;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF111827).withValues(alpha: 0.75)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: children,
        ),
      ),
    );
  }
}

// ──────────────────────── Single-Line Settings Row ────────────────────────
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    this.icon = Icons.settings,
    this.leadingWidget,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.value,
    this.showDivider = false,
  });

  final IconData icon;
  final Widget? leadingWidget;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;
  final String? value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final valueTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final chevronColor = isDark ? Colors.white38 : const Color(0xFF94A3B8);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                if (leadingWidget != null)
                  leadingWidget!
                else
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: accentColor,
                      size: 16,
                    ),
                  ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                ),
                // Trailing value
                if (value != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12.5,
                        color: valueTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: chevronColor,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 56,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF1F5F9),
          ),
      ],
    );
  }
}

// ──────────────────────── Compact Theme Swatches ────────────────────────
class _CompactThemeToggle extends StatelessWidget {
  const _CompactThemeToggle({
    required this.isThemeOne,
    required this.onToggle,
    required this.accentColor,
    required this.isDark,
  });

  final bool isThemeOne;
  final ValueChanged<bool> onToggle;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CompactThemeSwatch(
            label: 'Abyss (Dark)',
            isSelected: isThemeOne,
            baseColor: const Color(0xFF060913),
            dotColor: AppColors.abyssAccent,
            accentColor: accentColor,
            isDark: isDark,
            onTap: () => onToggle(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CompactThemeSwatch(
            label: 'Frost (Light)',
            isSelected: !isThemeOne,
            baseColor: const Color(0xFFF1F5F9),
            dotColor: AppColors.frostAccent,
            accentColor: accentColor,
            isDark: isDark,
            onTap: () => onToggle(false),
          ),
        ),
      ],
    );
  }
}

class _CompactThemeSwatch extends StatelessWidget {
  const _CompactThemeSwatch({
    required this.label,
    required this.isSelected,
    required this.baseColor,
    required this.dotColor,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color baseColor;
  final Color dotColor;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? accentColor
        : (isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFCBD5E1));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827).withValues(alpha: 0.75) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: baseColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: dotColor,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 16,
                color: accentColor,
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────── Compact Music Preferences Row ────────────────────────
class _CompactMusicPreferencesRow extends StatefulWidget {
  final Color accentColor;
  final bool isDark;

  const _CompactMusicPreferencesRow({
    required this.accentColor,
    required this.isDark,
  });

  @override
  State<_CompactMusicPreferencesRow> createState() => _CompactMusicPreferencesRowState();
}

class _CompactMusicPreferencesRowState extends State<_CompactMusicPreferencesRow> {
  final Set<String> _selectedGenres = {};
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('preferred_genres');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _selectedGenres.addAll(decoded.map((e) => e.toString()));
        }
      }
      if (_selectedGenres.isEmpty) {
        final list = prefs.getStringList('preferred_genres');
        if (list != null) _selectedGenres.addAll(list);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _toggleGenre(String genre) {
    setState(() {
      if (_selectedGenres.contains(genre)) {
        _selectedGenres.remove(genre);
      } else {
        _selectedGenres.add(genre);
      }
    });
  }

  Future<void> _savePreferences() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final listToSave = _selectedGenres.toList();
      await prefs.setString('preferred_genres', jsonEncode(listToSave));
      await prefs.setBool('has_completed_genre_onboarding', true);

      if (mounted) {
        setState(() => _isExpanded = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedGenres.isEmpty
                  ? 'Preferences updated (all genres enabled).'
                  : 'Saved ${_selectedGenres.length} preferred genres.',
            ),
            backgroundColor: widget.accentColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save music preferences'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final valueTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: widget.accentColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Preferred Music Genres',
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _selectedGenres.isEmpty ? 'All genres' : "${_selectedGenres.length} selected",
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 12.5,
                    color: valueTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                : Column(
                    children: [
                      GenreSelectorGrid(
                        selectedGenres: _selectedGenres,
                        onGenreToggled: _toggleGenre,
                        isDark: isDark,
                        accentColor: widget.accentColor,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _savePreferences,
                          icon: _isSaving
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(_isSaving ? 'Saving...' : 'Save Preferences', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        Divider(
          height: 1,
          thickness: 1,
          indent: 56,
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
        ),
      ],
    );
  }
}
