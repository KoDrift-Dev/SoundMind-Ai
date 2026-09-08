// hybrid_audio_classifier.dart
import '../models/audio_category.dart';
import '../models/track.dart';
import 'audio_classifier.dart';
import 'classification_result.dart';
import 'heuristic_audio_classifier.dart';
import 'ml_audio_classifier.dart';

/// Intelligent Hybrid Classifier that chains Heuristic and ML classifiers.
///
/// Workflow:
/// 1. Fast Heuristic Filter: Evaluates metadata, path tokens, duration, and file structure.
/// 2. If Heuristic is high confidence (>= 0.75) and definitive: returns immediately (zero ML CPU/battery overhead).
/// 3. If Heuristic is ambiguous or low confidence (< 0.75): delegates to [MlAudioClassifier] to inspect
///    acoustic byte entropy, dynamic range, and bitrate characteristics.
/// 4. Produces final verified classification.
class HybridAudioClassifier implements AudioClassifier {
  final HeuristicAudioClassifier heuristicClassifier;
  final MlAudioClassifier mlClassifier;

  HybridAudioClassifier({
    HeuristicAudioClassifier? heuristicClassifier,
    MlAudioClassifier? mlClassifier,
  })  : heuristicClassifier = heuristicClassifier ?? HeuristicAudioClassifier(),
        mlClassifier = mlClassifier ?? MlAudioClassifier();

  @override
  Future<ClassificationResult> classify(Track track) async {
    // 1. Run fast heuristic evaluation first
    final heuristicResult = await heuristicClassifier.classify(track);

    // If Heuristic has strong confidence and is not unknown, return it immediately
    if (heuristicResult.confidence >= ClassificationResult.musicConfidenceThreshold &&
        heuristicResult.category != AudioCategory.unknown) {
      return heuristicResult;
    }

    // 2. Track is ambiguous: pass to ML acoustic classifier
    final mlResult = await mlClassifier.classify(track);

    // If ML is confident, use its classification
    if (mlResult.confidence >= 0.70 && mlResult.category != AudioCategory.unknown) {
      return ClassificationResult(
        category: mlResult.category,
        confidence: mlResult.confidence,
        source: ClassificationSource.ml,
        explanation: 'Hybrid: Heuristic ambiguous (${heuristicResult.category.name} @ ${(heuristicResult.confidence * 100).toInt()}%). Resolved by ML: ${mlResult.explanation}',
      );
    }

    // 3. Both are uncertain: combine signals and mark for manual review
    final combinedCategory = (heuristicResult.category != AudioCategory.unknown)
        ? heuristicResult.category
        : mlResult.category;

    final combinedConfidence = (heuristicResult.confidence + mlResult.confidence) / 2.0;

    return ClassificationResult(
      category: combinedCategory,
      confidence: combinedConfidence,
      source: ClassificationSource.ml,
      explanation: 'Hybrid: Ambiguous signals across heuristic and acoustic ML. Flagged for user review.',
    );
  }
}
