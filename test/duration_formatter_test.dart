import 'package:flutter_test/flutter_test.dart';
import 'package:soundmindai/utils/duration_formatter.dart';

void main() {
  group('Duration Formatter Tests', () {
    test('formatDuration formats mm:ss correctly', () {
      expect(formatDuration(const Duration(seconds: 213)), '3:33');
      expect(formatDuration(const Duration(seconds: 60)), '1:00');
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(null), '0:00');
    });

    test('formatDuration formats h:mm:ss when hours > 0', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '1:23:45',
      );
      expect(
        formatDuration(const Duration(hours: 2, minutes: 5, seconds: 9)),
        '2:05:09',
      );
    });

    test('formatDurationMs formats milliseconds correctly', () {
      expect(formatDurationMs(213000), '3:33');
      expect(formatDurationMs(5025000), '1:23:45');
      expect(formatDurationMs(null), '--:--');
      expect(formatDurationMs(0), '--:--');
    });

    test('formatDurationSeconds formats raw seconds correctly', () {
      expect(formatDurationSeconds(213), '3:33');
      expect(formatDurationSeconds(135), '2:15');
      expect(formatDurationSeconds(null), '--:--');
    });

    test('formatDurationString formats various string representations', () {
      // Raw second string
      expect(formatDurationString('213'), '3:33');
      expect(formatDurationString('135'), '2:15');

      // Unformatted >60 min string like "83:45"
      expect(formatDurationString('83:45'), '1:23:45');

      // Standard mm:ss string remains intact
      expect(formatDurationString('3:33'), '3:33');

      // Empty or null
      expect(formatDurationString(null), '--:--');
      expect(formatDurationString(''), '--:--');
      expect(formatDurationString('   '), '--:--');
    });

    test('formatDurationAny supports polymorphic inputs', () {
      expect(formatDurationAny(const Duration(seconds: 213)), '3:33');
      expect(formatDurationAny(213000), '3:33');
      expect(formatDurationAny('213'), '3:33');
      expect(formatDurationAny('83:45'), '1:23:45');
      expect(formatDurationAny(null), '--:--');
    });

    test('parseDurationStringToMs parses strings to ms accurately', () {
      expect(parseDurationStringToMs('4:41'), (4 * 60 + 41) * 1000);
      expect(parseDurationStringToMs('0:45'), 45 * 1000);
      expect(parseDurationStringToMs('1:23:45'), (1 * 3600 + 23 * 60 + 45) * 1000);
      expect(parseDurationStringToMs('213'), 213 * 1000);
      expect(parseDurationStringToMs('213000'), 213000);
      expect(parseDurationStringToMs(null), isNull);
      expect(parseDurationStringToMs(''), isNull);
      expect(parseDurationStringToMs('invalid'), isNull);
    });
  });
}
