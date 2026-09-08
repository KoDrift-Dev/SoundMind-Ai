import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/theme/soundmind_theme.dart';
import 'screens/main_navigation.dart';
import 'screens/splash_screen.dart';
import 'services/audio_handler.dart';
import 'services/audio_player_service.dart';
import 'services/download/download_notification_service.dart';
import 'services/equalizer_service.dart';
import 'services/notification_service.dart';
import 'services/user_preferences_service.dart';

/// The single AudioHandler instance for the whole app.
late final SoundMindAudioHandler audioHandler;

/// Global navigator key for notification action routing.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and Firebase Crashlytics
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Firebase / Crashlytics init error: $e');
  }

  // Configure in-memory image cache limits (Flutter relies on memory cache, no unbounded disk cache)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024; // 100 MB
  PaintingBinding.instance.imageCache.maximumSize = 250; // max 250 images

  // Initialize notifications and persistent user preferences before first frame
  try {
    await NotificationService.instance.init();
    await DownloadNotificationService.instance.init();
    DownloadNotificationService.onViewDownloadsRequested = () {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      MainNavigation.navigateToDownloads(subTab: 0);
    };
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }

  try {
    await UserPreferencesService.instance.init();
  } catch (e) {
    debugPrint('UserPreferencesService init error: $e');
  }

  try {
    await EqualizerService.instance.init();
  } catch (e) {
    debugPrint('EqualizerService init error: $e');
  }

  // Register AudioService with native OS
  try {
    audioHandler = await AudioService.init(
      builder: () => SoundMindAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.soundmindai.audio.channel',
        androidNotificationChannelName: 'SoundMind AI Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService init error: $e');
    audioHandler = SoundMindAudioHandler();
  }

  // Restore persisted queue from previous session
  try {
    await AudioPlayerService.instance.restorePersistedQueue();
  } catch (e) {
    debugPrint('Queue restoration error: $e');
  }

  runApp(const SoundMindApp());
}

class SoundMindApp extends StatefulWidget {
  const SoundMindApp({super.key});

  @override
  State<SoundMindApp> createState() => _SoundMindAppState();
}

class _SoundMindAppState extends State<SoundMindApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      try {
        audioHandler.stop();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UserPreferencesService.instance,
      builder: (context, _) {
        final isDark = UserPreferencesService.instance.isDarkTheme;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'SoundMind AI',
          debugShowCheckedModeBanner: false,
          theme: SoundMindTheme.data(isThemeOne: isDark),
          darkTheme: SoundMindTheme.data(isThemeOne: true),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: const SplashScreen(),
        );
      },
    );
  }
}