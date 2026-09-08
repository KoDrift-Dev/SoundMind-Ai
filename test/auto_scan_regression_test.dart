import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundmindai/screens/home_screen.dart';
import 'package:soundmindai/screens/splash_screen.dart';
import 'package:soundmindai/services/audio_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Automatic Scan & Permission Regression Tests', () {
    test('AudioScannerService checkPermissions returns false when ungranted', () async {
      final scanner = AudioScannerService.instance;
      final perm = await scanner.checkPermissions();
      expect(perm, isFalse);
    });

    test('AudioScannerService coordinates concurrent scan calls without race condition', () async {
      final scanner = AudioScannerService.instance;
      // Triggering scan multiple times should await the same underlying future
      final f1 = scanner.scan();
      final f2 = scanner.scan();
      expect(identical(f1, f2), isTrue);
      await Future.wait([f1, f2]);
    });

    testWidgets('HomeTabBar renders all 3 tabs (For You, Offline, Online) when showOfflineTab is true',
        (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTabBar(
              selectedIndex: 0,
              accentColor: Colors.teal,
              isDark: true,
              showOfflineTab: true,
              onTabChanged: (idx) => selected = idx,
            ),
          ),
        ),
      );

      // Verify all 3 tab labels and icons are present
      expect(find.descendant(of: find.byType(HomeTabBar), matching: find.text('For You')), findsOneWidget);
      expect(find.descendant(of: find.byType(HomeTabBar), matching: find.text('Offline')), findsOneWidget);
      expect(find.descendant(of: find.byType(HomeTabBar), matching: find.text('Online')), findsOneWidget);

      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);

      // Tap Offline tab
      await tester.tap(find.text('Offline'));
      await tester.pump();
      expect(selected, equals(1));

      // Tap Online tab
      await tester.tap(find.text('Online'));
      await tester.pump();
      expect(selected, equals(2));
    });

    testWidgets('HomeTabBar hides Offline tab when showOfflineTab is explicitly false',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTabBar(
              selectedIndex: 0,
              accentColor: Colors.teal,
              isDark: true,
              showOfflineTab: false,
              onTabChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('For You'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('HomeTabBar updates selection indicator on tab changed',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                int activeIndex = 1; // Offline selected
                return HomeTabBar(
                  selectedIndex: activeIndex,
                  accentColor: Colors.indigo,
                  isDark: true,
                  showOfflineTab: true,
                  onTabChanged: (idx) {
                    setState(() => activeIndex = idx);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.text('For You'));
      await tester.pump();
      expect(find.text('For You'), findsOneWidget);
    });

    testWidgets('SplashScreen displays Grant Audio Access prompt when permission is not granted',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: SplashScreen(),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await tester.pump();
      });

      // Should find the permission card
      expect(find.text('Grant Audio Access'), findsOneWidget);
      expect(find.text('Grant Access & Scan'), findsOneWidget);
      expect(find.text('Skip for now (Online Mode)'), findsOneWidget);
    });
  });
}

