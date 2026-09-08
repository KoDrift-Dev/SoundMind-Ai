import 'dart:convert';
import 'dart:io';
import '../models/online_search_result.dart';
import '../../utils/duration_formatter.dart';

abstract class OnlineMusicProvider {
  Future<List<OnlineSearchResult>> search(String query);
  Future<List<OnlineSearchResult>> getDiscoveryFeeds();
}

class ItunesMusicProvider implements OnlineMusicProvider {
  static const String _searchUrl = 'https://itunes.apple.com/search';
  static const String _rssUrl = 'https://rss.applemarketingtools.com/api/v2/us/music/most-played/25/songs.json';

  @override
  Future<List<OnlineSearchResult>> search(String query) async {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return [];

    final url = Uri.parse('$_searchUrl?term=${Uri.encodeComponent(normalizedQuery)}&entity=song&limit=25');
    final httpClient = HttpClient();
    
    try {
      final request = await httpClient.getUrl(url);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody);
        
        final results = json['results'] as List;
        final List<OnlineSearchResult> tracks = [];
        for (final item in results) {
          final artworkUrl = item['artworkUrl100'] as String?;
          final highResArtwork = artworkUrl?.replaceAll('100x100bb', '600x600bb');
          final millis = item['trackTimeMillis'] as int?;
          if (millis != null) {
            final secs = millis ~/ 1000;
            if (secs < 60 || secs > 1200) continue;
          }

          tracks.add(
            OnlineSearchResult(
              id: item['trackId'].toString(),
              title: item['trackName'] ?? 'Unknown Title',
              artist: item['artistName'] ?? 'Unknown Artist',
              album: item['collectionName'],
              thumbnailUrl: highResArtwork ?? artworkUrl,
              duration: formatDurationMs(millis),
              source: 'iTunes',
              previewUrl: item['previewUrl'],
            ),
          );
        }
        return tracks;
      } else {
        throw Exception('Failed to load search results: ${response.statusCode}');
      }
    } finally {
      httpClient.close();
    }
  }

  @override
  Future<List<OnlineSearchResult>> getDiscoveryFeeds() async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(_rssUrl));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody);
        
        final results = json['feed']['results'] as List;
        return results.map((item) {
          final artworkUrl = item['artworkUrl100'] as String?;
          final highResArtwork = artworkUrl?.replaceAll('100x100bb', '300x300bb');
          
          return OnlineSearchResult(
            id: item['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
            title: item['name'] ?? 'Unknown Title',
            artist: item['artistName'] ?? 'Unknown Artist',
            thumbnailUrl: highResArtwork ?? artworkUrl,
            source: 'iTunes Discovery',
            // RSS feed doesn't provide preview URLs directly, we'd need to lookup by ID to play.
            // For discovery, we will rely on search or provide a dummy preview if absent, 
            // but let's leave it null to signify it needs resolving, or we can fetch lookup.
            previewUrl: null, 
          );
        }).toList();
      } else {
        throw Exception('Failed to load discovery feeds: ${response.statusCode}');
      }
    } finally {
      httpClient.close();
    }
  }
}
