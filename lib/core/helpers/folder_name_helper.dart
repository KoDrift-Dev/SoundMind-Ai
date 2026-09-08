import '../constants/app_strings.dart';

/// Extracts folder names from device file paths.
abstract final class FolderNameHelper {
  static String fromFilePath(String? filePath) {
    if (filePath == null) return AppStrings.unknownFolder;

    final parts = filePath.split('/');
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }

    return AppStrings.unknownFolder;
  }
}
