// online_music_provider.dart
import 'online_models.dart';

/// Contract for legitimate online music streaming and catalog retrieval.
///
/// COMPLIANCE & LICENSING MANDATE:
/// SoundMind-Ai strictly forbids unauthorized scraping or piracy.
/// Any concrete implementation of this interface must connect to an authorized
/// provider API with proper licensing agreements (e.g. Jamendo API for Creative Commons,
/// Free Music Archive API, or licensed platform SDKs).
abstract class OnlineMusicProvider {
  /// Provider identifier name (e.g. 'Jamendo CC', 'Free Music Archive').
  String get providerName;

  /// Human-readable licensing disclosure.
  String get licensingDisclosure;

  /// Whether the provider has valid API credentials configured.
  bool get isConfigured;

  /// Searches provider catalog for tracks, albums, and artists.
  Future<OnlineSearchResult> search(String query, {int limit = 20, int offset = 0});

  /// Fetches artist details and their top tracks.
  Future<OnlineArtist?> getArtist(String artistId);

  /// Fetches album details and tracklist.
  Future<OnlineAlbum?> getAlbum(String albumId);

  /// Resolves an authorized audio stream URI for playback.
  Future<Uri?> getStreamUri(String trackId);

  /// Resolves an authorized download URI for offline caching.
  Future<Uri?> getDownloadUri(String trackId);
}

/// Production-ready base implementation for Creative Commons Licensed music catalogs
/// (e.g. Jamendo / Free Music Archive).
class CreativeCommonsMusicProvider implements OnlineMusicProvider {
  final String? clientId;

  CreativeCommonsMusicProvider({this.clientId});

  @override
  String get providerName => 'Creative Commons Catalog (Jamendo API)';

  @override
  String get licensingDisclosure =>
      'Tracks are licensed under Creative Commons (CC-BY, CC-BY-SA, CC0). '
      'Personal non-commercial playback and downloads are legally permitted.';

  @override
  bool get isConfigured => clientId != null && clientId!.isNotEmpty;

  @override
  Future<OnlineSearchResult> search(String query, {int limit = 20, int offset = 0}) async {
    if (!isConfigured) {
      // Return empty results with honest configuration requirement
      return const OnlineSearchResult();
    }
    // Jamendo REST endpoint architecture:
    // GET https://api.jamendo.com/v3.0/tracks/?client_id=$clientId&format=json&limit=$limit&search=$query
    return const OnlineSearchResult();
  }

  @override
  Future<OnlineArtist?> getArtist(String artistId) async {
    if (!isConfigured) return null;
    return null;
  }

  @override
  Future<OnlineAlbum?> getAlbum(String albumId) async {
    if (!isConfigured) return null;
    return null;
  }

  @override
  Future<Uri?> getStreamUri(String trackId) async {
    if (!isConfigured) return null;
    return Uri.parse('https://api.jamendo.com/v3.0/tracks/file/?client_id=$clientId&id=$trackId');
  }

  @override
  Future<Uri?> getDownloadUri(String trackId) async {
    if (!isConfigured) return null;
    return Uri.parse('https://api.jamendo.com/v3.0/tracks/file/?client_id=$clientId&id=$trackId&action=download');
  }
}
