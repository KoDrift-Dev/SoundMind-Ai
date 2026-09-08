// duplicate_review_sheet.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/storage_insights.dart';
import '../models/track.dart';
import '../services/duplicate_detection_service.dart';
import '../utils/duration_formatter.dart';

/// Modal sheet allowing safe review and deletion of duplicate audio files.
class DuplicateReviewSheet extends StatefulWidget {
  final Color accentColor;

  const DuplicateReviewSheet({
    super.key,
    this.accentColor = AppColors.abyssAccent,
  });

  static Future<void> show(BuildContext context, {Color? accentColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.modalTop)),
      ),
      builder: (ctx) => DuplicateReviewSheet(
        accentColor: accentColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  State<DuplicateReviewSheet> createState() => _DuplicateReviewSheetState();
}

class _DuplicateReviewSheetState extends State<DuplicateReviewSheet> {
  final DuplicateDetectionService _dupService = DuplicateDetectionService.instance;
  List<DuplicateGroup> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _scanForDuplicates();
  }

  Future<void> _scanForDuplicates() async {
    setState(() => _isLoading = true);
    final results = await _dupService.findDuplicates();
    if (mounted) {
      setState(() {
        _groups = results;
        _isLoading = false;
      });
    }
  }

  int get _totalReclaimableBytes {
    return _groups.fold(0, (sum, g) => sum + g.reclaimableBytes);
  }

  Future<void> _confirmDelete(Track track) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1),
          ),
        ),
        title: Text(
          'Delete Duplicate Audio?',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontFamily: AppTypography.displayFont,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File to remove:\n${track.filePath ?? track.fileName ?? "Unknown"}',
              style: TextStyle(
                color: isDark ? Colors.white70 : const Color(0xFF334155),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This will permanently delete this redundant copy from storage and your library.',
              style: TextStyle(
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Copy', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _dupService.safelyDeleteDuplicate(track: track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Duplicate copy removed successfully' : 'Failed to delete duplicate file',
            ),
            backgroundColor: success
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A))
                : Colors.redAccent,
          ),
        );
        if (success) {
          setState(() {
            _groups = _groups
                .map((g) {
                  final filtered = g.tracks
                      .where((t) =>
                          t.id != track.id &&
                          (track.filePath == null || t.filePath != track.filePath))
                      .toList();
                  return DuplicateGroup(
                    title: g.title,
                    artist: g.artist,
                    matchReason: g.matchReason,
                    tracks: filtered,
                  );
                })
                .where((g) => g.tracks.length >= 2)
                .toList();
          });
        }
        _scanForDuplicates();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF334155);
    final mutedTextColor = isDark ? Colors.white38 : const Color(0xFF64748B);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC);
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0);

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Duplicate Audio Review',
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: 18,
                      fontFamily: AppTypography.displayFont,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: mutedTextColor, size: 20),
                    onPressed: _isLoading ? null : _scanForDuplicates,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Text(
                'Safety First: Review duplicate candidates below. No files are ever deleted automatically.',
                style: TextStyle(color: secondaryTextColor, fontSize: 12, fontFamily: AppTypography.bodyFont),
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_groups.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: widget.accentColor, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'No Duplicates Found',
                        style: TextStyle(color: primaryTextColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your music library has zero duplicate audio files.',
                        style: TextStyle(color: secondaryTextColor, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else ...[
                // Potential reclaim banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: widget.accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cleaning_services_rounded, color: widget.accentColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_groups.length} duplicate groups found. Potential space reclaim: ${StorageInsights.formatBytes(_totalReclaimableBytes)}',
                          style: TextStyle(
                            color: primaryTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppTypography.bodyFont,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Groups list
                ..._groups.map((group) => _buildGroupCard(group, isDark, primaryTextColor, secondaryTextColor, mutedTextColor, cardBg, cardBorder)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    DuplicateGroup group,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color mutedTextColor,
    Color cardBg,
    Color cardBorder,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  group.title,
                  style: TextStyle(
                    color: primaryTextColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: AppTypography.displayFont,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${group.tracks.length} Copies',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${group.artist} • ${group.matchReason}',
            style: TextStyle(color: widget.accentColor, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          Divider(height: 20, color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),

          // File copies
          ...group.tracks.asMap().entries.map((entry) {
            final idx = entry.key;
            final track = entry.value;
            final isPrimary = idx == 0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isPrimary ? Icons.star_rounded : Icons.subdirectory_arrow_right_rounded,
                    color: isPrimary ? widget.accentColor : mutedTextColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.filePath ?? track.fileName ?? 'Unknown path',
                          style: TextStyle(
                            color: isPrimary ? primaryTextColor : secondaryTextColor,
                            fontSize: 11,
                            fontFamily: AppTypography.bodyFont,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${StorageInsights.formatBytes(track.fileSize ?? 0)} • ${formatDurationMs(track.duration)}',
                          style: TextStyle(color: mutedTextColor, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  if (!isPrimary)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                      tooltip: 'Delete this copy',
                      onPressed: () => _confirmDelete(track),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Keep',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : const Color(0xFF475569),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
