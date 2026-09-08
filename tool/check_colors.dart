import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    // Exclude theme definitions and constants
    if (file.path.contains('app_colors.dart') ||
        file.path.contains('app_theme.dart') ||
        file.path.contains('section_accents.dart') ||
        file.path.contains('online_theme.dart')) {
      continue;
    }

    final lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Detect hardcoded white or black in TextStyle or Icon
      if (line.contains('TextStyle(') || line.contains('color: Colors.white') || line.contains('color: Colors.black')) {
        if (!line.contains('isDark') &&
            !line.contains('isLight') &&
            !line.contains('?') &&
            !line.contains('AppColors.') &&
            !line.contains('OnlineTheme.') &&
            !line.contains('Theme.of')) {
          // Check previous 3 lines for isDark condition
          bool hasIsDark = false;
          for (int j = (i - 3).clamp(0, lines.length - 1); j < i; j++) {
            if (lines[j].contains('isDark') || lines[j].contains('isLight') || lines[j].contains('?')) {
              hasIsDark = true;
              break;
            }
          }
          if (!hasIsDark && (line.contains('color: Colors.white') || line.contains('color: Colors.black87') || line.contains('color: Colors.black'))) {
            print('${file.path}:${i + 1} -> ${line.trim()}');
          }
        }
      }
    }
  }
}
