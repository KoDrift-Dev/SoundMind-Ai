import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    int rowStart = -1;
    bool inRow = false;
    int depth = 0;
    List<int> textLinesInRow = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.contains('childAspectRatio:')) {
        print('[ASPECT RATIO] ${file.path}:${i+1} -> ${line.trim()}');
      }

      if (line.contains('Row(')) {
        inRow = true;
        rowStart = i + 1;
        depth = 0;
        textLinesInRow = [];
      }

      if (inRow) {
        depth += '{'.allMatches(line).length + '('.allMatches(line).length + '['.allMatches(line).length;
        depth -= '}'.allMatches(line).length + ')'.allMatches(line).length + ']'.allMatches(line).length;

        if (line.contains('Text(') && !line.contains('Expanded(') && !line.contains('Flexible(')) {
          // Check if previous 2 lines had Expanded or Flexible
          bool hasWrapper = false;
          for (int j = (i - 3).clamp(0, lines.length - 1); j < i; j++) {
            if (lines[j].contains('Expanded(') || lines[j].contains('Flexible(')) {
              hasWrapper = true;
              break;
            }
          }
          if (!hasWrapper) {
            // Check if text is dynamic (contains $ or a variable name, not just a static short literal)
            final textPart = line.substring(line.indexOf('Text('));
            if (textPart.contains(r'$') || (!textPart.contains("''") && !textPart.contains('""') && !textPart.contains("'Cancel'") && !textPart.contains("'OK'") && !textPart.contains("'Save'"))) {
              textLinesInRow.add(i + 1);
            }
          }
        }

        if (depth <= 0) {
          inRow = false;
          if (textLinesInRow.length > 1) {
            print('[UNEXPANDED ROW TEXT] ${file.path}: Row at $rowStart has unexpanded text at lines $textLinesInRow');
          }
        }
      }
    }
  }
}
