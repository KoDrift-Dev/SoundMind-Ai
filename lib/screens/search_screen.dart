import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/constants/app_strings.dart';
import '../core/constants/app_typography.dart';
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import '../services/audio_library_service.dart';
import '../widgets/track_artwork.dart';
import '../online/models/online_search_result.dart';
import '../services/youtube_service.dart';
import '../services/online_playback_helper.dart';
import '../widgets/track_action_menu.dart';
import '../services/user_preferences_service.dart';
import '../utils/duration_formatter.dart';
import '../utils/song_heuristics.dart';

const List<String> kBrowseGenres = [
  'All', 'Trending', 'Pop', 'Rock', 'Hip Hop', 'Classical', 'Qawali', 'Sufi', 
  'Jazz', 'Lo-fi', 'Slow and Reverb', 'EDM', 'Bollywood', 'Hollywood', 'Coke Studio', 
  'Punjabi', 'Indie', 'Acoustic', 'Instrumental', 'Devotional', 'Ghazal', 'R&B', 
  'Trap', 'Ambient', 'Folk',
];

// ─── Color helpers (mirroring home screen) ───

class _SC {
  static Color primary(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF0D1117);
  static Color border(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : const Color(0xFFCBD5E1);
  static Color secondary(bool isDark) =>
      isDark ? const Color(0xFF8B9CB5) : const Color(0xFF64748B);
}

// ─── Main Widget ───

class SearchScreen extends StatefulWidget {
  final Color accentColor;
  final bool isThemeOne;
  final List<Track> localTracks;
  final void Function(List<Track> playlist, int index) onPlaySelected;

  static void switchToOnlineMode() {
    _SearchScreenState.instance?.switchToOnline();
  }

