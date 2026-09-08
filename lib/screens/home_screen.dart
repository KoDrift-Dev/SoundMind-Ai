// home_screen.dart — 100% redesigned UI (logic preserved)
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../core/theme/section_accents.dart';
import '../core/helpers/greeting_helper.dart';
import '../core/helpers/track_collection_helper.dart';

import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../services/local_recommendation_service.dart';
import '../services/audio_scanner_service.dart';
import '../services/notification_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/track_artwork.dart';
import '../online/models/online_search_result.dart';
import '../services/youtube_service.dart';
import '../services/online_playback_helper.dart';
import '../services/audio_player_service.dart';
import '../utils/duration_formatter.dart';
import '../widgets/online_section_error_widget.dart';
import '../widgets/track_action_menu.dart';
import '../core/widgets/user_avatar.dart';
import '../widgets/avatar_picker_sheet.dart';
import 'search_screen.dart';

enum CollectionSort { alphabetical, trackCount, duration, recentlyAdded }

// ─────────────────────────── Home Feed Item (Local / Online) ───────────────────────────

class _HomeFeedItem {
  final Track? localTrack;
  final OnlineSearchResult? onlineTrack;
  final bool isOnline;

  const _HomeFeedItem.local(Track track)
      : localTrack = track,
        onlineTrack = null,
        isOnline = false;

  const _HomeFeedItem.online(OnlineSearchResult track)
      : localTrack = null,
        onlineTrack = track,
        isOnline = true;

  String get title => isOnline ? (onlineTrack?.title ?? '') : (localTrack?.title ?? '');
  String get artist => isOnline ? (onlineTrack?.artist ?? '') : (localTrack?.artist ?? '');
  String? get thumbnailUrl => isOnline ? onlineTrack?.thumbnailUrl : localTrack?.artUrl;
  String get id => isOnline ? (onlineTrack?.id ?? '') : (localTrack?.filePath ?? '');

  String get uniqueKey => isOnline
      ? 'online_${onlineTrack?.id ?? ''}'
      : 'local_${localTrack?.filePath ?? localTrack?.id?.toString() ?? localTrack?.title ?? ''}';

  String get formattedDuration {
    if (isOnline) {
      final d = onlineTrack?.duration;
      return (d != null && d.isNotEmpty) ? formatDurationString(d) : 'Online';
    } else {
      return formatDurationMs(localTrack?.duration);
    }
  }
}

String _trackUniqueKey(Track t) =>
    'local_${t.filePath ?? t.id?.toString() ?? t.title}';

String _onlineUniqueKey(OnlineSearchResult o) => 'online_${o.id}';

/// Deduplicated interleaved section builder.
/// Respects [alreadyShown] to guarantee zero duplicate songs across For You sections,
/// while maintaining strict fallback backfilling so sections are never noticeably empty.
List<_HomeFeedItem> _buildDeduplicatedSection({
  required List<Track> localPool,
  required List<OnlineSearchResult> onlinePool,
  required Set<String> alreadyShown,
  required int targetCount,
  required int minCount,
}) {
  final unshownLocal = localPool
      .where((t) => !alreadyShown.contains(_trackUniqueKey(t)))
      .toList();
  final unshownOnline = onlinePool
      .where((o) => !alreadyShown.contains(_onlineUniqueKey(o)))
      .toList();

  int localNeeded = (targetCount / 2).ceil();
  int onlineNeeded = targetCount - localNeeded;

  List<Track> selectedLocal = unshownLocal.take(localNeeded).toList();
  List<OnlineSearchResult> selectedOnline = unshownOnline.take(onlineNeeded).toList();

  // If one source is short, backfill from other unshown source
  int currentTotal = selectedLocal.length + selectedOnline.length;
  if (currentTotal < targetCount) {
    if (selectedLocal.length < localNeeded) {
      final remainingOnline = unshownOnline.skip(selectedOnline.length).toList();
      final neededMore = targetCount - currentTotal;
      selectedOnline.addAll(remainingOnline.take(neededMore));
    } else if (selectedOnline.length < onlineNeeded) {
      final remainingLocal = unshownLocal.skip(selectedLocal.length).toList();
      final neededMore = targetCount - currentTotal;
      selectedLocal.addAll(remainingLocal.take(neededMore));
    }
  }

  // If still below minCount because pools were exhausted, backfill distinct candidates from source pool
  currentTotal = selectedLocal.length + selectedOnline.length;
  if (currentTotal < minCount) {
    for (final o in onlinePool) {
      if (currentTotal >= minCount) break;
      if (!selectedOnline.any((item) => item.id == o.id)) {
        selectedOnline.add(o);
        currentTotal++;
      }
    }
    for (final t in localPool) {
      if (currentTotal >= minCount) break;
      if (!selectedLocal.any((item) => _trackUniqueKey(item) == _trackUniqueKey(t))) {
        selectedLocal.add(t);
        currentTotal++;
      }
    }
  }

  // Interleave 1 offline, 1 online into the final list and register in alreadyShown
  final List<_HomeFeedItem> result = [];
  int l = 0;
  int o = 0;
  int safety = 0;
  while (result.length < targetCount &&
      (l < selectedLocal.length || o < selectedOnline.length) &&
      safety++ < 1000) {
    if (l < selectedLocal.length) {
      final item = _HomeFeedItem.local(selectedLocal[l++]);
      result.add(item);
      alreadyShown.add(item.uniqueKey);
    }
    if (result.length < targetCount && o < selectedOnline.length) {
      final item = _HomeFeedItem.online(selectedOnline[o++]);
      result.add(item);
      alreadyShown.add(item.uniqueKey);
    }
  }

  return result;
}

class _OnlineMix {
  final String genre;
  final String title;
  final List<OnlineSearchResult> tracks;

  const _OnlineMix({
    required this.genre,
    required this.title,
    required this.tracks,
  });
}

// ─────────────────────────── Animated Home Icon ───────────────────────────

class AnimatedHomeIcon extends StatefulWidget {
  final IconData icon;
  final Color? color;
  final double? size;
  final String? semanticLabel;
  final TextDirection? textDirection;

  const AnimatedHomeIcon(
    this.icon, {
    super.key,
    this.color,
    this.size,
    this.semanticLabel,
    this.textDirection,
  });

  @override
  State<AnimatedHomeIcon> createState() => _AnimatedHomeIconState();
}

class _AnimatedHomeIconState extends State<AnimatedHomeIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    final variance = (widget.icon.codePoint % 7) * 120;
    final dur = Duration(milliseconds: 1600 + variance);

    _controller = AnimationController(
      vsync: this,
      duration: dur,
    );

    _scaleAnim = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    final initialProgress = ((widget.icon.codePoint % 10) / 10.0);
    _controller.value = initialProgress;
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Icon(
        widget.icon,
        color: widget.color,
        size: widget.size,
        semanticLabel: widget.semanticLabel,
        textDirection: widget.textDirection,
      ),
    );
  }
}

// ─────────────────────────── Color Helpers ───────────────────────────

class _HomeColors {
  static Color surface(bool isDark) =>
      isDark ? const Color(0xFF0D1117).withValues(alpha: 0.65) : const Color(0xFFF7F8FC).withValues(alpha: 0.70);
  static Color card(bool isDark) =>
      isDark ? const Color(0xFF161B27).withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.75);
  static Color cardBorder(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08);
  static Color primaryText(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF0D1117);
  static Color secondaryText(bool isDark) =>
      isDark ? const Color(0xFF8B9CB5) : const Color(0xFF64748B);
  static Color divider(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);
  static List<Color> pageGradient(bool isDark, [Color? accent]) => isDark
      ? [
          (accent ?? const Color(0xFF3B82F6)).withValues(alpha: 0.28),
          const Color(0xFF0E1422),
          const Color(0xFF060911),
        ]
      : [
          (accent ?? const Color(0xFF3B82F6)).withValues(alpha: 0.20),
          (accent ?? const Color(0xFF3B82F6)).withValues(alpha: 0.05),
          Colors.white,
        ];
  static List<Color> forYouDarkGradient() => [
        const Color(0xFF03050C), // Deep dark black base
        const Color(0xFF0A122E).withValues(alpha: 0.95), // Deep midnight blue shade
        const Color(0xFF160B28).withValues(alpha: 0.92), // Deep royal purple shade
        const Color(0xFF020409), // Pitch dark abyss bottom
      ];
  static Color heroOverlay(bool isDark) =>
      isDark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.30);
}

// ─────────────────────────── Main Screen ───────────────────────────

class HomeScreen extends StatefulWidget {
  final Color accentColor;
  final bool isThemeOne;
  final List<Track> tracks;
  final void Function(List<Track> playlist, int index) onPlaySelected;
  final void Function(String? category) onNavigateToLibrary;
  final VoidCallback onNavigateToSearch;

  const HomeScreen({
    super.key,
    required this.accentColor,
    required this.isThemeOne,
    required this.tracks,
    required this.onPlaySelected,
    required this.onNavigateToLibrary,
    required this.onNavigateToSearch,
  });

  /// Selects weighted feed genres based on onboarding preferences and recency-decayed history.
  static Future<List<String>> selectFeedGenres({
    int weightedCount = 2,
    int discoveryCount = 1,
    SharedPreferences? sharedPrefs,
    math.Random? randomGenerator,
  }) async {
    final eligibleGenres = kBrowseGenres
        .where((g) => g != 'All' && g != 'Trending')
        .toList();
    if (eligibleGenres.isEmpty) {
      return [];
    }

    try {
      final prefs = sharedPrefs ?? await SharedPreferences.getInstance();

      final Map<String, String> canonicalGenres = {
        for (final g in eligibleGenres) g.toLowerCase().trim(): g,
      };

      // 1. Read preferred genres from onboarding / preferences
      final Set<String> preferredGenres = {};
      final servicePreferred = UserPreferencesService.instance.getPreferredGenres();
      if (servicePreferred.isNotEmpty) {
        preferredGenres.addAll(servicePreferred);
      }
      if (preferredGenres.isEmpty) {
        final rawPreferred = prefs.getString('preferred_genres');
        if (rawPreferred != null && rawPreferred.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawPreferred);
            if (decoded is List) {
              preferredGenres.addAll(decoded.map((e) => e.toString()));
            }
          } catch (e) {
            debugPrint('HomeScreen: Error decoding preferred_genres: $e');
          }
        }
        if (preferredGenres.isEmpty) {
          final list = prefs.getStringList('preferred_genres');
          if (list != null) preferredGenres.addAll(list);
        }
      }

      final Set<String> normalizedPreferred = {};
      for (final p in preferredGenres) {
        final canonical = canonicalGenres[p.toLowerCase().trim()];
        if (canonical != null) {
          normalizedPreferred.add(canonical);
        }
      }

