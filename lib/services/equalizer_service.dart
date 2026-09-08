// equalizer_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EqualizerPreset {
  flat('Flat', [0.0, 0.0, 0.0, 0.0, 0.0]),
  bassBoost('Bass Boost', [6.0, 4.5, 1.5, 0.0, 0.0]),
  trebleBoost('Treble Boost', [0.0, 0.0, 1.5, 4.5, 6.0]),
  vocal('Vocal', [-1.5, 2.0, 5.0, 3.0, -1.0]),
  rock('Rock', [4.5, 2.5, -1.0, 2.0, 4.0]),
  pop('Pop', [-1.0, 2.0, 4.0, 2.0, -1.0]),
  jazz('Jazz', [3.0, 1.5, -1.5, 2.0, 3.0]),
  classical('Classical', [4.0, 3.0, 0.0, 2.5, 3.5]),
  electronic('Electronic', [5.0, 3.5, -0.5, 2.0, 4.5]),
  acoustic('Acoustic', [3.5, 2.0, 1.0, 2.5, 3.0]),
  custom('Custom', [0.0, 0.0, 0.0, 0.0, 0.0]);

  final String label;
  /// Gains in dB (-10.0 to +10.0)
  final List<double> gains;
  const EqualizerPreset(this.label, this.gains);

  static EqualizerPreset fromName(String? name) {
    if (name == null) return EqualizerPreset.flat;
    return EqualizerPreset.values.firstWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase(),
      orElse: () => EqualizerPreset.flat,
    );
  }
}

typedef EqualizerPresetType = EqualizerPreset;

class EqualizerBandModel {
  final int index;
  final int centerFreqHz; // in Hz
  final String freqLabel;
  final String bandName;
  int levelMillibels; // in mB (100 mB = 1 dB)

  EqualizerBandModel({
    required this.index,
    required this.centerFreqHz,
    required this.freqLabel,
    required this.bandName,
    required this.levelMillibels,
  });

  double get centerFrequency => centerFreqHz.toDouble();
  double get levelDb => levelMillibels / 100.0;
  double get gain => levelDb;
  set gain(double db) => levelMillibels = (db * 100).round();
}

typedef EqualizerBandInfo = EqualizerBandModel;

/// Real Multi-Band Audio Equalizer Service bridging to Android Native Audio Effects
/// (`android.media.audiofx.Equalizer` and `android.media.audiofx.BassBoost`).
///
/// Features:
/// - Attached directly to ExoPlayer's native AudioSession ID (works identically for local & online).
/// - 10 tuned presets + Custom mode.
/// - Preamp gain & Bass Boost hardware control.
/// - Dynamic device capability query (band count, freq range, level range).
/// - Full SharedPreferences persistence across track changes and app restarts.
/// - Graceful fallback on unsupported platforms / devices.
class EqualizerService extends ChangeNotifier {
  static final EqualizerService instance = EqualizerService._internal();
  EqualizerService._internal();

  static const MethodChannel _channel = MethodChannel('com.soundmindai.equalizer');

  static const String _prefKeyEnabled = 'sm_eq_native_enabled';
  static const String _prefKeyPreset = 'sm_eq_native_preset';
  static const String _prefKeyCustomBands = 'sm_eq_native_custom_bands';
  static const String _prefKeyPreamp = 'sm_eq_native_preamp';
  static const String _prefKeyBassBoost = 'sm_eq_native_bass_boost';

  bool _isSupported = true;
  bool get isSupported => _isSupported;

  bool _isHardwareBound = false;
  bool get isHardwareBound => _isHardwareBound;

  bool _enabled = false;
  bool get isEnabled => _enabled;

  int _currentSessionId = 0;
  int get currentSessionId => _currentSessionId;

  int _minLevelMillibels = -1500; // -15 dB
  int get minLevelMillibels => _minLevelMillibels;

  int _maxLevelMillibels = 1500; // +15 dB
  int get maxLevelMillibels => _maxLevelMillibels;

  double get minLevelDb => _minLevelMillibels / 100.0;
  double get maxLevelDb => _maxLevelMillibels / 100.0;

