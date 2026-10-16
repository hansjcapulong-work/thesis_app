import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Mobile inference service for the 65-class hands-only sign recognition
/// model (see the delivered README.md, v2). This REPLACES the previous
/// ASL_CITIZEN_200 BiGRU model's contract entirely -- different input
/// shape, no body pose input at all, different normalization, and a
/// different segment-length strategy. Do not mix logic from the old
/// service back in; the two models are not compatible.
///
/// Expected model input:  [1, 30, 126] float32
///   30 = fixed sequence length (variable-length captures are resampled
///        to exactly 30, see _resampleTo).
///   126 = 2 hands x 21 landmarks x 3 coords (x, y, z), flattened.
///         Hand order is fixed: index 0 = Left, index 1 = Right.
/// Expected model output: [1, 65] float32 -- ALREADY softmax
///   probabilities. Do NOT re-apply softmax on this output.
///
/// Known limitations (from README):
///  - Signer-dependent model (trained on 4 signers).
///  - The "now" class has weaker training data; expect lower reliability.
///  - Trained on LANDSCAPE input only; deploy in landscape.
class GestureRecognitionService {
  static const int sequenceLength = 30;
  static const int handCount = 2; // 0 = left, 1 = right
  static const int handLandmarkCount = 21;
  static const int coordsPerPoint = 3;
  static const int featuresPerFrame =
      handCount * handLandmarkCount * coordsPerPoint; // 126
  static const int classCount = 65;

  /// Starting point; tune per on-device testing.
  static const double confidenceThreshold = 0.65;

  /// Placeholders -- need real on-device calibration. Log a few live
  /// idle-vs-signing motion values and adjust these two.
  static const double motionStartThreshold = 0.6;
  static const double motionIdleThreshold = 0.25;
  static const int idleFramesToEndSegment = 10;
  static const int minSegmentFrames = 6;

  /// Safety cap so a segment can't grow forever if idle-detection never fires.
  static const int maxSegmentFrames = sequenceLength * 20;

  static const String modelAssetPath =
      'assets/model/sign_language_model.tflite';
  static const String labelsAssetPath = 'assets/model/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = <String>[];

  final List<_CapturedFrame> _activeSegment = <_CapturedFrame>[];
  Float32List? _lastFrame;

  bool _isCapturing = false;
  int _idleFrameCount = 0;

  String modelStatus = 'Loading model...';
  String lastPrediction = '—';
  double lastConfidence = 0.0;
  String tensorInfo = '—';
  String lastError = '';

  bool get isModelLoaded =>
      _interpreter != null && _labels.length == classCount;
  bool get isCapturingSegment => _isCapturing;
  int get activeSegmentLength => _activeSegment.length;
  int get handClassCount => _labels.length;

  void Function(bool isLoaded, String message)? onModelStatusChanged;
  void Function(String word, double confidence)? onGestureRecognized;
  void Function(String topLabel, double confidence, bool accepted)?
  onSegmentClassified;
  void Function(int captured, int minRequired)? onSegmentDiscarded;

  Future<void> loadModel() async {
    try {
      lastError = '';
      _interpreter = await Interpreter.fromAsset(modelAssetPath);

      final input = _interpreter!.getInputTensor(0);
      final output = _interpreter!.getOutputTensor(0);
      tensorInfo = 'input shape=${input.shape} type=${input.type} | '
          'output shape=${output.shape} type=${output.type}';

      if (input.type != TensorType.float32 ||
          output.type != TensorType.float32 ||
          input.shape.length != 3 ||
          input.shape[0] != 1 ||
          input.shape[1] != sequenceLength ||
          input.shape[2] != featuresPerFrame ||
          output.shape.length != 2 ||
          output.shape[0] != 1 ||
          output.shape[1] != classCount) {
        throw StateError('Unexpected TFLite tensor contract: $tensorInfo');
      }

      // labels.txt is one word per line; line index == class index.
      final rawLabels = await rootBundle.loadString(labelsAssetPath);
      final parsed = rawLabels
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (parsed.length != classCount) {
        throw StateError(
          'Expected $classCount labels, found ${parsed.length} in $labelsAssetPath',
        );
      }

      _labels = parsed;
      modelStatus = 'Model loaded: ${_labels.length} classes';
      onModelStatusChanged?.call(isModelLoaded, modelStatus);
    } catch (e) {
      _interpreter = null;
      _labels = <String>[];
      lastError = e.toString();
      modelStatus = 'MODEL ERROR: $e';
      onModelStatusChanged?.call(isModelLoaded, modelStatus);
      rethrow;
    }
  }

  /// Add one camera frame's hand landmarks (hands ONLY, no pose).
  /// Each hand list, when present, must contain 21 normalized x/y/z
  /// triples. Pass null for a hand that wasn't detected this frame; it is
  /// written as zeros, and the frame counts as "no hand" only if BOTH are null.
  void addFrame({
    required List<List<double>>? leftHandLandmarks,
    required List<List<double>>? rightHandLandmarks,
  }) {
    if (!isModelLoaded) return;

    final handPresent =
        leftHandLandmarks != null || rightHandLandmarks != null;
    final raw = _buildRawVector(leftHandLandmarks, rightHandLandmarks);
    final normalized = _normalizePerHand(raw);

    final motion =
    _lastFrame == null ? 0.0 : _motion(_lastFrame!, normalized);
    _lastFrame = normalized;

    if (!_isCapturing) {
      if (motion > motionStartThreshold) {
        _isCapturing = true;
        _idleFrameCount = 0;
        _activeSegment.clear();
        _activeSegment.add(_CapturedFrame(normalized, handPresent));
      }
      return;
    }

    _activeSegment.add(_CapturedFrame(normalized, handPresent));
    _idleFrameCount = motion < motionIdleThreshold ? _idleFrameCount + 1 : 0;

    final tooLong = _activeSegment.length >= maxSegmentFrames;
    final wentIdle = _idleFrameCount >= idleFramesToEndSegment;

    if (tooLong || wentIdle) {
      _endSegmentAndClassify();
    }
  }

