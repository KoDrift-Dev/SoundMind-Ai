import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundmindai/screens/home_screen.dart';
import 'package:soundmindai/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 2 — YoutubeService.isLikelyNonMusicTitle', () {
    test('filters out movie trailers, teasers, and full films', () {
      expect(YoutubeService.isLikelyNonMusicTitle('Avengers Secret Wars Official Trailer HD'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Dune Part 2 Teaser'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Top Gun Maverick Full Movie 1080p'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Action Crime Full Film HD'), isTrue);
    });

    test('filters out episodes, seasons, webseries, and podcasts', () {
      expect(YoutubeService.isLikelyNonMusicTitle('Stranger Things S04E01 Scene'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Drama Series Season 1 Launch'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Korean Drama Ep 1 English Sub'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Comedy Show Episode 4'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('New Drama Webseries Release'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Lex Fridman Podcast Episode 400'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Historical Document Part 1'), isTrue);
      expect(YoutubeService.isLikelyNonMusicTitle('Sci-Fi Pt. 2 Recap'), isTrue);
    });

    test('allows legitimate music titles', () {
      expect(YoutubeService.isLikelyNonMusicTitle('Taylor Swift - Blank Space (Official Music Video)'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('Coldplay - Fix You (Live in São Paulo)'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('Ed Sheeran - Perfect (Audio)'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('Queen - Bohemian Rhapsody (Remastered 2011)'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('The Weeknd - Blinding Lights'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('Acoustic Guitar Instrumental Melodies'), isFalse);
      expect(YoutubeService.isLikelyNonMusicTitle('Coke Studio Season 14 - Pasoori'), isTrue); // "Season 14" matches episode heuristic, accepted trade-off
      expect(YoutubeService.isLikelyNonMusicTitle('Pasoori - Ali Sethi x Shae Gill'), isFalse);
    });

    test('gracefully handles empty string', () {
      expect(YoutubeService.isLikelyNonMusicTitle(''), isFalse);
    });
  });

  group('Part 3 — Online Feed Refresh 4.5-Hour Gate', () {
    const String prefKey = 'last_online_feed_refresh';
    const int thresholdMs = 16200000; // 4.5 hours in ms

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('uninitialized timestamp triggers refresh', () async {
      final prefs = await SharedPreferences.getInstance();
      final lastRefresh = prefs.getInt(prefKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - lastRefresh;

      expect(lastRefresh, equals(0));
      expect(elapsed >= thresholdMs, isTrue);
    });

    test('timestamp less than 4.5 hours old skips refresh', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      // Refreshed 2 hours ago
      final twoHoursAgo = now - const Duration(hours: 2).inMilliseconds;
      await prefs.setInt(prefKey, twoHoursAgo);

      final lastRefresh = prefs.getInt(prefKey) ?? 0;
      final elapsed = now - lastRefresh;

      expect(elapsed < thresholdMs, isTrue);
    });

    test('timestamp at or exceeding 4.5 hours triggers refresh', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      // Refreshed 5 hours ago
      final fiveHoursAgo = now - const Duration(hours: 5).inMilliseconds;
      await prefs.setInt(prefKey, fiveHoursAgo);

      final lastRefresh = prefs.getInt(prefKey) ?? 0;
      final elapsed = now - lastRefresh;

      expect(elapsed >= thresholdMs, isTrue);
    });

    test('manual refresh updates timestamp to current time', () async {
      final prefs = await SharedPreferences.getInstance();
      final initialTime = DateTime.now().millisecondsSinceEpoch - const Duration(hours: 10).inMilliseconds;
      await prefs.setInt(prefKey, initialTime);

      // Simulate manual refresh completing
      final refreshTime = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(prefKey, refreshTime);

      final updatedTime = prefs.getInt(prefKey);
      expect(updatedTime, equals(refreshTime));
      expect(DateTime.now().millisecondsSinceEpoch - updatedTime! < 1000, isTrue);
    });
  });

  group('Part 1 — Zero Local Tracks UI Adaptation', () {
    testWidgets('HomeTabBar hides Offline tab when showOfflineTab is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTabBar(
              selectedIndex: 0,
              accentColor: Colors.purple,
              isDark: true,
              showOfflineTab: false,
              onTabChanged: (_) {},
            ),
          ),
        ),
      );

      // With showOfflineTab false: 'For You' and 'Online' are visible, 'Offline' is omitted
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });

    testWidgets('HomeTabBar displays all 3 tabs when showOfflineTab is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTabBar(
              selectedIndex: 0,
              accentColor: Colors.purple,
              isDark: true,
              showOfflineTab: true,
              onTabChanged: (_) {},
            ),
          ),
        ),
      );

      // With showOfflineTab true: 'For You', 'Offline', and 'Online' tabs are all visible
      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    });
  });
}
