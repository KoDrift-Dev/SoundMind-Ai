// storage_insights_sheet.dart
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../models/audio_category.dart';
import '../models/storage_insights.dart';
import '../repositories/audio_repository.dart';
import 'duplicate_review_sheet.dart';

/// Modal sheet displaying real storage statistics and category distribution.
class StorageInsightsSheet extends StatefulWidget {
  final Color accentColor;

  const StorageInsightsSheet({
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
      builder: (ctx) => StorageInsightsSheet(
        accentColor: accentColor ?? Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  State<StorageInsightsSheet> createState() => _StorageInsightsSheetState();
}

class _StorageInsightsSheetState extends State<StorageInsightsSheet> {
  StorageInsights? _insights;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    final insights = await AudioRepository.instance.getStorageInsights();
    if (mounted) {
      setState(() {
        _insights = insights;
        _isLoading = false;
      });
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
    final progressBg = isDark ? Colors.white12 : const Color(0xFFE2E8F0);

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

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Storage & Category Insights',
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: 18,
                      fontFamily: AppTypography.displayFont,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: mutedTextColor, size: 20),
                    onPressed: () {
                      setState(() => _isLoading = true);
                      _loadInsights();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_insights != null) ...[
                // Storage Bar
                Container(
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
                          Text(
                            'Audio Storage Used',
                            style: TextStyle(color: secondaryTextColor, fontSize: 13, fontFamily: AppTypography.bodyFont),
                          ),
                          Text(
                            _insights!.formattedTotalStorage,
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _insights!.musicStoragePercentage,
                          backgroundColor: progressBg,
                          valueColor: AlwaysStoppedAnimation<Color>(widget.accentColor),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLegendItem(
                            color: widget.accentColor,
                            label: 'Music: ${_insights!.formattedMusicStorage}',
                            textColor: secondaryTextColor,
                          ),
                          _buildLegendItem(
                            color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                            label: 'Other Audio: ${_insights!.formattedNonMusicStorage}',
                            textColor: secondaryTextColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Category Breakdown Header
                Text(
                  'Classification Breakdown (${_insights!.totalAudioFiles} Files)',
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 14,
                    fontFamily: AppTypography.displayFont,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                // Category List
                _buildCategoryRow(
                  icon: AudioCategory.music.icon,
                  name: 'Music (Queue Verified)',
                  count: _insights!.musicCount,
                  color: widget.accentColor,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.recording.icon,
                  name: 'Recordings',
                  count: _insights!.recordingsCount,
                  color: Colors.orangeAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.voiceNote.icon,
                  name: 'Voice Notes',
                  count: _insights!.voiceNotesCount,
                  color: Colors.tealAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.podcast.icon,
                  name: 'Podcasts',
                  count: _insights!.podcastsCount,
                  color: Colors.purpleAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.ringtone.icon,
                  name: 'Ringtones',
                  count: _insights!.ringtonesCount,
                  color: Colors.amberAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.notification.icon,
                  name: 'Notifications',
                  count: _insights!.notificationsCount,
                  color: Colors.lightBlueAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                _buildCategoryRow(
                  icon: AudioCategory.unknown.icon,
                  name: 'Unknown / Under Review',
                  count: _insights!.unknownCount,
                  color: Colors.redAccent,
                  textColor: primaryTextColor,
                  countColor: secondaryTextColor,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      DuplicateReviewSheet.show(context, accentColor: widget.accentColor);
                    },
                    icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white, size: 20),
                    label: const Text('Scan & Review Duplicate Audio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label, required Color textColor}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: textColor, fontSize: 11, fontFamily: AppTypography.bodyFont),
        ),
      ],
    );
  }

  Widget _buildCategoryRow({
    required IconData icon,
    required String name,
    required int count,
    required Color color,
    required Color textColor,
    required Color countColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: textColor, fontSize: 13, fontFamily: AppTypography.bodyFont),
            ),
          ),
          Text(
            '$count files',
            style: TextStyle(
              color: countColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: AppTypography.bodyFont,
            ),
          ),
        ],
      ),
    );
  }
}
