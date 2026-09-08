// classification_result.dart
import '../models/audio_category.dart';

/// The origin or method used to classify an audio track.
enum ClassificationSource {
  heuristic,
  userOverride,
  ml;

  String get dbValue => name;

  static ClassificationSource fromDbValue(String? value) {
    if (value == null) return ClassificationSource.heuristic;
    return ClassificationSource.values.firstWhere(
      (s) => s.name.toLowerCase() == value.toLowerCase(),
      orElse: () => ClassificationSource.heuristic,
    );
  }
}

/// The output of classifying an audio file.
class ClassificationResult {
  final AudioCategory category;
  final double confidence; // Normalized 0.0 to 1.0
  final ClassificationSource source;
  final String explanation;

  const ClassificationResult({
    required this.category,
    required this.confidence,
    required this.source,
    this.explanation = '',
  });

  /// High confidence threshold required to treat as music without manual override.
  static const double musicConfidenceThreshold = 0.75;

  /// Low confidence threshold below which category becomes unknown / review.
  static const double reviewConfidenceThreshold = 0.50;

  /// Whether this result qualifies as verified music for playback.
  bool get isMusic {
    if (source == ClassificationSource.userOverride) {
      return category == AudioCategory.music;
    }
    return category == AudioCategory.music && confidence >= musicConfidenceThreshold;
  }

  /// Whether this result should be surfaced for user review.
  bool get needsReview {
    if (source == ClassificationSource.userOverride) return false;
    return category == AudioCategory.unknown || confidence < musicConfidenceThreshold;
  }

  @override
  String toString() =>
      'ClassificationResult(category: ${category.name}, confidence: ${confidence.toStringAsFixed(2)}, source: ${source.name})';
}
