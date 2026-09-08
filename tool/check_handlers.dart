import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check for empty callbacks or TODOs in onTap / onPressed
      if (line.contains('onTap:') || line.contains('onPressed:')) {
        final trimmed = line.trim();
        if (trimmed.contains('() {}') ||
            trimmed.contains('() => {}') ||
            trimmed.contains('() => null') ||
            trimmed.contains('(){}') ||
            trimmed.contains('()=>{}') ||
            trimmed.contains('TODO') ||
            trimmed.contains('{}')) {
          print('[EMPTY/SUSPICIOUS HANDLER] ${file.path}:${i + 1} -> $trimmed');
        }
      }

      if (line.toLowerCase().contains('todo') || line.toLowerCase().contains('unimplemented')) {
        if (!line.contains('//') && !line.contains('/*')) {
          print('[TODO/UNIMPLEMENTED] ${file.path}:${i + 1} -> ${line.trim()}');
        }
      }
    }
  }
}
