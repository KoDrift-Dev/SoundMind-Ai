import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_typography.dart';
import '../main.dart';
import '../models/storage_insights.dart';
import '../online/models/online_search_result.dart';
import '../screens/main_navigation.dart';
import '../services/download/download_models.dart';
import '../services/download/download_service.dart';
import '../services/user_preferences_service.dart';

/// Modal bottom sheet allowing format (M4A / MP3 / WAV) and quality tier selection with live estimated file size.
class DownloadOptionsSheet extends StatefulWidget {
  final OnlineSearchResult track;
  final Color accentColor;

  const DownloadOptionsSheet({
    super.key,
    required this.track,
    required this.accentColor,
  });

  static Future<void> show(
    BuildContext context, {
    required OnlineSearchResult track,
    required Color accentColor,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DownloadOptionsSheet(
        track: track,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<DownloadOptionsSheet> createState() => _DownloadOptionsSheetState();
}

class _DownloadOptionsSheetState extends State<DownloadOptionsSheet> {
  String _selectedFormat = 'm4a'; // 'm4a', 'mp3', 'wav'
  String _selectedQualityTier = DownloadQualityTier.high; // 'low', 'medium', 'high'
  int _durationSeconds = 210;

  @override
  void initState() {
    super.initState();
    _selectedFormat = UserPreferencesService.instance.defaultDownloadFormat;
    _selectedQualityTier = UserPreferencesService.instance.defaultDownloadQuality;
    _durationSeconds = _parseDurationSeconds(widget.track.duration);
  }

  int _parseDurationSeconds(String? duration) {
    if (duration == null || duration.trim().isEmpty) return 210;
    final parts = duration.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return int.tryParse(duration) ?? 210;
  }

  int get _estimatedBytes => DownloadTask.estimateBytes(
        qualityTier: _selectedQualityTier,
        format: _selectedFormat,
        durationSeconds: _durationSeconds,
      );

  void _onStartDownload() {
    DownloadService.instance.startDownload(
      videoId: widget.track.id,
      title: widget.track.title,
      artist: widget.track.artist,
      qualityTier: _selectedQualityTier,
      outputFormat: _selectedFormat,
      durationSeconds: _durationSeconds,
    );

    Navigator.of(context).pop();

    final fullTitle = widget.track.title;
    final halfTitle =
        fullTitle.length > 15 ? '${fullTitle.substring(0, 15)}…' : fullTitle;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.download_for_offline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Downloading "$halfTitle"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
            MainNavigation.navigateToDownloads(subTab: 0);
          },
        ),
        backgroundColor: widget.accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTask = DownloadService.instance.getTask(widget.track.id);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131826) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Track Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 52,
                  height: 52,
                  color: widget.accentColor.withValues(alpha: 0.15),
                  child: widget.track.thumbnailUrl != null
                      ? Image.network(
                          widget.track.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.music_note_rounded,
                            color: widget.accentColor,
                            size: 24,
                          ),
                        )
                      : Icon(
                          Icons.music_note_rounded,
                          color: widget.accentColor,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 13,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 16),

          // Existing Download Status (if active/completed)
          if (currentTask != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: widget.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    currentTask.status == DownloadStatus.completed
                        ? Icons.check_circle_rounded
                        : Icons.downloading_rounded,
                    color: widget.accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      currentTask.status == DownloadStatus.completed
                          ? 'Downloaded in ${currentTask.outputFormat.toUpperCase()} (${currentTask.formattedDownloadedSize})'
                          : 'Download ${currentTask.status.name} (${(currentTask.progress * 100).toInt()}%)',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Format Selection Section
          Text(
            'OUTPUT FORMAT',
            style: TextStyle(
              fontFamily: AppTypography.uiFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFormatChip('m4a', 'M4A (Default)', isDark),
              const SizedBox(width: 8),
              _buildFormatChip('mp3', 'MP3', isDark),
              const SizedBox(width: 8),
              _buildFormatChip('wav', 'WAV', isDark),
            ],
          ),

          const SizedBox(height: 18),

          // Quality Tier Selection Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AUDIO QUALITY',
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              // Live Estimated Size Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Est. Size: ~${StorageInsights.formatBytes(_estimatedBytes)}',
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3 Named Quality Tiers
          Row(
            children: [
              _buildQualityChip(
                DownloadQualityTier.low,
                'Low (64 kbps)',
                'Small file',
                isDark,
              ),
              const SizedBox(width: 8),
              _buildQualityChip(
                DownloadQualityTier.medium,
                'Medium (128 kbps)',
                'Balanced',
                isDark,
              ),
              const SizedBox(width: 8),
              _buildQualityChip(
                DownloadQualityTier.high,
                'High (192 kbps)',
                'Best quality',
                isDark,
              ),
            ],
          ),

          // WAV note
          if (_selectedFormat == 'wav') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WAV is uncompressed 16-bit PCM audio. File sizes are naturally large (~${StorageInsights.formatBytes(_estimatedBytes)}) regardless of quality tier.',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Download Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                currentTask?.status == DownloadStatus.completed
                    ? 'Re-download (~${StorageInsights.formatBytes(_estimatedBytes)})'
                    : 'Download Track (~${StorageInsights.formatBytes(_estimatedBytes)})',
                style: const TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _onStartDownload,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip(String format, String label, bool isDark) {
    final isSelected = _selectedFormat == format;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFormat = format);
      },
      selectedColor: widget.accentColor.withValues(alpha: 0.25),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05),
      labelStyle: TextStyle(
        fontFamily: AppTypography.uiFont,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected
            ? (isDark ? Colors.white : widget.accentColor)
            : (isDark ? Colors.white70 : Colors.black87),
      ),
      side: BorderSide(
        color: isSelected
            ? widget.accentColor
            : (isDark ? Colors.white12 : Colors.black12),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildQualityChip(
    String tier,
    String label,
    String subtitle,
    bool isDark,
  ) {
    final isSelected = _selectedQualityTier == tier;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedQualityTier = tier),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? widget.accentColor.withValues(alpha: 0.20)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? widget.accentColor
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tier[0].toUpperCase() + tier.substring(1),
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? (isDark ? Colors.white : widget.accentColor)
                      : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${DownloadQualityTier.getBitrateKbps(tier)} kbps',
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 10,
                  color: isSelected
                      ? (isDark ? Colors.white70 : widget.accentColor)
                      : (isDark ? Colors.white38 : Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
