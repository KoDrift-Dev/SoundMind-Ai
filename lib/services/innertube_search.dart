import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// One page of Innertube search results: the videos plus the token needed
/// to load the next page (null when there is no next page).
class InnertubeSearchPage {
  final List<Video> videos;
  final String? continuationToken;

  const InnertubeSearchPage(this.videos, this.continuationToken);
}

/// Searches YouTube through the official Innertube `youtubei/v1/search`
/// endpoint — the same JSON API the YouTube web client itself uses.
///
/// Why this exists: `youtube_explode_dart`'s search scrapes the `/results`
/// HTML page and parses `ytInitialData` out of it. YouTube keeps changing
/// that page (new layouts, consent / bot walls for stale user-agents,
/// region-dependent markup), so HTML scraping is the first thing to break
/// after a YouTube update. The Innertube endpoint returns structured JSON,
/// needs no cookies and no HTML parsing, and behaves the same in every
/// region (verified with gl=PK).
///
/// Robustness rules:
/// - One bad item never fails a whole search: every `videoRenderer` is
///   parsed defensively and skipped when required fields are missing.
/// - The caller ([YoutubeService]) falls back to the library's HTML search
///   if Innertube itself ever fails, so search keeps working either way.
///
/// Pure Dart (no Flutter imports) so this file can be tested standalone.
class InnertubeSearchClient {
  static const String _endpoint = 'https://www.youtube.com/youtubei/v1/search';

  /// Public WEB-client API key used by YouTube's own web app. This is not
  /// a secret — it is embedded in every YouTube web page.
  static const String _apiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  /// WEB client version. Bump this if YouTube starts rejecting the client.
  static const String _clientVersion = '2.20261120.00.00';

  /// Same filter as `youtube_explode_dart`'s `TypeFilters.video`
  /// (videos only, no channels / playlists / shorts shelves).
  static const String _videoOnlyParams = 'EgIQAQ==';

  final Dio _dio;

  InnertubeSearchClient([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Content-Type': 'application/json'},
            ),
          );

  Map<String, dynamic> _requestBody() => {
    'context': {
      'client': {
        'clientName': 'WEB',
        'clientVersion': _clientVersion,
        'hl': 'en',
        'gl': 'PK',
      },
    },
  };

  /// First page of results for [query].
  Future<InnertubeSearchPage> search(String query) async {
    final body = _requestBody()
      ..['query'] = query
      ..['params'] = _videoOnlyParams;
    final data = await _post(body);
    return _parseSearchResponse(data);
  }

