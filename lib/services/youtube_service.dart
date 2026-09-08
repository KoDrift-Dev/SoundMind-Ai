import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../online/models/online_search_result.dart';
import '../utils/duration_formatter.dart';

class YoutubeService {
  static final YoutubeService instance = YoutubeService();

  final YoutubeExplode _yt = YoutubeExplode();

  VideoSearchList? _browseSearchList;

  // The User-Agent that matches the androidSdkless client used to fetch streams.
  // The playback request MUST use the same UA so YouTube doesn't reject the URL.
  static const String _androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

  static const Map<String, String> playbackHeaders = {
    'User-Agent': _androidUserAgent,
    'Origin': 'https://www.youtube.com',
  };

  /// Curated search queries per genre in kBrowseGenres focused exclusively on Pakistani and Indian music.
  static const Map<String, String> genreToQuery = {
    'All': 'Pakistani and Indian top hit music songs',
    'Trending': 'trending Pakistani and Indian hit songs latest',
    'Pop': 'Pakistani pop and Bollywood pop hits songs',
    'Rock': 'Pakistani rock and Sufi rock songs',
    'Hip Hop': 'desi hip hop Pakistani Indian rap songs',
    'Classical': 'classical Indian Pakistani raag sangeet',
    'Qawali': 'Qawali Nusrat Fateh Ali Khan Rahat Sabri',
    'Sufi': 'Sufi songs Pakistani Indian',
    'Jazz': 'desi jazz fusion music',
    'Lo-fi': 'desi lofi Pakistani Indian chill songs',
    'Slow and Reverb': 'slowed and reverb Bollywood Pakistani songs',
    'EDM': 'desi EDM remix party songs',
    'Bollywood': 'Bollywood songs playlist latest hits',
    'Hollywood': 'Hollywood soundtrack songs',
    'Coke Studio': 'Coke Studio Pakistan hit songs',
    'Punjabi': 'Punjabi hit songs Pakistani Indian',
    'Indie': 'Pakistani indie and Indian indie songs',
    'Acoustic': 'acoustic unplugged Urdu Hindi songs',
    'Instrumental': 'desi instrumental flute sitar violin music',
    'Devotional': 'devotional spiritual music songs',
    'Ghazal': 'ghazal classics Mehdi Hassan Ghulam Ali Jagjit Singh',
    'R&B': 'desi R&B urban music songs',
    'Trap': 'desi trap beats songs',
    'Ambient': 'ambient relaxing Pakistani Indian music',
    'Folk': 'Pakistani and Indian folk traditional songs',
  };

  /// Returns a curated query for a genre, falling back to '$genre music' if unknown.
  static String queryForGenre(String genre) {
    return genreToQuery[genre] ?? '$genre music';
  }

  /// Keywords identifying religious / devotional content.
  /// Content matching these keywords is excluded globally from search results and feeds
  /// UNLESS the genre being searched is explicitly 'Devotional' or the user's query
  /// explicitly contains one of these keywords.
  static const List<String> negativeContentKeywords = [
    'bhajan',
    'aarti',
    'mandir',
    'devotional',
    'kirtan',
    'stuti',
    'chalisa',
  ];

