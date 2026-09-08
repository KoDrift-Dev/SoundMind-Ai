import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    int funcStart = -1;
    String funcHeader = '';
    bool inFunc = false;
    bool hasTry = false;
    bool hasDangerousCall = false;
    int braceDepth = 0;
    int dangerousLine = -1;
    String dangerousSnippet = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (!inFunc && (line.contains('async {') || line.contains('async* {') || (line.contains('async') && line.endsWith('{')))) {
        inFunc = true;
        funcStart = i + 1;
        funcHeader = line;
        hasTry = false;
        hasDangerousCall = false;
        braceDepth = 1;
        continue;
      }

      if (inFunc) {
        if (line.contains('{')) braceDepth += '{'.allMatches(line).length;
        if (line.contains('}')) braceDepth -= '}'.allMatches(line).length;

        if (line.contains('try {') || line.contains('try{')) {
          hasTry = true;
        }

        if (line.contains('SharedPreferences.getInstance') ||
            line.contains('.readAs') ||
            line.contains('.writeAs') ||
            line.contains('.delete(') ||
            line.contains('copy(') ||
            line.contains('openWrite(')) {
          hasDangerousCall = true;
          dangerousLine = i + 1;
          dangerousSnippet = line;
        }

        if (braceDepth <= 0) {
          if (hasDangerousCall && !hasTry) {
            print('${file.path}:$funcStart -> dangerous call at line $dangerousLine: $dangerousSnippet');
          }
          inFunc = false;
        }
      }
    }
  }
}
