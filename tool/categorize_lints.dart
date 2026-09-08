import 'dart:io';

void main() async {
  final res = await Process.run('flutter.bat', ['analyze'], runInShell: true);
  final output = (res.stdout as String) + (res.stderr as String);
  final lines = output.split('\n');

  final ruleCounts = <String, int>{};
  final fileCounts = <String, int>{};
  final examples = <String, String>{};

  for (final line in lines) {
    if (line.contains(' - ')) {
      final parts = line.split(' - ');
      if (parts.length >= 3) {
        final rule = parts.last.trim();
        final fileAndLine = parts[parts.length - 2].trim();
        final file = fileAndLine.split(':').first.trim();

        ruleCounts[rule] = (ruleCounts[rule] ?? 0) + 1;
        fileCounts[file] = (fileCounts[file] ?? 0) + 1;
        examples.putIfAbsent(rule, () => line.trim());
      }
    }
  }

  print('=== BREAKDOWN BY LINT RULE ===');
  ruleCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))
    ..forEach((e) => print('${e.key}: ${e.value}'));

  print('\n=== BREAKDOWN BY FILE ===');
  fileCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))
    ..forEach((e) => print('${e.key}: ${e.value}'));

  print('\n=== SAMPLE PER RULE ===');
  examples.forEach((k, v) => print('[$k] -> $v'));
}