  const SearchScreen({
    super.key,
    required this.accentColor,
    this.isThemeOne = true,
    required this.onPlaySelected,
    this.localTracks = const [],
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  static _SearchScreenState? instance;

  void switchToOnline() {
    if (mounted) {
      setState(() {
        _isLocalMode = false;
      });
    }
  }

  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _query = '';
  bool _isLocalMode = false;
  String _selectedGenre = 'All';

  List<String> get _browseGenres {
    final preferred = UserPreferencesService.instance.getPreferredGenres();
    if (preferred.isNotEmpty) {
      return ['All', ...preferred];
    }
    return kBrowseGenres;
  }

  List<Track> _localTracks = [];
  List<Track> _localResults = [];
  final List<String> _localRecentSearches = [];
  final List<String> _onlineRecentSearches = [];
  List<String> _liveSuggestions = [];
  Timer? _suggestDebounce;
  String _activeOnlineCategory = 'Songs';

  Timer? _debounce;
  List<OnlineSearchResult> _onlineResults = [];
  bool _isOnlineLoading = false;
  String? _onlineError;
  final YoutubeService _youtubeService = YoutubeService();

  List<OnlineSearchResult> _browseResults = [];
  bool _isBrowseLoading = true;
  bool _isBrowseLoadingMore = false;
  String? _browseError;
  int _browsePage = 0; // track how many pages/queries have been loaded
  final ScrollController _browseScrollController = ScrollController();
  final ScrollController _onlineResultsScrollController = ScrollController();
  bool _isOnlineSearchLoadingMore = false;

  // Local tab state
  String? _activeFilterTag;
  int _suggestedCount = 10;
  bool _isLocalLoadingMore = false;
  final ScrollController _localScrollController = ScrollController();

  // Voice search
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    instance = this;
    _localTracks = List.from(widget.localTracks);
    if (_localTracks.isEmpty) _loadDeviceTracks();
    _loadSearchHistory();
    _loadBrowseFeed('All');
    _searchFocusNode.addListener(_onSearchFocusChange);
    _browseScrollController.addListener(_onBrowseScroll);
    _onlineResultsScrollController.addListener(_onOnlineSearchScroll);
    _localScrollController.addListener(_onLocalScroll);
    _requestMicAndInitSpeech();
  }

  void _onSearchFocusChange() {
    if (mounted) setState(() {});
  }

  Future<void> _requestMicAndInitSpeech() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        await _initSpeech();
      }
    } catch (_) {}
  }

  void _onBrowseScroll() {
    if (!_browseScrollController.hasClients) return;
    final pos = _browseScrollController.position;
    if (pos.maxScrollExtent > 300 &&
        pos.pixels > 100 &&
        pos.pixels >= pos.maxScrollExtent - 300) {
      if (!_isBrowseLoadingMore && !_isBrowseLoading && _browseResults.isNotEmpty) {
        _loadBrowseFeed(_selectedGenre, loadMore: true);
      }
    }
  }

  void _onLocalScroll() {
    if (!_localScrollController.hasClients || _isLocalLoadingMore) return;
    final pos = _localScrollController.position;
    if (pos.maxScrollExtent > 300 &&
        pos.pixels > 100 &&
        pos.pixels >= pos.maxScrollExtent - 300) {
      final total = _filteredSuggestedTracks.length;
      if (_suggestedCount < total) {
        _isLocalLoadingMore = true;
        setState(() {
          _suggestedCount = (_suggestedCount + 10).clamp(0, total);
        });
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _isLocalLoadingMore = false;
        });
      }
    }
  }

  void _onOnlineSearchScroll() {
    if (!_onlineResultsScrollController.hasClients || _isOnlineSearchLoadingMore) return;
    final pos = _onlineResultsScrollController.position;
    if (pos.maxScrollExtent > 200 &&
        pos.pixels > 100 &&
        pos.pixels >= pos.maxScrollExtent - 300) {
      if (!_isOnlineSearchLoadingMore && !_isOnlineLoading && _onlineResults.isNotEmpty) {
        _loadMoreOnlineSearchResults();
      }
    }
  }

  Future<void> _loadMoreOnlineSearchResults() async {
    if (_isOnlineSearchLoadingMore || _isOnlineLoading || _onlineResults.isEmpty) return;
    setState(() => _isOnlineSearchLoadingMore = true);
    try {
      final more = await _youtubeService.loadMoreSearchVideos();
      if (!mounted) return;
      if (more.isNotEmpty) {
        final existingIds = _onlineResults.map((r) => r.id).toSet();
        final filtered = more.where((r) => !existingIds.contains(r.id)).toList();
        setState(() {
          _onlineResults.addAll(filtered);
        });
      }
    } catch (e) {
      debugPrint('SearchScreen: Error loading more search results: $e');
    } finally {
      if (mounted) {
        setState(() => _isOnlineSearchLoadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    if (instance == this) instance = null;
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _browseScrollController.removeListener(_onBrowseScroll);
    _browseScrollController.dispose();
    _onlineResultsScrollController.removeListener(_onOnlineSearchScroll);
    _onlineResultsScrollController.dispose();
    _localScrollController.removeListener(_onLocalScroll);
    _localScrollController.dispose();
    _youtubeService.dispose();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ─── Speech ───

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        debugLogging: false,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (err) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (mounted) setState(() => _speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _toggleVoiceSearch() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    
    // Check and request microphone permission
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeAccent = _isLocalMode ? widget.accentColor : OnlineTheme.accent(isDark);

    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission permanently denied. Please enable it in settings.'),
            backgroundColor: activeAccent,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    } else if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission is required for voice search.'),
            backgroundColor: activeAccent,
            action: SnackBarAction(
              label: 'Grant',
              textColor: Colors.white,
              onPressed: () async {
                final s = await Permission.microphone.request();
                if (s.isGranted) {
                  await _initSpeech();
                  _toggleVoiceSearch();
                } else if (s.isPermanentlyDenied) {
                  openAppSettings();
                }
              },
            ),
          ),
        );
      }
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
    }

    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Speech recognition is not available on this device.'),
            backgroundColor: activeAccent,
          ),
        );
      }
      return;
    }
    
    _showVoiceSearchModal(activeAccent, isDark);
  }

  void _showVoiceSearchModal(Color activeAccent, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => _VoiceSearchModal(
        speech: _speech,
        accentColor: activeAccent,
        isDark: isDark,
        onSearchSubmitted: (phrase) {
          final clean = phrase.trim();
          if (clean.isNotEmpty) {
            _controller.text = clean;
            _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: clean.length));
            _runSearch(clean);
            _commitToHistory(clean);
            _searchFocusNode.unfocus();
          }
        },
      ),
    );
  }

  List<Track> get _filteredSuggestedTracks {
    var list = _localTracks.where((t) => !isJunkTrack(t)).toList();

    if (_activeFilterTag != null) {
      final tag = _activeFilterTag!.toLowerCase();
      if (tag == 'favorites') {
        list = list.where((t) => t.isFavorite).toList();
      } else if (tag == 'downloads') {
        list = list.where((t) => t.isDownloaded).toList();
      } else {
        list = list.where((t) =>
            t.artist.toLowerCase().contains(tag) ||
            (t.album?.toLowerCase().contains(tag) ?? false) ||
            t.title.toLowerCase().contains(tag)).toList();
      }
    }
    return list;
  }

  // ─── Data Loading ───

  Future<void> _loadDeviceTracks() async {
    try {
      final service = AudioLibraryService();
      final perm = await service.requestPermissions();
      if (perm) {
        final tracks = await service.fetchDeviceTracks();
        if (mounted) {
          setState(() => _localTracks = tracks);
          if (_query.isNotEmpty) _runSearch(_query);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadBrowseFeed(String genre, {bool loadMore = false}) async {
    if (loadMore) {
      if (_isBrowseLoadingMore || _isBrowseLoading) return;
      setState(() => _isBrowseLoadingMore = true);
    } else {
      setState(() {
        _isBrowseLoading = true;
        _browseError = null;
        _browsePage = 0;
      });
    }

    const maxAttempts = 3;
    List<OnlineSearchResult>? results;
    dynamic lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (loadMore) {
          results = await _youtubeService.loadMoreBrowse();
        } else {
          final String query;
          if (genre == 'All' || genre == 'Trending') {
            final preferred = UserPreferencesService.instance.getPreferredGenres();
            if (preferred.isNotEmpty) {
              query = '${preferred.take(3).join(" ")} hits music';
            } else {
              query = 'trending music';
            }
          } else {
            query = YoutubeService.queryForGenre(genre);
          }
          results = await _youtubeService.searchBrowse(query, targetGenre: genre);
        }
        break; // Success
      } catch (e) {
        lastError = e;
        debugPrint('Browse feed attempt $attempt failed for genre "$genre": $e');
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          if (!mounted || _selectedGenre != genre) return;
        }
      }
    }

    if (!mounted || _selectedGenre != genre) return;

    if (results != null) {
      setState(() {
        if (loadMore) {
          final existingIds = _browseResults.map((r) => r.id).toSet();
          final newResults =
              results!.where((r) => !existingIds.contains(r.id)).toList();
          _browseResults.addAll(newResults);
          _browsePage++;
          _isBrowseLoadingMore = false;
        } else {
          _browseResults = results!;
          _isBrowseLoading = false;
        }
        debugPrint('Browse feed: genre="$genre", page=$_browsePage, count=${_browseResults.length}');
      });
    } else {
      setState(() {
        if (loadMore) {
          _isBrowseLoadingMore = false;
        } else {
          _browseError = _formatError(lastError);
          _isBrowseLoading = false;
        }
      });
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localRaw = prefs.getString('local_search_history');
      if (localRaw != null) {
        final decoded = jsonDecode(localRaw);
        if (decoded is List) {
          _localRecentSearches.clear();
          _localRecentSearches.addAll(decoded.map((e) => e.toString()).take(10));
        }
      }
      final onlineRaw = prefs.getString('online_search_history');
      if (onlineRaw != null) {
        final decoded = jsonDecode(onlineRaw);
        if (decoded is List) {
          _onlineRecentSearches.clear();
          _onlineRecentSearches.addAll(decoded.map((e) => e.toString()).take(10));
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSearchHistory(String term) async {
    try {
      final cleanTerm = term.trim();
      if (cleanTerm.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final key = _isLocalMode ? 'local_search_history' : 'online_search_history';
      final target = _isLocalMode ? _localRecentSearches : _onlineRecentSearches;
      target.remove(cleanTerm);
      target.insert(0, cleanTerm);
      if (target.length > 50) {
        target.removeRange(50, target.length);
      }
      await prefs.setString(key, jsonEncode(target));
    } catch (_) {}
  }

  Future<void> _recordOnlinePlayHistory(OnlineSearchResult track) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('online_play_history');
      List<Map<String, dynamic>> history = [];
      if (raw != null) {
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
        'genre': _selectedGenre,
        'timestamp': DateTime.now().toIso8601String(),
      };
      history.insert(0, entry);
      if (history.length > 200) {
        history = history.sublist(0, 200);
      }
      await prefs.setString('online_play_history', jsonEncode(history));
    } catch (e) {
      debugPrint('Error saving online play history: $e');
    }
  }

  String _formatError(dynamic e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socket') || s.contains('host lookup') || s.contains('failed to resolve')) {
      return 'No internet connection. Please check your network.';
    }
    if (s.contains('transientfailureexception') || s.contains('failed to retrieve initial data')) {
      return 'Online search is temporarily unavailable, please try again.';
    }
    return 'Something went wrong loading this. Pull down to try again.';
  }

  // ─── Search Logic (unchanged) ───

  void _runSearch(String value) {
    _query = value;
    _fetchLiveSuggestions(value);
    if (_query.isEmpty) {
      setState(() {
        _localResults = [];
        _onlineResults = [];
        _onlineError = null;
        _liveSuggestions = [];
      });
      return;
    }
    if (_isLocalMode) {
      _runLocalSearch(value);
    } else {
      _runOnlineSearchDebounced(value);
    }
  }

  void _fetchLiveSuggestions(String text) {
    if (_suggestDebounce?.isActive ?? false) _suggestDebounce!.cancel();
    final clean = text.trim();
    if (clean.isEmpty) {
      if (mounted) setState(() => _liveSuggestions = []);
      return;
    }

    _suggestDebounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) return;
      if (_isLocalMode) {
        final q = clean.toLowerCase();
        final matches = <String>{};
        for (final t in _localTracks) {
          if (t.title.toLowerCase().contains(q)) matches.add(t.title);
          if (t.artist.toLowerCase().contains(q) && t.artist != '<unknown>') {
            matches.add(t.artist);
          }
          if (t.album != null &&
              t.album!.toLowerCase().contains(q) &&
              t.album != '<unknown>') {
            matches.add(t.album!);
          }
          if (matches.length >= 8) break;
        }
        if (mounted && _query == text) {
          setState(() => _liveSuggestions = matches.toList());
        }
      } else {
        try {
          final res = await _youtubeService.getQuerySuggestions(clean);
          if (mounted && _query == text) {
            setState(() => _liveSuggestions = res.take(8).toList());
          }
        } catch (_) {}
      }
    });
  }

  String _localFilter = 'All';

  Future<void> _runLocalSearch(String value) async {
    final results = await AudioRepository.instance.searchMusicTracks(value);
    if (!mounted) return;
    setState(() {
      List<Track> unfiltered = [];
      if (results.isNotEmpty) {
        unfiltered = results;
      } else {
        final q = value.toLowerCase();
        unfiltered = _localTracks.where((t) {
          return t.isMusic &&
              (t.title.toLowerCase().contains(q) ||
                  t.artist.toLowerCase().contains(q) ||
                  (t.album?.toLowerCase().contains(q) ?? false));
        }).toList();
      }

      final q = value.toLowerCase();
      if (_localFilter == 'Artists') {
        _localResults = unfiltered.where((t) => t.artist.toLowerCase().contains(q)).toList();
      } else if (_localFilter == 'Albums') {
        _localResults = unfiltered.where((t) => (t.album?.toLowerCase().contains(q) ?? false)).toList();
      } else {
        _localResults = unfiltered; // 'All' or 'Songs'
      }
    });
  }

  void _runOnlineSearchDebounced(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    setState(() {
      _isOnlineLoading = true;
      _onlineError = null;
    });
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      await _runOnlineSearch(value);
    });
  }

  Future<void> _runOnlineSearch(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _onlineResults = [];
          _isOnlineLoading = false;
          _onlineError = null;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isOnlineLoading = true;
        _onlineError = null;
      });
    }

    try {
      const maxAttempts = 3;
      dynamic lastError;
      List<OnlineSearchResult>? results;

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (!mounted || _query != value) return;
        try {
          results = await _youtubeService.searchVideos(value, isManualSearch: true);
          break; // Success
        } catch (e) {
          lastError = e;
          debugPrint('Online search attempt $attempt failed for "$value": $e');
          if (attempt < maxAttempts) {
            await Future.delayed(Duration(milliseconds: 500 * attempt));
          }
        }
      }

      if (!mounted || _query != value) return;

      if (results != null) {
        setState(() {
          _onlineResults = results!;
          _isOnlineLoading = false;
        });
        if (results.isNotEmpty) {
          _saveSearchHistory(value);
        }
      } else {
        setState(() {
          _onlineError = _formatError(lastError);
          _isOnlineLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _onlineError = _formatError(e);
          _isOnlineLoading = false;
        });
      }
    }
  }

  void _commitToHistory(String term) {
    final cleanTerm = term.trim();
    if (cleanTerm.isEmpty) return;
    setState(() {
      final target = _isLocalMode ? _localRecentSearches : _onlineRecentSearches;
      target.remove(cleanTerm);
      target.insert(0, cleanTerm);
      if (target.length > 10) target.removeLast();
    });
    _saveSearchHistory(cleanTerm);
  }

  Future<void> _persistCurrentHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _isLocalMode ? 'local_search_history' : 'online_search_history';
      final target = _isLocalMode ? _localRecentSearches : _onlineRecentSearches;
      if (target.length > 50) {
        target.removeRange(50, target.length);
      }
      await prefs.setString(key, jsonEncode(target));
    } catch (_) {}
  }

  void _handleChipTap(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: term.length));
    _runSearch(term);
    _commitToHistory(term);
    _searchFocusNode.unfocus();
  }

  List<String> _generateQuickChips() {
    final chips = <String>{};
    if (_localTracks.any((t) => t.isFavorite)) chips.add('Favorites');
    if (_localTracks.any((t) => t.isDownloaded)) chips.add('Downloads');
    final artists = _localTracks
        .map((t) => t.artist)
        .where((a) => a.isNotEmpty && a != '<unknown>')
        .toSet()
        .toList();
    artists.take(2).forEach(chips.add);
    final albums = _localTracks
        .map((t) => t.album)
        .where((a) => a != null && a.isNotEmpty && a != '<unknown>')
        .toSet()
        .toList();
    albums.take(2).forEach((a) => chips.add(a!));
    return chips.toList();
  }

  Future<void> _playOnlineTrack(BuildContext context, OnlineSearchResult track) async {
    final success = await OnlinePlaybackHelper.playOnlineTrack(
      context,
      track,
      _youtubeService,
      widget.onPlaySelected,
      widget.accentColor,
    );
    if (success && mounted) {
      _recordOnlinePlayHistory(track);
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF070B14), const Color(0xFF0F1623), const Color(0xFF0A0E1A)]
              : [const Color(0xFFF0F4FF), const Color(0xFFECEFF8), const Color(0xFFE8EDF7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),

                // ── Header ──
                _buildHeader(context, isDark, canPop),
                const SizedBox(height: 16),

                // ── Search Bar ──
                _buildSearchBar(isDark),
                const SizedBox(height: 16),

                // ── Mode Toggle ──
                _buildModeToggle(isDark),
                const SizedBox(height: 16),

                // ── Results / Content ──
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                      child: child,
                    ),
                    child: _isLocalMode
                        ? _buildLocalMode(isDark)
                        : _buildOnlineMode(isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark, bool canPop) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (canPop)
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: _SC.border(isDark)),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: widget.accentColor,
                  size: 16,
                ),
              ),
            ),
          Expanded(
            child: Text(
              'Search',
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: _SC.primary(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    final activeAccent = _isLocalMode ? widget.accentColor : OnlineTheme.accent(isDark);
    final showBack = _searchFocusNode.hasFocus || _query.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _isListening ? activeAccent : _SC.border(isDark),
            width: _isListening ? 1.8 : 1.0,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            if (showBack)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _controller.clear();
                  _runSearch('');
                  _searchFocusNode.unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  child: Icon(Icons.arrow_back_rounded, color: activeAccent, size: 22),
                ),
              )
            else ...[
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, color: activeAccent, size: 22),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _searchFocusNode,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _runSearch,
                onSubmitted: (term) {
                  _commitToHistory(term);
                  _searchFocusNode.unfocus();
                },
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 15,
                  color: _SC.primary(isDark),
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _isLocalMode
                      ? 'Songs, artists, albums…'
                      : 'Search YouTube Music…',
                  hintStyle: TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 15,
                    color: _SC.secondary(isDark),
                  ),
                  isDense: true,
                ),
                cursorColor: activeAccent,
              ),
            ),
            // Clear button
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  _runSearch('');
                  if (_searchFocusNode.hasFocus) {
                    _searchFocusNode.requestFocus();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close_rounded,
                      color: _SC.secondary(isDark), size: 20),
                ),
              ),
            // Mic button
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleVoiceSearch,
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? activeAccent
                          : activeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _isListening ? Colors.white : activeAccent,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _SC.border(isDark)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeTab(
              label: 'Online',
              icon: Icons.language_rounded,
              isSelected: !_isLocalMode,
              accentColor: OnlineTheme.accent(isDark),
              onTap: () {
                HapticFeedback.selectionClick();
                if (_isLocalMode) {
                  _searchFocusNode.unfocus();
                  setState(() => _isLocalMode = false);
                  if (_query.isNotEmpty) _runSearch(_query);
                }
              },
            ),
            _ModeTab(
              label: 'Local Library',
              icon: Icons.library_music_rounded,
              isSelected: _isLocalMode,
              accentColor: widget.accentColor,
              onTap: () {
                HapticFeedback.selectionClick();
                if (!_isLocalMode) {
                  _searchFocusNode.unfocus();
                  setState(() => _isLocalMode = true);
                  if (_query.isNotEmpty) _runSearch(_query);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Local Mode ───

  Widget _buildLocalMode(bool isDark) {
    if (_searchFocusNode.hasFocus && _query.isNotEmpty && _liveSuggestions.isNotEmpty) {
      return ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 140, top: 4),
        itemCount: _liveSuggestions.length,
        itemBuilder: (context, i) {
          final s = _liveSuggestions[i];
          return InkWell(
            onTap: () {
              _controller.text = s;
              _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: s.length));
              _runSearch(s);
              _commitToHistory(s);
              _searchFocusNode.unfocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: widget.accentColor),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      s,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _SC.primary(isDark),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.north_west_rounded,
                        size: 18, color: _SC.secondary(isDark)),
                    onPressed: () {
                      _controller.text = s;
                      _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: s.length));
                      _runSearch(s);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    if (_query.isEmpty) return _buildIdleState(isDark);
    if (_localResults.isEmpty) {
      return _buildEmptyState(
        isDark: isDark,
        icon: Icons.search_off_rounded,
        title: 'No matches found',
        subtitle: 'Try a different song, artist, or album.',
        accentColor: widget.accentColor,
      );
    }
    return Column(
      children: [
        if (_liveSuggestions.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _liveSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _liveSuggestions[i];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _controller.text = s;
                    _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: s.length));
                    _runSearch(s);
                    _commitToHistory(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, size: 13, color: widget.accentColor),
                        const SizedBox(width: 6),
                        Text(
                          s,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _SC.primary(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: ListView.separated(
            key: const ValueKey('local_results'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 140, top: 4),
            itemCount: _localResults.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _TrackTile(
                key: ValueKey(_localResults[index].id ?? index),
                track: _localResults[index],
                accentColor: widget.accentColor,
                isDark: isDark,
                onTap: () {
                  _commitToHistory(_localResults[index].title);
                  widget.onPlaySelected(_localResults, index);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Online Mode ───

  Widget _buildOnlineMode(bool isDark) {
    final onlineAccent = OnlineTheme.accent(isDark);
    if (_searchFocusNode.hasFocus) {
      return _buildOnlineSuggestions(isDark, onlineAccent);
    }
    if (_query.isEmpty) {
      return _buildOnlineDiscovery(isDark);
    }
    if (_isOnlineLoading) {
      return ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 140, top: 4),
        itemCount: 8,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => _SkeletonOnlineTile(isDark: isDark),
      );
    }
    if (_onlineError != null) {
      return RefreshIndicator(
        color: onlineAccent,
        onRefresh: () async => _runOnlineSearchDebounced(_query),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(left: 20, right: 20, top: 80, bottom: 140),
          children: [
            _buildEmptyState(
              isDark: isDark,
              icon: Icons.error_outline_rounded,
              title: 'Search Error',
              subtitle: _onlineError!,
              accentColor: onlineAccent,
            ),
          ],
        ),
      );
    }
    if (_onlineResults.isEmpty) {
      return RefreshIndicator(
        color: onlineAccent,
        onRefresh: () async => _runOnlineSearchDebounced(_query),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(left: 20, right: 20, top: 80, bottom: 140),
          children: [
            _buildEmptyState(
              isDark: isDark,
              icon: Icons.search_off_rounded,
              title: 'No online matches',
              subtitle: 'Try a different keyword.',
              accentColor: onlineAccent,
            ),
          ],
        ),
      );
    }

    final categories = ['Songs', 'Videos', 'Artists', 'Albums'];
    return Column(
      children: [
        if (_liveSuggestions.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _liveSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _liveSuggestions[i];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _controller.text = s;
                    _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: s.length));
                    _runSearch(s);
                    _commitToHistory(s);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: onlineAccent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_rounded, size: 13, color: onlineAccent),
                        const SizedBox(width: 6),
                        Text(
                          s,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _SC.primary(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 40,
          child: ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final selected = _activeOnlineCategory == categories[i];
              return GestureDetector(
                onTap: () => setState(() => _activeOnlineCategory = categories[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? onlineAccent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.white.withValues(alpha: 0.8)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected
                            ? onlineAccent
                            : _SC.border(isDark)),
                  ),
                  child: Text(
                    categories[i],
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : _SC.secondary(isDark),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: onlineAccent,
            onRefresh: () async => _runOnlineSearchDebounced(_query),
            child: ListView.separated(
              controller: _onlineResultsScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.only(bottom: 140, top: 4),
              itemCount: _onlineResults.length + (_isOnlineSearchLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i >= _onlineResults.length) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(onlineAccent),
                        ),
                      ),
                    ),
                  );
                }
                return _OnlineTile(
                  result: _onlineResults[i],
                  accentColor: onlineAccent,
                  isDark: isDark,
                  onTap: () => _playOnlineTrack(context, _onlineResults[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineDiscovery(bool isDark) {
    final onlineAccent = OnlineTheme.accent(isDark);
    return Column(
      children: [
        // ─── Horizontal Genre Chips ───
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _browseGenres.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final genre = _browseGenres[i];
              final selected = _selectedGenre == genre;
              return GestureDetector(
                onTap: () {
                  if (_selectedGenre == genre) return;
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedGenre = genre;
                    _browseResults = [];
                    _browsePage = 0;
                    _isBrowseLoading = true;
                  });
                  _loadBrowseFeed(genre);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? onlineAccent
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.white.withValues(alpha: 0.8)),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? onlineAccent
                          : _SC.border(isDark),
                    ),
                  ),
                  child: Text(
                    genre,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : _SC.secondary(isDark),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // ─── 2-Column Grid Feed ───
        Expanded(
          child: _isBrowseLoading
              ? GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 4,
                    bottom: 140,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: 8,
                  itemBuilder: (_, __) =>
                      _SkeletonBrowseCard(isDark: isDark),
                )
              : _browseError != null && _browseResults.isEmpty
                  ? RefreshIndicator(
                      color: onlineAccent,
                      onRefresh: () => _loadBrowseFeed(_selectedGenre),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 80,
                          bottom: 140,
                        ),
                        children: [
                          _buildEmptyState(
                            isDark: isDark,
                            icon: Icons.wifi_off_rounded,
                            title: 'Connection Error',
                            subtitle: _browseError!,
                            accentColor: onlineAccent,
                          ),
                        ],
                      ),
                    )
                  : _browseResults.isEmpty
                      ? RefreshIndicator(
                          color: onlineAccent,
                          onRefresh: () => _loadBrowseFeed(_selectedGenre),
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.only(
                              left: 20,
                              right: 20,
                              top: 80,
                              bottom: 140,
                            ),
                            children: [
                              _buildEmptyState(
                                isDark: isDark,
                                icon: Icons.music_off_rounded,
                                title: 'Nothing found',
                                subtitle:
                                    'Unable to load tracks for $_selectedGenre.',
                                accentColor: onlineAccent,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: onlineAccent,
                          onRefresh: () => _loadBrowseFeed(_selectedGenre),
                          child: GridView.builder(
                            controller: _browseScrollController,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.only(
                              left: 20,
                              right: 20,
                              top: 4,
                              bottom: 140,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _browseResults.length +
                                (_isBrowseLoadingMore ? 2 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _browseResults.length) {
                                return _SkeletonBrowseCard(isDark: isDark);
                              }
                              final item = _browseResults[i];
                              return _BrowseCard(
                                result: item,
                                accentColor: onlineAccent,
                                isDark: isDark,
                                onTap: () => _playOnlineTrack(context, item),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildOnlineSuggestions(bool isDark, Color onlineAccent) {
    // When the user has typed words, show live word suggestions!
    if (_query.isNotEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 140, top: 4),
        children: [
          if (_liveSuggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: _SectionLabel(
                label: 'Search Suggestions',
                icon: Icons.auto_awesome_rounded,
                accentColor: onlineAccent,
                isDark: isDark,
              ),
            ),
            ..._liveSuggestions.map((s) {
              return InkWell(
                onTap: () {
                  _controller.text = s;
                  _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length));
                  _runSearch(s);
                  _commitToHistory(s);
                  _searchFocusNode.unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 20, color: onlineAccent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          s,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _SC.primary(isDark),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.north_west_rounded,
                            size: 18, color: _SC.secondary(isDark)),
                        onPressed: () {
                          _controller.text = s;
                          _controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: s.length));
                          _runSearch(s);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else ...[
            InkWell(
              onTap: () {
                _commitToHistory(_query);
                _searchFocusNode.unfocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 20, color: onlineAccent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Search for "$_query"',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _SC.primary(isDark),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    const popularSuggestions = [
      'Trending Now',
      'Coke Studio',
      'Lo-Fi Beats',
      'Top 50 Bollywood',
      'Slowed & Reverb',
      'Punjabi Hits',
      'Sufi Classics',
      'Acoustic Pop',
      'EDM Party',
      'Classical Ragas',
      'Hip Hop Essentials',
      'Ghazals',
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140, top: 8),
      children: [
        // Recent searches section (Online isolated)
        if (_onlineRecentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionLabel(
                  label: AppStrings.recentSearches,
                  icon: Icons.history_rounded,
                  accentColor: onlineAccent,
                  isDark: isDark,
                ),
                GestureDetector(
                  onTap: () {
                    setState(() => _onlineRecentSearches.clear());
                    _persistCurrentHistory();
                  },
                  child: Text(
                    AppStrings.clearAll,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: onlineAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _onlineRecentSearches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final term = _onlineRecentSearches[i];
                return _HistoryChip(
                  term: term,
                  isDark: isDark,
                  accentColor: onlineAccent,
                  onTap: () {
                    _controller.text = term;
                    _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: term.length));
                    _runSearch(term);
                    _commitToHistory(term);
                    _searchFocusNode.unfocus();
                  },
                  onRemove: () {
                    setState(() => _onlineRecentSearches.remove(term));
                    _persistCurrentHistory();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Online Suggestions section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SectionLabel(
            label: 'Popular Searches',
            icon: Icons.auto_awesome_rounded,
            accentColor: onlineAccent,
            isDark: isDark,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 10,
            children: popularSuggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _controller.text = s;
                  _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: s.length));
                  _runSearch(s);
                  _commitToHistory(s);
                  _searchFocusNode.unfocus();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: onlineAccent.withValues(alpha: isDark ? 0.25 : 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_rounded, size: 14, color: onlineAccent),
                      const SizedBox(width: 6),
                      Text(
                        s,
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _SC.primary(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ─── Idle State (Local Library) ───

  Widget _buildIdleState(bool isDark) {
    final quickChips = _generateQuickChips();
    final displayedTracks =
        _filteredSuggestedTracks.take(_suggestedCount).toList();

    return ListView(
      controller: _localScrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        // Voice search prompt
        if (_isLocalMode && _speechAvailable) ...[
          _VoiceSearchPrompt(
            accentColor: widget.accentColor,
            isDark: isDark,
            isListening: _isListening,
            onTap: _toggleVoiceSearch,
          ),
          const SizedBox(height: 20),
        ],

        // Recent searches (Local isolated)
        if (_localRecentSearches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionLabel(
                  label: AppStrings.recentSearches,
                  icon: Icons.history_rounded,
                  accentColor: widget.accentColor,
                  isDark: isDark,
                ),
                GestureDetector(
                  onTap: () {
                    setState(() => _localRecentSearches.clear());
                    _persistCurrentHistory();
                  },
                  child: Text(
                    AppStrings.clearAll,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _localRecentSearches.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final term = _localRecentSearches[i];
                return _HistoryChip(
                  term: term,
                  isDark: isDark,
                  accentColor: widget.accentColor,
                  onTap: () => _handleChipTap(term),
                  onRemove: () {
                    setState(() => _localRecentSearches.remove(term));
                    _persistCurrentHistory();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Suggested For You Header with Side Dropdown Filter & Active Tag
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _SectionLabel(
                      label: 'Suggested For You',
                      icon: Icons.auto_awesome_rounded,
                      accentColor: widget.accentColor,
                      isDark: isDark,
                    ),
                    if (_activeFilterTag != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: widget.accentColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _activeFilterTag!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppTypography.uiFont,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: widget.accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    _activeFilterTag = null;
                                    _suggestedCount = 10;
                                  });
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: widget.accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (quickChips.isNotEmpty)
                PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _activeFilterTag != null
                          ? widget.accentColor.withValues(alpha: 0.15)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _activeFilterTag != null
                            ? widget.accentColor.withValues(alpha: 0.4)
                            : _SC.border(isDark),
                      ),
                    ),
                    child: Icon(
                      Icons.filter_list_rounded,
                      color: _activeFilterTag != null
                          ? widget.accentColor
                          : _SC.secondary(isDark),
                      size: 18,
                    ),
                  ),
                  color: isDark ? const Color(0xFF131B2A) : Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: _SC.border(isDark)),
                  ),
                  offset: const Offset(0, 38),
                  onSelected: (val) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (val == '__ALL__') {
                        _activeFilterTag = null;
                      } else {
                        _activeFilterTag = val;
                      }
                      _suggestedCount = 10;
                    });
                  },
                  itemBuilder: (context) {
                    final textCol = _SC.primary(isDark);
                    return [
                      PopupMenuItem<String>(
                        value: '__ALL__',
                        child: Row(
                          children: [
                            Icon(
                              Icons.all_inclusive_rounded,
                              color: _activeFilterTag == null
                                  ? widget.accentColor
                                  : _SC.secondary(isDark),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'All Tracks',
                              style: TextStyle(
                                color: _activeFilterTag == null
                                    ? widget.accentColor
                                    : textCol,
                                fontFamily: AppTypography.uiFont,
                                fontWeight: _activeFilterTag == null
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...quickChips.map((chip) => PopupMenuItem<String>(
                            value: chip,
                            child: Row(
                              children: [
                                Icon(
                                  chip == 'Favorites'
                                      ? Icons.favorite_rounded
                                      : chip == 'Downloads'
                                          ? Icons.download_done_rounded
                                          : Icons.music_note_rounded,
                                  color: _activeFilterTag == chip
                                      ? widget.accentColor
                                      : _SC.secondary(isDark),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  chip,
                                  style: TextStyle(
                                    color: _activeFilterTag == chip
                                        ? widget.accentColor
                                        : textCol,
                                    fontFamily: AppTypography.uiFont,
                                    fontWeight: _activeFilterTag == chip
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ];
                  },
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 2-Column Grid of Filtered Local Tracks (Paginated)
        if (displayedTracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: displayedTracks.length,
              itemBuilder: (context, index) {
                final track = displayedTracks[index];
                return _LocalSuggestedCard(
                  track: track,
                  accentColor: widget.accentColor,
                  isDark: isDark,
                  onTap: () {
                    _commitToHistory(track.title);
                    widget.onPlaySelected(_filteredSuggestedTracks, index);
                  },
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No suggested tracks found in local library',
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 14,
                  color: _SC.secondary(isDark),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accentColor,
  }) {
    final effectiveAccent = accentColor ?? widget.accentColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: effectiveAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: effectiveAccent.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, size: 38, color: effectiveAccent),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _SC.primary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 14,
                color: _SC.secondary(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Label ───

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool isDark;

  const _SectionLabel({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accentColor, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.displayFont,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _SC.primary(isDark),
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

// ─── Mode Tab ───

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isSelected ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.4),
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
                size: 14,
                color: isSelected
                    ? Colors.white
                    : _SC.secondary(isDark),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : _SC.secondary(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Voice Search Prompt ───

class _VoiceSearchPrompt extends StatefulWidget {
  final Color accentColor;
  final bool isDark;
  final bool isListening;
  final VoidCallback onTap;

  const _VoiceSearchPrompt({
    required this.accentColor,
    required this.isDark,
    required this.isListening,
    required this.onTap,
  });

  @override
  State<_VoiceSearchPrompt> createState() => _VoiceSearchPromptState();
}

class _VoiceSearchPromptState extends State<_VoiceSearchPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didUpdateWidget(covariant _VoiceSearchPrompt old) {
    super.didUpdateWidget(old);
    if (widget.isListening && !old.isListening) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isListening && old.isListening) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulse = widget.isListening
                ? 0.94 + _pulseController.value * 0.06
                : 1.0;
            return Transform.scale(
              scale: pulse,
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: widget.isListening
                  ? widget.accentColor.withValues(alpha: 0.15)
                  : (widget.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.8)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isListening
                    ? widget.accentColor.withValues(alpha: 0.5)
                    : _SC.border(widget.isDark),
              ),
              boxShadow: widget.isListening
                  ? [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.25),
                        blurRadius: 20,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: widget.accentColor
                        .withValues(alpha: widget.isListening ? 1.0 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isListening
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded,
                    color: widget.isListening
                        ? Colors.white
                        : widget.accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isListening ? 'Listening…' : 'Search by Voice',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _SC.primary(widget.isDark),
                      ),
                    ),
                    Text(
                      widget.isListening
                          ? 'Say a song, artist or album name'
                          : 'Tap to speak',
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        color: _SC.secondary(widget.isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Local Suggested Card (for 2-column Grid) ───

class _LocalSuggestedCard extends StatelessWidget {
  final Track track;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _LocalSuggestedCard({
    required this.track,
    required this.accentColor,
    required this.isDark,
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
          border: Border.all(color: _SC.border(isDark)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: TrackArtwork(
                  track: track,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 12,
                  showShadow: false,
                ),
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
                color: _SC.primary(isDark),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 11,
                color: _SC.secondary(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── History Chip ───

class _HistoryChip extends StatelessWidget {
  final String term;
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _HistoryChip({
    required this.term,
    required this.isDark,
    required this.accentColor,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, size: 13, color: accentColor),
            const SizedBox(width: 6),
            Text(
              term,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _SC.primary(isDark),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close_rounded,
                  size: 13, color: _SC.secondary(isDark)),
            ),
          ],
        ),
      ),
    );
  }
}



// ─── Track Tile ───

class _TrackTile extends StatefulWidget {
  final Track track;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _TrackTile({
    super.key,
    required this.track,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _pressed
                ? (widget.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.04))
                : (widget.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.85)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _SC.border(widget.isDark)),
            boxShadow: widget.isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: TrackArtwork(
                  track: widget.track,
                  width: 50,
                  height: 50,
                  borderRadius: 10,
                  showShadow: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _SC.primary(widget.isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.track.artist}${widget.track.duration != null ? " • ${formatDurationMs(widget.track.duration)}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        color: _SC.secondary(widget.isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill_rounded,
                  color: widget.accentColor, size: 26),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  TrackActionMenu.show(
                    context,
                    localTrack: widget.track,
                    accentColor: widget.accentColor,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: _SC.secondary(widget.isDark),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Online Tile ───

class _OnlineTile extends StatelessWidget {
  final OnlineSearchResult result;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _OnlineTile({
    required this.result,
    required this.accentColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.22 : 0.16),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: result.thumbnailUrl != null
                    ? Image.network(
                        result.thumbnailUrl!,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _SC.primary(isDark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${result.artist}${result.duration != null && result.duration!.isNotEmpty ? " • ${formatDurationString(result.duration)}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        color: _SC.secondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill_rounded,
                  color: accentColor, size: 26),
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  TrackActionMenu.show(
                    context,
                    onlineTrack: result,
                    accentColor: accentColor,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: _SC.secondary(isDark),
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.album_rounded, color: accentColor, size: 24),
      );
}

// ─── Browse Card (for 2-column Grid) ───

class _BrowseCard extends StatelessWidget {
  final OnlineSearchResult result;
  final Color accentColor;
  final bool isDark;
  final VoidCallback onTap;

  const _BrowseCard({
    required this.result,
    required this.accentColor,
    required this.isDark,
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
            color: accentColor.withValues(alpha: isDark ? 0.22 : 0.16),
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: result.thumbnailUrl != null
                    ? Image.network(
                        result.thumbnailUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _SC.primary(isDark),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${result.artist}${result.duration != null && result.duration!.isNotEmpty ? " • ${formatDurationString(result.duration)}" : ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 11,
                      color: _SC.secondary(isDark),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    TrackActionMenu.show(
                      context,
                      onlineTrack: result,
                      accentColor: accentColor,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: 16,
                      color: _SC.secondary(isDark),
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

  Widget _placeholder() => Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.album_rounded, color: accentColor, size: 36),
      );
}

// ─── Pulse Shimmer & Skeleton Loaders ───

class _PulseShimmer extends StatefulWidget {
  final Widget child;
  const _PulseShimmer({required this.child});

  @override
  State<_PulseShimmer> createState() => _PulseShimmerState();
}

class _PulseShimmerState extends State<_PulseShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

class _SkeletonBrowseCard extends StatelessWidget {
  final bool isDark;
  const _SkeletonBrowseCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return _PulseShimmer(
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _SC.border(isDark)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: placeholderColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 13,
              width: double.infinity,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 10,
              width: 80,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonOnlineTile extends StatelessWidget {
  final bool isDark;
  const _SkeletonOnlineTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return _PulseShimmer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _SC.border(isDark)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 50,
                height: 50,
                color: placeholderColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 10,
                    width: 100,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: placeholderColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Voice Search Animated Modal ───

class _VoiceSearchModal extends StatefulWidget {
  final stt.SpeechToText speech;
  final Color accentColor;
  final bool isDark;
  final ValueChanged<String> onSearchSubmitted;

  const _VoiceSearchModal({
    required this.speech,
    required this.accentColor,
    required this.isDark,
    required this.onSearchSubmitted,
  });

  @override
  State<_VoiceSearchModal> createState() => _VoiceSearchModalState();
}

class _VoiceSearchModalState extends State<_VoiceSearchModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String _liveWords = '';
  double _soundLevel = 0.0;
  bool _isDone = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _startListening();
  }

  void _startListening() {
    if (_isDone) return;
    setState(() {
      _isListening = true;
      _liveWords = '';
    });
    try {
      widget.speech.listen(
        onResult: (result) {
          if (!mounted || _isDone) return;
          setState(() {
            _liveWords = result.recognizedWords;
          });
          if (result.finalResult && _liveWords.trim().isNotEmpty) {
            _isDone = true;
            HapticFeedback.mediumImpact();
            final phrase = _liveWords.trim();
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) {
                Navigator.of(context).pop();
                widget.onSearchSubmitted(phrase);
              }
            });
          }
        },
        onSoundLevelChange: (level) {
          if (mounted) {
            setState(() {
              _soundLevel = ((level.clamp(-2.0, 10.0) + 2.0) / 12.0).clamp(0.0, 1.0);
            });
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.search,
          cancelOnError: false,
          partialResults: true,
        ),
      );
    } catch (_) {}
  }

  void _stopListening() {
    try {
      widget.speech.stop();
    } catch (_) {}
    if (mounted) setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (widget.speech.isListening) {
      widget.speech.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF131826) : Colors.white;
    final primaryColor = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.6)
        : const Color(0xFF64748B);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulseScale = 1.0 + (_pulseController.value * 0.18) + (_soundLevel * 0.22);
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag pill
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Header with close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening
                              ? const Color(0xFF10B981)
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isListening ? 'Listening...' : 'Tap mic to speak',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.accentColor,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: secondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),

              // Animated Pulsing Mic Visualizer
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer glow ring
                      if (_isListening)
                        Transform.scale(
                          scale: pulseScale * 1.35,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.accentColor.withValues(
                                alpha: (0.12 * (1.0 - _pulseController.value)).clamp(0.02, 0.15),
                              ),
                            ),
                          ),
                        ),
                      // Middle pulse ring
                      if (_isListening)
                        Transform.scale(
                          scale: pulseScale * 1.15,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.accentColor.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                      // Core button
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening
                              ? widget.accentColor
                              : widget.accentColor.withValues(alpha: 0.2),
                          boxShadow: [
                            BoxShadow(
                              color: widget.accentColor.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening ? Colors.white : widget.accentColor,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Sound Wave Visualizer Bars
              if (_isListening)
                SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final wave = (math.sin((_pulseController.value * 2 * math.pi) + (index * 0.8)) + 1) / 2;
                      final barHeight = (8 + (wave * 18 * (_soundLevel > 0.1 ? 1.4 : 0.6))).clamp(6.0, 26.0);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 4,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: widget.accentColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                )
              else
                const SizedBox(height: 28),
              const SizedBox(height: 16),

              // Live Transcript Area
              Container(
                constraints: const BoxConstraints(minHeight: 52),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _liveWords.isNotEmpty
                      ? Text(
                          '“$_liveWords”',
                          key: ValueKey(_liveWords),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: primaryColor,
                            letterSpacing: -0.3,
                          ),
                        )
                      : Text(
                          'Speak now... Say song, artist, or album',
                          key: const ValueKey('prompt'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: secondaryColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),

              // Submit button if words are recognized
              if (_liveWords.trim().isNotEmpty && !_isDone) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _isDone = true;
                    Navigator.of(context).pop();
                    widget.onSearchSubmitted(_liveWords.trim());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.accentColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.search_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Search Now',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}