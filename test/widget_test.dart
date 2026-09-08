import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundmindai/core/theme/soundmind_theme.dart';
import 'package:soundmindai/core/widgets/ambient_background.dart';
import 'package:soundmindai/core/widgets/glass_card.dart';
import 'package:soundmindai/core/widgets/glass_list_tile.dart';
import 'package:soundmindai/core/widgets/page_header.dart';
import 'package:soundmindai/core/widgets/section_header.dart';
import 'package:soundmindai/models/track.dart';
import 'package:soundmindai/screens/welcome_onboarding_screen.dart';
import 'package:soundmindai/services/audio_player_service.dart';
import 'package:soundmindai/services/user_preferences_service.dart';
import 'package:soundmindai/widgets/mini_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UserPreferencesService default values and updates', () async {
    final service = UserPreferencesService.instance;
    expect(service.isThemeOne, isTrue);
    expect(service.isDarkTheme, isTrue);

    await service.setUserName('Maestro');
    expect(service.userName, 'Maestro');

    await service.setTheme(false);
    expect(service.isThemeOne, isFalse);
    expect(service.isDarkTheme, isFalse);

    await service.setTheme(true);
    expect(service.isThemeOne, isTrue);
  });

  testWidgets('WelcomeOnboardingScreen renders Feel Every Beat and Get Ready button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WelcomeOnboardingScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Welcome Headline RichText
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Feel Every Beat'),
      ),
      findsOneWidget,
    );

    // Verify Subtitle and Badge
    expect(
      find.textContaining('AI-Powered Music Experience'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your Music. Your Mood.'),
      findsOneWidget,
    );

    // Verify Get Ready button
    expect(find.text('Get Ready'), findsOneWidget);

    // Tap Get Ready to move to Step 1 (Name Input)
    await tester.tap(find.text('Get Ready'));
    await tester.pumpAndSettle();

    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Continue to Theme'), findsOneWidget);

    // Tap Continue to move to Step 2 (Theme Selection)
    await tester.tap(find.text('Continue to Theme'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Your Vibe'), findsOneWidget);
    expect(find.text('Dark Mode (Abyss)'), findsOneWidget);
    expect(find.text('Light Mode (Frost)'), findsOneWidget);
    expect(find.text("Let's Get Started"), findsOneWidget);

    // Tap Light Mode to switch theme
    await tester.tap(find.text('Light Mode (Frost)'));
    await tester.pumpAndSettle();

    // Tap Dark Mode to switch back
    await tester.tap(find.text('Dark Mode (Abyss)'));
    await tester.pumpAndSettle();
  });

  testWidgets('AmbientBackground renders with blurred artwork in Light and Dark themes',
      (WidgetTester tester) async {
    // Dark Theme
    await tester.pumpWidget(
      MaterialApp(
        theme: SoundMindTheme.data(isThemeOne: true),
        home: const Scaffold(
          body: Stack(
            children: [
              AmbientBackground(isThemeOne: true),
              Center(child: Text('Dark Content')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Dark Content'), findsOneWidget);

    // Light Theme
    await tester.pumpWidget(
      MaterialApp(
        theme: SoundMindTheme.data(isThemeOne: false),
        home: const Scaffold(
          body: Stack(
            children: [
              AmbientBackground(isThemeOne: false),
              Center(child: Text('Light Content')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Light Content'), findsOneWidget);
  });

  testWidgets('Glass components render high contrast text and glowing borders',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SoundMindTheme.data(isThemeOne: false),
        home: Scaffold(
          body: Column(
            children: [
              const PageHeader(
                title: 'Library',
                subtitle: 'Your local collection',
                accentColor: Color(0xFF0284C7),
              ),
              SectionHeader(
                title: 'Albums',
                accentColor: const Color(0xFF0284C7),
                onSeeAll: () {},
              ),
              const GlassCard(
                child: Text('Card Content'),
              ),
              GlassListTile(
                icon: Icons.person_rounded,
                label: 'User Profile',
                subtitle: 'Manage account',
                accentColor: const Color(0xFF0284C7),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Your local collection'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Card Content'), findsOneWidget);
    expect(find.text('User Profile'), findsOneWidget);
    expect(find.text('Manage account'), findsOneWidget);
  });

  testWidgets('AnimatedPlayPauseButton renders and morphs smoothly in Dark and Light modes',
      (WidgetTester tester) async {
    bool tapped = false;

    // Dark Mode
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedPlayPauseButton(
              isPlaying: false,
              isDark: true,
              accentColor: const Color(0xFF00F0FF),
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AnimatedPlayPauseButton), findsOneWidget);

    // Tap button
    await tester.tap(find.byType(AnimatedPlayPauseButton));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tapped, isTrue);

    // Light Mode with playing = true
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AnimatedPlayPauseButton(
              isPlaying: true,
              isDark: false,
              accentColor: const Color(0xFF0284C7),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedPlayPauseButton), findsOneWidget);
  });

  testWidgets('MiniPlayer renders track info, close button, and dismisses on close tap',
      (WidgetTester tester) async {
    final track = Track(
      id: 9999,
      title: 'Neon Horizon',
      artist: 'Cyber Dreamer',
      filePath: '/music/neon.mp3',
      fileSize: 1024,
      duration: 180000,
      confidence: 1.0,
      isMusic: true,
    );

    AudioPlayerService.instance.currentPlaylist = [track];
    AudioPlayerService.instance.testTrackOverride = track;
    AudioPlayerService.instance.notifyListeners();

    await tester.pumpWidget(
      MaterialApp(
        theme: SoundMindTheme.data(isThemeOne: true),
        home: Scaffold(
          body: MiniPlayer(
            accentColor: const Color(0xFF00F0FF),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify track title and artist
    expect(find.text('Neon Horizon'), findsOneWidget);
    expect(find.text('Cyber Dreamer'), findsOneWidget);

    // Verify close button exists
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Tap close button -> triggers dismiss & stop
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Verify queue is cleared and track is null
    expect(AudioPlayerService.instance.currentPlaylist, isEmpty);
    expect(AudioPlayerService.instance.currentTrack, isNull);
  });

  testWidgets('MiniPlayer dismisses and halts playback on downward and horizontal gestures',
      (WidgetTester tester) async {
    final trackDown = Track(
      id: 9998,
      title: 'Downward Beat',
      artist: 'Gesture Master',
      filePath: '/music/down.mp3',
      fileSize: 1024,
      duration: 180000,
      confidence: 1.0,
      isMusic: true,
    );

    // 1. Downward swipe dismiss
    AudioPlayerService.instance.currentPlaylist = [trackDown];
    AudioPlayerService.instance.testTrackOverride = trackDown;
    AudioPlayerService.instance.notifyListeners();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniPlayer(
            accentColor: const Color(0xFF00F0FF),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Downward Beat'), findsOneWidget);

    // Perform downward swipe gesture
    await tester.fling(find.text('Downward Beat'), const Offset(0, 300), 1000.0);
    await tester.pumpAndSettle();

    expect(AudioPlayerService.instance.currentPlaylist, isEmpty);
    expect(AudioPlayerService.instance.currentTrack, isNull);

    // 2. Horizontal swipe dismiss
    final trackHoriz = Track(
      id: 9997,
      title: 'Horizontal Wave',
      artist: 'Swipe Master',
      filePath: '/music/horiz.mp3',
      fileSize: 1024,
      duration: 180000,
      confidence: 1.0,
      isMusic: true,
    );

    AudioPlayerService.instance.currentPlaylist = [trackHoriz];
    AudioPlayerService.instance.testTrackOverride = trackHoriz;
    AudioPlayerService.instance.notifyListeners();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniPlayer(
            accentColor: const Color(0xFF00F0FF),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Horizontal Wave'), findsOneWidget);

    // Perform horizontal swipe gesture
    await tester.fling(find.text('Horizontal Wave'), const Offset(300, 0), 1000.0);
    await tester.pumpAndSettle();

    expect(AudioPlayerService.instance.currentPlaylist, isEmpty);
    expect(AudioPlayerService.instance.currentTrack, isNull);
  });
}

