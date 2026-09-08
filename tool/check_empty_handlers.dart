import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('onTap:') || line.contains('onPressed:')) {
        // Look ahead 5 lines
        final combined = lines.sublist(i, (i + 6).clamp(0, lines.length)).join(' ');
        final match = RegExp(r'(onTap|onPressed):\s*(\(\)\s*\{[\s;]*\}|\(\)\s*async\s*\{[\s;]*\}|\(\)\s*=>\s*\{\s*\})').firstMatch(combined);
        if (match != null) {
          print('[EMPTY HANDLER] ${file.path}:${i + 1} -> ${match.group(0)}');
        }
      }
    }
  }
}