  Float32List _buildRawVector(
      List<List<double>>? left,
      List<List<double>>? right,
      ) {
    final values = Float32List(featuresPerFrame);
    var index = 0;

    void writeHand(List<List<double>>? points) {
      for (var i = 0; i < handLandmarkCount; i++) {
        final point = (points != null && i < points.length)
            ? points[i]
            : const <double>[0.0, 0.0, 0.0];
        values[index++] = point.isNotEmpty ? point[0] : 0.0;
        values[index++] = point.length > 1 ? point[1] : 0.0;
        values[index++] = point.length > 2 ? point[2] : 0.0;
      }
    }

    writeHand(left); // hand 0 = Left
    writeHand(right); // hand 1 = Right
    return values;
  }

  /// README step 3: subtract each hand's OWN wrist (landmark 0) from all of
  /// its landmarks. Plain subtraction only, no scale division.
  Float32List _normalizePerHand(Float32List raw) {
    final out = Float32List(raw.length);
    final handStride = handLandmarkCount * coordsPerPoint; // 63

    for (var hand = 0; hand < handCount; hand++) {
      final base = hand * handStride;
      final wristX = raw[base];
      final wristY = raw[base + 1];
      final wristZ = raw[base + 2];
      for (var i = 0; i < handStride; i += 3) {
        out[base + i] = raw[base + i] - wristX;
        out[base + i + 1] = raw[base + i + 1] - wristY;
        out[base + i + 2] = raw[base + i + 2] - wristZ;
      }
    }
    return out;
  }

  double _motion(Float32List previous, Float32List current) {
    var total = 0.0;
    for (var i = 0; i < current.length; i++) {
      total += (current[i] - previous[i]).abs();
    }
    return total;
  }

  void _endSegmentAndClassify() {
    final captured = List<_CapturedFrame>.from(_activeSegment);
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;

    // README step 4 (trim): drop leading/trailing frames with no hand.
    var start = 0;
    var end = captured.length - 1;
    while (start <= end && !captured[start].handPresent) {
      start++;
    }
    while (end >= start && !captured[end].handPresent) {
      end--;
    }

    if (start > end) {
      onSegmentDiscarded?.call(0, minSegmentFrames);
      return;
    }

    final trimmed = captured.sublist(start, end + 1);

    if (trimmed.length < minSegmentFrames) {
      onSegmentDiscarded?.call(trimmed.length, minSegmentFrames);
      return;
    }

    final resampled =
    _resampleTo(trimmed.map((f) => f.vector).toList(), sequenceLength);
    _runInference(resampled);
  }

  /// README step 4 (resample): NEAREST-NEIGHBOR index selection, evenly
  /// spaced -- NOT linear interpolation. Equivalent to
  /// np.linspace(0, n-1, 30).round().astype(int) in the training pipeline.
  /// If your training script used int() truncation, change .round() to .floor().
  List<Float32List> _resampleTo(List<Float32List> frames, int targetLength) {
    if (frames.length == targetLength) return frames;

    final result = <Float32List>[];
    final lastIndex = frames.length - 1;

    for (var t = 0; t < targetLength; t++) {
      final pos =
      targetLength == 1 ? 0.0 : (t * lastIndex) / (targetLength - 1);
      final idx = pos.round().clamp(0, lastIndex);
      result.add(Float32List.fromList(frames[idx]));
    }
    return result;
  }

  void _runInference(List<Float32List> frames) {
    final interpreter = _interpreter;
    if (interpreter == null) return;

    final sequence = frames.map((f) => f.toList()).toList();
    final input = <List<List<double>>>[sequence];
    final output = <List<double>>[List<double>.filled(classCount, 0.0)];

    try {
      interpreter.run(input, output);
    } catch (e) {
      lastError = 'Inference failed: $e';
      return;
    }

    // Output is already softmax probabilities -- do not re-apply softmax.
    final probs = output[0];
    var bestIndex = 0;
    var best = probs[0];
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > best) {
        best = probs[i];
        bestIndex = i;
      }
    }

    lastPrediction = _labels[bestIndex];
    lastConfidence = best;

    final accepted = best >= confidenceThreshold;
    onSegmentClassified?.call(lastPrediction, best, accepted);
    if (accepted) {
      onGestureRecognized?.call(lastPrediction, best);
    }
  }

  void reset() {
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;
    _lastFrame = null;
    lastPrediction = '—';
    lastConfidence = 0.0;
    lastError = '';
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}

class _CapturedFrame {
  final Float32List vector;
  final bool handPresent;
  _CapturedFrame(this.vector, this.handPresent);
}