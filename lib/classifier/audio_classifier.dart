// audio_classifier.dart
import '../models/track.dart';
import 'classification_result.dart';

/// Pluggable audio classifier interface.
/// Allows swapping Heuristic classifier with future ML/TFLite model.
abstract class AudioClassifier {
  Future<ClassificationResult> classify(Track track);
}
