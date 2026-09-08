import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  int totalScannedAsyncFuncs = 0;
  int asyncFuncsWithAwaitAndContext = 0;
  int unguardedCount = 0;

  for (final file in files) {
    final lines = file.readAsLinesSync();
    bool inAsyncFunc = false;
    int braceDepth = 0;
    int funcStartLine = -1;
    String funcSignature = '';
    bool hasPendingAwait = false;
    int lastAwaitLine = -1;
    String lastAwaitSnippet = '';
    List<String> contextCallsInFunc = [];

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final cleanLine = _stripCommentsAndStrings(rawLine).trim();

      // Check start of async function/closure
      if (!inAsyncFunc) {
        if (cleanLine.contains('async {') ||
            cleanLine.contains('async* {') ||
            (cleanLine.contains('async') && cleanLine.endsWith('{'))) {
          inAsyncFunc = true;
          totalScannedAsyncFuncs++;
          funcStartLine = i + 1;
          funcSignature = rawLine.trim();
          hasPendingAwait = false;
          lastAwaitLine = -1;
          lastAwaitSnippet = '';
          braceDepth = 1;
          contextCallsInFunc = [];
          continue;
        }
      }

      if (inAsyncFunc) {
        // Track brace depth
        final openCount = '{'.allMatches(cleanLine).length;
        final closeCount = '}'.allMatches(cleanLine).length;
        braceDepth += (openCount - closeCount);

        // Check if function ended
        if (braceDepth <= 0) {
          inAsyncFunc = false;
          hasPendingAwait = false;
          continue;
        }

        // Mounted check clears pending await
        if (cleanLine.contains('if (!mounted) return') ||
            cleanLine.contains('if (!context.mounted) return') ||
            cleanLine.contains('if (!mounted)') ||
            cleanLine.contains('if (!context.mounted)') ||
            cleanLine.contains('if (mounted)') ||
            cleanLine.contains('if (context.mounted)')) {
          hasPendingAwait = false;
        }

        // Context operations
        final usesContext = cleanLine.contains('Navigator.') ||
            cleanLine.contains('ScaffoldMessenger.') ||
            cleanLine.contains('Theme.of(context)') ||
            cleanLine.contains('MediaQuery.of(context)');

        final isDialogPop = (cleanLine.contains('Navigator.pop(ctx') ||
                cleanLine.contains('Navigator.pop(alertCtx') ||
                cleanLine.contains('Navigator.pop(dialogCtx)')) &&
            !cleanLine.contains('Navigator.pop(context');

        if (usesContext && !isDialogPop) {
          if (hasPendingAwait) {
            unguardedCount++;
            print('🚨 UNGUARDED: ${file.path}:${i + 1}');
            print('   Method at L$funcStartLine: $funcSignature');
            print('   Await at L$lastAwaitLine: $lastAwaitSnippet');
            print('   Context Call at L${i + 1}: ${rawLine.trim()}');
            print('   BraceDepth: $braceDepth\n');
          } else {
            contextCallsInFunc.add('L${i + 1}: ${rawLine.trim()}');
          }
        }

        // Await statement
        if (cleanLine.contains('await ') || cleanLine.contains('await(')) {
          // If the await call is itself Navigator.push(context, ...), it's using context BEFORE awaiting the result!
          // So hasPendingAwait should become true AFTER this line, not before.
          hasPendingAwait = true;
          lastAwaitLine = i + 1;
          lastAwaitSnippet = rawLine.trim();
        }
      }
    }
  }

  print('========================================');
  print('Total Async Functions Scanned: $totalScannedAsyncFuncs');
  print('Total Unguarded Context Usages: $unguardedCount');
  print('========================================');
}

String _stripCommentsAndStrings(String line) {
  var s = line;
  final commentIdx = s.indexOf('//');
  if (commentIdx != -1) {
    s = s.substring(0, commentIdx);
  }
  s = s.replaceAll(RegExp(r"'(\\.|[^'])*'"), "''");
  s = s.replaceAll(RegExp(r'"(\\.|[^"])*"'), '""');
  return s;
}