  /// Next page using a continuation token from a previous page.
  Future<InnertubeSearchPage> nextPage(String continuationToken) async {
    final body = _requestBody()..['continuation'] = continuationToken;
    final data = await _post(body);
    return _parseContinuationResponse(data);
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_endpoint?key=$_apiKey',
      data: jsonEncode(body),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Innertube search returned an empty body');
    }
    return data;
  }

  InnertubeSearchPage _parseSearchResponse(Map<String, dynamic> data) {
    final videos = <Video>[];
    String? token;
    for (final section in _sectionContents(data)) {
      final map = section is Map<String, dynamic> ? section : null;
      if (map == null) continue;
      if (map.containsKey('itemSectionRenderer')) {
        final items =
            map['itemSectionRenderer']?['contents'] as List? ?? const [];
        for (final item in items) {
          final video = _parseVideoItem(item);
          if (video != null) videos.add(video);
        }
      } else if (map.containsKey('continuationItemRenderer')) {
        token =
            map['continuationItemRenderer']?['continuationEndpoint']?['continuationCommand']?['token']
                as String?;
      }
    }
    return InnertubeSearchPage(videos, token);
  }

  InnertubeSearchPage _parseContinuationResponse(Map<String, dynamic> data) {
    final videos = <Video>[];
    String? token;
    final commands = data['onResponseReceivedCommands'] as List? ?? const [];
    for (final command in commands) {
      final cmd = command is Map<String, dynamic> ? command : null;
      final items =
          cmd?['appendContinuationItemsAction']?['continuationItems']
              as List? ??
          const [];
      for (final item in items) {
        final map = item is Map<String, dynamic> ? item : null;
        if (map == null) continue;
        if (map.containsKey('continuationItemRenderer')) {
          token =
              map['continuationItemRenderer']?['continuationEndpoint']?['continuationCommand']?['token']
                  as String?;
          continue;
        }
        if (map.containsKey('itemSectionRenderer')) {
          // Continuation items arrive wrapped in an itemSectionRenderer,
          // exactly like the first page's sections — the videos live in
          // its `contents`, not at the top level of the item.
          final inner =
              map['itemSectionRenderer']?['contents'] as List? ?? const [];
          for (final innerItem in inner) {
            final video = _parseVideoItem(innerItem);
            if (video != null) videos.add(video);
          }
          continue;
        }
        final video = _parseVideoItem(item);
        if (video != null) videos.add(video);
      }
    }
    return InnertubeSearchPage(videos, token);
  }

  List<dynamic> _sectionContents(Map<String, dynamic> data) {
    try {
      final contents =
          data['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents']
              as List?;
      return contents ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Parses one `videoRenderer` item into a [Video], or null when the item
  /// is not a video or is missing required fields. Never throws.
  Video? _parseVideoItem(dynamic item) {
    try {
      final map = item is Map<String, dynamic> ? item : null;
      final renderer = map?['videoRenderer'] as Map<String, dynamic>?;
      if (renderer == null) return null;

      final videoId = renderer['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) return null;

      final title = _runsText(renderer['title']);
      if (title == null || title.isEmpty) return null;

      final author =
          _runsText(renderer['ownerText']) ??
          _runsText(renderer['longBylineText']) ??
          (renderer['channelName'] is Map
              ? (renderer['channelName'] as Map)['simpleText'] as String?
              : null) ??
          'Unknown';

      final channelId = _channelId(renderer);
      // ChannelId() throws on an invalid id; without a valid channel id
      // the item cannot be represented as a Video, so skip it instead of
      // failing the whole search (same rule as every other bad field).
      if (channelId == null) return null;

      final description =
          _runsText(_firstSnippet(renderer['detailedMetadataSnippets'])) ?? '';

      final durationText = renderer['lengthText']?['simpleText'] as String?;
      final duration = _parseDuration(durationText);

      final publishedText =
          renderer['publishedTimeText']?['simpleText'] as String?;

      final viewCount = _parseViewCount(renderer['viewCountText']);

      return Video(
        VideoId(videoId),
        title,
        author,
        ChannelId(channelId),
        null, // uploadDate: not needed by the app; raw text is below.
        publishedText,
        null, // publishDate
        description,
        duration,
        ThumbnailSet(videoId),
        null, // keywords
        Engagement(viewCount, null, null),
        _isLive(renderer),
      );
    } catch (_) {
      return null;
    }
  }

  String? _channelId(Map<String, dynamic> renderer) {
    try {
      final runs = renderer['ownerText']?['runs'] as List?;
      if (runs == null || runs.isEmpty) return null;
      final first = runs.first as Map?;
      final nav = first?['navigationEndpoint'] as Map?;
      final browseId = nav?['browseEndpoint']?['browseId'] as String?;
      if (browseId == null || browseId.isEmpty) return null;
      if (!ChannelId.validateChannelId(browseId)) return null;
      return browseId;
    } catch (_) {
      return null;
    }
  }

  dynamic _firstSnippet(dynamic snippets) {
    try {
      final list = snippets as List?;
      if (list == null || list.isEmpty) return null;
      return (list.first as Map?)?['snippetText'];
    } catch (_) {
      return null;
    }
  }

  /// Joins the `runs[].text` parts of a title/byline object, falling back
  /// to `simpleText`. Returns null when there is no text at all.
  String? _runsText(dynamic node) {
    try {
      final map = node is Map<String, dynamic> ? node : null;
      if (map == null) return null;
      final runs = map['runs'] as List?;
      if (runs != null && runs.isNotEmpty) {
        final buffer = StringBuffer();
        for (final run in runs) {
          final text = (run as Map?)?['text'] as String?;
          if (text != null) buffer.write(text);
        }
        final joined = buffer.toString().trim();
        if (joined.isNotEmpty) return joined;
      }
      final simple = map['simpleText'] as String?;
      if (simple != null && simple.trim().isNotEmpty) return simple.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parses "M:SS" / "H:MM:SS" the same way youtube_explode_dart does.
  /// Returns null for live / upcoming videos (no length text).
  Duration? _parseDuration(String? text) {
    if (text == null) return null;
    final clean = text.trim();
    if (clean.isEmpty || clean == 'LIVE' || clean == 'SHORTS') return null;
    final parts = clean.split(':');
    try {
      if (parts.length == 1) {
        return Duration(seconds: int.parse(parts.first));
      }
      if (parts.length == 2) {
        return Duration(
          minutes: int.parse(parts[0]),
          seconds: int.parse(parts[1]),
        );
      }
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Parses the view count ("1.2M views", "123,456 views", "No views").
  int _parseViewCount(dynamic node) {
    try {
      final map = node is Map<String, dynamic> ? node : null;
      if (map == null) return 0;
      String? text = map['simpleText'] as String?;
      text ??= _runsText(map);
      if (text == null) return 0;
      final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return 0;
      return int.parse(digits);
    } catch (_) {
      return 0;
    }
  }

  bool _isLive(Map<String, dynamic> renderer) {
    try {
      final badges = renderer['badges'] as List? ?? const [];
      for (final badge in badges) {
        final label =
            (badge as Map?)?['metadataBadgeRenderer']?['label'] as String?;
        if (label != null && label.toUpperCase().contains('LIVE')) {
          return true;
        }
      }
    } catch (_) {
      // ignore
    }
    return false;
  }
}
