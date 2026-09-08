import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundmindai/screens/home_screen.dart';
import 'package:soundmindai/screens/search_screen.dart' show kBrowseGenres;
import 'package:soundmindai/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STEP 1 — Genre to Query Construction', () {
    test('genreToQuery covers all genres in kBrowseGenres', () {
      for (final genre in kBrowseGenres) {
        expect(
          YoutubeService.genreToQuery.containsKey(genre),
          isTrue,
          reason: 'Missing query mapping for genre: $genre',
        );
        final query = YoutubeService.genreToQuery[genre]!;
        expect(query.trim().isNotEmpty, isTrue);
      }
    });

    test('queryForGenre returns curated queries for specific genres', () {
      expect(
        YoutubeService.queryForGenre('Qawali'),
        equals('Qawali Nusrat Fateh Ali Khan Rahat Sabri'),
      );
      expect(
        YoutubeService.queryForGenre('Sufi'),
        equals('Sufi songs Pakistani Indian'),
      );
      expect(
        YoutubeService.queryForGenre('Slow and Reverb'),
        equals('slowed and reverb Bollywood Pakistani songs'),
      );
      expect(
        YoutubeService.queryForGenre('Bollywood'),
        equals('Bollywood songs playlist latest hits'),
      );
      expect(
        YoutubeService.queryForGenre('Lo-fi'),
        equals('desi lofi Pakistani Indian chill songs'),
      );
    });

    test('HomeScreen default seed tracks are Pakistani and Indian hits, sidelining English pop', () {
      final seeds = HomeScreen.defaultSeedOnlineTracks;
      expect(seeds.isNotEmpty, isTrue);

      // Verify iconic Pakistani & Indian tracks are present
      final titles = seeds.map((s) => s.title.toLowerCase()).toList();
      expect(titles.any((t) => t.contains('pasoori')), isTrue);
      expect(titles.any((t) => t.contains('afreen')), isTrue);
      expect(titles.any((t) => t.contains('kesariya')), isTrue);
      expect(titles.any((t) => t.contains('tu jhoom')), isTrue);

      // Verify old English tracks are completely removed
      const prohibitedEnglishTracks = [
        'despacito',
        'shape of you',
        'uptown funk',
        'closer',
        'bad habits',
        'stay',
        'blinding lights',
      ];
      for (final bad in prohibitedEnglishTracks) {
        expect(
          titles.any((t) => t.contains(bad)),
          isFalse,
          reason: 'Prohibited English seed track found: $bad',
        );
      }
    });

    test('queryForGenre gracefully falls back for unmapped genres', () {
      expect(
        YoutubeService.queryForGenre('UnknownGenreXYZ'),
        equals('UnknownGenreXYZ music'),
      );
    });
  });

  group('STEP 2 & 4 — Negative Keyword Content Filter', () {
    test('negativeContentKeywords includes all required terms', () {
      const requiredKeywords = [
        'bhajan',
        'aarti',
        'mandir',
        'devotional',
        'kirtan',
        'stuti',
        'chalisa',
      ];
      for (final kw in requiredKeywords) {
        expect(YoutubeService.negativeContentKeywords.contains(kw), isTrue);
      }
    });

    test('hasNegativeKeywords correctly identifies religious/devotional titles', () {
      final sampleDevotionalTitles = [
        'Krishna Bhajan Non Stop 2026',
        'Morning Shiv Aarti Full HD',
        'Ayodhya Ram Mandir Special Song',
        'Morning Devotional Chants and Mantra',
        'Radha Krishna Ras Kirtan Live',
        'Shree Hanuman Chalisa Gulshan Kumar',
        'Mahalaxmi Stuti with Lyrics',
        'BHAJAN SPECIAL MORNING',
      ];

      for (final title in sampleDevotionalTitles) {
        expect(
          YoutubeService.hasNegativeKeywords(title),
          isTrue,
          reason: 'Expected "$title" to be flagged as devotional',
        );
      }
    });

    test('hasNegativeKeywords allows standard music titles without false positives', () {
      final sampleMusicTitles = [
        'Nusrat Fateh Ali Khan - Dum Mast Qalandar',
        'Arijit Singh - Kesariya Audio Song',
        'Taylor Swift - Cruel Summer (Official Music Video)',
        'Coldplay - Yellow (Live)',
        'Rahat Fateh Ali Khan - Afreen Afreen',
        'Bollywood 90s Romantic Songs Collection',
        'Slowed and Reverb Chill Lofi Mix',
        'Coke Studio - Tu Jhoom',
      ];

      for (final title in sampleMusicTitles) {
        expect(
          YoutubeService.hasNegativeKeywords(title),
          isFalse,
          reason: 'Did not expect "$title" to be flagged',
        );
      }
    });
  });

  group('STEP 3 — Genre Selection Diversity & 10-Call Simulation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('all preferred_genres are read, normalized, and weighted', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'preferred_genres',
        jsonEncode(['Qawali', 'Sufi', 'Slow and Reverb', 'Bollywood']),
      );

      final result = await HomeScreen.selectFeedGenres(
        weightedCount: 3,
        discoveryCount: 1,
        sharedPrefs: prefs,
      );

      expect(result.length, equals(4));
      // Verify all items are unique
      expect(result.toSet().length, equals(result.length));
    });

    test('10-call diversity test: does NOT converge on one genre (no genre selected >=8/10)', () async {
      final prefs = await SharedPreferences.getInstance();
      // User selected 4 genres during onboarding:
      final preferred = ['Qawali', 'Sufi', 'Slow and Reverb', 'Bollywood'];
      await prefs.setString('preferred_genres', jsonEncode(preferred));

      // Simulate online play history where Bollywood was played several times recently:
      final now = DateTime.now();
      final history = List.generate(
        10,
        (i) => {
          'title': 'Track $i',
          'artist': 'Artist $i',
          'genre': 'Bollywood',
          'timestamp': now.subtract(Duration(hours: i * 2)).toIso8601String(),
        },
      );
      await prefs.setString('online_play_history', jsonEncode(history));

      // Track how many times each genre is selected across 10 calls:
      final Map<String, int> genreCounts = {};
      final List<List<String>> callSelections = [];
      final testRandom = math.Random(42); // Deterministic seed for test repeatability

      for (int call = 1; call <= 10; call++) {
        final selection = await HomeScreen.selectFeedGenres(
          weightedCount: 2,
          discoveryCount: 1,
          sharedPrefs: prefs,
          randomGenerator: testRandom,
        );
        callSelections.add(selection);
        for (final g in selection) {
          genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        }
      }

      // Print log for reporting back
      // ignore: avoid_print
      print('=== 10-CALL GENRE DIVERSITY TEST RESULTS ===');
      for (int i = 0; i < callSelections.length; i++) {
        // ignore: avoid_print
        print('Call #${i + 1}: ${callSelections[i]}');
      }
      // ignore: avoid_print
      print('Overall Frequencies across 10 calls: $genreCounts');

      // (b) Verification requirement: No single genre picked 8+/10 times
      for (final entry in genreCounts.entries) {
        expect(
          entry.value < 8,
          isTrue,
          reason: 'Genre "${entry.key}" was picked ${entry.value} times (>=8/10), indicating excessive convergence!',
        );
      }

      // Verify that multiple onboarding preferred genres were selected across the 10 calls
      final selectedPreferred = preferred.where((p) => (genreCounts[p] ?? 0) > 0).toList();
      expect(
        selectedPreferred.length >= 3,
        isTrue,
        reason: 'Expected at least 3 distinct preferred genres to be picked across 10 calls, got: $selectedPreferred',
      );
    });
  });
}
