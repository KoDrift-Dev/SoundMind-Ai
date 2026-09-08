import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages user settings, personalization (User Name), theme selection,
/// and onboarding completion status across the application.
class UserPreferencesService extends ChangeNotifier {
  UserPreferencesService._internal();

  static final UserPreferencesService instance =
      UserPreferencesService._internal();

  static const String _keyUserName = 'sm_user_name';
  static const String _keyThemeOne = 'sm_is_theme_one';
  static const String _keyOnboardingDone = 'sm_onboarding_completed';
  static const String _keyGenreOnboardingDone = 'has_completed_genre_onboarding';
  static const String _keyDownloadFolderChoice = 'sm_download_folder_choice';
  static const String _keyCustomDownloadPath = 'sm_custom_download_path';
  static const String _keyDefaultDownloadQuality = 'sm_default_download_quality';
  static const String _keyDefaultDownloadFormat = 'sm_default_download_format';
  static const String _keyAvatarType = 'sm_avatar_type';
  static const String _keyAvatarValue = 'sm_avatar_value';

  SharedPreferences? _prefs;

  String _userName = 'Music Lover';
  String _avatarType = 'preset'; // 'preset' | 'file'
  String _avatarValue = 'headphones'; // preset ID or file path
  bool _isThemeOne = true; // Default: Dark Mode (Abyss)
  bool _isOnboardingCompleted = false;
  bool _isGenreOnboardingCompleted = false;
  String _downloadFolderChoice = 'default'; // 'default' (Download/SoundMind), 'music' (Music/SoundMind), 'custom'
  String _customDownloadPath = '';
  String _defaultDownloadQuality = 'high'; // 'high' | 'medium' | 'low'
  String _defaultDownloadFormat = 'm4a'; // 'm4a' | 'mp3' | 'wav'
  bool _isInitialized = false;

  String get userName => _userName;
  String get avatarType => _avatarType;
  String get avatarValue => _avatarValue;
  bool get isThemeOne => _isThemeOne;
  bool get isDarkTheme => _isThemeOne;
  bool get isOnboardingCompleted => _isOnboardingCompleted;
  bool get isGenreOnboardingCompleted => _isGenreOnboardingCompleted;
  bool get hasCompletedGenreOnboarding =>
      _prefs?.getBool(_keyGenreOnboardingDone) ?? _isGenreOnboardingCompleted;
  String get downloadFolderChoice => _downloadFolderChoice;
  String get customDownloadPath => _customDownloadPath;
  String get defaultDownloadQuality => _defaultDownloadQuality;
  String get defaultDownloadFormat => _defaultDownloadFormat;
  bool get isInitialized => _isInitialized;

  /// Returns the list of genres the user selected during onboarding.
  List<String> getPreferredGenres() {
    try {
      final raw = _prefs?.getString('preferred_genres');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          if (list.isNotEmpty) return list;
        }
      }
      final list = _prefs?.getStringList('preferred_genres');
      if (list != null && list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('Error getting preferred genres: $e');
    }
    return [];
  }

  /// Updates preferred genres.
  Future<void> setPreferredGenres(List<String> genres) async {
    await _prefs?.setString('preferred_genres', jsonEncode(genres));
    notifyListeners();
  }

  /// Loads persisted settings from disk.
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _userName = _prefs?.getString(_keyUserName) ?? 'Music Lover';
      _isThemeOne = _prefs?.getBool(_keyThemeOne) ?? true;
      _isOnboardingCompleted = _prefs?.getBool(_keyOnboardingDone) ?? false;
      _isGenreOnboardingCompleted =
          _prefs?.getBool(_keyGenreOnboardingDone) ?? false;
      _downloadFolderChoice =
          _prefs?.getString(_keyDownloadFolderChoice) ?? 'default';
      _customDownloadPath = _prefs?.getString(_keyCustomDownloadPath) ?? '';
      _defaultDownloadQuality =
          _prefs?.getString(_keyDefaultDownloadQuality) ?? 'high';
      _defaultDownloadFormat =
          _prefs?.getString(_keyDefaultDownloadFormat) ?? 'm4a';
      _avatarType = _prefs?.getString(_keyAvatarType) ?? 'preset';
      _avatarValue = _prefs?.getString(_keyAvatarValue) ?? 'headphones';
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('UserPreferencesService init error: $e');
      _isInitialized = true;
    }
  }

  /// Sets and saves the default download quality ('high' | 'medium' | 'low').
  Future<void> setDefaultDownloadQuality(String quality) async {
    _defaultDownloadQuality = quality;
    notifyListeners();
    await _prefs?.setString(_keyDefaultDownloadQuality, quality);
  }

  /// Sets and saves the default download format ('m4a' | 'mp3' | 'wav').
  Future<void> setDefaultDownloadFormat(String format) async {
    _defaultDownloadFormat = format;
    notifyListeners();
    await _prefs?.setString(_keyDefaultDownloadFormat, format);
  }

  /// Sets and saves the download folder choice ('default' | 'music' | 'custom').
  Future<void> setDownloadFolderChoice(String choice) async {
    _downloadFolderChoice = choice;
    notifyListeners();
    await _prefs?.setString(_keyDownloadFolderChoice, choice);
  }

  /// Sets and saves a custom download directory path.
  Future<void> setCustomDownloadPath(String path) async {
    _customDownloadPath = path;
    notifyListeners();
    await _prefs?.setString(_keyCustomDownloadPath, path);
  }

  /// Sets and saves the user's name.
  Future<void> setUserName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _userName = trimmed;
    notifyListeners();
    await _prefs?.setString(_keyUserName, _userName);
  }

  /// Sets and saves a preset avatar ('headphones', 'music', 'dj', etc.).
  Future<void> setPresetAvatar(String presetId) async {
    _avatarType = 'preset';
    _avatarValue = presetId;
    notifyListeners();
    await _prefs?.setString(_keyAvatarType, 'preset');
    await _prefs?.setString(_keyAvatarValue, presetId);
  }

  /// Sets and saves a custom image file path for the avatar.
  Future<void> setFileAvatar(String filePath) async {
    _avatarType = 'file';
    _avatarValue = filePath;
    notifyListeners();
    await _prefs?.setString(_keyAvatarType, 'file');
    await _prefs?.setString(_keyAvatarValue, filePath);
  }

  /// Sets and saves the theme selection (true = Dark, false = Light).
  Future<void> setTheme(bool isThemeOne) async {
    _isThemeOne = isThemeOne;
    notifyListeners();
    await _prefs?.setBool(_keyThemeOne, _isThemeOne);
  }

  /// Sets and saves the onboarding completion state.
  Future<void> setOnboardingCompleted(bool completed) async {
    _isOnboardingCompleted = completed;
    notifyListeners();
    await _prefs?.setBool(_keyOnboardingDone, _isOnboardingCompleted);
  }

  /// Sets and saves the genre onboarding completion state.
  Future<void> setGenreOnboardingCompleted(bool completed) async {
    _isGenreOnboardingCompleted = completed;
    // Do not call notifyListeners() here: main.dart's ListenableBuilder rebuilds
    // MaterialApp on notifyListeners(), which would recreate SplashScreen and cause a loop!
    await _prefs?.setBool(_keyGenreOnboardingDone, _isGenreOnboardingCompleted);
  }

  /// Resets onboarding status to allow the user to replay the intro.
  Future<void> resetOnboarding() async {
    _isOnboardingCompleted = false;
    notifyListeners();
    await _prefs?.setBool(_keyOnboardingDone, false);
  }
}