  int _preampGainMillibels = 0; // -600 to +600 mB (-6.0 dB to +6.0 dB)
  int get preampGainMillibels => _preampGainMillibels;
  double get preampGainDb => _preampGainMillibels / 100.0;
  double get preampGain => preampGainDb;

  int _bassBoostStrength = 0; // 0 to 1000
  int get bassBoostStrength => _bassBoostStrength;

  bool _bassBoostSupported = true;
  bool get bassBoostSupported => _bassBoostSupported;

  EqualizerPreset _currentPreset = EqualizerPreset.flat;
  EqualizerPreset get currentPreset => _currentPreset;

  List<int> _customBandLevels = [];

  List<EqualizerBandModel> _bands = [
    EqualizerBandModel(index: 0, centerFreqHz: 60, freqLabel: '60 Hz', bandName: 'Bass', levelMillibels: 0),
    EqualizerBandModel(index: 1, centerFreqHz: 230, freqLabel: '230 Hz', bandName: 'Low-Mid', levelMillibels: 0),
    EqualizerBandModel(index: 2, centerFreqHz: 910, freqLabel: '910 Hz', bandName: 'Mid', levelMillibels: 0),
    EqualizerBandModel(index: 3, centerFreqHz: 3600, freqLabel: '3.6 kHz', bandName: 'High-Mid', levelMillibels: 0),
    EqualizerBandModel(index: 4, centerFreqHz: 14000, freqLabel: '14 kHz', bandName: 'Treble', levelMillibels: 0),
  ];
  List<EqualizerBandModel> get bands => List.unmodifiable(_bands);

  bool _initialized = false;

