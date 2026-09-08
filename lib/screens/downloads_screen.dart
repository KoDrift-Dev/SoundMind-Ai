import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../core/helpers/accent_color_helper.dart';
import '../core/widgets/ambient_background.dart';
import '../core/widgets/glass_card.dart';
import '../models/storage_insights.dart';
import '../models/track.dart';
import '../online/models/online_search_result.dart';
import '../services/audio_player_service.dart';
import '../services/download/download_models.dart';
import '../services/download/download_service.dart';
import '../widgets/download_options_sheet.dart';

/// Top Header Icon Screen: Dedicated "Download History, Visuals, Analytics & Records" screen.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  String _filterStatus = 'All'; // 'All', 'Completed', 'Failed', 'In Progress'

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AccentColorHelper.resolve(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: AmbientBackground(isThemeOne: isDark),
          ),
          SafeArea(
            child: StreamBuilder<List<DownloadTask>>(
              stream: DownloadService.instance.watchAllDownloads(),
              initialData: DownloadService.instance.getAllTasks(),
              builder: (context, snapshot) {
                final allTasks = snapshot.data ?? [];

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(context, accentColor, isDark, allTasks),
                    ),
                    SliverToBoxAdapter(
                      child: _buildVisualAnalytics(accentColor, isDark, allTasks),
                    ),
                    SliverToBoxAdapter(
                      child: _buildRecordsHeader(accentColor, isDark, allTasks),
                    ),
                    _buildRecordsList(context, accentColor, isDark, allTasks),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 80),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Color accentColor,
    bool isDark,
    List<DownloadTask> tasks,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Download History & Analytics',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Visual analytics, storage footprint & overall records',
                  style: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualAnalytics(
    Color accentColor,
    bool isDark,
    List<DownloadTask> tasks,
  ) {
    final completed = tasks.where((t) => t.status == DownloadStatus.completed).toList();
    final active = tasks.where((t) =>
        t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.queued ||
        t.status == DownloadStatus.paused ||
        t.status == DownloadStatus.converting).toList();
    final failed = tasks.where((t) =>
        t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.cancelled).toList();

    int totalBytes = 0;
    int m4aCount = 0;
    int mp3Count = 0;
    int wavCount = 0;
    int highQualityCount = 0;
    int mediumQualityCount = 0;
    int lowQualityCount = 0;

    for (final t in completed) {
      totalBytes += t.bytesDownloaded;
      final fmt = t.outputFormat.toLowerCase();
      if (fmt == 'mp3') mp3Count++;
      else if (fmt == 'wav') wavCount++;
      else m4aCount++;

      final q = t.qualityTier.toLowerCase();
      if (q == 'low') lowQualityCount++;
      else if (q == 'medium') mediumQualityCount++;
      else highQualityCount++;
    }

    final totalCompleted = completed.length;
    final totalAttempts = completed.length + failed.length;
    final double successRate = totalAttempts > 0
        ? (completed.length / totalAttempts) * 100
        : 100.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero Analytics Card ──
          GlassCard(
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildMetricColumn(
                        label: 'Total Downloaded',
                        value: '$totalCompleted',
                        sub: 'Tracks',
                        color: const Color(0xFF10B981),
                        isDark: isDark,
                      ),
                      Container(width: 1, height: 40, color: isDark ? Colors.white12 : Colors.black12),
                      _buildMetricColumn(
                        label: 'Storage Footprint',
                        value: StorageInsights.formatBytes(totalBytes),
                        sub: 'On Storage',
                        color: accentColor,
                        isDark: isDark,
                      ),
                      Container(width: 1, height: 40, color: isDark ? Colors.white12 : Colors.black12),
                      _buildMetricColumn(
                        label: 'Success Rate',
                        value: '${successRate.toStringAsFixed(0)}%',
                        sub: '$totalAttempts Total',
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Visual Format Distribution ──
          GlassCard(
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Format Distribution',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$totalCompleted Completed',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 11,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Proportion Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          if (totalCompleted == 0)
                            Expanded(child: Container(color: isDark ? Colors.white12 : Colors.black12))
                          else ...[
                            if (m4aCount > 0)
                              Expanded(
                                flex: m4aCount,
                                child: Container(color: accentColor),
                              ),
                            if (mp3Count > 0)
                              Expanded(
                                flex: mp3Count,
                                child: Container(color: const Color(0xFF3B82F6)),
                              ),
                            if (wavCount > 0)
                              Expanded(
                                flex: wavCount,
                                child: Container(color: const Color(0xFFEC4899)),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFormatPill('M4A (AAC)', m4aCount, accentColor, isDark),
                      _buildFormatPill('MP3', mp3Count, const Color(0xFF3B82F6), isDark),
                      _buildFormatPill('WAV', wavCount, const Color(0xFFEC4899), isDark),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Quality Tiers & Active Status ──
          Row(
            children: [
              Expanded(
                child: GlassCard(
                  borderRadius: AppRadius.md,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quality Tiers',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('High (192k): $highQualityCount', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 3),
                        Text('Medium (128k): $mediumQualityCount', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 3),
                        Text('Low (64k): $lowQualityCount', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassCard(
                  borderRadius: AppRadius.md,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Task Status',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Active: ${active.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Completed: ${completed.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('Cancelled: ${failed.length}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required String label,
    required String value,
    required String sub,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        Text(
          sub,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 9,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildFormatPill(String label, int count, Color color, bool isDark) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          '$label: $count',
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsHeader(
    Color accentColor,
    bool isDark,
    List<DownloadTask> tasks,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Historical Download Records (${tasks.length})',
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              if (tasks.isNotEmpty)
                TextButton(
                  onPressed: () => _confirmClearAllRecords(context, isDark),
                  child: const Text('Clear List', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Filter chips: All, Completed, Failed, In Progress
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Completed', 'Failed', 'In Progress'].map((status) {
                final isSelected = _filterStatus == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(status),
                    selected: isSelected,
                    selectedColor: accentColor.withValues(alpha: 0.25),
                    checkmarkColor: accentColor,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    onSelected: (_) => setState(() => _filterStatus = status),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordThumbnail(DownloadTask task, {double size = 38}) {
    final isCompleted = task.status == DownloadStatus.completed;
    final isFailed = task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled;
    final fallbackColor = isCompleted
        ? const Color(0xFF10B981)
        : isFailed
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);
    final fallbackIcon = isCompleted
        ? Icons.check_circle_rounded
        : isFailed
            ? Icons.error_outline_rounded
            : Icons.downloading_rounded;
    final thumbUrl = 'https://img.youtube.com/vi/${task.videoId}/mqdefault.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: fallbackColor.withValues(alpha: 0.15),
        child: Image.network(
          thumbUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                fallbackIcon,
                color: fallbackColor,
                size: size * 0.5,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: size * 0.4,
                height: size * 0.4,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: fallbackColor.withValues(alpha: 0.5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecordsList(
    BuildContext context,
    Color accentColor,
    bool isDark,
    List<DownloadTask> tasks,
  ) {
    List<DownloadTask> filtered = List.from(tasks);

    if (_filterStatus == 'Completed') {
      filtered = filtered.where((t) => t.status == DownloadStatus.completed).toList();
    } else if (_filterStatus == 'Failed') {
      filtered = filtered.where((t) => t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled).toList();
    } else if (_filterStatus == 'In Progress') {
      filtered = filtered.where((t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued ||
          t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.converting).toList();
    }

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No download records matching filter.',
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 13,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final task = filtered[index];
            final isCompleted = task.status == DownloadStatus.completed;
            final isFailed = task.status == DownloadStatus.failed || task.status == DownloadStatus.cancelled;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                borderRadius: AppRadius.md,
                child: ListTile(
                  dense: true,
                  leading: _buildRecordThumbnail(task, size: 38),
                  title: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${task.artist} • ${task.outputFormat.toUpperCase()} • ${task.formattedDownloadedSize}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCompleted)
                        IconButton(
                          icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF10B981), size: 24),
                          tooltip: 'Play',
                          onPressed: () {
                            if (task.finalFilePath != null && File(task.finalFilePath!).existsSync()) {
                              final localTrack = Track(
                                id: task.videoId.hashCode.abs(),
                                filePath: task.finalFilePath,
                                title: task.title,
                                artist: task.artist,
                                isDownloaded: true,
                                isMusic: true,
                              );
                              AudioPlayerService.instance.loadPlaylist([localTrack], 0);
                            }
                          },
                        )
                      else if (isFailed)
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Color(0xFFEF4444), size: 22),
                          tooltip: 'Retry',
                          onPressed: () => DownloadService.instance.retryDownload(task.videoId),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        color: isDark ? Colors.white38 : Colors.black38,
                        tooltip: 'Remove Record',
                        onPressed: () => DownloadService.instance.removeTaskFromList(task.videoId),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: filtered.length,
        ),
      ),
    );
  }

  void _confirmClearAllRecords(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Clear Download Records?'),
        content: const Text('This removes all completed and cancelled entries from the history log. Your downloaded audio files on storage will remain intact.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              final all = DownloadService.instance.getAllTasks();
              for (final t in all) {
                if (t.status == DownloadStatus.completed || t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled) {
                  DownloadService.instance.removeTaskFromList(t.videoId);
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text('Clear Log'),
          ),
        ],
      ),
    );
  }
}

/// The 3-sub-tab Downloads widget with In Progress, Completed, and Cancelled sub-tabs,
/// featuring full 3-dot action menus for each item.
class DownloadsSubTabsWidget extends StatefulWidget {
  final Color accentColor;
  final bool isDark;
  final int initialIndex;
  final void Function(Track track)? onPlaySelected;

  const DownloadsSubTabsWidget({
    super.key,
    required this.accentColor,
    required this.isDark,
    this.initialIndex = 0,
    this.onPlaySelected,
  });

  @override
  State<DownloadsSubTabsWidget> createState() => DownloadsSubTabsWidgetState();
}

class DownloadsSubTabsWidgetState extends State<DownloadsSubTabsWidget>
    with SingleTickerProviderStateMixin {
  static DownloadsSubTabsWidgetState? instance;

  late TabController _tabController;

  static const Color colorInProgress = Color(0xFFF59E0B); // Amber
  static const Color colorCompleted = Color(0xFF10B981);  // Green
  static const Color colorCancelled = Color(0xFFEF4444);  // Red

  @override
  void initState() {
    super.initState();
    instance = this;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    if (instance == this) instance = null;
    _tabController.dispose();
    super.dispose();
  }

  void switchToSubTab(int index) {
    if (mounted && _tabController.index != index) {
      _tabController.animateTo(index);
    }
  }

  Widget _buildTrackThumbnail(
    DownloadTask task, {
    double size = 44,
    Color? fallbackColor,
    IconData fallbackIcon = Icons.music_note_rounded,
  }) {
    final thumbUrl = 'https://img.youtube.com/vi/${task.videoId}/mqdefault.jpg';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: fallbackColor ?? widget.accentColor.withValues(alpha: 0.15),
        child: Image.network(
          thumbUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                fallbackIcon,
                color: fallbackColor != null ? Colors.white70 : widget.accentColor,
                size: size * 0.48,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: size * 0.35,
                height: size * 0.35,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: widget.accentColor.withValues(alpha: 0.5),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _playDownloadedTrack(DownloadTask task) {
    if (task.finalFilePath == null || !File(task.finalFilePath!).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio file not found on device memory.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final localTrack = Track(
      id: task.videoId.hashCode.abs(),
      filePath: task.finalFilePath,
      title: task.title,
      artist: task.artist,
      fileSize: task.totalBytes ?? task.bytesDownloaded,
      mimeType: 'audio/${task.outputFormat}',
      isDownloaded: true,
      isMusic: true,
    );

    if (widget.onPlaySelected != null) {
      widget.onPlaySelected!(localTrack);
    } else {
      AudioPlayerService.instance.loadPlaylist([localTrack], 0);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing: ${task.title}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareTrack(DownloadTask task) async {
    if (task.finalFilePath != null && File(task.finalFilePath!).existsSync()) {
      try {
        await Share.shareXFiles(
          [XFile(task.finalFilePath!)],
          text: '${task.title} by ${task.artist}',
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share file.')),
        );
      }
    } else {
      await Share.share('${task.title} by ${task.artist}');
    }
  }

  // ── 3-Dot Options Bottom Sheet for Completed Items ──
  void _showCompletedOptions(DownloadTask task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildTrackThumbnail(
                      task,
                      size: 42,
                      fallbackColor: colorCompleted.withValues(alpha: 0.15),
                      fallbackIcon: Icons.music_note_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            '${task.artist} • ${task.outputFormat.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded, color: colorCompleted),
                title: const Text('Play Track'),
                onTap: () {
                  Navigator.pop(ctx);
                  _playDownloadedTrack(task);
                },
              ),
              ListTile(
                leading: Icon(Icons.share_rounded, color: widget.accentColor),
                title: const Text('Share Audio File'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareTrack(task);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_remove_rounded, color: Colors.amber),
                title: const Text('Remove from List'),
                subtitle: const Text('Removes history record without deleting file from device', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await DownloadService.instance.removeTaskFromList(task.videoId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Removed from download history')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                title: const Text('Delete from Storage', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Permanently deletes the audio file from device memory', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (alertCtx) => AlertDialog(
                      backgroundColor: widget.isDark ? const Color(0xFF0D1527) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                      title: const Text('Delete File?'),
                      content: Text('Are you sure you want to delete "${task.title}" from device storage?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(alertCtx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(alertCtx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await DownloadService.instance.deleteTaskAndFile(task.videoId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File deleted from device storage')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3-Dot Options Bottom Sheet for In-Progress Items ──
  void _showInProgressOptions(DownloadTask task) {
    final isPaused = task.status == DownloadStatus.paused;

    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildTrackThumbnail(
                      task,
                      size: 42,
                      fallbackColor: colorInProgress.withValues(alpha: 0.15),
                      fallbackIcon: Icons.downloading_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            isPaused ? 'Paused' : 'Downloading • ${task.formattedProgress}',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (isPaused)
                ListTile(
                  leading: const Icon(Icons.play_arrow_rounded, color: colorInProgress),
                  title: const Text('Resume Download'),
                  onTap: () {
                    Navigator.pop(ctx);
                    DownloadService.instance.resumeDownload(task.videoId);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.pause_rounded, color: Colors.amber),
                  title: const Text('Pause Download'),
                  onTap: () {
                    Navigator.pop(ctx);
                    DownloadService.instance.pauseDownload(task.videoId);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.cancel_rounded, color: Colors.redAccent),
                title: const Text('Cancel & Delete Task', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Stops download and clears partial temp files', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await DownloadService.instance.deleteTaskAndFile(task.videoId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Download cancelled and removed')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 3-Dot Options Bottom Sheet for Cancelled / Failed Items ──
  void _showCancelledOptions(DownloadTask task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildTrackThumbnail(
                      task,
                      size: 42,
                      fallbackColor: colorCancelled.withValues(alpha: 0.15),
                      fallbackIcon: Icons.error_outline_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            task.status == DownloadStatus.failed ? 'Failed' : 'Cancelled',
                            style: const TextStyle(fontSize: 12, color: colorCancelled),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.refresh_rounded, color: colorCancelled),
                title: const Text('Restart Download'),
                subtitle: Text('Re-download as ${task.outputFormat.toUpperCase()} (${task.qualityTier})', style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  DownloadService.instance.retryDownload(task.videoId);
                },
              ),
              ListTile(
                leading: Icon(Icons.tune_rounded, color: widget.accentColor),
                title: const Text('Select Format & Quality Again'),
                subtitle: const Text('Choose a different bitrate or audio format before downloading', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  final onlineTrack = OnlineSearchResult(
                    id: task.videoId,
                    title: task.title,
                    artist: task.artist,
                    source: 'YouTube',
                  );
                  DownloadOptionsSheet.show(
                    context,
                    track: onlineTrack,
                    accentColor: widget.accentColor,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Delete from List', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Removes task from cancelled history', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await DownloadService.instance.deleteTaskAndFile(task.videoId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Task removed')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DownloadTask>>(
      stream: DownloadService.instance.watchAllDownloads(),
      initialData: DownloadService.instance.getAllTasks(),
      builder: (context, snapshot) {
        final allTasks = snapshot.data ?? [];

        final inProgressTasks = allTasks
            .where((t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.queued ||
                t.status == DownloadStatus.paused ||
                t.status == DownloadStatus.converting)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final completedTasks = allTasks
            .where((t) => t.status == DownloadStatus.completed)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        final cancelledTasks = allTasks
            .where((t) =>
                t.status == DownloadStatus.cancelled ||
                t.status == DownloadStatus.failed)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

        return Column(
          children: [
            // 3 Sub-Tabs Pill Bar: In Progress / Completed / Cancelled
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: widget.accentColor,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                labelColor: Colors.white,
                unselectedLabelColor: widget.isDark ? Colors.white60 : Colors.black54,
                labelStyle: const TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(
                    text: inProgressTasks.isNotEmpty
                        ? 'In Progress (${inProgressTasks.length})'
                        : 'In Progress',
                  ),
                  Tab(
                    text: completedTasks.isNotEmpty
                        ? 'Completed (${completedTasks.length})'
                        : 'Completed',
                  ),
                  Tab(
                    text: cancelledTasks.isNotEmpty
                        ? 'Cancelled (${cancelledTasks.length})'
                        : 'Cancelled',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInProgressList(inProgressTasks),
                  _buildCompletedList(completedTasks),
                  _buildCancelledList(cancelledTasks),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── SUB-TAB 1: In Progress ──
  Widget _buildInProgressList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_download_outlined,
        title: 'No Active Downloads',
        subtitle: 'Downloading songs will display live progress and controls here.',
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isPaused = task.status == DownloadStatus.paused;
        final isConverting = task.status == DownloadStatus.converting;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTrackThumbnail(
                        task,
                        size: 40,
                        fallbackColor: colorInProgress.withValues(alpha: 0.15),
                        fallbackIcon: Icons.downloading_rounded,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 12,
                                color: widget.isDark ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusPill(
                        label: isConverting
                            ? 'Converting'
                            : isPaused
                                ? 'Paused'
                                : task.status == DownloadStatus.queued
                                    ? 'Queued'
                                    : 'Downloading',
                        color: colorInProgress,
                      ),
                      const SizedBox(width: 4),
                      // 3-Dots Menu Button
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                        color: widget.isDark ? Colors.white60 : Colors.black54,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => _showInProgressOptions(task),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Live Progress Indicator
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: isConverting ? null : task.progress,
                      minHeight: 6,
                      backgroundColor: widget.isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(colorInProgress),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildBadge(task.outputFormat.toUpperCase(), colorInProgress),
                      const SizedBox(width: 6),
                      _buildBadge(DownloadQualityTier.getLabel(task.qualityTier).split(' ').first, Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isConverting ? 'Optimizing audio track...' : task.formattedProgress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: widget.isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      if (!isConverting) ...[
                        if (isPaused)
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded),
                            color: colorInProgress,
                            iconSize: 22,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: 'Resume',
                            onPressed: () => DownloadService.instance.resumeDownload(task.videoId),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.pause_rounded),
                            color: colorInProgress,
                            iconSize: 22,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: 'Pause',
                            onPressed: () => DownloadService.instance.pauseDownload(task.videoId),
                          ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: widget.isDark ? Colors.white54 : Colors.black45,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        tooltip: 'Cancel',
                        onPressed: () => DownloadService.instance.cancelDownload(task.videoId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── SUB-TAB 2: Completed ──
  Widget _buildCompletedList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No Completed Downloads',
        subtitle: 'Downloaded music ready for offline playback will appear here.',
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _buildTrackThumbnail(
                    task,
                    size: 44,
                    fallbackColor: colorCompleted.withValues(alpha: 0.15),
                    fallbackIcon: Icons.music_note_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            color: widget.isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildBadge(task.outputFormat.toUpperCase(), colorCompleted),
                            const SizedBox(width: 6),
                            _buildBadge(DownloadQualityTier.getLabel(task.qualityTier).split(' ').first, Colors.grey),
                            const SizedBox(width: 6),
                            Text(
                              task.formattedDownloadedSize,
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: widget.isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Play Button
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: const BoxDecoration(
                        color: colorCompleted,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                    ),
                    tooltip: 'Play',
                    onPressed: () => _playDownloadedTrack(task),
                  ),
                  // 3-Dots Menu Button
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    color: widget.isDark ? Colors.white60 : Colors.black54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _showCompletedOptions(task),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── SUB-TAB 3: Cancelled / Failed ──
  Widget _buildCancelledList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cancel_outlined,
        title: 'No Cancelled Downloads',
        subtitle: 'Cancelled or failed tasks will appear here.',
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        final isFailed = task.status == DownloadStatus.failed;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _buildTrackThumbnail(
                    task,
                    size: 44,
                    fallbackColor: colorCancelled.withValues(alpha: 0.15),
                    fallbackIcon: Icons.music_off_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: AppTypography.displayFont,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusPill(
                              label: isFailed ? 'Failed' : 'Cancelled',
                              color: colorCancelled,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          task.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            color: widget.isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildBadge(task.outputFormat.toUpperCase(), colorCancelled),
                            const SizedBox(width: 6),
                            _buildBadge(DownloadQualityTier.getLabel(task.qualityTier).split(' ').first, Colors.grey),
                          ],
                        ),
                        if (isFailed && task.errorMessage != null && task.errorMessage!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            task.errorMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 11,
                              color: colorCancelled,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Inline Retry Button
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: colorCancelled),
                    tooltip: 'Retry',
                    onPressed: () {
                      DownloadService.instance.retryDownload(task.videoId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Retrying "${task.title}"...')),
                      );
                    },
                  ),
                  // 3-Dots Menu Button
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    color: widget.isDark ? Colors.white60 : Colors.black54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => _showCancelledOptions(task),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.uiFont,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.uiFont,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: widget.isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 12,
                color: widget.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
