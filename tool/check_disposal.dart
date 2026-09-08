import 'dart:io';

void main() {
  final dir = Directory('lib');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  
  final controllerTypes = [
    'AnimationController',
    'ScrollController',
    'TextEditingController',
    'StreamController',
    'StreamSubscription',
    'TabController',
    'PageController',
  ];

  for (final file in files) {
    final content = file.readAsStringSync();
    final lines = file.readAsLinesSync();

    // Check for fields of these types
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      for (final type in controllerTypes) {
        if (line.contains(type) && (line.contains('late ') || line.contains('final ') || line.startsWith(type) || line.contains('? '))) {
          // Extract variable name
          final parts = line.split(RegExp(r'\s+'));
          String? varName;
          for (int p = 0; p < parts.length; p++) {
            if (parts[p].startsWith('_') && parts[p].length > 1) {
              varName = parts[p].replaceAll(';', '').replaceAll('=', '').replaceAll('?', '').trim();
              break;
            }
          }
          if (varName != null && varName.isNotEmpty) {
            // Check if varName.dispose() or varName?.cancel() exists in file
            final hasDispose = content.contains('$varName.dispose()') || content.contains('$varName?.dispose()');
            final hasCancel = content.contains('$varName.cancel()') || content.contains('$varName?.cancel()');
            final hasClose = content.contains('$varName.close()') || content.contains('$varName?.close()');
            
            if (!hasDispose && !hasCancel && !hasClose) {
              print('${file.path}:${i+1} -> $varName of type $type not disposed/cancelled');
            }
          }
        }
      }
    }
  }
}
