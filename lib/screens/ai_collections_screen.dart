import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_typography.dart';
import '../core/helpers/accent_color_helper.dart';
import '../core/widgets/sm_text_field.dart';
import '../models/audio_category.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_player_service.dart';
import '../widgets/add_to_playlist_dialog.dart';
import '../widgets/edit_metadata_dialog.dart';
import '../widgets/storage_insights_sheet.dart';
import '../widgets/track_artwork.dart';
import '../services/library_intelligence_service.dart';
import '../services/download/download_models.dart';
import '../services/download/download_service.dart';
import 'downloads_screen.dart';
import 'playlist_detail_screen.dart';
import '../utils/song_heuristics.dart';
import '../core/theme/section_accents.dart';

enum LibrarySort { newest, oldest, aToZ, zToA, duration, size, playCount, dateAdded }

class AiCollectionsScreen extends StatefulWidget {
  final List<Track> allTracks;
  final String? initialCategory;
  final void Function(List<Track> playlist, int index) onPlaySelected;

  static final GlobalKey<AiCollectionsScreenState> globalKey =
      GlobalKey<AiCollectionsScreenState>();

  const AiCollectionsScreen({
    super.key,
    required this.allTracks,
    required this.onPlaySelected,
    this.initialCategory,
  });

  @override
  State<AiCollectionsScreen> createState() => AiCollectionsScreenState();
}

class AiCollectionsScreenState extends State<AiCollectionsScreen> with SingleTickerProviderStateMixin {
  static AiCollectionsScreenState? instance;

  late TabController _tabController;
  final GlobalKey<DownloadsSubTabsWidgetState> downloadsSubTabsKey =
      GlobalKey<DownloadsSubTabsWidgetState>();