      // 2. Read online play history and compute recency-decayed scores
      final Map<String, double> historyScores = {};
      final rawHistory = prefs.getString('online_play_history');
      if (rawHistory != null && rawHistory.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawHistory);
          if (decoded is List) {
            final now = DateTime.now();
            for (final entry in decoded) {
              if (entry is Map) {
                final genre = entry['genre'] as String?;
                if (genre != null) {
                  final canonical = canonicalGenres[genre.toLowerCase().trim()];
                  if (canonical != null) {
                    final tsStr = entry['timestamp'] as String?;
                    double daysOld = 0.0;
                    if (tsStr != null) {
                      final ts = DateTime.tryParse(tsStr);
                      if (ts != null) {
                        final diffHours = now.difference(ts).inMinutes / (60.0 * 24.0);
                        daysOld = diffHours > 0 ? diffHours : 0.0;
                      }
                    }
                    final recencyFactor = 1.0 / (1.0 + daysOld * 0.1);
                    historyScores[canonical] = (historyScores[canonical] ?? 0.0) + recencyFactor;
                  }
                }
              }
            }
          }
        } catch (e) {
          debugPrint('HomeScreen: Error decoding online_play_history: $e');
        }
      }

      // 3. Compute combined weights for all eligible genres.
      // Base onboarding preferences receive a strong baseline weight of 3.0.
      // History recency is capped at 1.5 so it nudges selection without dominating
      // and drowning out the variety of preferred genres.
      const double basePreferredWeight = 3.0;
      const double maxHistoryBonus = 1.5;

      final Map<String, double> weights = {};
      for (final genre in eligibleGenres) {
        double weight = 0.0;
        if (normalizedPreferred.contains(genre)) {
          weight += basePreferredWeight;
        }
        if (historyScores.containsKey(genre)) {
          final rawScore = historyScores[genre]!;
          final cappedScore = math.min(rawScore, maxHistoryBonus);
          weight += cappedScore;
        }
        if (weight > 0) {
          weights[genre] = weight;
        }
      }

      // 4. Sample weighted genres using cumulative weights
      final List<String> selectedGenres = [];
      final random = randomGenerator ?? math.Random();

      // If user has preferences or history, sample weighted genres
      if (weights.isNotEmpty) {
        final weightedCandidates = Map<String, double>.from(weights);
        while (selectedGenres.length < weightedCount && weightedCandidates.isNotEmpty) {
          final totalWeight = weightedCandidates.values.fold(0.0, (a, b) => a + b);
          if (totalWeight <= 0) break;
          final roll = random.nextDouble() * totalWeight;
          double cumulative = 0.0;
          String? chosen;
          for (final entry in weightedCandidates.entries) {
            cumulative += entry.value;
            if (roll < cumulative) {
              chosen = entry.key;
              break;
            }
          }
          chosen ??= weightedCandidates.keys.last;
          selectedGenres.add(chosen);
          weightedCandidates.remove(chosen);
        }
      }

      // 5. Pick random discovery genre(s) from remaining genres
      final remainingForDiscovery = eligibleGenres
          .where((g) => !selectedGenres.contains(g))
          .toList();
      if (remainingForDiscovery.isNotEmpty) {
        remainingForDiscovery.shuffle(random);
        selectedGenres.addAll(remainingForDiscovery.take(discoveryCount));
      }

      // 6. Cold-start fallback: if we don't have target genres yet, fill with random eligible genres
      final targetTotal = weightedCount + discoveryCount;
      if (selectedGenres.length < targetTotal) {
        final pool = eligibleGenres
            .where((g) => !selectedGenres.contains(g))
            .toList();
        pool.shuffle(random);
        int safetyLoop = 0;
        while (selectedGenres.length < targetTotal && pool.isNotEmpty && safetyLoop < 100) {
          safetyLoop++;
          selectedGenres.add(pool.removeLast());
        }
      }

      return selectedGenres;
    } catch (e, st) {
      debugPrint('HomeScreen: error in selectFeedGenres: $e\n$st');
      // Fallback: random genres on any error
      final fallback = List<String>.from(eligibleGenres)..shuffle(math.Random());
      return fallback.take(weightedCount + discoveryCount).toList();
    }
  }

  static List<OnlineSearchResult> get defaultSeedOnlineTracks => _HomeScreenState._defaultSeedOnlineTracks;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _FavoritesScope extends InheritedWidget {
  final Set<String> favoriteKeys;

  const _FavoritesScope({
    required this.favoriteKeys,
    required super.child,
  });

  static bool isFav(
    BuildContext context, {
    Track? localTrack,
    OnlineSearchResult? onlineTrack,
    _HomeFeedItem? feedItem,
  }) {
    final scope = context.dependOnInheritedWidgetOfExactType<_FavoritesScope>();
    final keys = scope?.favoriteKeys ?? const {};
    if (localTrack != null) {
      if (localTrack.isFavorite) return true;
      if (localTrack.id != null && keys.contains('id_${localTrack.id}')) return true;
      if (localTrack.filePath != null && keys.contains('path_${localTrack.filePath}')) return true;
      if (localTrack.onlineId != null && keys.contains('online_${localTrack.onlineId}')) return true;
    }
    if (onlineTrack != null) {
      if (keys.contains('online_${onlineTrack.id}')) return true;
    }
    if (feedItem != null) {
      if (feedItem.isOnline && feedItem.onlineTrack != null) {
        return keys.contains('online_${feedItem.onlineTrack!.id}');
      } else if (!feedItem.isOnline && feedItem.localTrack != null) {
        return isFav(context, localTrack: feedItem.localTrack);
      }
    }
    return false;
  }

  @override
  bool updateShouldNotify(_FavoritesScope oldWidget) =>
      favoriteKeys != oldWidget.favoriteKeys;
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _wasBackgrounded = false;
  int _selectedTabIndex = 0; // 0 = For You, 1 = Offline, 2 = Online
  String _selectedCategory = AppStrings.allCategory;
  List<String> _dynamicCategories = [AppStrings.allCategory];
  final Map<String, List<Track>> _groupedCollections = {};

  List<Track>? _localTracks;
  bool _isLoading = false;
  bool _isFirstRunScanning = false;
  bool _isScannerActive = false;
  ScanProgress _scanProgress = const ScanProgress();
  StreamSubscription<ScanProgress>? _scanProgressSub;
  Set<String> _favoriteTrackKeys = {};
  bool _hasPermission = true;

  List<Track> _filteredTracks = [];
  List<Track> _displayRail = [];

  static const List<OnlineSearchResult> _defaultSeedOnlineTracks = [
    OnlineSearchResult(
      id: '5Eqb_-j3FDA',
      title: 'Pasoori',
      artist: 'Ali Sethi x Shae Gill (Coke Studio)',
      thumbnailUrl: 'https://i.ytimg.com/vi/5Eqb_-j3FDA/hqdefault.jpg',
      duration: '3:44',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'kw4tT7SCmaY',
      title: 'Afreen Afreen',
      artist: 'Rahat Fateh Ali Khan x Momina Mustehsan',
      thumbnailUrl: 'https://i.ytimg.com/vi/kw4tT7SCmaY/hqdefault.jpg',
      duration: '6:45',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'BddP6PYo2gs',
      title: 'Kesariya',
      artist: 'Arijit Singh (Brahmāstra)',
      thumbnailUrl: 'https://i.ytimg.com/vi/BddP6PYo2gs/hqdefault.jpg',
      duration: '4:28',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: '7D4vNcK6D38',
      title: 'Tu Jhoom',
      artist: 'Abida Parveen x Naseebo Lal (Coke Studio)',
      thumbnailUrl: 'https://i.ytimg.com/vi/7D4vNcK6D38/hqdefault.jpg',
      duration: '6:36',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'a18py61EcP4',
      title: 'Tajdar-e-Haram',
      artist: 'Atif Aslam (Coke Studio)',
      thumbnailUrl: 'https://i.ytimg.com/vi/a18py61EcP4/hqdefault.jpg',
      duration: '10:28',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'ElZfdU54Cp8',
      title: 'Apna Bana Le',
      artist: 'Arijit Singh (Bhediya)',
      thumbnailUrl: 'https://i.ytimg.com/vi/ElZfdU54Cp8/hqdefault.jpg',
      duration: '4:21',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'zQ3PeDGswz4',
      title: 'Kana Yaari',
      artist: 'Kaifi Khalil x Eva B x Abdul Wahab Bugti',
      thumbnailUrl: 'https://i.ytimg.com/vi/zQ3PeDGswz4/hqdefault.jpg',
      duration: '3:35',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'GvXYBvst16A',
      title: 'Kahani Suno 2.0',
      artist: 'Kaifi Khalil',
      thumbnailUrl: 'https://i.ytimg.com/vi/GvXYBvst16A/hqdefault.jpg',
      duration: '2:53',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'gvyUuxdRdR4',
      title: 'Raataan Lambiyan',
      artist: 'Jubin Nautiyal & Asees Kaur',
      thumbnailUrl: 'https://i.ytimg.com/vi/gvyUuxdRdR4/hqdefault.jpg',
      duration: '3:50',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'IJq0yyWug1k',
      title: 'Tum Hi Ho',
      artist: 'Arijit Singh (Aashiqui 2)',
      thumbnailUrl: 'https://i.ytimg.com/vi/IJq0yyWug1k/hqdefault.jpg',
      duration: '4:22',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'SAcpESN_GO8',
      title: 'Dil Diyan Gallan',
      artist: 'Atif Aslam (Tiger Zinda Hai)',
      thumbnailUrl: 'https://i.ytimg.com/vi/SAcpESN_GO8/hqdefault.jpg',
      duration: '4:20',
      source: 'YouTube',
    ),
    OnlineSearchResult(
      id: 'VAdGW7QDJUI',
      title: 'Chaleya',
      artist: 'Arijit Singh & Shilpa Rao (Jawan)',
      thumbnailUrl: 'https://i.ytimg.com/vi/VAdGW7QDJUI/hqdefault.jpg',
      duration: '3:20',
      source: 'YouTube',
    ),
  ];

  List<OnlineSearchResult> _onlineFeedPool = List.from(_defaultSeedOnlineTracks);
  List<OnlineSearchResult> _featuredOnlinePool = [];
  List<OnlineSearchResult> _popularOnlinePool = [];
  List<OnlineSearchResult> _yourMusicOnlinePool = [];
  final YoutubeService _youtubeService = YoutubeService();

  // Online Tab dedicated state
  List<OnlineSearchResult> _topTracks = [];
  bool _isTopTracksLoading = false;
  dynamic _topTracksError;

  List<_OnlineMix> _mixes = [];
  bool _isMixesLoading = false;
  dynamic _mixesError;

  List<OnlineSearchResult> _singles = [];
  bool _isSinglesLoading = false;
  bool _isSinglesLoadingMore = false;
  dynamic _singlesError;
  String _selectedSinglesGenre = 'All';
  int _singlesPage = 0;
  bool _isShuffling = false;

  // ignore: unused_field
  final CollectionSort _collectionSort = CollectionSort.alphabetical;
  RecommendationBatch _recommendations = const RecommendationBatch();
  List<Track> _recentlyPlayed = [];
  List<String> _userPreferredGenres = [];

  List<Track> get _activeTracks => _localTracks ?? widget.tracks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserPreferredGenres();
    _loadFavoriteKeys();

    // Connect scanner stream so scanner is visible on For You instead of hidden in background
    _isScannerActive = AudioScannerService.instance.isScanning;
    _scanProgressSub =
        AudioScannerService.instance.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _scanProgress = progress;
        _isScannerActive = progress.isScanning;
      });
      if (!progress.isScanning) {
        _onRepositoryUpdated();
      }
    });

    _checkFirstRunAndScan();
    _processDeviceData();
    _loadRecommendations();
    _loadRecentlyPlayed();
    AudioRepository.instance.addListener(_onRepositoryUpdated);
    NotificationService.instance
        .add('System Ready', 'Neural mapping sequence complete.', type: 'system');
    _loadOnlineFeedPool();
    _loadTopTracks();
    _loadMixes();
    _loadSingles();
  }

  Future<void> _loadFavoriteKeys() async {
    try {
      final favs = await AudioRepository.instance.getFavorites();
      final prefs = await SharedPreferences.getInstance();
      final onlineFavs = prefs.getStringList('online_favorites') ?? [];
      final Set<String> keys = {};
      for (final t in favs) {
        if (t.id != null) keys.add('id_${t.id}');
        if (t.filePath != null) keys.add('path_${t.filePath}');
        if (t.onlineId != null) keys.add('online_${t.onlineId}');
      }
      for (final id in onlineFavs) {
        keys.add('online_$id');
      }
      if (mounted) {
        setState(() => _favoriteTrackKeys = keys);
      }
    } catch (_) {}
  }

  static const String _prefKeyLastOnlineFeedRefresh = 'last_online_feed_refresh';
  static const int _onlineFeedRefreshThresholdMs = 16200000; // 4.5 hours in ms

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _refreshOnlineContentOnResume();
    }
  }

  Future<void> _refreshOnlineContentOnResume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRefresh = prefs.getInt(_prefKeyLastOnlineFeedRefresh) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastRefresh;

      if (elapsed >= _onlineFeedRefreshThresholdMs) {
        debugPrint(
            'HomeScreen: App resumed and last refresh was ${(elapsed / 3600000).toStringAsFixed(1)}h ago (>= 4.5h) - refreshing online feeds and tabs');
        _loadOnlineFeedPool();
        _loadTopTracks();
        _loadMixes();
        _loadSingles(refresh: true);
      } else {
        debugPrint(
            'HomeScreen: App resumed but last refresh was only ${(elapsed / 60000).toStringAsFixed(1)}m ago (< 4.5h) - skipping automatic refresh');
      }
    } catch (e) {
      debugPrint('HomeScreen: Error checking refresh timestamp on resume: $e');
    }
  }

  void _loadUserPreferredGenres() {
    final genres = UserPreferencesService.instance.getPreferredGenres();
    if (mounted) {
      setState(() {
        _userPreferredGenres = genres;
      });
    } else {
      _userPreferredGenres = genres;
    }
  }

  void _onRepositoryUpdated() {
    _loadRecommendations();
    _loadRecentlyPlayed();
    _loadFavoriteKeys();
    AudioRepository.instance.getMusicOnlyTracks().then((tracks) {
      if (!mounted) return;
      setState(() {
        _localTracks = tracks;
        _processDeviceData();
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _scanProgressSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AudioRepository.instance.removeListener(_onRepositoryUpdated);
    _youtubeService.dispose();
    super.dispose();
  }

  Future<List<String>> _selectFeedGenres({
    int weightedCount = 2,
    int discoveryCount = 1,
  }) =>
      HomeScreen.selectFeedGenres(
        weightedCount: weightedCount,
        discoveryCount: discoveryCount,
      );

  Future<void> _loadOnlineFeedPool() async {
    try {
      final preferred = UserPreferencesService.instance.getPreferredGenres();

      // 1. Featured Pool: User's selected genres from onboarding / preferences
      final List<String> featuredGenres = preferred.isNotEmpty
          ? preferred
          : (await _selectFeedGenres(weightedCount: 3, discoveryCount: 1));

      final List<OnlineSearchResult> featuredCombined = [];
      for (final genre in featuredGenres.take(3)) {
        try {
          final results = await _youtubeService
              .searchVideos(
                '${YoutubeService.queryForGenre(genre)} featured hits',
                targetGenre: genre,
              )
              .timeout(const Duration(seconds: 8), onTimeout: () => []);
          featuredCombined.addAll(results);
        } catch (e) {
          debugPrint('HomeScreen: Featured search error for "$genre": $e');
        }
      }
      featuredCombined.shuffle();

      // 2. Popular Songs Pool: Trending and latest Pakistani & Indian songs
      final List<OnlineSearchResult> popularCombined = [];
      try {
        final trendingRes = await _youtubeService
            .searchVideos(
              'trending Pakistani and Indian hit songs latest',
              targetGenre: 'Trending',
            )
            .timeout(const Duration(seconds: 8), onTimeout: () => []);
        popularCombined.addAll(trendingRes);

        final latestRes = await _youtubeService
            .searchVideos(
              'latest Bollywood Pakistani viral hit songs',
              targetGenre: 'Trending',
            )
            .timeout(const Duration(seconds: 8), onTimeout: () => []);
        popularCombined.addAll(latestRes);
      } catch (e) {
        debugPrint('HomeScreen: Popular search error: $e');
      }
      popularCombined.shuffle();

      // 3. Your Music Pool: Top searches across genres
      final List<OnlineSearchResult> yourMusicCombined = [];
      final Set<String> topGenres = {
        ...preferred,
        'Coke Studio',
        'Bollywood',
        'Qawali',
        'Sufi',
        'Punjabi',
        'Indie',
      };
      for (final genre in topGenres.take(4)) {
        try {
          final results = await _youtubeService
              .searchVideos(
                YoutubeService.queryForGenre(genre),
                targetGenre: genre,
              )
              .timeout(const Duration(seconds: 8), onTimeout: () => []);
          yourMusicCombined.addAll(results);
        } catch (e) {
          debugPrint('HomeScreen: Your Music search error for "$genre": $e');
        }
      }
      yourMusicCombined.shuffle();

      final fullPool = [
        ...featuredCombined,
        ...popularCombined,
        ...yourMusicCombined,
      ];
      fullPool.shuffle();

      if (mounted) {
        setState(() {
          _featuredOnlinePool = featuredCombined.take(30).toList();
          _popularOnlinePool = popularCombined.take(30).toList();
          _yourMusicOnlinePool = yourMusicCombined.take(40).toList();
          _onlineFeedPool = fullPool.take(60).toList();
        });
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefKeyLastOnlineFeedRefresh, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
    } catch (e, st) {
      debugPrint('HomeScreen: _loadOnlineFeedPool error: $e\n$st');
      // Graceful silent degradation on network / YouTube error
    }
  }

  Future<void> _recordOnlinePlayHistory(OnlineSearchResult track, {String? genre}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('online_play_history');
      List<Map<String, dynamic>> history = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          history = decoded
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
      final entry = {
        'id': track.id,
        'thumbnailUrl': track.thumbnailUrl,
        'title': track.title,
        'artist': track.artist,
        'genre': genre ?? 'Online',
        'timestamp': DateTime.now().toIso8601String(),
      };
      history.insert(0, entry);
      if (history.length > 200) {
        history = history.sublist(0, 200);
      }
      await prefs.setString('online_play_history', jsonEncode(history));
    } catch (e) {
      debugPrint('HomeScreen: Error saving online play history: $e');
    }
  }

  Future<void> _loadTopTracks() async {
    if (!mounted) return;
    setState(() {
      _isTopTracksLoading = true;
      _topTracksError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('online_play_history');
      if (raw == null || raw.isEmpty) {
        if (mounted) {
          setState(() {
            _topTracks = [];
            _isTopTracksLoading = false;
          });
        }
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) {
        if (mounted) {
          setState(() {
            _topTracks = [];
            _isTopTracksLoading = false;
          });
        }
        return;
      }

      final Map<String, int> counts = {};
      final Map<String, Map<String, dynamic>> latestInfo = {};

      for (final item in decoded) {
        if (item is Map) {
          final title = (item['title'] as String?) ?? '';
          final artist = (item['artist'] as String?) ?? '';
          if (title.isEmpty) continue;
          final key = '${title.toLowerCase()}___${artist.toLowerCase()}';
          counts[key] = (counts[key] ?? 0) + 1;
          latestInfo.putIfAbsent(key, () => Map<String, dynamic>.from(item));
        }
      }

      final sortedKeys = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

      final userPreferred = UserPreferencesService.instance.getPreferredGenres();
      final bool isDevotionalPreferred = userPreferred.any((g) => g.toLowerCase() == 'devotional');

      final List<OnlineSearchResult> top = [];
      for (final key in sortedKeys.take(30)) {
        final info = latestInfo[key]!;
        final title = (info['title'] as String?) ?? 'Unknown';
        if (!isDevotionalPreferred && YoutubeService.hasNegativeKeywords(title)) {
          continue;
        }
        final id = (info['id'] as String?) ?? '';
        final artist = (info['artist'] as String?) ?? 'Unknown';
        final thumb = info['thumbnailUrl'] as String?;
        top.add(
          OnlineSearchResult(
            id: id.isNotEmpty ? id : key,
            title: title,
            artist: artist,
            thumbnailUrl: thumb,
            duration: null,
            source: (info['source'] as String?) ?? 'youtube',
          ),
        );
        if (top.length >= 15) break;
      }

      if (mounted) {
        setState(() {
          _topTracks = top;
          _isTopTracksLoading = false;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Error loading top tracks: $e');
      if (mounted) {
        setState(() {
          _topTracksError = e;
          _isTopTracksLoading = false;
        });
      }
    }
  }

  Future<void> _loadMixes() async {
    if (!mounted) return;
    setState(() {
      _isMixesLoading = true;
      _mixesError = null;
    });
    try {
      final List<String> chosenGenres = await _selectFeedGenres(
        weightedCount: 4,
        discoveryCount: 2,
      );
      debugPrint('DEBUG: [HomeScreen] _loadMixes selected genres: $chosenGenres');

      final mixFutures = chosenGenres.map((genre) async {
        try {
          final results = await _youtubeService
              .searchVideos(YoutubeService.queryForGenre(genre), targetGenre: genre)
              .timeout(const Duration(seconds: 10), onTimeout: () => []);

          final filteredTracks = results.where((track) {
            final dur = track.duration?.trim() ?? '';
            // If duration contains hours (e.g. 1:23:45)
            if (dur.split(':').length > 2) return false;
            if (dur.contains(':')) {
              final mins = int.tryParse(dur.split(':')[0]) ?? 0;
              if (mins > 10) return false;
            }
            final titleLower = track.title.toLowerCase();
            if (titleLower.contains('1 hour') ||
                titleLower.contains('2 hour') ||
                titleLower.contains('3 hour') ||
                titleLower.contains('hours') ||
                titleLower.contains('full album') ||
                titleLower.contains('megamix') ||
                titleLower.contains('compilation') ||
                titleLower.contains('non stop') ||
                titleLower.contains('nonstop') ||
                titleLower.contains('jukebox') ||
                titleLower.contains('24/7') ||
                titleLower.contains('dj mix')) {
              return false;
            }
            return true;
          }).take(12).toList();

          if (filteredTracks.isNotEmpty) {
            return _OnlineMix(
              genre: genre,
              title: '$genre Mix',
              tracks: filteredTracks,
            );
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(mixFutures);
      final List<_OnlineMix> loaded = results.whereType<_OnlineMix>().toList();

      if (mounted) {
        setState(() {
          _mixes = loaded;
          _isMixesLoading = false;
        });
        if (loaded.isNotEmpty) {
          NotificationService.instance.addRecommendation(
            'Mixes Ready',
            'Fresh mixes for ${chosenGenres.take(3).join(", ")} are ready.',
            type: 'online',
          );
        }
      }
    } catch (e) {
      debugPrint('HomeScreen: Error loading mixes: $e');
      if (mounted) {
        setState(() {
          _mixesError = e;
          _isMixesLoading = false;
        });
        NotificationService.instance.addError(
          'Mixes Offline',
          'Could not fetch curated mixes. Tap to retry.',
        );
      }
    }
  }

  Future<void> _loadSingles({bool refresh = false}) async {
    if (!mounted) return;
    if (refresh) {
      setState(() {
        _singlesPage = 0;
        _singles.clear();
        _singlesError = null;
        _isSinglesLoading = true;
      });
    } else {
      setState(() {
        _isSinglesLoading = true;
        _singlesError = null;
      });
    }

    try {
      final preferred = UserPreferencesService.instance.getPreferredGenres();
      final String query;
      if (_selectedSinglesGenre == 'All') {
        if (preferred.isNotEmpty) {
          query = '${preferred.take(3).join(" ")} hits songs';
        } else {
          query = 'trending music hits songs';
        }
      } else {
        query = YoutubeService.queryForGenre(_selectedSinglesGenre);
      }

      final results = await _youtubeService
          .searchVideos(query, targetGenre: _selectedSinglesGenre)
          .timeout(const Duration(seconds: 9), onTimeout: () => []);

      if (mounted) {
        setState(() {
          _singles = results;
          _isSinglesLoading = false;
          _singlesPage = 1;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Error loading singles: $e');
      if (mounted) {
        setState(() {
          _singlesError = e;
          _isSinglesLoading = false;
        });
        NotificationService.instance.addError(
          'Singles Offline',
          'Could not load fresh tracks. Please try again.',
        );
      }
    }
  }

  Future<void> _loadMoreSingles() async {
    if (_isSinglesLoadingMore || _isSinglesLoading || _singles.isEmpty) return;
    setState(() => _isSinglesLoadingMore = true);
    try {
      final page = _singlesPage + 1;
      final base = _selectedSinglesGenre == 'All'
          ? 'trending hits songs'
          : YoutubeService.queryForGenre(_selectedSinglesGenre);
      final query = '$base page $page';

      final more = await _youtubeService
          .searchVideos(query, targetGenre: _selectedSinglesGenre)
          .timeout(const Duration(seconds: 8), onTimeout: () => []);

      if (mounted) {
        final existingIds = _singles.map((s) => s.id).toSet();
        final filtered = more.where((s) => !existingIds.contains(s.id)).toList();
        setState(() {
          _singles.addAll(filtered);
          _singlesPage = page;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSinglesLoadingMore = false);
    }
  }

  Future<void> _handleShuffleAll() async {
    if (_isShuffling) return;
    setState(() => _isShuffling = true);
    try {
      final pool = List<OnlineSearchResult>.from(_onlineFeedPool);
      for (final m in _mixes) {
        pool.addAll(m.tracks);
      }
      pool.addAll(_singles);

      final uniqueMap = <String, OnlineSearchResult>{};
      for (final t in pool) {
        if (t.id.isNotEmpty) uniqueMap[t.id] = t;
      }
      List<OnlineSearchResult> candidates = uniqueMap.values.toList();

      if (candidates.length < 15) {
        try {
          final genres = await _selectFeedGenres();
          final g = genres.isNotEmpty ? genres.first : 'trending';
          final extra = await _youtubeService
              .searchVideos(YoutubeService.queryForGenre(g), targetGenre: g)
              .timeout(const Duration(seconds: 6), onTimeout: () => []);
          for (final t in extra) {
            if (t.id.isNotEmpty) uniqueMap[t.id] = t;
          }
          candidates = uniqueMap.values.toList();
        } catch (_) {}
      }

      if (candidates.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No online tracks available to shuffle.')),
          );
        }
        return;
      }

      candidates.shuffle();
      final first = candidates.first;
      final remaining = candidates.skip(1).take(14).toList();

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final onlineAccent = OnlineTheme.accent(isDark);
        await OnlinePlaybackHelper.playOnlineTrack(
          context,
          first,
          _youtubeService,
          widget.onPlaySelected,
          onlineAccent,
        );
        _recordOnlinePlayHistory(first);

        // Queue continuation in the background
        Future.microtask(() async {
          for (final item in remaining) {
            try {
              final streamUrl = await _youtubeService.getAudioStreamUrl(item.id);
              if (streamUrl != null && streamUrl.isNotEmpty) {
                await AudioPlayerService.instance.addToQueue(
                  Track(
                    filePath: streamUrl,
                    title: item.title,
                    artist: item.artist,
                    album: item.album,
                    artUrl: item.thumbnailUrl ?? '',
                    isMusic: true,
                    isResolving: false,
                  ),
                );
              }
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Error in _handleShuffleAll: $e');
    } finally {
      if (mounted) setState(() => _isShuffling = false);
    }
  }

  void _playMix(_OnlineMix mix) {
    if (mix.tracks.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onlineAccent = OnlineTheme.accent(isDark);
    final first = mix.tracks.first;
    final remaining = mix.tracks.skip(1).toList();

    OnlinePlaybackHelper.playOnlineTrack(
      context,
      first,
      _youtubeService,
      widget.onPlaySelected,
      onlineAccent,
    );
    _recordOnlinePlayHistory(first, genre: mix.genre);

    // Queue continuation
    Future.microtask(() async {
      for (final item in remaining) {
        try {
          final streamUrl = await _youtubeService.getAudioStreamUrl(item.id);
          if (streamUrl != null && streamUrl.isNotEmpty) {
            await AudioPlayerService.instance.addToQueue(
              Track(
                filePath: streamUrl,
                title: item.title,
                artist: item.artist,
                album: item.album,
                artUrl: item.thumbnailUrl ?? '',
                isMusic: true,
                isResolving: false,
              ),
            );
          }
        } catch (_) {}
      }
    });
  }

  void _loadOnlineTabIfNeeded() {
    if (_mixes.isEmpty && !_isMixesLoading) {
      _loadMixes();
    }
    if (_singles.isEmpty && !_isSinglesLoading) {
      _loadSingles();
    }
    if (_topTracks.isEmpty && !_isTopTracksLoading) {
      _loadTopTracks();
    }
  }

  Future<void> _loadRecommendations() async {
    try {
      final recs =
          await LocalRecommendationService.instance.generateRecommendations();
      if (mounted) {
        setState(() => _recommendations = recs);
        if (recs.heavyRotation.isNotEmpty) {
          final top = recs.heavyRotation.first;
          NotificationService.instance.addRecommendation(
            'Offline Discovery',
            'Rediscover "${top.title}" from your personal library.',
            type: 'offline',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRecentlyPlayed() async {
    try {
      final recents = await AudioRepository.instance.getRecentlyPlayed(limit: 15);
      if (mounted) setState(() => _recentlyPlayed = recents);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks != widget.tracks && _localTracks == null) {
      setState(_processDeviceData);
    }
  }

  Future<void> _checkFirstRunAndScan() async {
    try {
      final scanner = AudioScannerService.instance;
      final prefs = await SharedPreferences.getInstance();

      // Check if permissions are already granted
      final bool hasPerm = await scanner.checkPermissions();

      // Check existing tracks in local repository
      final existingTracks = await AudioRepository.instance.getMusicOnlyTracks();

      if (existingTracks.isNotEmpty && hasPerm) {
        // We already have permissions and local tracks populated in repository
        if (mounted) {
          setState(() {
            _hasPermission = true;
            _localTracks = existingTracks;
            _processDeviceData();
          });
        }
        return;
      }

      // On first app start, or any start where local tracks are empty or permission not yet granted:
      // Automatically request permissions and scan device library with skeleton loading
      await _autoFirstRunScan(prefs);
    } catch (e, st) {
      debugPrint('HomeScreen: Error checking first run scan: $e\n$st');
      await _checkInitialPermission();
    }
  }

  Future<void> _autoFirstRunScan(SharedPreferences prefs) async {
    if (!mounted) return;
    setState(() => _isFirstRunScanning = true);
    try {
      final scanner = AudioScannerService.instance;
      final perm = await scanner.requestPermissions();
      List<Track> tracks = [];
      if (perm) {
        await scanner.scan(isRescan: false);
        tracks = await AudioRepository.instance.getMusicOnlyTracks();
        await prefs.setBool('has_scanned_library', true);
      }
      if (!mounted) return;
      setState(() {
        _hasPermission = perm;
        _localTracks = tracks;
        _processDeviceData();
      });
    } catch (e, st) {
      debugPrint('HomeScreen: Error during _autoFirstRunScan: $e\n$st');
    } finally {
      if (mounted) setState(() => _isFirstRunScanning = false);
    }
  }

  Future<void> _checkInitialPermission() async {
    final scanner = AudioScannerService.instance;
    final perm = await scanner.checkPermissions();
    if (mounted) setState(() => _hasPermission = perm);
  }

  Future<void> _handlePullToRefresh() async {
    final localScanFuture = _rescanLibrary();
    final onlinePoolFuture = _loadOnlineFeedPool();
    if (_selectedTabIndex == 2) {
      await Future.wait([
        localScanFuture,
        onlinePoolFuture,
        _loadTopTracks(),
        _loadMixes(),
        _loadSingles(refresh: true),
      ]);
    } else {
      await Future.wait([
        localScanFuture,
        onlinePoolFuture,
      ]);
    }
  }

  Future<void> _rescanLibrary() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final scanner = AudioScannerService.instance;
      final perm = await scanner.requestPermissions();
      List<Track> tracks = [];
      if (perm) {
        await scanner.scan(isRescan: true);
        tracks = await AudioRepository.instance.getMusicOnlyTracks();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_scanned_library', true);
      }
      if (!mounted) return;
      setState(() {
        _hasPermission = perm;
        _localTracks = tracks;
        _processDeviceData();
      });
    } catch (e, st) {
      debugPrint('HomeScreen: Error during _rescanLibrary: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to complete library scan. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processDeviceData() {
    final tracks = _activeTracks;
    _groupedCollections.clear();

    final List<Track> shortAudio = [];
    final List<Track> generalMix = [];
    final List<Track> recordings = [];
    final Map<String, List<Track>> filteredFolders = {};

    for (var track in tracks) {
      int digitCount =
          track.title.replaceAll(RegExp(r'[^0-9]'), '').length;
      if (digitCount >= 5) {
        recordings.add(track);
        continue;
      }

      String folderPath = track.folderPath != null && track.folderPath!.isNotEmpty
          ? track.folderPath!
          : 'Unknown';
      String folderName = folderPath
          .split('/')
          .lastWhere((part) => part.isNotEmpty, orElse: () => 'Unknown');

      if (track.duration != null && track.duration! < 120000) {
        shortAudio.add(track);
      } else if (track.duration != null && track.duration! >= 180000) {
        bool hasGoodMetadata =
            (track.album != null &&
                    track.album!.isNotEmpty &&
                    track.album != 'Unknown Album') ||
                (track.folderPath != null &&
                    track.folderPath!.isNotEmpty &&
                    track.folderPath != 'Unknown');
        if (!hasGoodMetadata) {
          generalMix.add(track);
        } else {
          filteredFolders.putIfAbsent(folderName, () => []).add(track);
        }
      } else {
        filteredFolders.putIfAbsent(folderName, () => []).add(track);
      }
    }

    _groupedCollections.addAll(filteredFolders);
    if (generalMix.isNotEmpty) _groupedCollections['General Mix'] = generalMix;
    if (shortAudio.isNotEmpty) _groupedCollections['Short Audio'] = shortAudio;
    if (recordings.isNotEmpty) _groupedCollections['Recordings'] = recordings;

    _dynamicCategories = [AppStrings.allCategory];
    if (_groupedCollections.containsKey('General Mix')) {
      _dynamicCategories.add('General Mix');
    }
    if (_groupedCollections.containsKey('Short Audio')) {
      _dynamicCategories.add('Short Audio');
    }
    if (_groupedCollections.containsKey('Recordings')) {
      _dynamicCategories.add('Recordings');
    }

    final otherCategories =
        TrackCollectionHelper.topCategories(_groupedCollections)
          ..remove('General Mix')
          ..remove('Short Audio')
          ..remove('Recordings')
          ..remove(AppStrings.allCategory);

    _dynamicCategories.addAll(otherCategories);

    if (!_dynamicCategories.contains(_selectedCategory)) {
      _selectedCategory = AppStrings.allCategory;
    }

    _updateCategoryData();
  }

  void _updateCategoryData() {
    if (_selectedCategory == AppStrings.allCategory) {
      _filteredTracks = _activeTracks
          .where((t) =>
              t.title.replaceAll(RegExp(r'[^0-9]'), '').length < 5)
          .toList();
    } else {
      _filteredTracks = _groupedCollections[_selectedCategory] ?? [];
    }

    _displayRail =
        TrackCollectionHelper.intelligentRail(_filteredTracks).where((track) {
      bool hasGoodAlbum = track.album != null &&
          track.album!.isNotEmpty &&
          track.album != 'Unknown Album';
      bool hasGoodArtist = track.artist.isNotEmpty &&
          track.artist != 'Unknown Artist';
      return hasGoodAlbum || hasGoodArtist;
    }).toList();

    if (_displayRail.isEmpty && _filteredTracks.isNotEmpty) {
      _displayRail = _filteredTracks.take(10).toList();
    }
  }

  void _setCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _updateCategoryData();
    });
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTabAccent = _selectedTabIndex == 2
        ? OnlineTheme.accent(isDark)
        : widget.accentColor;

    return _FavoritesScope(
      favoriteKeys: _favoriteTrackKeys,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: (_selectedTabIndex == 0 && isDark)
                ? _HomeColors.forYouDarkGradient()
                : _HomeColors.pageGradient(isDark, currentTabAccent),
            stops: (_selectedTabIndex == 0 && isDark)
                ? const [0.0, 0.38, 0.72, 1.0]
                : null,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: SafeArea(
            top: true,
            bottom: false,
            child: RefreshIndicator(
              color: widget.accentColor,
              backgroundColor: isDark
                  ? const Color(0xFF161B27)
                  : Colors.white,
              onRefresh: _handlePullToRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _HomeHeader(
                          accentColor: widget.accentColor,
                          onSearchTap: () => _openSearch(context),
                        ),
                        const SizedBox(height: 16),
                        _ScanProgressBanner(accentColor: widget.accentColor),
                        _buildBody(isDark),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openSearch(BuildContext context) {
    HapticFeedback.lightImpact();
    widget.onNavigateToSearch();
  }

  Widget _buildBody(bool isDark) {
    if (_isScannerActive || _isFirstRunScanning || (_isLoading && _activeTracks.isEmpty)) {
      return _HomeScanningVisualizer(
        accentColor: widget.accentColor,
        isDark: isDark,
        progress: _scanProgress,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeTabBar(
          selectedIndex: _selectedTabIndex,
          accentColor: widget.accentColor,
          isDark: isDark,
          showOfflineTab: true,
          onTabChanged: (index) {
            if (_selectedTabIndex == index) return;
            HapticFeedback.selectionClick();
            setState(() => _selectedTabIndex = index);
            if (index == 2) {
              _loadOnlineTabIfNeeded();
            }
          },
        ),
        const SizedBox(height: 20),
        _buildTabContent(isDark),
      ],
    );
  }

  Widget _buildTabContent(bool isDark) {
    if (_selectedTabIndex == 2) {
      final singlesPills = [
        'All',
        ...(_userPreferredGenres.isNotEmpty
            ? _userPreferredGenres
            : kBrowseGenres.where((g) => g != 'All' && g != 'Trending')),
      ];

      // Dedicated Online tab: accessible even if local library is empty
      return _OnlineView(
        isDark: isDark,
        accentColor: widget.accentColor,
        youtubeService: _youtubeService,
        onPlaySelected: widget.onPlaySelected,
        isShuffling: _isShuffling,
        onShuffleAll: _handleShuffleAll,
        topTracks: _topTracks,
        isTopTracksLoading: _isTopTracksLoading,
        topTracksError: _topTracksError,
        onRetryTopTracks: _loadTopTracks,
        mixes: _mixes,
        isMixesLoading: _isMixesLoading,
        mixesError: _mixesError,
        onRetryMixes: _loadMixes,
        onPlayMix: _playMix,
        singles: _singles,
        isSinglesLoading: _isSinglesLoading,
        singlesError: _singlesError,
        onRetrySingles: () => _loadSingles(refresh: true),
        availableSinglesGenres: singlesPills,
        selectedSinglesGenre: _selectedSinglesGenre,
        onSelectSinglesGenre: (genre) {
          if (_selectedSinglesGenre == genre) return;
          HapticFeedback.selectionClick();
          setState(() {
            _selectedSinglesGenre = genre;
          });
          _loadSingles(refresh: true);
        },
        onLoadMoreSingles: _loadMoreSingles,
        onTrackPlayed: (t) => _recordOnlinePlayHistory(t, genre: _selectedSinglesGenre),
      );
    }

    if (_selectedTabIndex == 1) {
      if (!_hasPermission) {
        return _EmptyStateCard(
          accentColor: widget.accentColor,
          icon: Icons.security_rounded,
          title: 'Permission Required',
          subtitle: 'Storage access is needed to discover your local audio files.',
          buttonText: 'Grant Access',
          onAction: _rescanLibrary,
        );
      }

      if (_activeTracks.isEmpty) {
        return _EmptyStateCard(
          accentColor: widget.accentColor,
          icon: Icons.audio_file_outlined,
          title: 'Offline Library Empty',
          subtitle: 'No audio files detected on your device storage. Add music files or rescan storage.',
          buttonText: 'Rescan Storage',
          onAction: _rescanLibrary,
        );
      }

      return _OfflineView(
        accentColor: widget.accentColor,
        activeTracks: _activeTracks,
        filteredTracks: _filteredTracks,
        displayRail: _displayRail,
        groupedCollections: _groupedCollections,
        recommendations: _recommendations,
        recentlyPlayed: _recentlyPlayed,
        onPlaySelected: widget.onPlaySelected,
        onNavigateToLibrary: widget.onNavigateToLibrary,
        onRescan: _rescanLibrary,
        onSwitchToOffline: () {
          setState(() => _selectedTabIndex = 1);
        },
        onSwitchToOnline: () {
          setState(() => _selectedTabIndex = 2);
          _loadOnlineTabIfNeeded();
        },
      );
    }

    // Default tab: _selectedTabIndex == 0 ("For You")
    // Renders mixed content when local tracks exist, or pure online content when device has 0 local tracks.
    return _HomeBody(
      accentColor: widget.accentColor,
      activeTracks: _activeTracks,
      filteredTracks: _filteredTracks,
      displayRail: _displayRail,
      groupedCollections: _groupedCollections,
      dynamicCategories: _dynamicCategories,
      selectedCategory: _selectedCategory,
      recommendations: _recommendations,
      recentlyPlayed: _recentlyPlayed,
      onlineFeedPool: _onlineFeedPool,
      featuredOnlinePool: _featuredOnlinePool,
      popularOnlinePool: _popularOnlinePool,
      yourMusicOnlinePool: _yourMusicOnlinePool,
      youtubeService: _youtubeService,
      onPlaySelected: widget.onPlaySelected,
      onNavigateToLibrary: widget.onNavigateToLibrary,
      onNavigateToSearch: widget.onNavigateToSearch,
      onSetCategory: _setCategory,
      onRescan: _rescanLibrary,
      onSwitchToOffline: () {
        setState(() => _selectedTabIndex = 1);
      },
      onSwitchToOnline: () {
        setState(() => _selectedTabIndex = 2);
        _loadOnlineTabIfNeeded();
      },
    );
  }
}

// ─────────────────────────── Scanning Visualizer & Feed Preparation ───────────────────────────

class _HomeScanningVisualizer extends StatefulWidget {
  final Color accentColor;
  final bool isDark;
  final ScanProgress? progress;

  const _HomeScanningVisualizer({
    required this.accentColor,
    required this.isDark,
    this.progress,
  });

  @override
  State<_HomeScanningVisualizer> createState() => _HomeScanningVisualizerState();
}

class _HomeScanningVisualizerState extends State<_HomeScanningVisualizer>
    with TickerProviderStateMixin {
  late final AnimationController _waveController;
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  Timer? _tipTimer;
  int _tipIndex = 0;

  static const List<String> _scanningTips = [
    '🎧 AI Neural Audio Engine analyzing local directories...',
    '✨ Deep spectrum analysis separating music from voice notes...',
    '🎵 Curating Pakistani, Indian, Sufi & Bollywood soundscapes...',
    '⚡ Pre-generating dynamic waveforms & high-fidelity caching...',
    '🔥 Dual-layer indexing active: offline library & streaming sync...',
    '🚀 Finalizing tailored recommendations for your For You feed...',
  ];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    _tipTimer = Timer.periodic(const Duration(milliseconds: 3200), (t) {
      if (mounted) {
        setState(() {
          _tipIndex = (_tipIndex + 1) % _scanningTips.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    _tipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accentColor = widget.accentColor;
    final prog = widget.progress ?? const ScanProgress();
    final pct = (prog.percentage * 100).toInt().clamp(0, 100);

    return AnimatedBuilder(
      animation: Listenable.merge([_waveController, _pulseController, _rotationController]),
      builder: (context, _) {
        final waveVal = _waveController.value;
        final pulseVal = _pulseController.value;
        final rotVal = _rotationController.value;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main Engaging Visualizer Showcase Card ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF161E33).withValues(alpha: 0.95),
                          const Color(0xFF0F1422).withValues(alpha: 0.95),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.95),
                          const Color(0xFFF1F5F9).withValues(alpha: 0.90),
                        ],
                ),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35 + waveVal * 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.18 + pulseVal * 0.12),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF2E7E).withValues(alpha: 0.10 * waveVal),
                    blurRadius: 30,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Rotating Orb + Title + Percentage
                  Row(
                    children: [
                      // Glowing sound orb with rotating dashes
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer pulse ripple
                          Container(
                            width: 60 + pulseVal * 8,
                            height: 60 + pulseVal * 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor.withValues(alpha: 0.08 * (1 - pulseVal)),
                            ),
                          ),
                          // Rotating border
                          Transform.rotate(
                            angle: rotVal * 2 * math.pi,
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(
                                  colors: [
                                    Color(0xFF3B82F6),
                                    Color(0xFFFF2E7E),
                                    Color(0xFF9933FF),
                                    Color(0xFF3B82F6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Inner disc
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? const Color(0xFF0E1424) : Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                )
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                color: accentColor,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Title & subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Curating Your Sound',
                                  style: TextStyle(
                                    fontFamily: AppTypography.uiFont,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _HomeColors.primaryText(isDark),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: accentColor.withValues(alpha: 0.15),
                                    border: Border.all(
                                      color: accentColor.withValues(alpha: 0.4),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    '$pct%',
                                    style: TextStyle(
                                      fontFamily: AppTypography.uiFont,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: accentColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Indexing audio library & neural discovery...',
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _HomeColors.secondaryText(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Multi-band Equalizer Waveform Spectrum ──
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.35)
                          : const Color(0xFFF8FAFC),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(24, (i) {
                        final phase = (i / 24.0) * math.pi * 2;
                        final h = 10.0 + 28.0 * (0.35 + 0.65 * math.sin(phase + waveVal * math.pi).abs());
                        final Color barColor = i % 3 == 0
                            ? const Color(0xFFFF2E7E)
                            : (i % 2 == 0 ? accentColor : const Color(0xFF9933FF));

                        return Container(
                          width: 4.5,
                          height: h,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                barColor.withValues(alpha: 0.6),
                                barColor,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: barColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                                spreadRadius: -1,
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Glowing Gradient Progress Bar ──
                  Stack(
                    children: [
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: (prog.percentage).clamp(0.04, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(
                              colors: [
                                accentColor,
                                const Color(0xFFFF2E7E),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF2E7E).withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Stats Row: Scanned Count & Categorized Music Count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.folder_copy_rounded,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            prog.scannedCount > 0
                                ? '${prog.scannedCount} audio files scanned'
                                : 'Scanning storage...',
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _HomeColors.primaryText(isDark),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.library_music_rounded,
                            size: 14,
                            color: Color(0xFFFF2E7E),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            prog.classifiedMusicCount > 0
                                ? '${prog.classifiedMusicCount} songs ready'
                                : 'Classifying genres...',
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFFF2E7E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Live file ticker if scanning a file
                  if (prog.currentFilePath.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.radar_rounded,
                            size: 13,
                            color: accentColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Scanning: ${prog.currentFilePath.replaceAll('\\', '/').split('/').last}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 11,
                                color: _HomeColors.secondaryText(isDark),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Rotating AI Music Insight / Quote
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _scanningTips[_tipIndex],
                      key: ValueKey<int>(_tipIndex),
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFFB4C6E7) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Skeleton Previews Below ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Preparing Your Daily Soundscape...',
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _HomeColors.secondaryText(isDark),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.04 + waveVal * 0.04),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.03 + waveVal * 0.03),
                          Colors.black.withValues(alpha: 0.01),
                        ],
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.headphones_rounded,
                  size: 48,
                  color: accentColor.withValues(alpha: 0.2 + waveVal * 0.2),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

// ─────────────────────────── Body ───────────────────────────

class _HomeBody extends StatelessWidget {
  final Color accentColor;
  final List<Track> activeTracks;
  final List<Track> filteredTracks;
  final List<Track> displayRail;
  final Map<String, List<Track>> groupedCollections;
  final List<String> dynamicCategories;
  final String selectedCategory;
  final RecommendationBatch recommendations;
  final List<Track> recentlyPlayed;
  final List<OnlineSearchResult> onlineFeedPool;
  final List<OnlineSearchResult> featuredOnlinePool;
  final List<OnlineSearchResult> popularOnlinePool;
  final List<OnlineSearchResult> yourMusicOnlinePool;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;
  final void Function(String?) onNavigateToLibrary;
  final VoidCallback onNavigateToSearch;
  final Function(String) onSetCategory;
  final VoidCallback onRescan;
  final VoidCallback onSwitchToOffline;
  final VoidCallback onSwitchToOnline;

  const _HomeBody({
    required this.accentColor,
    required this.activeTracks,
    required this.filteredTracks,
    required this.displayRail,
    required this.groupedCollections,
    required this.dynamicCategories,
    required this.selectedCategory,
    required this.recommendations,
    required this.recentlyPlayed,
    required this.onlineFeedPool,
    required this.featuredOnlinePool,
    required this.popularOnlinePool,
    required this.yourMusicOnlinePool,
    required this.youtubeService,
    required this.onPlaySelected,
    required this.onNavigateToLibrary,
    required this.onNavigateToSearch,
    required this.onSetCategory,
    required this.onRescan,
    required this.onSwitchToOffline,
    required this.onSwitchToOnline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectivePool = onlineFeedPool.isNotEmpty
        ? onlineFeedPool
        : _HomeScreenState._defaultSeedOnlineTracks;

    final effectiveFeaturedPool = featuredOnlinePool.isNotEmpty
        ? featuredOnlinePool
        : effectivePool;

    final effectivePopularPool = popularOnlinePool.isNotEmpty
        ? popularOnlinePool
        : effectivePool;

    final effectiveYourMusicPool = yourMusicOnlinePool.isNotEmpty
        ? yourMusicOnlinePool
        : effectivePool;

    // Deduplication tracker across For You sections in strict priority order:
    // 1. Featured (first) -> 2. Popular Songs (second) -> 3. Your Music (third)
    final Set<String> alreadyShown = {};

    // ── Priority 1: Featured (Personalized to user's selected genres) ──
    final featuredItems = _buildDeduplicatedSection(
      localPool: displayRail.isNotEmpty ? displayRail : activeTracks,
      onlinePool: effectiveFeaturedPool,
      alreadyShown: alreadyShown,
      targetCount: 6,
      minCount: 4,
    );
    final featuredLocal = featuredItems
        .where((item) => !item.isOnline && item.localTrack != null)
        .map((item) => item.localTrack!)
        .toList();

    // ── Priority 2: Popular Songs (Trending & Latest Pakistani and Indian hits) ──
    final popularItems = _buildDeduplicatedSection(
      localPool: displayRail.isNotEmpty ? displayRail : activeTracks,
      onlinePool: effectivePopularPool,
      alreadyShown: alreadyShown,
      targetCount: 15,
      minCount: 6,
    );
    final popularLocal = popularItems
        .where((item) => !item.isOnline && item.localTrack != null)
        .map((item) => item.localTrack!)
        .toList();

    // Section: Recently Played / Jump Back In (replacing Recommended For You)
    final recentTracks = recentlyPlayed.isNotEmpty
        ? recentlyPlayed
        : (activeTracks.isNotEmpty
            ? (recommendations.heavyRotation.isNotEmpty
                ? recommendations.heavyRotation
                : recommendations.dailyMix)
            : const <Track>[]);
    final hasRealRecents = recentlyPlayed.isNotEmpty;

    // ── Priority 3: Your Music (Top searches across all genres) ──
    final musicItems = _buildDeduplicatedSection(
      localPool: filteredTracks.isNotEmpty ? filteredTracks : activeTracks,
      onlinePool: effectiveYourMusicPool,
      alreadyShown: alreadyShown,
      targetCount: 24,
      minCount: 8,
    );
    final musicLocal = musicItems
        .where((item) => !item.isOnline && item.localTrack != null)
        .map((item) => item.localTrack!)
        .toList();

    // Recordings
    final recordings = groupedCollections['Recordings'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Low music quantity card if user has fewer than 5 local tracks
        if (activeTracks.isNotEmpty && activeTracks.length < 5) ...[
          _LowMusicPromptCard(
            accentColor: accentColor,
            isDark: isDark,
            isCompletelyEmpty: false,
            trackCount: activeTracks.length,
            onSwitchToOnline: onSwitchToOnline,
            onRescan: onRescan,
          ),
          const SizedBox(height: 24),
        ],

        // ── 1. Hero Carousel (Featured) ──
        if (featuredItems.isNotEmpty) ...[
          _SectionLabel(
            label: 'Featured',
            icon: Icons.auto_awesome_rounded,
            accentColor: accentColor,
            onSeeAll: () {
              if (activeTracks.isEmpty) {
                SearchScreen.switchToOnlineMode();
                onNavigateToSearch();
              } else {
                _showOnlineOfflineModePicker(
                  context: context,
                  title: 'Featured Music',
                  subtitle: 'Select whether to browse offline library or search online',
                  accentColor: accentColor,
                  onOfflineSelected: () => onNavigateToLibrary('All Songs'),
                  onOnlineSelected: () {
                    SearchScreen.switchToOnlineMode();
                    onNavigateToSearch();
                  },
                );
              }
            },
          ),
          const SizedBox(height: 14),
          _HeroCarousel(
            items: featuredItems,
            localTracks: featuredLocal,
            accentColor: accentColor,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // ── 2. Popular Songs — compact horizontal cards ──
        if (popularItems.isNotEmpty) ...[
          _SectionLabel(
            label: 'Popular Songs',
            icon: Icons.trending_up_rounded,
            accentColor: accentColor,
            onSeeAll: () {
              if (activeTracks.isEmpty) {
                onSwitchToOnline();
              } else {
                _showOnlineOfflineModePicker(
                  context: context,
                  title: 'Popular Songs',
                  subtitle: 'Select whether to view offline songs or online trending',
                  accentColor: accentColor,
                  onOfflineSelected: onSwitchToOffline,
                  onOnlineSelected: onSwitchToOnline,
                );
              }
            },
          ),
          const SizedBox(height: 14),
          _PopularSongsStrip(
            items: popularItems,
            localTracks: popularLocal,
            accentColor: accentColor,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // ── 3. Recently Played / Jump Back In ──
        if (recentTracks.isNotEmpty) ...[
          _SectionLabel(
            label: hasRealRecents ? 'Jump Back In' : 'Recommended For You',
            icon: hasRealRecents ? Icons.history_rounded : Icons.recommend_rounded,
            accentColor: accentColor,
            onSeeAll: () => onNavigateToLibrary('History'),
          ),
          const SizedBox(height: 14),
          _RecentlyPlayedRow(
            tracks: recentTracks,
            accentColor: accentColor,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // ── 4. Music List — Your Music (Offline & Online) ──
        if (musicItems.isNotEmpty) ...[
          _SectionLabel(
            label: 'Your Music',
            icon: Icons.library_music_rounded,
            accentColor: accentColor,
          ),
          const SizedBox(height: 14),
          _MusicListSection(
            items: musicItems,
            localTracks: musicLocal,
            accentColor: accentColor,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // ── 5. Recordings — moved exact after Your Music ──
        if (recordings.isNotEmpty) ...[
          _SectionLabel(
            label: 'Recordings',
            icon: Icons.mic_rounded,
            accentColor: accentColor,
          ),
          const SizedBox(height: 14),
          _RecordingsCard(
            tracks: recordings,
            accentColor: accentColor,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

// ─────────────────────────── Offline View ───────────────────────────

class _OfflineView extends StatelessWidget {
  final Color accentColor;
  final List<Track> activeTracks;
  final List<Track> filteredTracks;
  final List<Track> displayRail;
  final Map<String, List<Track>> groupedCollections;
  final RecommendationBatch recommendations;
  final List<Track> recentlyPlayed;
  final void Function(List<Track>, int) onPlaySelected;
  final void Function(String?) onNavigateToLibrary;
  final VoidCallback onRescan;
  final VoidCallback onSwitchToOffline;
  final VoidCallback onSwitchToOnline;

  const _OfflineView({
    required this.accentColor,
    required this.activeTracks,
    required this.filteredTracks,
    required this.displayRail,
    required this.groupedCollections,
    required this.recommendations,
    required this.recentlyPlayed,
    required this.onPlaySelected,
    required this.onNavigateToLibrary,
    required this.onRescan,
    required this.onSwitchToOffline,
    required this.onSwitchToOnline,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pure local Popular Songs (no interleaving, no online items)
    final popularLocal = displayRail.take(15).toList();
    final popularItems = popularLocal.map((t) => _HomeFeedItem.local(t)).toList();

    final recentTracks = recentlyPlayed.isNotEmpty
        ? recentlyPlayed
        : (recommendations.heavyRotation.isNotEmpty
            ? recommendations.heavyRotation
            : recommendations.dailyMix);
    final hasRealRecents = recentlyPlayed.isNotEmpty;
    final listTracks = filteredTracks.take(15).toList();
    final recordings = groupedCollections['Recordings'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Low music quantity card if user has fewer than 5 local tracks
        if (activeTracks.length < 5) ...[
          _LowMusicPromptCard(
            accentColor: accentColor,
            isDark: isDark,
            isCompletelyEmpty: false,
            trackCount: activeTracks.length,
            onSwitchToOnline: onSwitchToOnline,
            onRescan: onRescan,
          ),
          const SizedBox(height: 24),
        ],

        // 1. Popular Songs (local only, zero violet accents)
        if (popularItems.isNotEmpty) ...[
          _SectionLabel(
            label: 'Popular Songs',
            icon: Icons.trending_up_rounded,
            accentColor: accentColor,
            onSeeAll: () {
              _showOnlineOfflineModePicker(
                context: context,
                title: 'Popular Songs',
                subtitle: 'Select whether to view offline songs or online trending',
                accentColor: accentColor,
                onOfflineSelected: onSwitchToOffline,
                onOnlineSelected: onSwitchToOnline,
              );
            },
          ),
          const SizedBox(height: 14),
          _PopularSongsStrip(
            items: popularItems,
            localTracks: popularLocal,
            accentColor: accentColor,
            youtubeService: YoutubeService(),
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],


        // 3. Jump Back In / Recently Played
        if (recentTracks.isNotEmpty) ...[
          _SectionLabel(
            label: hasRealRecents ? 'Jump Back In' : 'Recommended For You',
            icon: hasRealRecents ? Icons.history_rounded : Icons.recommend_rounded,
            accentColor: accentColor,
            onSeeAll: () => onNavigateToLibrary('History'),
          ),
          const SizedBox(height: 14),
          _RecentlyPlayedRow(
            tracks: recentTracks,
            accentColor: accentColor,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // 4. Your Music
        if (listTracks.isNotEmpty) ...[
          _SectionLabel(
            label: 'Your Music',
            icon: Icons.library_music_rounded,
            accentColor: accentColor,
          ),
          const SizedBox(height: 14),
          _MusicListSection(
            tracks: listTracks,
            accentColor: accentColor,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],

        // 5. Recordings
        if (recordings.isNotEmpty) ...[
          _SectionLabel(
            label: 'Recordings',
            icon: Icons.mic_rounded,
            accentColor: accentColor,
          ),
          const SizedBox(height: 14),
          _RecordingsCard(
            tracks: recordings,
            accentColor: accentColor,
            onPlaySelected: onPlaySelected,
          ),
          const SizedBox(height: 32),
        ],
      ],
    );
  }
}

// ─────────────────────────── Dedicated Online View ───────────────────────────

class _OnlineView extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;
  final bool isShuffling;
  final VoidCallback onShuffleAll;
  final List<OnlineSearchResult> topTracks;
  final bool isTopTracksLoading;
  final dynamic topTracksError;
  final VoidCallback onRetryTopTracks;
  final List<_OnlineMix> mixes;
  final bool isMixesLoading;
  final dynamic mixesError;
  final VoidCallback onRetryMixes;
  final void Function(_OnlineMix) onPlayMix;
  final List<OnlineSearchResult> singles;
  final bool isSinglesLoading;
  final dynamic singlesError;
  final VoidCallback onRetrySingles;
  final List<String> availableSinglesGenres;
  final String selectedSinglesGenre;
  final ValueChanged<String> onSelectSinglesGenre;
  final VoidCallback onLoadMoreSingles;
  final ValueChanged<OnlineSearchResult> onTrackPlayed;

  const _OnlineView({
    required this.isDark,
    required this.accentColor,
    required this.youtubeService,
    required this.onPlaySelected,
    required this.isShuffling,
    required this.onShuffleAll,
    required this.topTracks,
    required this.isTopTracksLoading,
    required this.topTracksError,
    required this.onRetryTopTracks,
    required this.mixes,
    required this.isMixesLoading,
    required this.mixesError,
    required this.onRetryMixes,
    required this.onPlayMix,
    required this.singles,
    required this.isSinglesLoading,
    required this.singlesError,
    required this.onRetrySingles,
    this.availableSinglesGenres = const ['All'],
    required this.selectedSinglesGenre,
    required this.onSelectSinglesGenre,
    required this.onLoadMoreSingles,
    required this.onTrackPlayed,
  });

  @override
  Widget build(BuildContext context) {
    final onlineAccent = OnlineTheme.accent(isDark);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. Shuffle All Prominent Card ──
        _OnlineShuffleCard(
          isDark: isDark,
          isShuffling: isShuffling,
          onShuffle: onShuffleAll,
        ),
        const SizedBox(height: 20),

        // ── 2. Your Top Tracks (Hidden if history is empty) ──
        if (topTracksError != null)
          OnlineSectionErrorWidget(
            error: topTracksError,
            onRetry: onRetryTopTracks,
          )
        else if (isTopTracksLoading || topTracks.isNotEmpty) ...[
          _OnlineSectionHeader(
            label: 'Your Top Tracks',
            icon: Icons.local_fire_department_rounded,
            accentColor: onlineAccent,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          _OnlineTopTracksStrip(
            tracks: topTracks,
            isLoading: isTopTracksLoading,
            isDark: isDark,
            accentColor: onlineAccent,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
            onTrackPlayed: onTrackPlayed,
          ),
          const SizedBox(height: 16),
        ],

        // ── 3. Mixes Section ──
        _OnlineSectionHeader(
          label: 'Curated Mixes',
          icon: Icons.album_rounded,
          accentColor: onlineAccent,
          isDark: isDark,
        ),
        const SizedBox(height: 10),
        if (mixesError != null)
          OnlineSectionErrorWidget(
            error: mixesError,
            onRetry: onRetryMixes,
          )
        else
          _OnlineMixesRow(
            mixes: mixes,
            isLoading: isMixesLoading,
            isDark: isDark,
            accentColor: onlineAccent,
            onTapMix: (mix) {
              _showMixDetailSheet(
                context: context,
                mix: mix,
                accentColor: onlineAccent,
                youtubeService: youtubeService,
                onPlaySelected: onPlaySelected,
                onTrackPlayed: onTrackPlayed,
                onPlayAll: () => onPlayMix(mix),
              );
            },
          ),
        const SizedBox(height: 32),

        // ── 4. Singles & Fresh Tracks Section ──
        _OnlineSectionHeader(
          label: 'Singles & Fresh Tracks',
          icon: Icons.music_note_rounded,
          accentColor: onlineAccent,
          isDark: isDark,
        ),
        const SizedBox(height: 14),
        // Genre filter pills
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: availableSinglesGenres.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final genre = availableSinglesGenres[i];
              final isSelected = genre == selectedSinglesGenre;
              return GestureDetector(
                onTap: () => onSelectSinglesGenre(genre),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? onlineAccent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.8)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? onlineAccent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.6)
                              : const Color(0xFF64748B)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        if (singlesError != null)
          OnlineSectionErrorWidget(
            error: singlesError,
            onRetry: onRetrySingles,
          )
        else
          _OnlineSinglesGrid(
            singles: singles,
            isLoading: isSinglesLoading,
            isDark: isDark,
            accentColor: onlineAccent,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
            onTrackPlayed: onTrackPlayed,
            onLoadMore: onLoadMoreSingles,
          ),
      ],
    );
  }
}

// ─────────────────────────── Online Shuffle Card ───────────────────────────

class _OnlineShuffleCard extends StatelessWidget {
  final VoidCallback onShuffle;
  final bool isShuffling;
  final bool isDark;

  const _OnlineShuffleCard({
    required this.onShuffle,
    required this.isShuffling,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF6D28D9), Color(0xFF4F46E5), Color(0xFF2563EB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D28D9).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: isShuffling ? null : onShuffle,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: isShuffling
                        ? const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.shuffle_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Shuffle All',
                              style: TextStyle(
                                fontFamily: AppTypography.displayFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Online Mix',
                                style: TextStyle(
                                  fontFamily: AppTypography.uiFont,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Endless discovery tuned to your vibe',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF6D28D9),
                          size: 18,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Play',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6D28D9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Online Section Header ───────────────────────────

class _OnlineSectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isDark;

  const _OnlineSectionHeader({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 15),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Online Top Tracks Strip ───────────────────────────

class _OnlineTopTracksStrip extends StatelessWidget {
  final List<OnlineSearchResult> tracks;
  final bool isLoading;
  final bool isDark;
  final Color accentColor;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;
  final ValueChanged<OnlineSearchResult> onTrackPlayed;

  const _OnlineTopTracksStrip({
    required this.tracks,
    required this.isLoading,
    required this.isDark,
    required this.accentColor,
    required this.youtubeService,
    required this.onPlaySelected,
    required this.onTrackPlayed,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && tracks.isEmpty) {
      return SizedBox(
        height: 142,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, __) => Container(
            width: 94,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return GestureDetector(
            onTap: () async {
              final success = await OnlinePlaybackHelper.playOnlineTrack(
                context,
                track,
                youtubeService,
                onPlaySelected,
                accentColor,
              );
              if (success) {
                onTrackPlayed(track);
              }
            },
            child: SizedBox(
              width: 94,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accentColor.withValues(alpha: isDark ? 0.35 : 0.20),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: isDark ? 0.16 : 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty)
                            Image.network(
                              track.thumbnailUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: accentColor.withValues(alpha: 0.15),
                                child: Icon(Icons.music_note_rounded, color: accentColor, size: 20),
                              ),
                            )
                          else
                            Container(
                              color: accentColor.withValues(alpha: 0.15),
                              child: Icon(Icons.music_note_rounded, color: accentColor, size: 20),
                            ),
                          // 3-dot options menu button in top-left
                          Positioned(
                            top: 4,
                            left: 4,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                TrackActionMenu.show(
                                  context,
                                  onlineTrack: track,
                                  accentColor: accentColor,
                                );
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.more_vert_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Pink heart badge if favorite
                          if (_FavoritesScope.isFav(context, onlineTrack: track))
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFF2E7E),
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.favorite_rounded,
                                    size: 11,
                                    color: Color(0xFFFF2E7E),
                                  ),
                                ),
                              ),
                            ),
                          // Play button
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.45),
                                    blurRadius: 5,
                                  )
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 10,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────── Mix Detail Bottom Sheet ───────────────────────────

void _showMixDetailSheet({
  required BuildContext context,
  required _OnlineMix mix,
  required Color accentColor,
  required YoutubeService youtubeService,
  required void Function(List<Track>, int) onPlaySelected,
  required ValueChanged<OnlineSearchResult> onTrackPlayed,
  required VoidCallback onPlayAll,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  HapticFeedback.lightImpact();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.74,
        minChildSize: 0.25,
        maxChildSize: 0.90,
        expand: false,
        snap: true,
        builder: (sheetContext, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF13111C) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                color: accentColor.withValues(alpha: isDark ? 0.28 : 0.18),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: isDark ? 0.22 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: accentColor.withValues(alpha: 0.15),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: mix.tracks.isNotEmpty && mix.tracks.first.thumbnailUrl != null
                              ? Image.network(
                                  mix.tracks.first.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(Icons.album_rounded, color: accentColor, size: 28),
                                )
                              : Icon(Icons.album_rounded, color: accentColor, size: 28),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mix.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.displayFont,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${mix.tracks.length} curated tracks • ${mix.genre}',
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 12,
                                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          onPlayAll();
                        },
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'Play All',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 4,
                          shadowColor: accentColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                // Track list
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: mix.tracks.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 64,
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                    ),
                    itemBuilder: (context, idx) {
                      final track = mix.tracks[idx];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: accentColor.withValues(alpha: 0.12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
                                ? Image.network(
                                    track.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Icon(Icons.music_note_rounded, color: accentColor, size: 20),
                                  )
                                : Icon(Icons.music_note_rounded, color: accentColor, size: 20),
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        subtitle: Text(
                          '${track.artist}${track.duration != null && track.duration!.isNotEmpty ? " • ${formatDurationString(track.duration)}" : ""}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 11.5,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 18),
                          color: isDark ? Colors.white60 : Colors.black54,
                          onPressed: () {
                            TrackActionMenu.show(
                              context,
                              onlineTrack: track,
                              accentColor: accentColor,
                            );
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          OnlinePlaybackHelper.playOnlineTrack(
                            context,
                            track,
                            youtubeService,
                            onPlaySelected,
                            accentColor,
                          );
                          onTrackPlayed(track);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// ─────────────────────────── Online Mixes Row (4-card square view) ───────────────────────────

class _OnlineMixesRow extends StatelessWidget {
  final List<_OnlineMix> mixes;
  final bool isLoading;
  final bool isDark;
  final Color accentColor;
  final void Function(_OnlineMix) onTapMix;

  const _OnlineMixesRow({
    required this.mixes,
    required this.isLoading,
    required this.isDark,
    required this.accentColor,
    required this.onTapMix,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && mixes.isEmpty) {
      return SizedBox(
        height: 174,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: 2,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, _) => Column(
            children: [
              Container(
                width: 164,
                height: 82,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 164,
                height: 82,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (mixes.isEmpty) {
      return Container(
        height: 100,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No mixes available right now.',
            style: TextStyle(
              fontFamily: AppTypography.uiFont,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // Pair mixes into columns of 2: 2 rows x 2 columns = 4 cards in one view
    final int columnCount = (mixes.length / 2).ceil();

    return SizedBox(
      height: 174,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: columnCount,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, colIndex) {
          final topIndex = colIndex * 2;
          final bottomIndex = topIndex + 1;

          final topMix = topIndex < mixes.length ? mixes[topIndex] : null;
          final bottomMix = bottomIndex < mixes.length ? mixes[bottomIndex] : null;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (topMix != null)
                _OnlineMixCard(
                  mix: topMix,
                  isDark: isDark,
                  accentColor: accentColor,
                  onTap: () => onTapMix(topMix),
                ),
              if (bottomMix != null) ...[
                const SizedBox(height: 10),
                _OnlineMixCard(
                  mix: bottomMix,
                  isDark: isDark,
                  accentColor: accentColor,
                  onTap: () => onTapMix(bottomMix),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OnlineMixCard extends StatelessWidget {
  final _OnlineMix mix;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _OnlineMixCard({
    required this.mix,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final thumb = mix.tracks.isNotEmpty ? mix.tracks.first.thumbnailUrl : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 164,
        height: 82,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: isDark ? 0.28 : 0.16),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: isDark ? 0.12 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Artwork with mini play icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: accentColor.withValues(alpha: 0.15),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (thumb != null && thumb.isNotEmpty)
                      Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.album_rounded,
                          color: accentColor,
                          size: 24,
                        ),
                      )
                    else
                      Icon(Icons.album_rounded, color: accentColor, size: 24),
                    Center(
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Title + track count + genre badge
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mix.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.displayFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${mix.tracks.length} tracks',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 10.5,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      mix.genre,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Online Singles Grid ───────────────────────────

class _OnlineSinglesGrid extends StatelessWidget {
  final List<OnlineSearchResult> singles;
  final bool isLoading;
  final bool isDark;
  final Color accentColor;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;
  final ValueChanged<OnlineSearchResult> onTrackPlayed;
  final VoidCallback onLoadMore;

  const _OnlineSinglesGrid({
    required this.singles,
    required this.isLoading,
    required this.isDark,
    required this.accentColor,
    required this.youtubeService,
    required this.onPlaySelected,
    required this.onTrackPlayed,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && singles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: 4,
          itemBuilder: (_, __) => _OnlineSkeletonCard(isDark: isDark),
        ),
      );
    }

    if (singles.isEmpty) {
      return Container(
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            'No singles available right now.',
            style: TextStyle(
              fontFamily: AppTypography.uiFont,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif.metrics.extentAfter < 400) {
          onLoadMore();
        }
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: singles.length,
          itemBuilder: (context, index) {
            final track = singles[index];
            return _OnlineSingleCard(
              track: track,
              isDark: isDark,
              accentColor: accentColor,
              onTap: () async {
                final success = await OnlinePlaybackHelper.playOnlineTrack(
                  context,
                  track,
                  youtubeService,
                  onPlaySelected,
                  accentColor,
                );
                if (success) {
                  onTrackPlayed(track);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _OnlineSingleCard extends StatelessWidget {
  final OnlineSearchResult track;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _OnlineSingleCard({
    required this.track,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: isDark ? 0.22 : 0.14),
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: track.thumbnailUrl != null && track.thumbnailUrl!.isNotEmpty
                        ? Image.network(
                            track.thumbnailUrl!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => _singlePlaceholder(),
                          )
                        : _singlePlaceholder(),
                  ),
                  // Duration / Online badge
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        (track.duration != null && track.duration!.isNotEmpty)
                            ? formatDurationString(track.duration)
                            : 'Online',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Pink heart badge if favorite
                  if (_FavoritesScope.isFav(context, onlineTrack: track))
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFF2E7E),
                            width: 1.2,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color: Color(0xFFFF2E7E),
                          ),
                        ),
                      ),
                    ),
                  // Play button
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.45),
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 11,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    TrackActionMenu.show(
                      context,
                      onlineTrack: track,
                      accentColor: accentColor,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 16,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _singlePlaceholder() => Container(
        color: accentColor.withValues(alpha: 0.12),
        child: Icon(Icons.music_note_rounded, color: accentColor, size: 28),
      );
}

class _OnlineSkeletonCard extends StatelessWidget {
  final bool isDark;
  const _OnlineSkeletonCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 12,
            width: double.infinity,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 10,
            width: 70,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Header / Top Navbar ───────────────────────────

class _HomeHeader extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onSearchTap;

  const _HomeHeader({required this.accentColor, required this.onSearchTap});

  void _showNotificationPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          alignment: const Alignment(0.85, -0.9),
          scale: CurvedAnimation(
              parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 76, right: 16, left: 24),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 320,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.62,
                  ),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A).withValues(alpha: 0.96)
                        : Colors.white.withValues(alpha: 0.98),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.5)
                          : const Color(0xFFBAE6FD),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? const Color(0xFF000000).withValues(alpha: 0.70)
                            : Colors.black.withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: (isDark
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF0284C7))
                                      .withValues(alpha: 0.18),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.notifications_rounded,
                                  size: 16,
                                  color: isDark
                                      ? const Color(0xFF38BDF8)
                                      : const Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Notifications',
                                style: TextStyle(
                                  fontFamily: AppTypography.displayFont,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0C4A6E),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              NotificationService.instance.clearAll();
                              Navigator.pop(ctx);
                            },
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                      ),
                      const SizedBox(height: 10),
                      Flexible(
                        child: ListenableBuilder(
                          listenable: NotificationService.instance,
                          builder: (context, _) {
                            final notifs =
                                NotificationService.instance.notifications;
                            if (notifs.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.notifications_off_outlined,
                                        size: 34,
                                        color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No notifications yet',
                                        style: TextStyle(
                                          fontFamily: AppTypography.uiFont,
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white54
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              itemCount: notifs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final n = notifs[i];
                                final isError = n.type == 'error';
                                final isRecommendation = n.type == 'recommendation' ||
                                    n.type == 'online' ||
                                    n.type == 'offline';
                                final Color typeColor = isError
                                    ? Colors.redAccent
                                    : (isRecommendation
                                        ? const Color(0xFF8B5CF6)
                                        : accentColor);
                                final IconData typeIcon = isError
                                    ? Icons.error_outline_rounded
                                    : (n.type == 'online'
                                        ? Icons.cloud_done_rounded
                                        : (n.type == 'offline'
                                            ? Icons.headset_rounded
                                            : Icons.auto_awesome_rounded));

                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? (n.isRead
                                            ? Colors.white.withValues(alpha: 0.03)
                                            : typeColor.withValues(alpha: 0.08))
                                        : (n.isRead
                                            ? const Color(0xFFF8FAFC)
                                            : typeColor.withValues(alpha: 0.08)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isDark
                                          ? (n.isRead
                                              ? Colors.white.withValues(alpha: 0.06)
                                              : typeColor.withValues(alpha: 0.25))
                                          : (n.isRead
                                              ? const Color(0xFFE2E8F0)
                                              : typeColor.withValues(alpha: 0.25)),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: typeColor.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Icon(typeIcon,
                                              color: typeColor, size: 16),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              n.title,
                                              style: TextStyle(
                                                fontFamily: AppTypography.uiFont,
                                                fontSize: 13,
                                                fontWeight: n.isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.bold,
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              n.message,
                                              style: TextStyle(
                                                fontFamily: AppTypography.uiFont,
                                                fontSize: 11.5,
                                                color: isDark
                                                    ? Colors.white70
                                                    : const Color(0xFF475569),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (!n.isRead)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(
                                              top: 4, left: 4),
                                          decoration: BoxDecoration(
                                            color: typeColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(
        () => NotificationService.instance.markAllAsRead());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar - dynamic user avatar connected to preferences
          ListenableBuilder(
            listenable: UserPreferencesService.instance,
            builder: (context, _) => UserAvatar(
              size: 40,
              isDark: isDark,
              onTap: () => AvatarPickerSheet.show(context, accentColor: accentColor),
            ),
          ),
          const SizedBox(width: 12),
          // Greeting - tighter vertical rhythm, no sparkle emoji
          Expanded(
            child: ListenableBuilder(
              listenable: UserPreferencesService.instance,
              builder: (context, _) {
                final userName = UserPreferencesService.instance.userName;
                final greeting = GreetingHelper.forCurrentTime();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      greeting,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 11.5,
                        letterSpacing: 0.3,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFBAE6FD)
                            : const Color(0xFF0369A1),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Search icon button - 40x40 subtle circular button
          GestureDetector(
            onTap: onSearchTap,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.90),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),
          // Notification bell button - 40x40 subtle circular button with rose accent dot
          ListenableBuilder(
            listenable: NotificationService.instance,
            builder: (context, _) {
              final hasUnread = NotificationService.instance.unreadCount > 0;
              final roseDotColor = SectionAccents.favorites(isDark);
              return GestureDetector(
                onTap: () => _showNotificationPanel(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.90),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.notifications_outlined,
                        size: 20,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                      if (hasUnread)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: roseDotColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: roseDotColor.withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────── Scan Progress Banner ───────────────────────────

class _ScanProgressBanner extends StatelessWidget {
  final Color accentColor;
  const _ScanProgressBanner({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AudioScannerService.instance,
      builder: (context, _) {
        final progress = AudioScannerService.instance.currentProgress;
        if (!progress.isScanning) return const SizedBox.shrink();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accentColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scanning Audio Files…',
                      style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _HomeColors.primaryText(isDark)),
                    ),
                  ),
                  Text(
                    '${progress.scannedCount}/${progress.totalCount}',
                    style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.percentage,
                  backgroundColor: Colors.white12,
                  color: accentColor,
                  minHeight: 4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────── Section Label ───────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onSeeAll;

  const _SectionLabel({
    required this.label,
    required this.icon,
    required this.accentColor,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedHomeIcon(icon, color: accentColor, size: 16),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _HomeColors.primaryText(isDark),
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onSeeAll!();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0C4A6E).withValues(alpha: 0.40)
                        : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.65)
                          : const Color(0xFF0284C7),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? const Color(0xFF7DD3FC)
                              : const Color(0xFF0C4A6E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: isDark
                            ? const Color(0xFF7DD3FC)
                            : const Color(0xFF0C4A6E),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Mode Selection Sheet (Online vs Offline) ───────────────────────────

void _showOnlineOfflineModePicker({
  required BuildContext context,
  required String title,
  required String subtitle,
  required VoidCallback onOfflineSelected,
  required VoidCallback onOnlineSelected,
  required Color accentColor,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final onlineAccent = OnlineTheme.accent(isDark);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    builder: (sheetContext) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1527) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFFCBD5E1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.15),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),

              // Offline Card
              _ModeSelectionCard(
                isDark: isDark,
                icon: Icons.phone_android_rounded,
                iconColor: accentColor,
                title: 'Offline Music',
                description: 'Browse local songs on your device',
                tag: 'OFFLINE',
                onTap: () {
                  Navigator.pop(sheetContext);
                  HapticFeedback.lightImpact();
                  onOfflineSelected();
                },
              ),
              const SizedBox(height: 12),

              // Online Card
              _ModeSelectionCard(
                isDark: isDark,
                icon: Icons.cloud_rounded,
                iconColor: onlineAccent,
                title: 'Online Music',
                description: 'Stream & discover songs online',
                tag: 'ONLINE',
                onTap: () {
                  Navigator.pop(sheetContext);
                  HapticFeedback.lightImpact();
                  onOnlineSelected();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ModeSelectionCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String tag;
  final VoidCallback onTap;

  const _ModeSelectionCard({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: AnimatedHomeIcon(icon, color: iconColor, size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: iconColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Home 3-Tab Bar ───────────────────────────

class HomeTabBar extends StatelessWidget {
  final int selectedIndex;
  final Color accentColor;
  final bool isDark;
  final bool showOfflineTab;
  final ValueChanged<int> onTabChanged;

  const HomeTabBar({
    super.key,
    required this.selectedIndex,
    required this.accentColor,
    required this.isDark,
    this.showOfflineTab = true,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final onlineAccent = OnlineTheme.accent(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 50,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141826) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark ? const Color(0xFF262E44) : const Color(0xFFD6DFE8),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.45)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeTabItem(
              label: 'For You',
              icon: Icons.auto_awesome_rounded,
              isSelected: selectedIndex == 0,
              activeColor: accentColor,
              activeGradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              onTap: () => onTabChanged(0),
            ),
            if (showOfflineTab) ...[
              const SizedBox(width: 4),
              _HomeTabItem(
                label: 'Offline',
                icon: Icons.cloud_off_rounded,
                isSelected: selectedIndex == 1,
                activeColor: accentColor,
                onTap: () => onTabChanged(1),
              ),
            ],
            const SizedBox(width: 4),
            _HomeTabItem(
              label: 'Online',
              icon: Icons.language_rounded,
              isSelected: selectedIndex == 2,
              activeColor: onlineAccent,
              onTap: () => onTabChanged(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTabItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final Gradient? activeGradient;
  final VoidCallback onTap;

  const _HomeTabItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    this.activeGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: isSelected ? activeGradient : null,
            color: isSelected ? (activeGradient == null ? activeColor : null) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: (activeGradient != null ? const Color(0xFF0284C7) : activeColor)
                          .withValues(alpha: 0.38),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Hero Carousel ───────────────────────────

class _HeroCarousel extends StatefulWidget {
  final List<_HomeFeedItem> items;
  final List<Track> localTracks;
  final Color accentColor;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;

  const _HeroCarousel({
    required this.items,
    required this.localTracks,
    required this.accentColor,
    required this.youtubeService,
    required this.onPlaySelected,
  });

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  bool _isUserTouching = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    _scheduleNextAutoScroll(delay: const Duration(seconds: 4));
  }

  void _scheduleNextAutoScroll({Duration delay = const Duration(seconds: 4)}) {
    _autoScrollTimer?.cancel();
    if (!mounted || widget.items.length <= 1) return;
    _autoScrollTimer = Timer(delay, _advancePage);
  }

  void _advancePage() {
    if (!mounted || _isUserTouching || widget.items.length <= 1) return;
    if (!_pageController.hasClients) return;
    final next = (_currentPage + 1) % widget.items.length;
    _pageController
        .animateToPage(
      next,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    )
        .then((_) {
      if (mounted && !_isUserTouching) {
        _scheduleNextAutoScroll(delay: const Duration(seconds: 4));
      }
    });
  }

  void _onUserTouchStart() {
    _isUserTouching = true;
    _autoScrollTimer?.cancel();
  }

  void _onUserTouchEnd() {
    _isUserTouching = false;
    // As soon as user releases finger, wait 2.5 seconds on the landed card and resume auto-scroll
    _scheduleNextAutoScroll(delay: const Duration(milliseconds: 2500));
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackGifs = [
      'assets/gif/child.gif',
      'assets/gif/dj.gif',
      'assets/gif/fan.gif',
      'assets/gif/headphones.gif',
      'assets/gif/pianist.gif',
    ];

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _onUserTouchStart(),
            onPointerUp: (_) => _onUserTouchEnd(),
            onPointerCancel: (_) => _onUserTouchEnd(),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction != ScrollDirection.idle) {
                    _onUserTouchStart();
                  } else if (!_isUserTouching) {
                    _onUserTouchEnd();
                  }
                } else if (notification is ScrollEndNotification) {
                  if (!_isUserTouching) {
                    _onUserTouchEnd();
                  }
                }
                return false;
              },
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  setState(() => _currentPage = i);
                  if (!_isUserTouching) {
                    _scheduleNextAutoScroll(delay: const Duration(milliseconds: 2500));
                  }
                },
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final gif = fallbackGifs[index % fallbackGifs.length];
                final isActive = index == _currentPage;
                final isOnline = item.isOnline;
                final onlineAccent = OnlineTheme.accent(isDark);
                final cardBorderColor = isOnline
                    ? onlineAccent.withValues(alpha: isDark ? 0.70 : 0.50)
                    : widget.accentColor.withValues(alpha: isDark ? 0.25 : 0.15);

                return AnimatedScale(
                  scale: isActive ? 1.0 : 0.93,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: GestureDetector(
                    onTap: () {
                      if (isOnline) {
                        OnlinePlaybackHelper.playOnlineTrack(
                          context,
                          item.onlineTrack!,
                          widget.youtubeService,
                          widget.onPlaySelected,
                          onlineAccent,
                        );
                      } else {
                        final localIdx = widget.localTracks.indexOf(item.localTrack!);
                        widget.onPlaySelected(
                          widget.localTracks,
                          localIdx != -1 ? localIdx : 0,
                        );
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cardBorderColor,
                          width: isOnline ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isOnline
                                ? onlineAccent.withValues(alpha: isDark ? 0.25 : 0.12)
                                : Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Artwork / gif fallback / online image
                            if (isOnline)
                              (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                                  ? Image.network(
                                      item.thumbnailUrl!,
                                      width: double.infinity,
                                      height: 220,
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, __, ___) =>
                                          Image.asset(gif, fit: BoxFit.cover),
                                    )
                                  : Image.asset(gif, fit: BoxFit.cover)
                            else
                              TrackArtwork(
                                track: item.localTrack!,
                                width: double.infinity,
                                height: 220,
                                borderRadius: 24,
                                showShadow: false,
                                customFallback: Image.asset(gif, fit: BoxFit.cover),
                              ),
                            // Gradient overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    _HomeColors.heroOverlay(isDark),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                            // Source badge (top-right corner)
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? (isDark
                                          ? onlineAccent.withValues(alpha: 0.35)
                                          : onlineAccent.withValues(alpha: 0.20))
                                      : (isDark
                                          ? Colors.black.withValues(alpha: 0.55)
                                          : Colors.white.withValues(alpha: 0.75)),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isOnline
                                        ? onlineAccent.withValues(alpha: 0.7)
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : Colors.black.withValues(alpha: 0.12)),
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: AnimatedHomeIcon(
                                    isOnline
                                        ? Icons.cloud_rounded
                                        : Icons.phone_android_rounded,
                                    size: 14,
                                    color: isOnline
                                        ? (isDark
                                            ? const Color(0xFFB4A5FF)
                                            : onlineAccent)
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                            // Text + play button
                            Positioned(
                              left: 18,
                              right: 18,
                              bottom: 18,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontFamily: AppTypography.displayFont,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            shadows: [
                                              Shadow(
                                                blurRadius: 8,
                                                color: Colors.black54,
                                              )
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontFamily: AppTypography.uiFont,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      TrackActionMenu.show(
                                        context,
                                        localTrack: item.localTrack,
                                        onlineTrack: item.onlineTrack,
                                        accentColor: isOnline ? onlineAccent : widget.accentColor,
                                      );
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.30),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.more_vert_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isOnline ? onlineAccent : widget.accentColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isOnline ? onlineAccent : widget.accentColor)
                                              .withValues(alpha: 0.5),
                                          blurRadius: 12,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
                                    ),
                                    child: const AnimatedHomeIcon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ),
        ),
        // Dot indicators
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.items.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _currentPage ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _currentPage
                    ? widget.accentColor
                    : _HomeColors.secondaryText(isDark).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Popular Songs Strip ───────────────────────────

class _PopularSongsStrip extends StatelessWidget {
  final List<_HomeFeedItem> items;
  final List<Track> localTracks;
  final Color accentColor;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;

  const _PopularSongsStrip({
    required this.items,
    required this.localTracks,
    required this.accentColor,
    required this.youtubeService,
    required this.onPlaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackGifs = [
      'assets/gif/child.gif',
      'assets/gif/dj.gif',
      'assets/gif/fan.gif',
      'assets/gif/headphones.gif',
      'assets/gif/pianist.gif',
    ];

    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          final gif = fallbackGifs[index % fallbackGifs.length];
          return _PopSongCard(
            item: item,
            localTracks: localTracks,
            accentColor: accentColor,
            isDark: isDark,
            fallbackGif: gif,
            youtubeService: youtubeService,
            onPlaySelected: onPlaySelected,
          );
        },
      ),
    );
  }
}

class _PopSongCard extends StatefulWidget {
  final _HomeFeedItem item;
  final List<Track> localTracks;
  final Color accentColor;
  final bool isDark;
  final String fallbackGif;
  final YoutubeService youtubeService;
  final void Function(List<Track>, int) onPlaySelected;

  const _PopSongCard({
    required this.item,
    required this.localTracks,
    required this.accentColor,
    required this.isDark,
    required this.fallbackGif,
    required this.youtubeService,
    required this.onPlaySelected,
  });

  @override
  State<_PopSongCard> createState() => _PopSongCardState();
}

class _PopSongCardState extends State<_PopSongCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.item.isOnline;
    final onlineAccent = OnlineTheme.accent(widget.isDark);
    final cardBorderColor = isOnline
        ? onlineAccent.withValues(alpha: widget.isDark ? 0.65 : 0.45)
        : widget.accentColor.withValues(alpha: widget.isDark ? 0.25 : 0.15);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (isOnline) {
          OnlinePlaybackHelper.playOnlineTrack(
            context,
            widget.item.onlineTrack!,
            widget.youtubeService,
            widget.onPlaySelected,
            onlineAccent,
          );
        } else {
          final localIdx = widget.localTracks.indexOf(widget.item.localTrack!);
          widget.onPlaySelected(widget.localTracks, localIdx != -1 ? localIdx : 0);
        }
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: cardBorderColor,
                    width: isOnline ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isOnline
                          ? onlineAccent.withValues(alpha: widget.isDark ? 0.22 : 0.12)
                          : Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (isOnline)
                        (widget.item.thumbnailUrl != null && widget.item.thumbnailUrl!.isNotEmpty)
                            ? Image.network(
                                widget.item.thumbnailUrl!,
                                width: 118,
                                height: 118,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) =>
                                    Image.asset(widget.fallbackGif, fit: BoxFit.cover),
                              )
                            : Image.asset(widget.fallbackGif, fit: BoxFit.cover)
                      else
                        TrackArtwork(
                          track: widget.item.localTrack!,
                          width: 118,
                          height: 118,
                          borderRadius: 18,
                          showShadow: false,
                          customFallback:
                              Image.asset(widget.fallbackGif, fit: BoxFit.cover),
                        ),
                      // 3-dot options menu button (top-left)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            TrackActionMenu.show(
                              context,
                              localTrack: widget.item.localTrack,
                              onlineTrack: widget.item.onlineTrack,
                              accentColor: widget.accentColor,
                            );
                          },
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.more_vert_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Pink heart badge if favorite
                      if (_FavoritesScope.isFav(context, feedItem: widget.item))
                        Positioned(
                          top: 6,
                          right: 32,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFF2E7E),
                                width: 1.2,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 12,
                                color: Color(0xFFFF2E7E),
                              ),
                            ),
                          ),
                        ),
                      // Top-right corner source badge
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? (widget.isDark
                                    ? onlineAccent.withValues(alpha: 0.35)
                                    : onlineAccent.withValues(alpha: 0.20))
                                : (widget.isDark
                                    ? Colors.black.withValues(alpha: 0.55)
                                    : Colors.white.withValues(alpha: 0.75)),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isOnline
                                  ? onlineAccent.withValues(alpha: 0.7)
                                  : (widget.isDark
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.black.withValues(alpha: 0.12)),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: AnimatedHomeIcon(
                              isOnline
                                  ? Icons.cloud_rounded
                                  : Icons.phone_android_rounded,
                              size: 12,
                              color: isOnline
                                  ? (widget.isDark
                                      ? const Color(0xFFB4A5FF)
                                      : onlineAccent)
                                  : (widget.isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                      // Duration badge
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            widget.item.formattedDuration,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      // Play button
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isOnline ? onlineAccent : widget.accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isOnline ? onlineAccent : widget.accentColor)
                                    .withValues(alpha: 0.5),
                                blurRadius: 8,
                              )
                            ],
                          ),
                          child: const AnimatedHomeIcon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _HomeColors.primaryText(widget.isDark),
                ),
              ),
              Text(
                widget.item.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 11,
                  color: _HomeColors.secondaryText(widget.isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────── Recently Played / Jump Back In ───────────────────────────

class _RecentlyPlayedRow extends StatelessWidget {
  final List<Track> tracks;
  final Color accentColor;
  final void Function(List<Track>, int) onPlaySelected;

  const _RecentlyPlayedRow({
    required this.tracks,
    required this.accentColor,
    required this.onPlaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = tracks.take(10).toList();

    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: display.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = display[index];
          return GestureDetector(
            onTap: () => onPlaySelected(display, index),
            child: Container(
              width: 265,
              decoration: BoxDecoration(
                color: isDark
                    ? _HomeColors.card(isDark).withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? accentColor.withValues(alpha: 0.20)
                      : accentColor.withValues(alpha: 0.12),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(18)),
                    child: TrackArtwork(
                      track: track,
                      width: 94,
                      height: 94,
                      borderRadius: 18,
                      showShadow: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _HomeColors.primaryText(isDark),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 11,
                            color: _HomeColors.secondaryText(isDark),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: isDark ? 0.18 : 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedHomeIcon(
                                    Icons.history_rounded,
                                    size: 10,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Resume',
                                    style: TextStyle(
                                      fontFamily: AppTypography.uiFont,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_FavoritesScope.isFav(context, localTrack: track)) ...[
                          const Icon(
                            Icons.favorite_rounded,
                            size: 16,
                            color: Color(0xFFFF2E7E),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: isDark ? 0.22 : 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: AnimatedHomeIcon(
                              Icons.play_arrow_rounded,
                              color: accentColor,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            TrackActionMenu.show(
                              context,
                              localTrack: track,
                              accentColor: accentColor,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.more_vert_rounded,
                              size: 18,
                              color: _HomeColors.secondaryText(isDark),
                            ),
                          ),
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
    );
  }
}

// ─────────────────────────── Music List ───────────────────────────

class _MusicListSection extends StatelessWidget {
  final List<Track>? tracks;
  final List<_HomeFeedItem>? items;
  final List<Track>? localTracks;
  final YoutubeService? youtubeService;
  final Color accentColor;
  final void Function(List<Track>, int) onPlaySelected;

  const _MusicListSection({
    this.tracks,
    this.items,
    this.localTracks,
    this.youtubeService,
    required this.accentColor,
    required this.onPlaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int count = items?.length ?? tracks?.length ?? 0;
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _HomeColors.cardBorder(isDark)),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: count,
          separatorBuilder: (_, __) => Divider(
            indent: 72,
            endIndent: 16,
            height: 1,
            color: _HomeColors.divider(isDark),
          ),
          itemBuilder: (context, index) {
            final feedItem = items != null ? items![index] : null;
            final isOnline = feedItem?.isOnline ?? false;
            final onlineAccent = OnlineTheme.accent(isDark);
            final Track? localTrack = feedItem != null ? feedItem.localTrack : (tracks != null ? tracks![index] : null);
            final onlineTrack = feedItem?.onlineTrack;

            final title = isOnline ? (onlineTrack?.title ?? '') : (localTrack?.title ?? '');
            final artist = isOnline ? (onlineTrack?.artist ?? '') : (localTrack?.artist ?? '');
            final durationStr = isOnline ? (onlineTrack?.duration ?? '') : _formatDuration(localTrack?.duration ?? 0);
            final itemAccent = isOnline ? onlineAccent : accentColor;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (isOnline && onlineTrack != null && youtubeService != null) {
                    OnlinePlaybackHelper.playOnlineTrack(
                      context,
                      onlineTrack,
                      youtubeService!,
                      onPlaySelected,
                      onlineAccent,
                    );
                  } else if (localTrack != null) {
                    final allLocals = localTracks ?? (tracks ?? [localTrack]);
                    final idx = allLocals.indexOf(localTrack);
                    onPlaySelected(allLocals, idx != -1 ? idx : 0);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // Number badge
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: index < 3
                                ? itemAccent
                                : _HomeColors.secondaryText(isDark)
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Artwork with source badge (cloud for online, phone for offline)
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: isOnline
                                    ? ((feedItem?.thumbnailUrl != null && feedItem!.thumbnailUrl!.isNotEmpty)
                                        ? Image.network(
                                            feedItem.thumbnailUrl!,
                                            width: 46,
                                            height: 46,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            errorBuilder: (_, _, _) => Container(
                                              color: onlineAccent.withValues(alpha: 0.18),
                                              child: Icon(Icons.cloud_rounded, color: onlineAccent, size: 20),
                                            ),
                                          )
                                        : Container(
                                            color: onlineAccent.withValues(alpha: 0.18),
                                            child: Icon(Icons.cloud_rounded, color: onlineAccent, size: 20),
                                          ))
                                    : (localTrack != null
                                        ? TrackArtwork(
                                            track: localTrack,
                                            width: 46,
                                            height: 46,
                                            borderRadius: 10,
                                            showShadow: false,
                                          )
                                        : Container(
                                            color: accentColor.withValues(alpha: 0.15),
                                            child: const Icon(Icons.music_note_rounded, size: 20),
                                          )),
                              ),
                            ),
                            // Corner source badge exactly like Popular & Featured
                            Positioned(
                              top: 2,
                              right: 2,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? (isDark
                                          ? onlineAccent.withValues(alpha: 0.35)
                                          : onlineAccent.withValues(alpha: 0.20))
                                      : (isDark
                                          ? Colors.black.withValues(alpha: 0.55)
                                          : Colors.white.withValues(alpha: 0.75)),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isOnline
                                        ? onlineAccent.withValues(alpha: 0.7)
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.2)
                                            : Colors.black.withValues(alpha: 0.12)),
                                    width: 1,
                                  ),
                                ),
                                child: Center(
                                  child: AnimatedHomeIcon(
                                    isOnline
                                        ? Icons.cloud_rounded
                                        : Icons.phone_android_rounded,
                                    size: 10,
                                    color: isOnline
                                        ? (isDark
                                            ? const Color(0xFFB4A5FF)
                                            : onlineAccent)
                                        : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title / artist with source tag
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTypography.uiFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _HomeColors.primaryText(isDark),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? onlineAccent.withValues(alpha: isDark ? 0.22 : 0.12)
                                        : accentColor.withValues(alpha: isDark ? 0.20 : 0.10),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isOnline
                                          ? onlineAccent.withValues(alpha: 0.4)
                                          : accentColor.withValues(alpha: 0.3),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isOnline ? Icons.cloud_rounded : Icons.phone_android_rounded,
                                        size: 9.5,
                                        color: isOnline ? onlineAccent : accentColor,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        isOnline ? 'Online' : 'Offline',
                                        style: TextStyle(
                                          fontFamily: AppTypography.uiFont,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: isOnline ? onlineAccent : accentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: AppTypography.uiFont,
                                      fontSize: 12,
                                      color: _HomeColors.secondaryText(isDark),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Duration
                      if (durationStr.isNotEmpty) ...[
                        Text(
                          durationStr,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            color: _HomeColors.secondaryText(isDark),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      AnimatedHomeIcon(Icons.play_circle_fill_rounded,
                          color: itemAccent, size: 24),
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          TrackActionMenu.show(
                            context,
                            localTrack: localTrack,
                            onlineTrack: onlineTrack,
                            accentColor: itemAccent,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: _HomeColors.secondaryText(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────── Recordings Card ───────────────────────────

class _RecordingsCard extends StatefulWidget {
  final List<Track> tracks;
  final Color accentColor;
  final void Function(List<Track>, int) onPlaySelected;

  const _RecordingsCard({
    required this.tracks,
    required this.accentColor,
    required this.onPlaySelected,
  });

  @override
  State<_RecordingsCard> createState() => _RecordingsCardState();
}

class _RecordingsCardState extends State<_RecordingsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shown = _expanded ? widget.tracks.take(8).toList() : [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _HomeColors.cardBorder(isDark)),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            widget.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AnimatedHomeIcon(Icons.mic_rounded,
                          color: widget.accentColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recordings',
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _HomeColors.primaryText(isDark),
                            ),
                          ),
                          Text(
                            '${widget.tracks.length} files',
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 12,
                              color: _HomeColors.secondaryText(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: AnimatedHomeIcon(Icons.keyboard_arrow_down_rounded,
                          color: _HomeColors.secondaryText(isDark),
                          size: 22),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ...shown.asMap().entries.map((entry) {
                final i = entry.key;
                final track = entry.value;
                final isLast = i == shown.length - 1;
                return Column(
                  children: [
                    if (i == 0) Divider(height: 1, color: _HomeColors.divider(isDark)),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            widget.onPlaySelected(widget.tracks, i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: TrackArtwork(
                                  track: track,
                                  width: 40,
                                  height: 40,
                                  borderRadius: 8,
                                  showShadow: false,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily:
                                            AppTypography.uiFont,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _HomeColors
                                            .primaryText(isDark),
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(track.duration),
                                      style: TextStyle(
                                        fontFamily:
                                            AppTypography.uiFont,
                                        fontSize: 11,
                                        color: _HomeColors
                                            .secondaryText(isDark),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedHomeIcon(
                                Icons.play_circle_outline_rounded,
                                color: widget.accentColor,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(
                          height: 1,
                          indent: 68,
                          endIndent: 16,
                          color: _HomeColors.divider(isDark)),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Library Summary Panel ───────────────────────────

// ignore: unused_element
class _LibrarySummaryPanel extends StatelessWidget {
  final List<Track> tracks;
  final Color accentColor;
  final VoidCallback onRescan;

  const _LibrarySummaryPanel({
    required this.tracks,
    required this.accentColor,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final artistsCount =
        tracks.map((t) => t.artist).toSet().length;
    final albumsCount = tracks
        .map((t) => t.album)
        .where((a) => a != null && a.isNotEmpty && a != 'Unknown Album')
        .toSet()
        .length;
    final totalDurationMs =
        tracks.fold<int>(0, (sum, t) => sum + (t.duration ?? 0));
    final hours = (totalDurationMs / (1000 * 60 * 60)).toStringAsFixed(1);
    final shortCount =
        tracks.where((t) => (t.duration ?? 0) < 60000).length;
    final totalMb = tracks.length * 4.2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    accentColor.withValues(alpha: 0.20),
                    _HomeColors.card(isDark).withValues(alpha: 0.72),
                    _HomeColors.surface(isDark).withValues(alpha: 0.90),
                  ]
                : [
                    accentColor.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.92),
                    Colors.white.withValues(alpha: 0.85),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: accentColor.withValues(alpha: isDark ? 0.32 : 0.22),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: isDark ? 0.16 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: accentColor.withValues(alpha: isDark ? 0.40 : 0.28),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: isDark ? 0.25 : 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: AnimatedHomeIcon(Icons.auto_graph_rounded,
                      color: accentColor, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Library Summary',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _HomeColors.primaryText(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Cohesive glowing stat chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(
                  value: '${tracks.length}',
                  label: 'Songs',
                  icon: Icons.music_note_rounded,
                  iconColor: accentColor,
                  isDark: isDark,
                ),
                _StatChip(
                  value: '$shortCount',
                  label: 'Short',
                  icon: Icons.timelapse_rounded,
                  iconColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                _StatChip(
                  value: '${hours}h',
                  label: 'Playtime',
                  icon: Icons.headphones_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  isDark: isDark,
                ),
                _StatChip(
                  value: '${totalMb.toStringAsFixed(0)}MB',
                  label: 'Storage',
                  icon: Icons.cloud_done_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: _HomeColors.divider(isDark)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniLabel(
                  Icons.person_rounded,
                  '$artistsCount Artists',
                  accentColor,
                  isDark,
                ),
                _miniLabel(
                  Icons.album_rounded,
                  '$albumsCount Albums',
                  const Color(0xFF8B5CF6),
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onRescan();
                },
                icon: const AnimatedHomeIcon(Icons.refresh_rounded, size: 18),
                label: const Text('Rescan Library'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 4,
                  shadowColor: accentColor.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniLabel(
      IconData icon, String text, Color iconColor, bool isDark) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.18 : 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: iconColor.withValues(alpha: isDark ? 0.30 : 0.18),
              width: 1,
            ),
          ),
          child: Center(
            child: AnimatedHomeIcon(icon, size: 14, color: iconColor),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _HomeColors.primaryText(isDark),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  const _StatChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: isDark ? 0.18 : 0.10),
            shape: BoxShape.circle,
            border: Border.all(
              color: iconColor.withValues(alpha: isDark ? 0.38 : 0.24),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: AnimatedHomeIcon(icon, color: iconColor, size: 19),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: _HomeColors.primaryText(isDark),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.uiFont,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _HomeColors.secondaryText(isDark),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Low / Empty Music Prompt Card ───────────────────────────

class _LowMusicPromptCard extends StatelessWidget {
  final Color accentColor;
  final bool isDark;
  final bool isCompletelyEmpty;
  final int trackCount;
  final VoidCallback onSwitchToOnline;
  final VoidCallback? onRescan;

  const _LowMusicPromptCard({
    required this.accentColor,
    required this.isDark,
    required this.isCompletelyEmpty,
    this.trackCount = 0,
    required this.onSwitchToOnline,
    this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final onlineColor = OnlineTheme.accent(isDark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    onlineColor.withValues(alpha: 0.18),
                    const Color(0xFF141724),
                    const Color(0xFF0F111A),
                  ]
                : [
                    onlineColor.withValues(alpha: 0.12),
                    const Color(0xFFF3F0FF),
                    Colors.white,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: onlineColor.withValues(alpha: isDark ? 0.35 : 0.25),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: onlineColor.withValues(alpha: isDark ? 0.18 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: onlineColor.withValues(alpha: isDark ? 0.22 : 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: onlineColor.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.language_rounded,
                      color: onlineColor,
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
                        isCompletelyEmpty
                            ? 'No Local Songs Found'
                            : 'Expand Your Music World',
                        style: TextStyle(
                          fontFamily: AppTypography.displayFont,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: _HomeColors.primaryText(isDark),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCompletelyEmpty
                            ? 'Your device storage has no audio tracks. Explore unlimited trending tracks, curated mixes, and genres online!'
                            : 'You only have $trackCount local track${trackCount == 1 ? '' : 's'}. Switch to the Online tab to discover curated mixes, top hits, and new releases.',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 12.5,
                          height: 1.4,
                          color: _HomeColors.secondaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onSwitchToOnline();
                    },
                    icon: const Icon(Icons.stream_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'Explore Online Music',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: onlineColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 3,
                      shadowColor: onlineColor.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                if (onRescan != null) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onRescan!();
                    },
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: _HomeColors.primaryText(isDark),
                    ),
                    label: Text(
                      'Rescan',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _HomeColors.primaryText(isDark),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      side: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Empty State ───────────────────────────

class _EmptyStateCard extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onAction;

  const _EmptyStateCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _HomeColors.cardBorder(isDark)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedHomeIcon(icon, size: 56, color: accentColor),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _HomeColors.primaryText(isDark),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 14,
                color: _HomeColors.secondaryText(isDark),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Helpers ───────────────────────────

String _formatDuration(int? ms) {
  return formatDurationMs(ms);
}