  /// Initializes equalizer from persistent storage.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) {
      _isSupported = false;
      _isHardwareBound = false;
    }

    await _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKeyEnabled) ?? false;
      _preampGainMillibels = prefs.getInt(_prefKeyPreamp) ?? 0;
      _bassBoostStrength = prefs.getInt(_prefKeyBassBoost) ?? 0;
      final presetName = prefs.getString(_prefKeyPreset);
      _currentPreset = EqualizerPreset.fromName(presetName);

      final bandsJson = prefs.getString(_prefKeyCustomBands);
      if (bandsJson != null && bandsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(bandsJson);
        _customBandLevels = decoded.map((e) => (e as num).toInt()).toList();
      }

      _recalculateBandLevels();
      notifyListeners();
    } catch (e) {
      debugPrint('EqualizerService: Error loading preferences: $e');
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, _enabled);
      await prefs.setString(_prefKeyPreset, _currentPreset.name);
      await prefs.setInt(_prefKeyPreamp, _preampGainMillibels);
      await prefs.setInt(_prefKeyBassBoost, _bassBoostStrength);
      if (_customBandLevels.isNotEmpty) {
        await prefs.setString(_prefKeyCustomBands, jsonEncode(_customBandLevels));
      }
    } catch (e) {
      debugPrint('EqualizerService: Error saving preferences: $e');
    }
  }

  /// Called whenever a new audio session ID is available from just_audio.
  Future<void> attachToSession(int sessionId) async {
    if (sessionId <= 0 || !Platform.isAndroid) return;
    if (sessionId == _currentSessionId && _isHardwareBound) return;

    _currentSessionId = sessionId;

    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'attachToSession',
        {'sessionId': sessionId},
      );

      if (res != null) {
        _isSupported = (res['isSupported'] as bool?) ?? true;
        _bassBoostSupported = (res['bassBoostSupported'] as bool?) ?? true;
        final rawRange = res['bandLevelRange'] as List<dynamic>?;
        if (rawRange != null && rawRange.length >= 2) {
          _minLevelMillibels = (rawRange[0] as num).toInt();
          _maxLevelMillibels = (rawRange[1] as num).toInt();
        }

        final rawBands = res['bands'] as List<dynamic>?;
        if (rawBands != null && rawBands.isNotEmpty) {
          _buildBandsFromDevice(rawBands);
        }

        _isHardwareBound = true;

        // Configure band levels, preamp, and bass boost BEFORE enabling effect
        // to prevent abrupt audio stepping pops/glitches
        await _channel.invokeMethod('setBassBoostStrength', {'strength': _bassBoostStrength});
        await _channel.invokeMethod('setPreampGain', {'gainMillibels': _preampGainMillibels});
        await _syncBandLevelsToDevice();
        await _channel.invokeMethod('setEnabled', {'enabled': _enabled});

        debugPrint('EqualizerService: Successfully attached to audio session $sessionId (${_bands.length} bands)');
      }
    } on PlatformException catch (e) {
      debugPrint('EqualizerService: PlatformException on attachToSession: $e');
      _isSupported = false;
      _isHardwareBound = false;
    } catch (e) {
      debugPrint('EqualizerService: Error attaching to session: $e');
      _isSupported = false;
      _isHardwareBound = false;
    }

    notifyListeners();
  }

  void _buildBandsFromDevice(List<dynamic> rawBands) {
    final List<EqualizerBandModel> newBands = [];
    for (int i = 0; i < rawBands.length; i++) {
      final b = Map<String, dynamic>.from(rawBands[i] as Map);
      final index = (b['index'] as num?)?.toInt() ?? i;
      final centerMilliHz = (b['centerFreq'] as num?)?.toInt() ?? 0;
      final centerHz = (centerMilliHz / 1000).round();

      String label;
      if (centerHz >= 1000) {
        final khz = centerHz / 1000.0;
        label = '${khz.toStringAsFixed(centerHz % 1000 == 0 ? 0 : 1)} kHz';
      } else {
        label = '$centerHz Hz';
      }

      String bandName;
      if (centerHz < 150) {
        bandName = 'Bass';
      } else if (centerHz < 600) {
        bandName = 'Low-Mid';
      } else if (centerHz < 2000) {
        bandName = 'Mid';
      } else if (centerHz < 6000) {
        bandName = 'High-Mid';
      } else {
        bandName = 'Treble';
      }

      newBands.add(
        EqualizerBandModel(
          index: index,
          centerFreqHz: centerHz,
          freqLabel: label,
          bandName: bandName,
          levelMillibels: 0,
        ),
      );
    }

    if (newBands.isNotEmpty) {
      _bands = newBands;
    }

    _recalculateBandLevels();
  }

  void _recalculateBandLevels() {
    if (_bands.isEmpty) return;

    if (_currentPreset == EqualizerPreset.custom) {
      for (int i = 0; i < _bands.length; i++) {
        if (i < _customBandLevels.length) {
          _bands[i].levelMillibels = _customBandLevels[i].clamp(_minLevelMillibels, _maxLevelMillibels);
        } else {
          _bands[i].levelMillibels = 0;
        }
      }
    } else {
      final presetGains = _currentPreset.gains;
      for (int i = 0; i < _bands.length; i++) {
        double dbGain = 0.0;
        if (_bands.length == presetGains.length) {
          dbGain = presetGains[i];
        } else if (_bands.length == 1) {
          dbGain = presetGains.first;
        } else {
          final t = i / (_bands.length - 1);
          dbGain = _interpolateGain(t, presetGains);
        }

        final mB = (dbGain * 100).round();
        _bands[i].levelMillibels = mB.clamp(_minLevelMillibels, _maxLevelMillibels);
      }
    }
  }

  double _interpolateGain(double t, List<double> gains) {
    if (gains.isEmpty) return 0.0;
    if (gains.length == 1) return gains.first;
    final maxIdx = gains.length - 1;
    final pos = t * maxIdx;
    final lowIdx = pos.floor().clamp(0, maxIdx);
    final highIdx = pos.ceil().clamp(0, maxIdx);
    if (lowIdx == highIdx) return gains[lowIdx];
    final frac = pos - lowIdx;
    return gains[lowIdx] * (1.0 - frac) + gains[highIdx] * frac;
  }

  /// Sets whether the equalizer effects are enabled.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await _savePreferences();

    if (_isHardwareBound && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setEnabled', {'enabled': _enabled});
      } catch (e) {
        debugPrint('EqualizerService: setEnabled error: $e');
      }
    }
  }

  /// Selects one of the 10 presets or Custom.
  Future<void> setPreset(EqualizerPreset preset) async {
    _currentPreset = preset;
    _recalculateBandLevels();
    notifyListeners();
    await _savePreferences();
    await _syncBandLevelsToDevice();
  }

  /// Sets a specific band's level in millibels (manual slider adjustment triggers Custom mode).
  Future<void> setBandLevel(int bandIndex, int levelMillibels) async {
    if (bandIndex < 0 || bandIndex >= _bands.length) return;
    _bands[bandIndex].levelMillibels = levelMillibels.clamp(_minLevelMillibels, _maxLevelMillibels);

    // Switching to custom preset
    _currentPreset = EqualizerPreset.custom;
    _customBandLevels = _bands.map((b) => b.levelMillibels).toList();

    notifyListeners();
    await _savePreferences();

    if (_isHardwareBound && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setBandLevel', {
          'band': bandIndex,
          'levelMillibels': _bands[bandIndex].levelMillibels,
        });
      } catch (e) {
        debugPrint('EqualizerService: setBandLevel error: $e');
      }
    }
  }

  /// Sets a specific band's gain in dB (-10.0 to +10.0 dB).
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    final clampedDb = gainDb.clamp(-10.0, 10.0);
    await setBandLevel(bandIndex, (clampedDb * 100).round());
  }

  /// Sets Preamp gain. Supports both dB (-6.0 to +6.0 dB) or millibels (-600 to +600 mB).
  Future<void> setPreampGain(num gain) async {
    double db;
    if (gain is double || gain.abs() <= 20) {
      db = gain.toDouble().clamp(-6.0, 6.0);
    } else {
      db = (gain.clamp(-600, 600) / 100.0);
    }

    _preampGainMillibels = (db * 100).round();
    notifyListeners();
    await _savePreferences();

    if (_isHardwareBound && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setPreampGain', {
          'gainMillibels': _preampGainMillibels,
        });
      } catch (e) {
        debugPrint('EqualizerService: setPreampGain error: $e');
      }
    }
  }

  /// Sets Bass Boost strength (0 to 1000).
  Future<void> setBassBoostStrength(int strength) async {
    _bassBoostStrength = strength.clamp(0, 1000);
    notifyListeners();
    await _savePreferences();

    if (_isHardwareBound && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setBassBoostStrength', {
          'strength': _bassBoostStrength,
        });
      } catch (e) {
        debugPrint('EqualizerService: setBassBoostStrength error: $e');
      }
    }
  }

  /// Resets all equalizer settings back to Flat.
  Future<void> resetToFlat() async {
    _currentPreset = EqualizerPreset.flat;
    _preampGainMillibels = 0;
    _bassBoostStrength = 0;
    _customBandLevels = List.filled(_bands.length, 0);
    _recalculateBandLevels();
    notifyListeners();
    await _savePreferences();

    if (_isHardwareBound && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setBassBoostStrength', {'strength': 0});
        await _channel.invokeMethod('setPreampGain', {'gainMillibels': 0});
        await _syncBandLevelsToDevice();
      } catch (e) {
        debugPrint('EqualizerService: resetToFlat error: $e');
      }
    }
  }

  Future<void> _syncBandLevelsToDevice() async {
    if (!_isHardwareBound || !Platform.isAndroid) return;
    try {
      final levels = _bands.map((b) => b.levelMillibels).toList();
      await _channel.invokeMethod('setAllBandLevels', {'levels': levels});
    } catch (e) {
      debugPrint('EqualizerService: syncBandLevels error: $e');
    }
  }

  /// Releases native audio effect instances.
  Future<void> release() async {
    if (!_isHardwareBound || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('release');
      _isHardwareBound = false;
      _currentSessionId = 0;
    } catch (e) {
      debugPrint('EqualizerService: release error: $e');
    }
  }
}