  void switchToDownloadTab({int subTab = 0}) {
    if (mounted) {
      if (_inlineTitle != null) {
        setState(() {
          _inlineTitle = null;
          _inlineTracks = null;
        });
      }
      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
      void trySubTab() {
        final subTabs =
            downloadsSubTabsKey.currentState ?? DownloadsSubTabsWidgetState.instance;
        subTabs?.switchToSubTab(subTab);
      }

      trySubTab();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        trySubTab();
      });
    }
  }
  
  void switchToTab(int tabIndex) {
    if (mounted) {
      if (_inlineTitle != null) {
        setState(() {
          _inlineTitle = null;
          _inlineTracks = null;
        });
      }
      if (_tabController.index != tabIndex) {
        _tabController.animateTo(tabIndex);
      }
    }
  }

  List<Track> _libraryTracks = [];
  List<Track> _reviewTracks = [];
  List<Track> _favoriteTracks = [];
  List<Track> _historyTracks = [];
  List<Playlist> _customPlaylists = [];
  
  // Selection & Filtering state
  final Set<Track> _selectedTracks = {};
  bool _isSelectionMode = false;
  String _searchQuery = '';
  LibrarySort _sortMode = LibrarySort.aToZ;
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Favorites', 'Downloaded', 'Unplayed'];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Inline view state
  String? _inlineTitle;
  List<Track>? _inlineTracks;

  @override
  void initState() {
    super.initState();
    instance = this;
    _tabController = TabController(length: 10, vsync: this);
    
    if (widget.initialCategory != null) {
      final cat = widget.initialCategory!.toLowerCase().trim();
      if (cat == 'all songs' || cat == 'songs' || cat == 'all') {
        _tabController.index = 1;
        _inlineTitle = null;
        _inlineTracks = null;
        _libraryTracks = widget.allTracks.where((t) => !isJunkTrack(t)).toList();
      } else if (cat == 'history' || cat == 'recent' || cat == 'recently played' || cat == 'jumps back in') {
        _tabController.index = 8;
        _inlineTitle = null;
        _inlineTracks = null;
        _libraryTracks = widget.allTracks.where((t) => !isJunkTrack(t)).toList();
      } else if (cat == 'download' || cat == 'downloads') {
        _tabController.index = 0;
        _inlineTitle = null;
        _inlineTracks = null;
        _libraryTracks = widget.allTracks.where((t) => !isJunkTrack(t)).toList();
      } else {
        _inlineTitle = widget.initialCategory;
        _inlineTracks = List.from(widget.allTracks);
      }
    } else {
      _libraryTracks = widget.allTracks.where((t) => !isJunkTrack(t)).toList();
    }

    _loadRepositoryData();
    AudioRepository.instance.addListener(_loadRepositoryData);
  }

  @override
  void didUpdateWidget(AiCollectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != null && widget.initialCategory != oldWidget.initialCategory) {
      final cat = widget.initialCategory!.toLowerCase().trim();
      if (cat == 'all songs' || cat == 'songs' || cat == 'all') {
        switchToTab(1);
      } else if (cat == 'history' || cat == 'recent' || cat == 'recently played' || cat == 'jumps back in') {
        switchToTab(8);
      } else if (cat == 'download' || cat == 'downloads') {
        switchToTab(0);
      } else {
        setState(() {
          _inlineTitle = widget.initialCategory;
          _inlineTracks = List.from(widget.allTracks);
        });
      }
    }
  }

  Future<void> _loadRepositoryData() async {
    final music = await AudioRepository.instance.getMusicOnlyTracks();
    final nonJunkMusic = music.where((t) => !isJunkTrack(t)).toList();
    final reviews = await AudioRepository.instance.getReviewTracks();
    final favs = await AudioRepository.instance.getFavorites();
    final nonJunkFavs = favs.where((t) => !isJunkTrack(t)).toList();
    final hist = await AudioRepository.instance.getRecentlyPlayed();
    final nonJunkHist = hist.where((t) => !isJunkTrack(t)).toList();
    final playlists = await AudioRepository.instance.getPlaylists();
    if (mounted) {
      setState(() {
        if (widget.initialCategory == null ||
            widget.initialCategory!.toLowerCase().trim() == 'all songs' ||
            widget.initialCategory!.toLowerCase().trim() == 'history' ||
            widget.initialCategory!.toLowerCase().trim() == 'download') {
          _libraryTracks = nonJunkMusic;
        }
        _reviewTracks = reviews;
        _favoriteTracks = nonJunkFavs;
        _historyTracks = nonJunkHist;
        _customPlaylists = playlists;
      });
    }
  }

  @override
  void dispose() {
    if (instance == this) instance = null;
    AudioRepository.instance.removeListener(_loadRepositoryData);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Helper Grouping Methods
  Map<String, List<Track>> _groupBy(List<Track> tracks, String Function(Track) keySelector) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      final key = keySelector(t);
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  String _extractFolder(Track t) {
    if (t.filePath == null || t.filePath!.isEmpty) return 'Unknown Folder';
    final parts = t.filePath!.split('/');
    if (parts.length > 1) return parts[parts.length - 2];
    return 'Root';
  }

  // Formatting Methods
  String _formatSize(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  String _formatDuration(int ms) {
    final int totalMinutes = (ms / 1000 / 60).truncate();
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  // List Sorting
  void _sortTracksList(List<Track> list) {
    list.sort((a, b) {
      switch (_sortMode) {
        case LibrarySort.newest:
          return (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0);
        case LibrarySort.oldest:
          return (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
        case LibrarySort.aToZ:
          return a.title.compareTo(b.title);
        case LibrarySort.zToA:
          return b.title.compareTo(a.title);
        case LibrarySort.duration:
          return (b.duration ?? 0).compareTo(a.duration ?? 0);
        case LibrarySort.size:
          return (b.size ?? 0).compareTo(a.size ?? 0);
        case LibrarySort.playCount:
          return b.playCount.compareTo(a.playCount);
        case LibrarySort.dateAdded:
          return (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0);
      }
    });
  }

  void _openInlineView(String title, List<Track> tracks) {
    setState(() {
      _inlineTitle = title;
      _inlineTracks = tracks;
    });
  }

  void _handleAction(String action) {
    if (action == 'Delete') {
      setState(() {
        _libraryTracks.removeWhere((t) => _selectedTracks.contains(t));
        _selectedTracks.clear();
        _isSelectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from Library'), backgroundColor: AppColors.voidOverlay),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action ${_selectedTracks.length} tracks'), backgroundColor: AppColors.voidOverlay),
      );
      setState(() {
        _selectedTracks.clear();
        _isSelectionMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor = AccentColorHelper.resolve(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: (widget.initialCategory != null) || (_inlineTitle == null && !_isSelectionMode),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          setState(() {
            _isSelectionMode = false;
            _selectedTracks.clear();
          });
        } else if (_inlineTitle != null && widget.initialCategory == null) {
          setState(() {
            _inlineTitle = null;
            _inlineTracks = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xFF070B14), Color(0xFF0F1623), Color(0xFF0A0E1A)]
                  : const [Color(0xFFF0F4FF), Color(0xFFECEFF8), Color(0xFFE8EDF7)],
            ),
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _buildHeader(accentColor),
                Expanded(
                  child: _inlineTitle != null 
                      ? _buildInlineTrackList(accentColor) 
                      : _buildTabBarView(accentColor, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isSelectionMode) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _isSelectionMode = false;
                _selectedTracks.clear();
              }),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                '${_selectedTracks.length} Selected',
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: AppTypography.displayM,
                  color: Colors.white,
                  letterSpacing: AppTypography.displayLetterSpacing,
                ),
              ),
            ),
            IconButton(icon: Icon(Icons.play_arrow_rounded, color: accentColor), onPressed: () => _handleAction('Play')),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
              color: AppColors.voidDeep,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
              onSelected: _handleAction,
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'Queue', child: Text('Add to Queue', style: TextStyle(color: Colors.white, fontFamily: AppTypography.uiFont))),
                const PopupMenuItem(value: 'Favorite', child: Text('Favorite', style: TextStyle(color: Colors.white, fontFamily: AppTypography.uiFont))),
                const PopupMenuItem(value: 'Share', child: Text('Share', style: TextStyle(color: Colors.white, fontFamily: AppTypography.uiFont))),
                const PopupMenuItem(value: 'Delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent, fontFamily: AppTypography.uiFont))),
              ],
            ),
          ],
        ),
      );
    }

    if (_inlineTitle != null) {
      return Padding(
        padding: AppSpacing.searchTitlePadding,
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (widget.initialCategory != null) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    _inlineTitle = null;
                    _inlineTracks = null;
                  });
                }
              },
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1)),
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: accentColor, size: 16),
              ),
            ),
            Expanded(
              child: Text(
                _inlineTitle!,
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: AppTypography.displayM,
                  color: accentColor,
                  letterSpacing: AppTypography.displayLetterSpacing,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Library',
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: AppTypography.displayM,
                  color: accentColor,
                  letterSpacing: AppTypography.displayLetterSpacing,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<List<DownloadTask>>(
                    stream: DownloadService.instance.watchAllDownloads(),
                    initialData: DownloadService.instance.getAllTasks(),
                    builder: (context, snapshot) {
                      final activeCount = (snapshot.data ?? [])
                          .where(
                            (t) =>
                                t.status == DownloadStatus.downloading ||
                                t.status == DownloadStatus.converting,
                          )
                          .length;
                      final iconColor = isDark ? Colors.white70 : const Color(0xFF1E293B);
                      return IconButton(
                        icon: Badge(
                          isLabelVisible: activeCount > 0,
                          label: Text('$activeCount'),
                          backgroundColor: accentColor,
                          child: Icon(
                            Icons.download_rounded,
                            color: iconColor,
                            size: 22,
                          ),
                        ),
                        tooltip: 'Download History & Analytics',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DownloadsScreen(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.pie_chart_outline_rounded,
                      color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                      size: 22,
                    ),
                    tooltip: 'Storage & Category Insights',
                    onPressed: () => StorageInsightsSheet.show(
                      context,
                      accentColor: accentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final currentAccent = _getTabAccent(_tabController.index, isDark, accentColor);
            return TabBar(
              controller: _tabController,
              isScrollable: true,
              indicator: BoxDecoration(
                color: currentAccent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: currentAccent.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : const Color(0xFF0B132B).withValues(alpha: 0.60),
              labelStyle: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: AppTypography.labelL,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: AppTypography.labelL,
                fontWeight: FontWeight.w600,
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Download'),
                const Tab(text: 'All Songs'),
                const Tab(text: 'Playlists'),
                const Tab(text: 'Recently Added'),
                const Tab(text: 'Favorites'),
                const Tab(text: 'Artists'),
                const Tab(text: 'Albums'),
                const Tab(text: 'Folders'),
                const Tab(text: 'History'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Review'),
                      if (_reviewTracks.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: currentAccent.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_reviewTracks.length}',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: currentAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Color _getTabAccent(int tabIndex, bool isDark, Color defaultAccent) {
    switch (tabIndex) {
      case 0:
        return SectionAccents.downloads(isDark);
      case 2:
        return SectionAccents.playlists(isDark);
      case 4:
        return SectionAccents.favorites(isDark);
      default:
        return defaultAccent;
    }
  }

  Widget _buildTabBarView(Color accentColor, bool isDark) {
    final downloadsAccent = SectionAccents.downloads(isDark);
    final playlistsAccent = SectionAccents.playlists(isDark);
    final favoritesAccent = SectionAccents.favorites(isDark);

    return TabBarView(
      controller: _tabController,
      children: [
        DownloadsSubTabsWidget(
          key: downloadsSubTabsKey,
          accentColor: downloadsAccent,
          isDark: isDark,
          onPlaySelected: (track) => widget.onPlaySelected([track], 0),
        ),
        _buildSongsTab(accentColor, _libraryTracks, isDark),
        _buildPlaylistsTab(playlistsAccent, isDark),
        _buildRecentlyAddedTab(accentColor, isDark),
        _buildFavoritesTab(favoritesAccent, isDark),
        _buildGroupedTab(accentColor, _groupBy(_libraryTracks, (t) => t.artist), Icons.person_rounded),
        _buildGroupedTab(accentColor, _groupBy(_libraryTracks, (t) => t.album ?? 'Unknown Album'), Icons.album_rounded),
        _buildFoldersTab(accentColor),
        _buildHistoryTab(accentColor),
        _buildReviewTab(accentColor, _reviewTracks, isDark),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB BUILDERS
  // ---------------------------------------------------------------------------

  Widget _buildSongsTab(Color accentColor, List<Track> sourceTracks, bool isDark) {
    List<Track> displayList = sourceTracks.where((t) {
      if (isJunkTrack(t)) return false;
      if (_searchQuery.isNotEmpty && !t.title.toLowerCase().contains(_searchQuery.toLowerCase()) && !t.artist.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_activeFilter == 'Favorites' && !t.isFavorite) return false;
      if (_activeFilter == 'Downloaded' && !t.isDownloaded) return false;
      if (_activeFilter == 'Unplayed' && t.playCount > 0) return false;
      return true;
    }).toList();

    _sortTracksList(displayList);

    return Column(
      children: [
        _buildToolbar(accentColor, isDark),
        Expanded(
          child: displayList.isEmpty
              ? _buildEmptyState(Icons.music_off_rounded, 'No Songs Found', 'Adjust your filters or search query.')
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: AppSpacing.homeScrollPadding,
                  itemCount: displayList.length,
                  itemBuilder: (context, index) {
                    final track = displayList[index];
                    return _buildTrackTile(track, index, displayList, accentColor);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(Color accentColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: SmTextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    accentColor: accentColor,
                    isDark: isDark,
                    hint: 'Search songs...',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B1730).withValues(alpha: 0.20)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isDark
                        ? accentColor.withValues(alpha: 0.35)
                        : const Color(0xFFCBD5E1),
                    width: 1.0,
                  ),
                ),
                child: PopupMenuButton<LibrarySort>(
                  icon: Icon(Icons.sort_rounded, color: accentColor, size: 20),
                  color: isDark ? const Color(0xFF0D1527) : Colors.white,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  onSelected: (sort) => setState(() => _sortMode = sort),
                  itemBuilder: (context) => LibrarySort.values.map((s) {
                    String label = s.toString().split('.').last;
                    label = label[0].toUpperCase() +
                        label.substring(1).replaceAll(RegExp(r'(?=[A-Z])'), ' ');
                    final isSortActive = _sortMode == s;
                    return PopupMenuItem(
                      value: s,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSortActive
                              ? accentColor
                              : (isDark ? Colors.white : const Color(0xFF0F172A)),
                          fontFamily: AppTypography.uiFont,
                          fontWeight:
                              isSortActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isActive = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(
                      filter,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 12,
                        color: isActive
                            ? (isDark ? Colors.white : accentColor)
                            : (isDark ? Colors.white70 : const Color(0xFF334155)),
                      ),
                    ),
                    selected: isActive,
                    onSelected: (selected) =>
                        setState(() => _activeFilter = filter),
                    selectedColor: isDark
                        ? accentColor.withValues(alpha: 0.22)
                        : accentColor.withValues(alpha: 0.15),
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE2E8F0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      side: BorderSide(
                        color: isActive
                            ? accentColor
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : const Color(0xFFCBD5E1)),
                        width: 1.0,
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Future<void> _showCreatePlaylistInlineDialog() async {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AccentColorHelper.resolve(context);

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
          ),
          title: Text(
            'New Playlist',
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor.withValues(alpha: 0.5))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accentColor)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (created == true && controller.text.trim().isNotEmpty) {
      final name = controller.text.trim();
      try {
        await AudioRepository.instance.createPlaylist(name);
        await _loadRepositoryData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Created playlist "$name"'), backgroundColor: AppColors.voidOverlay),
          );
        }
      } catch (e) {
        debugPrint('Error creating playlist: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not create playlist. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Widget _buildPlaylistsTab(Color accentColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Smart Playlists Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Smart Playlists',
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'AI & Rules',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Grid of 8 Smart Playlists
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.0,
          ),
          itemCount: SmartPlaylistType.values.length,
          itemBuilder: (context, index) {
            final type = SmartPlaylistType.values[index];
            IconData icon;
            switch (type) {
              case SmartPlaylistType.recentlyPlayed:
                icon = Icons.history_rounded;
                break;
              case SmartPlaylistType.mostPlayed:
                icon = Icons.local_fire_department_rounded;
                break;
              case SmartPlaylistType.recentlyAdded:
                icon = Icons.fiber_new_rounded;
                break;
              case SmartPlaylistType.favorites:
                icon = Icons.favorite_rounded;
                break;
              case SmartPlaylistType.longTracks:
                icon = Icons.hourglass_top_rounded;
                break;
              case SmartPlaylistType.shortTracks:
                icon = Icons.bolt_rounded;
                break;
              case SmartPlaylistType.highConfidenceMusic:
                icon = Icons.verified_rounded;
                break;
              case SmartPlaylistType.neverPlayed:
                icon = Icons.explore_outlined;
                break;
            }

            return InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () async {
                final tracks = await AudioRepository.instance.getSmartPlaylistTracks(type);
                _openInlineView(type.displayName, tracks);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1527) : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.22 : 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            type.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),

        // Advanced Composable Intelligence Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Advanced Intelligence',
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Composable Rules',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AdvancedSmartRule.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final rule = AdvancedSmartRule.values[index];
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () async {
                  final tracks = await LibraryIntelligenceService.instance.getAdvancedSmartPlaylist(rule);
                  _openInlineView(rule.displayName, tracks);
                },
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F1A30) : Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.25 : 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: accentColor, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              rule.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rule.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Custom Playlists Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Custom Playlists',
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            TextButton.icon(
              onPressed: _showCreatePlaylistInlineDialog,
              icon: Icon(Icons.add, color: accentColor, size: 18),
              label: Text(
                'New Playlist',
                style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_customPlaylists.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1527) : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Column(
              children: [
                Icon(Icons.queue_music_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
                const SizedBox(height: 12),
                Text(
                  'No custom playlists yet',
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create playlists to organize your favorite music for workouts, road trips, and focus sessions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _showCreatePlaylistInlineDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create Playlist'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _customPlaylists.length,
            itemBuilder: (context, index) {
              final playlist = _customPlaylists[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1527) : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.22 : 0.3)),
                ),
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 24),
                  ),
                  title: Text(
                    playlist.name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '${playlist.trackCount} ${playlist.trackCount == 1 ? "song" : "songs"}',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                  ),
                  trailing: Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 14),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(
                          playlist: playlist,
                          accentColor: accentColor,
                          onPlaySelected: widget.onPlaySelected,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    _loadRepositoryData();
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGroupedTab(Color accentColor, Map<String, List<Track>> groupedData, IconData fallbackIcon) {
    final keys = groupedData.keys.toList()..sort();
    if (keys.isEmpty) return _buildEmptyState(fallbackIcon, 'No Items', 'Library is empty.');

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: AppSpacing.homeScrollPadding,
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final tracks = groupedData[key]!;
        final firstTrack = tracks.first;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return GestureDetector(
          onTap: () => _openInlineView(key, tracks),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1527).withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.22 : 0.30)),
              boxShadow: [
                BoxShadow(color: accentColor.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                TrackArtwork(track: firstTrack, width: 56, height: 56, borderRadius: AppRadius.md, showShadow: false),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(key, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontFamily: AppTypography.uiFont, fontSize: AppTypography.trackTitle, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                      const SizedBox(height: 4),
                      Text('${tracks.length} Songs', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black54, fontFamily: AppTypography.uiFont, fontSize: AppTypography.trackArtist)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black12, size: 16),
                const SizedBox(width: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFoldersTab(Color accentColor) {
    final Map<String, List<Track>> folders = _groupBy(_libraryTracks, _extractFolder);
    final keys = folders.keys.toList()..sort();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (keys.isEmpty) return _buildEmptyState(Icons.folder_rounded, 'No Folders', 'No local folders detected.');

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: AppSpacing.homeScrollPadding,
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final folderName = keys[index];
        final tracks = folders[folderName]!;
        final firstTrack = tracks.first;

        final int totalMs = tracks.fold(0, (sum, t) => sum + (t.duration ?? 0));
        final int totalSize = tracks.fold(0, (sum, t) => sum + (t.size ?? 0));
        final int lastUpdated = tracks.fold(0, (max, t) => math.max(max, t.dateAdded ?? 0));

        return GestureDetector(
          onTap: () => _openInlineView(folderName, tracks),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1527).withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: accentColor.withValues(alpha: isDark ? 0.22 : 0.30)),
              boxShadow: [
                BoxShadow(color: accentColor.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                TrackArtwork(track: firstTrack, width: 64, height: 64, borderRadius: AppRadius.md, showShadow: false),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folderName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontFamily: AppTypography.uiFont, fontSize: AppTypography.trackTitle, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                      const SizedBox(height: 6),
                      Text('${tracks.length} Songs • ${_formatDuration(totalMs)}', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black54, fontFamily: AppTypography.uiFont, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text('${_formatSize(totalSize)} • Updated: ${DateTime.fromMillisecondsSinceEpoch(lastUpdated * 1000).toString().split(' ')[0]}', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black38, fontFamily: AppTypography.uiFont, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black12, size: 16),
                const SizedBox(width: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReviewTab(Color accentColor, List<Track> reviewTracks, bool isDark) {
    if (reviewTracks.isEmpty) {
      return _buildEmptyState(
        Icons.verified_rounded,
        'All Audio Classified',
        'No ambiguous or low-confidence audio files requiring review.',
        accentColor,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: accentColor.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: accentColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Safe Playback Protection: Ambiguous tracks are quarantined from Music Play All until verified.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF1E293B),
                      fontSize: 11,
                      fontFamily: AppTypography.uiFont,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: AppSpacing.homeScrollPadding,
            itemCount: reviewTracks.length,
            itemBuilder: (context, index) {
              final track = reviewTracks[index];
              return _buildTrackTile(track, index, reviewTracks, accentColor);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlyAddedTab(Color accentColor, bool isDark) {
    final recent = List<Track>.from(_libraryTracks)
      ..sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
    if (recent.isEmpty) {
      return _buildEmptyState(
        Icons.schedule_rounded,
        'No Recently Added Tracks',
        'Songs discovered on your device will appear here in chronological order.',
      );
    }
    return _buildSongsTab(accentColor, recent, isDark);
  }

  Widget _buildFavoritesTab(Color accentColor, bool isDark) {
    final favorites = _favoriteTracks.isNotEmpty
        ? _favoriteTracks
        : _libraryTracks.where((t) => t.isFavorite).toList();
    if (favorites.isEmpty) {
      return _buildEmptyState(Icons.favorite_outline_rounded, 'No Favorites', 'Tap the heart icon on any track to add it here.');
    }
    return _buildSongsTab(accentColor, favorites, isDark);
  }

  Widget _buildHistoryTab(Color accentColor) {
    final history = _historyTracks.isNotEmpty
        ? _historyTracks
        : AudioPlayerService.instance.playbackHistory;
    
    if (history.isEmpty) {
      return _buildEmptyState(Icons.history_rounded, 'No History', 'Songs you play will show up here.');
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: AppSpacing.homeScrollPadding,
      itemCount: history.length,
      itemBuilder: (context, index) => _buildTrackTile(history[index], index, history, accentColor),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED COMPONENTS
  // ---------------------------------------------------------------------------

  Widget _buildInlineTrackList(Color accentColor) {
    if (_inlineTracks == null || _inlineTracks!.isEmpty) {
      return _buildEmptyState(Icons.library_music_rounded, 'Empty', 'No tracks found in this category.');
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: AppSpacing.homeScrollPadding,
      itemCount: _inlineTracks!.length,
      itemBuilder: (context, index) => _buildTrackTile(_inlineTracks![index], index, _inlineTracks!, accentColor),
    );
  }

  Widget _buildTrackTile(Track track, int index, List<Track> playlist, Color accentColor) {
    final isSelected = _selectedTracks.contains(track);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0B132B);
    final secondaryTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          _selectedTracks.add(track);
        });
      },
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedTracks.remove(track);
            } else {
              _selectedTracks.add(track);
            }
            if (_selectedTracks.isEmpty) _isSelectionMode = false;
          });
        } else {
          widget.onPlaySelected(playlist, index);
        }
      },
      child: AnimatedContainer(

        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? accentColor.withValues(alpha: 0.18) 
              : (isDark
                  ? const Color(0xFF0D1527).withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.85)),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected
                ? accentColor
                : accentColor.withValues(alpha: isDark ? 0.22 : 0.30),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (_isSelectionMode) ...[
              SizedBox(
                width: 32,
                child: Checkbox(
                  value: isSelected,
                  activeColor: accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  side: BorderSide(
                    color: isDark ? Colors.white54 : const Color(0xFF0B132B).withValues(alpha: 0.5),
                  ),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedTracks.add(track);
                      } else {
                        _selectedTracks.remove(track);
                      }
                      if (_selectedTracks.isEmpty) _isSelectionMode = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              TrackArtwork(
                track: track,
                width: 50,
                height: 50,
                borderRadius: AppRadius.sm,
                showShadow: false,
              ),
              const SizedBox(width: 14),
            ],
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: AppTypography.trackTitle,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? accentColor : primaryTextColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: AppTypography.trackArtist,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            
            if (track.isFavorite) ...[
              const Icon(
                Icons.favorite_rounded,
                color: Color(0xFFFF2E7E),
                size: 16,
              ),
              const SizedBox(width: 4),
            ],
            if (!_isSelectionMode)
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: isDark ? Colors.white54 : const Color(0xFF0B132B).withValues(alpha: 0.5),
                  size: 20,
                ),
                onPressed: () => _showTrackOptions(track, accentColor, isDark),
              ),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(Track track, Color accentColor, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TrackArtwork(track: track, width: 48, height: 48, borderRadius: AppRadius.sm, showShadow: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87)),
                          const SizedBox(height: 2),
                          Text('${track.artist} • ${track.audioCategory.displayName}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                          Text(
                            '${(track.confidence * 100).toStringAsFixed(0)}% Confidence (${track.userOverride ? "User Override" : track.classificationSource.name})',
                            style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                ListTile(
                  leading: Icon(track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: track.isFavorite ? const Color(0xFFFF2E7E) : accentColor),
                  title: Text(track.isFavorite ? 'Remove from Favorites' : 'Add to Favorites', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AudioPlayerService.instance.toggleFavorite(track);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.playlist_add_rounded, color: accentColor),
                  title: Text('Add to Playlist', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Add to custom playlist', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                  onTap: () {
                    Navigator.pop(ctx);
                    AddToPlaylistDialog.show(context, track, accentColor: accentColor);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.edit_note_rounded, color: accentColor),
                  title: Text('Change Classification', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Override category (persists permanently)', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCategoryPickerDialog(track, accentColor, isDark);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined, color: Colors.cyanAccent),
                  title: Text('Edit Metadata', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                  subtitle: Text('Edit Title, Artist, Album, Genre, Year', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
                  onTap: () {
                    Navigator.pop(ctx);
                    EditMetadataDialog.show(context, track, accentColor: accentColor);
                  },
                ),
                if (track.userOverride)
                  ListTile(
                    leading: const Icon(Icons.restore_rounded, color: Colors.amberAccent),
                    title: Text('Reset to Heuristic Classification', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (track.id != null) {
                        await AudioRepository.instance.resetOverride(track.id!);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Reset classification override'), backgroundColor: AppColors.voidOverlay),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCategoryPickerDialog(Track track, Color accentColor, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0D1527) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Classify Audio', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AudioCategory.values.where((c) => c != AudioCategory.unknown).map((cat) {
              final isCurrent = track.audioCategory == cat;
              return ListTile(
                leading: Icon(cat.icon, color: isCurrent ? accentColor : (isDark ? Colors.white70 : Colors.black54)),
                title: Text(cat.displayName, style: TextStyle(color: isCurrent ? accentColor : (isDark ? Colors.white : Colors.black87), fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                trailing: isCurrent ? Icon(Icons.check_rounded, color: accentColor) : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  if (track.id != null) {
                    await AudioRepository.instance.overrideClassification(track.id!, cat);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Marked as ${cat.displayName}'), backgroundColor: AppColors.voidOverlay),
                      );
                    }
                  }
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle, [Color? accent]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = accent ?? (isDark ? AppColors.abyssAccent : AppColors.frostAccent);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Icon(icon, size: 38, color: accentColor),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0B132B),
                fontSize: AppTypography.headingXS,
                fontFamily: AppTypography.uiFont,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                fontFamily: AppTypography.uiFont,
                fontSize: AppTypography.bodyS,
              ),
            ),
          ],
        ),
      ),
    );
  }
}