// audio_library_service.dart
import '../models/track.dart';
import '../repositories/audio_repository.dart';
import 'audio_scanner_service.dart';

/// Service interfacing UI screens with the persistent audio repository and smart scanner.
class AudioLibraryService {
  final AudioScannerService _scanner = AudioScannerService.instance;
  final AudioRepository _repository = AudioRepository.instance;

  Future<bool> requestPermissions() async {
    return await _scanner.requestPermissions();
  }

  /// Fetches verified Music tracks from the database.
  /// If database is empty on first launch, initiates smart audio scan.
  Future<List<Track>> fetchDeviceTracks() async {
    final existingMusic = await _repository.getMusicOnlyTracks();
    if (existingMusic.isNotEmpty) {
      return existingMusic;
    }

    // First scan on empty database
    await _scanner.scan();
    return await _repository.getMusicOnlyTracks();
  }

  /// Triggers a full rescan of device audio files.
  Future<List<Track>> rescanDeviceTracks() async {
    await _scanner.scan(isRescan: true);
    return await _repository.getMusicOnlyTracks();
  }

  /// Fetches all verified music tracks from database.
  Future<List<Track>> fetchMusicTracks({int? limit, int? offset}) async {
    return await _repository.getMusicOnlyTracks(limit: limit, offset: offset);
  }
}