  /// Returns true if the title or text contains negative religious/devotional keywords.
  static bool hasNegativeKeywords(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final kw in negativeContentKeywords) {
      if (lower.contains(kw)) {
        return true;
      }
    }
    return false;
  }

  /// Heuristic patterns to identify and exclude strong non-music video titles
  /// (movie trailers, drama/TV episodes, full films, web series, podcasts, etc.).
  ///
  /// NOTE: This is a heuristic improvement, not a perfect filter. Some non-music
  /// content may still slip through, and occasionally a legitimately-titled music
  /// piece with overlapping phrasing (e.g. "Part 1") could theoretically be excluded.
  /// This trade-off is accepted to ensure a cleaner, music-first experience.
  static final List<RegExp> nonMusicTitlePatterns = [
    RegExp(r'\b(?:official\s+)?trailer\b', caseSensitive: false),
    RegExp(r'\bteaser\b', caseSensitive: false),
    RegExp(r'\bfull\s+(?:movie|film)\b', caseSensitive: false),
    RegExp(r'\bweb\s*series\b', caseSensitive: false),
    RegExp(r'\bpodcast(?:\s+episode)?\b', caseSensitive: false),
    RegExp(r'\bepisode\b', caseSensitive: false),
    RegExp(r'\b[sS]\d{1,2}\s*[eE]\d{1,2}\b', caseSensitive: false), // e.g. S01E01
    RegExp(r'\bseason\s+\d+\b', caseSensitive: false),               // e.g. Season 1
    RegExp(r'\bep(?:isode)?\.?\s*\d+\b', caseSensitive: false),      // e.g. Ep 1, Ep. 02
    RegExp(r'\b(?:part|pt)\.?\s*\d+\b', caseSensitive: false),       // e.g. Part 1, Pt. 2
    RegExp(r'\bdrama\s+series\b', caseSensitive: false),
  ];

  /// Returns true if the title contains strong non-music signals.
  static bool isLikelyNonMusicTitle(String title) {
    if (title.isEmpty) return false;
    for (final pattern in nonMusicTitlePatterns) {
      if (pattern.hasMatch(title)) {
        return true;
      }
    }
    return false;
  }

  VideoSearchList? _lastSearchList;
  String? _lastSearchQuery;

  List<OnlineSearchResult> _mapVideos(
    Iterable<Video> videos, {
    String? query,
    String? targetGenre,
    bool isManualSearch = false,
  }) {
    // When user manually searches in Search: NO filter applied! All data is displayed without restriction.
    if (isManualSearch) {
      final List<OnlineSearchResult> results = [];
      for (final v in videos) {
        if (v.duration == null) continue;
        final sec = v.duration!.inSeconds;
        // Basic sanity check: skip sub-15s clips or multi-hour livestreams (>3 hours)
        if (sec < 15 || sec > 10800) continue;

        results.add(
          OnlineSearchResult(
            id: v.id.value,
            title: v.title,
            artist: v.author,
            thumbnailUrl: v.thumbnails.highResUrl,
            duration: formatDuration(v.duration),
            source: 'YouTube',
            previewUrl: null,
          ),
        );
      }
      return results;
    }

    final bool allowDevotional =
        (targetGenre != null && targetGenre.trim().toLowerCase() == 'devotional') ||
        (query != null && hasNegativeKeywords(query));

    final List<OnlineSearchResult> results = [];
    for (final v in videos) {
      if (v.duration == null) continue;
      final sec = v.duration!.inSeconds;
      // Filter out non-song content: < 60s (Shorts clips) and > 20 mins (1200s, long videos/podcasts)
      if (sec < 60 || sec > 1200) continue;

      // Filter out non-music content (trailers, drama episodes, full films, etc.)
      if (isLikelyNonMusicTitle(v.title)) continue;

      // Filter out devotional/religious content unless explicitly requested/in Devotional genre
      if (!allowDevotional && hasNegativeKeywords(v.title)) continue;

      results.add(
        OnlineSearchResult(
          id: v.id.value,
          title: v.title,
          artist: v.author,
          thumbnailUrl: v.thumbnails.highResUrl,
          duration: formatDuration(v.duration),
          source: 'YouTube',
          previewUrl: null, // Resolved immediately before playback
        ),
      );
    }
    return results;
  }

  Future<List<OnlineSearchResult>> searchVideos(
    String query, {
    String? targetGenre,
    bool isManualSearch = false,
  }) async {
    try {
      final videos = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 15));
      if (isManualSearch) {
        _lastSearchList = videos;
        _lastSearchQuery = query;
      }
      return _mapVideos(
        videos,
        query: query,
        targetGenre: targetGenre,
        isManualSearch: isManualSearch,
      );
    } on TransientFailureException catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService TransientFailureException: $e');
      rethrow;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService search error (${e.runtimeType}): $e');
      rethrow;
    }
  }

  /// Loads more search results for manual search ("unlimited data").
  Future<List<OnlineSearchResult>> loadMoreSearchVideos() async {
    try {
      if (_lastSearchList == null) return [];
      final nextPage = await _lastSearchList!
          .nextPage()
          .timeout(const Duration(seconds: 15));
      if (nextPage == null) return [];
      _lastSearchList = nextPage;
      return _mapVideos(
        _lastSearchList!,
        query: _lastSearchQuery,
        isManualSearch: true,
      );
    } catch (e) {
      debugPrint('YoutubeService loadMoreSearchVideos error (${e.runtimeType}): $e');
      return [];
    }
  }

  /// Fetches related or similar auto-next tracks for a given online song.
  Future<List<OnlineSearchResult>> getRelatedOrAutoNextTracks(
    String videoId,
    String title,
    String artist,
  ) async {
    final List<OnlineSearchResult> results = [];
    final Set<String> seenIds = {videoId};

    // 1. First attempt: Direct YouTube related videos
    if (videoId.isNotEmpty) {
      try {
        final video = await _yt.videos.get(videoId).timeout(const Duration(seconds: 10));
        final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 10));
        if (related != null) {
          final mapped = _mapVideos(related);
          for (final item in mapped) {
            if (!seenIds.contains(item.id)) {
              seenIds.add(item.id);
              results.add(item);
              if (results.length >= 8) break;
            }
          }
        }
      } catch (e) {
        debugPrint('YoutubeService: getRelatedVideos failed ($e), falling back to search');
      }
    }

    // 2. Second attempt / Fallback: Targeted query based on artist and title
    if (results.length < 5) {
      try {
        final cleanArtist = artist.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
        final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
        final query = cleanArtist.isNotEmpty && !cleanArtist.toLowerCase().contains('unknown')
            ? '$cleanArtist songs'
            : '$cleanTitle music';
        final searchResults = await searchVideos(query);
        for (final item in searchResults) {
          if (!seenIds.contains(item.id)) {
            seenIds.add(item.id);
            results.add(item);
            if (results.length >= 8) break;
          }
        }
      } catch (e) {
        debugPrint('YoutubeService: AutoNext search fallback failed: $e');
      }
    }

    return results;
  }

  Future<List<String>> getQuerySuggestions(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    try {
      final suggestions = await _yt.search
          .getQuerySuggestions(clean)
          .timeout(const Duration(seconds: 8));
      return suggestions.toList();
    } catch (_) {
      return [];
    }
  }

  String? _lastBrowseQuery;
  String? _lastBrowseGenre;

  Future<List<OnlineSearchResult>> searchBrowse(
    String query, {
    String? targetGenre,
  }) async {
    try {
      _lastBrowseQuery = query;
      _lastBrowseGenre = targetGenre;
      _browseSearchList = await _yt.search
          .search(query)
          .timeout(const Duration(seconds: 15));
      return _mapVideos(_browseSearchList!, query: query, targetGenre: targetGenre);
    } on TransientFailureException catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService browse TransientFailureException: $e');
      rethrow;
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService browse error (${e.runtimeType}): $e');
      rethrow;
    }
  }

  Future<List<OnlineSearchResult>> loadMoreBrowse() async {
    try {
      if (_browseSearchList == null) return [];
      final nextPage = await _browseSearchList!
          .nextPage()
          .timeout(const Duration(seconds: 15));
      if (nextPage == null) return [];
      _browseSearchList = nextPage;
      return _mapVideos(_browseSearchList!, query: _lastBrowseQuery, targetGenre: _lastBrowseGenre);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService loadMoreBrowse error (${e.runtimeType}): $e');
      return [];
    }
  }

  final Map<String, _CachedStreamUrl> _streamCache = {};

  Future<String?> getAudioStreamUrl(String videoId) async {
    final overallSw = Stopwatch()..start();

    // 0. Return cached stream URL instantly if valid
    final cached = _streamCache[videoId];
    if (cached != null && cached.isValid) {
      overallSw.stop();
      debugPrint('YoutubeService [PROFILER]: Stream URL served from cache in ${overallSw.elapsedMicroseconds}us for $videoId');
      return cached.url;
    }

    try {
      final manifestSw = Stopwatch()..start();
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidSdkless],
      ).timeout(const Duration(seconds: 15));
      manifestSw.stop();

      // IMPORTANT: audio-only formats are currently the ones YouTube 403s
      // (they trigger a PO Token check that androidSdkless no longer avoids
      // as of mid/late 2026 — yt-dlp itself flagged this client as broken
      // for this exact case in Jan 2026, see yt-dlp issue #15712).
      // Muxed (video+audio combined) streams are NOT affected by this
      // restriction, so we prefer a muxed stream and simply never render
      // its video track — the player will output audio only.
      final selectionSw = Stopwatch()..start();
      String? resolvedUrl;
      if (manifest.muxed.isNotEmpty) {
        // Lowest resolution on purpose: sort by video height ascending (e.g. 144p/240p/360p)
        // to minimize video decoding overhead on mobile chipsets, and then by lowest bitrate.
        // The video track is never rendered, so this prevents ANR/frame-skipping on device.
        final muxedList = manifest.muxed.toList()
          ..sort((a, b) {
            final resComp = a.videoResolution.height.compareTo(b.videoResolution.height);
            if (resComp != 0) return resComp;
            return a.bitrate.compareTo(b.bitrate);
          });
        final muxedInfo = muxedList.first;
        resolvedUrl = muxedInfo.url.toString();
      } else {
        // Fallback: no muxed stream available for this video, try audio-only
        final streamInfo = manifest.audioOnly.withHighestBitrate();
        resolvedUrl = streamInfo.url.toString();
      }
      selectionSw.stop();
      overallSw.stop();

      if (resolvedUrl.isNotEmpty) {
        _streamCache[videoId] = _CachedStreamUrl(resolvedUrl, DateTime.now());
      }

      debugPrint('YoutubeService [PROFILER]: $videoId resolved in ${overallSw.elapsedMilliseconds}ms '
          '(manifestFetch=${manifestSw.elapsedMilliseconds}ms, selection=${selectionSw.elapsedMicroseconds}us)');
      return resolvedUrl;
    } catch (e, stack) {
      overallSw.stop();
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      debugPrint('YoutubeService [PROFILER]: $videoId failed after ${overallSw.elapsedMilliseconds}ms (${e.runtimeType}): $e');
      return null;
    }
  }

  Future<List<MuxedStreamInfo>> getAvailableQualities(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidSdkless],
      ).timeout(const Duration(seconds: 15));
      final muxedList = manifest.muxed.toList()
        ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
      return muxedList;
    } catch (e) {
      debugPrint('YoutubeService getAvailableQualities error (${e.runtimeType}): $e');
      return [];
    }
  }

  Future<MuxedStreamInfo?> getFreshStreamForQuality(String videoId, int itag) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidSdkless],
      ).timeout(const Duration(seconds: 15));
      if (manifest.muxed.isEmpty) return null;
      for (final s in manifest.muxed) {
        if (s.tag == itag) return s;
      }
      // If exact itag not found, fallback to highest bitrate muxed stream
      final sorted = manifest.muxed.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      return sorted.first;
    } catch (e) {
      debugPrint('YoutubeService getFreshStreamForQuality error (${e.runtimeType}): $e');
      return null;
    }
  }

  void clearStreamCache() {
    _streamCache.clear();
  }

  void dispose() {
    _browseSearchList = null;
    _lastBrowseQuery = null;
    _lastBrowseGenre = null;
    _lastSearchList = null;
    _lastSearchQuery = null;
    _streamCache.clear();
    _yt.close();
  }
}

class _CachedStreamUrl {
  final String url;
  final DateTime timestamp;

  const _CachedStreamUrl(this.url, this.timestamp);

  /// YouTube stream URLs are valid for ~6 hours; cached entries are fresh for 3 hours.
  bool get isValid => DateTime.now().difference(timestamp).inHours < 3;
}