import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// ===========================================================================
/// THE ONLY TWO FILES YOU EVER NEED TO ADD/REPLACE ONCE YOUR MODEL IS TRAINED:
///   assets/model/gesture_model.tflite   <- your trained LSTM, converted
///   assets/model/labels.txt             <- one class label per line, in the
///                                          exact order your model outputs
///
/// Everything else in this service (buffering, preprocessing, inference
/// plumbing) is already built and works with a stub/missing model, so you
/// can test the whole camera -> recognition -> speech pipeline today and
/// swap in the real files later without touching any other code.
/// ===========================================================================
class GestureRecognitionService {
  // MUST match your training pipeline exactly -- see the big warning
  // in _buildFeatureVector below. Getting this wrong is the #1 way a
  // perfectly good trained model still produces garbage predictions.
  static const int sequenceLength = 80; // frames per prediction window

  static const int _handLandmarkCount = 21;
  static const int _handCoordsPerPoint = 3; // x, y, z
  static const int handFeaturesPerFrame =
      2 * _handLandmarkCount * _handCoordsPerPoint; // 2 hands x 21 x 3 = 126

  static const int _poseLandmarkCount = 33;
  // Matches your existing offline extraction pipeline, which captured
  // pose as [x, y] only (no z). Change to 3 below if your training
  // data actually includes pose z-coordinates.
  static const int _poseCoordsPerPoint = 2;
  static const int poseFeaturesPerFrame =
      _poseLandmarkCount * _poseCoordsPerPoint; // 33 x 2 = 66

  static const int featuresPerFrame = handFeaturesPerFrame + poseFeaturesPerFrame; // 192

  static const double confidenceThreshold = 0.60;

  static const String _modelAssetPath = 'assets/model/gesture_model.tflite';
  static const String _labelsAssetPath = 'assets/model/labels.txt';

  Interpreter? _interpreter;
  List<String> _labels = [];
  final List<Float32List> _frameBuffer = [];

  /// Called with (recognizedWord, confidence) whenever a full 80-frame
  /// window is classified above [confidenceThreshold]. Set this from
  /// your camera screen.
  void Function(String word, double confidence)? onGestureRecognized;

  /// Called once after attempting to load the model, so the UI can show
  /// "model not loaded yet" instead of silently doing nothing.
  void Function(bool isLoaded, String message)? onModelStatusChanged;

  bool get isModelLoaded => _interpreter != null && _labels.isNotEmpty;

  /// Attempts to load the TFLite model and label list. If the files
  /// don't exist yet (expected during development, before training is
  /// done), this fails gracefully instead of crashing the app -- the
  /// rest of the pipeline (camera, landmark extraction, buffering)
  /// keeps working, it just won't produce predictions yet.
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelAssetPath);
      final labelsRaw = await rootBundle.loadString(_labelsAssetPath);
      _labels = labelsRaw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      onModelStatusChanged?.call(
        true,
        'Model loaded: ${_labels.length} gesture classes.',
      );
    } catch (e) {
      _interpreter = null;
      _labels = [];
      onModelStatusChanged?.call(
        false,
        'No trained model found yet (this is expected until training is '
        'done). Drop gesture_model.tflite and labels.txt into '
        'assets/model/ to enable recognition. ($e)',
      );
    }
  }

  /// Feeds one frame's worth of landmark data into the rolling buffer.
  /// Pass null for anything not detected in this frame -- it will be
  /// zero-padded, matching the convention described in your thesis's
  /// data preparation section.
  ///
  /// [leftHandLandmarks] / [rightHandLandmarks]: 21 [x, y, z] triples each.
  /// [poseLandmarks]: 33 [x, y] pairs (see _poseCoordsPerPoint above).
  void addFrame({
    required List<List<double>>? leftHandLandmarks,
    required List<List<double>>? rightHandLandmarks,
    List<List<double>>? poseLandmarks,
  }) {
    final frame = _buildFeatureVector(
      leftHandLandmarks,
      rightHandLandmarks,
      poseLandmarks,
    );
    _frameBuffer.add(frame);

    if (_frameBuffer.length >= sequenceLength) {
      _runInference(List.of(_frameBuffer));
      _frameBuffer.clear();
    }
  }

  /// Flattens hand + pose landmarks into a single feature vector:
  ///   [ left hand: 21 x (x,y,z) = 63 values,
  ///     right hand: 21 x (x,y,z) = 63 values,
  ///     pose: 33 x (x,y) = 66 values ]
  ///   = 192 values total, in that exact order.
  ///
  /// *** CRITICAL -- READ BEFORE TRAINING/CONVERTING YOUR MODEL ***
  /// This ordering (hands first, then pose; x-y-z per hand point;
  /// x-y per pose point) is an assumption based on your existing
  /// pipeline. Your team's actual training script may use a different
  /// order, coordinate count, or padding convention. Whatever your
  /// training script does, THIS function must produce identical output
  /// for identical input, or predictions will be wrong even with a
  /// perfectly trained model. Update this function to match your real
  /// training script exactly -- don't assume this guess is correct.
  Float32List _buildFeatureVector(
    List<List<double>>? left,
    List<List<double>>? right,
    List<List<double>>? pose,
  ) {
    final values = Float32List(featuresPerFrame);
    int i = 0;

    void writeHand(List<List<double>>? hand) {
      for (int j = 0; j < _handLandmarkCount; j++) {
        final point = (hand != null && j < hand.length) ? hand[j] : const [0.0, 0.0, 0.0];
        values[i++] = point[0];
        values[i++] = point[1];
        values[i++] = point.length > 2 ? point[2] : 0.0;
      }
    }

    void writePose(List<List<double>>? poseData) {
      for (int j = 0; j < _poseLandmarkCount; j++) {
        final point = (poseData != null && j < poseData.length) ? poseData[j] : const [0.0, 0.0];
        values[i++] = point[0];
        values[i++] = point[1];
      }
    }

    writeHand(left);
    writeHand(right);
    writePose(pose);
    return values;
  }

  void _runInference(List<Float32List> frames) {
    final interpreter = _interpreter;
    if (interpreter == null || _labels.isEmpty) return;

    // Shape: [1, sequenceLength, featuresPerFrame]
    final input = [frames.map((f) => f.toList()).toList()];
    final output = [List.filled(_labels.length, 0.0)];

    try {
      interpreter.run(input, output);
    } catch (e) {
      onModelStatusChanged?.call(false, 'Inference failed: $e');
      return;
    }

    final scores = output[0];
    var bestIndex = 0;
    var bestScore = scores[0];
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > bestScore) {
        bestScore = scores[i];
        bestIndex = i;
      }
    }

    if (bestScore >= confidenceThreshold) {
      onGestureRecognized?.call(_labels[bestIndex], bestScore);
    }
  }

  /// Clears the current buffer without running inference -- useful when
  /// the user explicitly stops/resets a live session.
  void resetBuffer() {
    _frameBuffer.clear();
  }

  void dispose() {
    _interpreter?.close();
  }
}
