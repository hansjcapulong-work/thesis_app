import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// ===========================================================================
/// Rebuilt against the trained ASL_CITIZEN_200 model's actual spec
/// (model_spec.json / preprocessing_spec.json / DEPLOYMENT_README.md),
/// and verified against real training samples pulled from the published
/// dataset shards (train/val/test *_features.npy).
///
/// Currently targeting the BiLSTM + Temporal Attention variant
/// (bilstm_model_spec.json / BILSTM_DEPLOYMENT_README.md). Note per
/// bilstm_training_metrics.json's own comparison block: the BiGRU sibling
/// model scored higher on test top-1 (98.37% vs this model's 97.75%) with
/// fewer parameters (2.59M vs 3.24M). Swapping back to the BiGRU .tflite
/// later needs no code changes here -- input/output shapes and
/// preprocessing are identical between the two, only _modelAssetPath
/// below would need to change.
///
/// CONFIRMED FROM REAL SAMPLES (not just the docs):
///   - Clips shorter than 200 frames are zero-padded at the FRONT --
///     the real signing frames are right-aligned to the end of the
///     200-frame window, both for position AND velocity.
///   - Most training clips were already >=200 frames and got trimmed,
///     not padded -- so most isolated signs in the source data took the
///     full ~6.6s window. Live single-word signs in this app will very
///     often be shorter than that, so the short-clip padding path below
///     matters a lot in practice, not just as an edge case. This was
///     confirmed against the shared preprocessing spec, not something
///     specific to one model variant, so it still applies here.
///
/// Because of that, this version no longer just waits for a hard
/// 200-frame buffer to fill. It watches hand motion to detect when a
/// sign starts and stops, then right-aligns + zero-pads whatever it
/// captured to match how the model was trained.
///
/// Files to drop in under assets/model/:
///   ASL_CITIZEN_200_BiLSTM.tflite
///   class_list.txt   <- 200 real classes, "<index> <LABEL>" per line,
///                        exact order (0=ACTION ... 199=ZOOMOFF)
/// ===========================================================================
class GestureRecognitionService {
  // --- Sequence -------------------------------------------------------------
  // Model was trained on fixed 200-frame clips. Must match exactly.
  static const int sequenceLength = 200;

  // --- Landmarks --------------------------------------------------------
  // Order matters and MUST match training: pose, then left hand, then right hand.
  static const int _poseLandmarkCount = 33;
  static const int _handLandmarkCount = 21;
  static const int totalLandmarks =
      _poseLandmarkCount + _handLandmarkCount + _handLandmarkCount; // 75

  // Every landmark (pose + both hands) is x,y,z -- 3 coords. The model spec
  // is explicit that pose needs z too, unlike your old 80-frame LSTM plan
  // which only stored pose as (x,y).
  static const int _coordsPerPoint = 3;
  static const int positionFeatures = totalLandmarks * _coordsPerPoint; // 225
  static const int velocityFeatures = positionFeatures; // 225, frame-to-frame delta
  static const int featuresPerFrame = positionFeatures + velocityFeatures; // 450

  // Shoulder landmarks (within the pose block) used for normalization.
  static const int _leftShoulderIdx = 11;
  static const int _rightShoulderIdx = 12;

  // Model output is raw logits (per model_spec.json: "type": "logits"),
  // so we softmax before applying a confidence threshold. Threshold is on
  // the softmax probability, same semantics as before.
  static const double confidenceThreshold = 0.60;

  static const String _modelAssetPath = 'assets/model/ASL_CITIZEN_200_BiLSTM.tflite';
  static const String _labelsAssetPath = 'assets/model/class_list.txt';

  // --- Motion-based segmentation ---------------------------------------
  // These thresholds operate on normalized coordinates (post shoulder-
  // center/shoulder-width scaling), NOT raw pixels, so they should be
  // fairly camera/resolution independent -- but they're still a
  // starting guess. Tune against real recordings from your camera
  // pipeline; there's no ground truth for "right" values here, only
  // what feels responsive without false-triggering on small idle jitter.

  // Sum of per-coordinate |delta| between consecutive normalized frames,
  // restricted to the hand landmarks (index 33 onward in the 75-point
  // block), since that's where actual signing motion shows up. Pose
  // stays mostly still for isolated one-hand/two-hand signs.
  static const double _motionStartThreshold = 1.2;
  static const double _motionIdleThreshold = 0.5;

  // Consecutive low-motion frames required to decide a sign has ended.
  // At ~30fps this is roughly 1/3 second of stillness.
  static const int _idleFramesToEndSegment = 10;

  // Ignore segments shorter than this -- avoids firing on camera noise
  // or a hand briefly passing through frame.
  static const int _minSegmentFrames = 8;

  Interpreter? _interpreter;
  List<String> _labels = [];

  // Frames captured since the current sign segment started (variable
  // length, capped at sequenceLength). Cleared between segments.
  final List<Float32List> _activeSegment = [];

  bool _isCapturing = false;
  int _idleFrameCount = 0;
  Float32List? _lastFrame;

  /// Called with (recognizedWord, confidence) whenever a full 200-frame
  /// window is classified above [confidenceThreshold].
  void Function(String word, double confidence)? onGestureRecognized;

  /// Called after EVERY segment is classified, regardless of whether it
  /// cleared [confidenceThreshold] -- unlike [onGestureRecognized], this
  /// always fires once a segment finishes and inference runs. Use this to
  /// show "the model saw a segment and guessed X at 12%" in a debug UI,
  /// which [onGestureRecognized] alone can't tell you since it stays
  /// silent below the threshold. `accepted` is true exactly when
  /// [onGestureRecognized] also fired for this same segment.
  void Function(String topLabel, double confidence, bool accepted)? onSegmentClassified;

  /// Called when a segment ends but was too short to bother classifying
  /// (see [_minSegmentFrames]) -- e.g. a brief flinch or the camera
  /// misreading a moment of stillness as motion. Without this, a
  /// too-short segment and "no segment captured at all" look identical
  /// from the UI.
  void Function(int capturedFrames, int minRequiredFrames)? onSegmentDiscarded;

  /// Called once after attempting to load the model.
  void Function(bool isLoaded, String message)? onModelStatusChanged;

  bool get isModelLoaded => _interpreter != null && _labels.isNotEmpty;

  /// True while a sign segment is actively being captured (motion has
  /// started and hasn't gone idle/hit max length yet). Useful for a
  /// debug indicator so it's visible whether frames are actually
  /// reaching the segmenter, independent of whether a word has been
  /// classified yet.
  bool get isCapturingSegment => _isCapturing;

  /// Number of frames currently buffered in the in-progress segment.
  int get activeSegmentLength => _activeSegment.length;

  /// Returns a human-readable summary of the loaded model's input/output
  /// tensor shapes and types, e.g. for a debug/smoke-test screen to log
  /// before trusting any real predictions. Returns null if no model is
  /// loaded.
  String? debugTensorInfo() {
    final interpreter = _interpreter;
    if (interpreter == null) return null;
    final inTensor = interpreter.getInputTensor(0);
    final outTensor = interpreter.getOutputTensor(0);
    return 'input: shape=${inTensor.shape} type=${inTensor.type} | '
        'output: shape=${outTensor.shape} type=${outTensor.type}';
  }

  /// Test-only entry point that skips motion-based segmentation entirely
  /// and runs a fixed 200-frame position sequence straight through
  /// inference (assumes the sequence is ALREADY normalized) -- use this
  /// to verify the model/tensor plumbing works before trusting the full
  /// camera -> segmentation -> inference path. `positionFrames` must be
  /// a list of exactly [sequenceLength] frames, each [positionFeatures]
  /// long.
  void debugClassifySequence(List<Float32List> positionFrames) {
    assert(positionFrames.length == sequenceLength,
    'Expected $sequenceLength frames, got ${positionFrames.length}');
    _runInference(positionFrames);
  }

  /// Like [debugClassifySequence], but returns the raw top-1 label and
  /// probability regardless of [confidenceThreshold], and never touches
  /// [onGestureRecognized]. Use this for smoke-testing: it tells you
  /// whether the model is producing a sane, structured probability
  /// distribution at all (not NaN, not flat/uniform, not all-zero),
  /// independent of whether any real sign would actually clear the
  /// confidence bar. A low top score on synthetic/fake input is
  /// expected and fine -- what matters is that it returns a real
  /// label with a real (non-NaN, non-zero, non-uniform) probability.
  Map<String, Object>? debugRawTopPrediction(List<Float32List> positionFrames) {
    final interpreter = _interpreter;
    if (interpreter == null || _labels.isEmpty) return null;
    assert(positionFrames.length == sequenceLength,
    'Expected $sequenceLength frames, got ${positionFrames.length}');

    final sequence = List.generate(sequenceLength, (t) {
      final frame = Float32List(featuresPerFrame);
      final pos = positionFrames[t];
      for (int k = 0; k < positionFeatures; k++) {
        frame[k] = pos[k];
      }
      if (t == 0) {
        for (int k = 0; k < velocityFeatures; k++) {
          frame[positionFeatures + k] = 0.0;
        }
      } else {
        final prev = positionFrames[t - 1];
        for (int k = 0; k < velocityFeatures; k++) {
          frame[positionFeatures + k] = pos[k] - prev[k];
        }
      }
      return frame.toList();
    });

    final input = [sequence];
    final output = [List.filled(_labels.length, 0.0)];
    interpreter.run(input, output);

    final probs = _softmax(output[0]);
    var bestIndex = 0;
    var bestScore = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestScore) {
        bestScore = probs[i];
        bestIndex = i;
      }
    }

    return {
      'label': _labels[bestIndex],
      'probability': bestScore,
      'rawLogitsSample': output[0].take(5).toList(), // first 5 logits, sanity check
    };
  }

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(_modelAssetPath);
      final labelsRaw = await rootBundle.loadString(_labelsAssetPath);

      // class_list.txt lines look like "  0 ACTION" / "199 ZOOMOFF" --
      // right-justified index, whitespace, label. Parse both the index
      // and label explicitly and verify the index matches the line's
      // position rather than just trusting file order, since a
      // silently-misordered class list would map every prediction to
      // the wrong word without ever throwing an error.
      final lines = labelsRaw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();

      final parsedLabels = <String>[];
      for (int i = 0; i < lines.length; i++) {
        final parts = lines[i].split(RegExp(r'\s+'));
        if (parts.length < 2) {
          onModelStatusChanged?.call(
            false,
            'class_list.txt line ${i + 1} ("${lines[i]}") doesn\'t match '
                'the expected "<index> <LABEL>" format.',
          );
          return;
        }
        final parsedIndex = int.tryParse(parts.first);
        if (parsedIndex != i) {
          onModelStatusChanged?.call(
            false,
            'class_list.txt is out of order at line ${i + 1}: expected '
                'index $i, found "${parts.first}". Predictions would be '
                'silently mapped to the wrong labels if this were ignored.',
          );
          return;
        }
        parsedLabels.add(parts.sublist(1).join(' '));
      }
      _labels = parsedLabels;

      if (_labels.length != 200) {
        onModelStatusChanged?.call(
          false,
          'class_list.txt has ${_labels.length} entries, expected 200. '
              'Check you replaced the placeholder file correctly.',
        );
        return;
      }

      onModelStatusChanged?.call(
        true,
        'Model loaded: ${_labels.length} gesture classes.',
      );
    } catch (e) {
      _interpreter = null;
      _labels = [];
      onModelStatusChanged?.call(
        false,
        'No trained model found yet. Drop ASL_CITIZEN_200_BiLSTM.tflite and '
            'class_list.txt into assets/model/ to enable recognition. ($e)',
      );
    }
  }

  /// Feeds one frame's worth of landmark data into the segmenter.
  /// Pass null for anything not detected in this frame -- zero-padded.
  ///
  /// [poseLandmarks]: 33 [x, y, z] triples.
  /// [leftHandLandmarks] / [rightHandLandmarks]: 21 [x, y, z] triples each.
  ///
  /// NOTE: pose now needs z (previously x,y only in the 80-frame LSTM
  /// plan) -- make sure whatever calls this passes pose landmarks with
  /// 3 values per point, not 2.
  ///
  /// IMPORTANT: unlike the hand landmark lists, [poseLandmarks] is NOT
  /// safely nullable in practice. [_normalize] centers and scales every
  /// point using the shoulder landmarks pulled out of the pose block
  /// (see [_leftShoulderIdx]/[_rightShoulderIdx]). If pose data is
  /// missing, both shoulders resolve to (0,0,0), shoulderWidth collapses
  /// to the div-by-zero guard, and every landmark -- hands included --
  /// gets divided by a near-zero number. That doesn't fail loudly; it
  /// silently produces a garbage-but-well-formed input, which the model
  /// will happily classify with a confident-looking (and wrong) label.
  /// So frames without real pose data are dropped here rather than fed
  /// through, and [onModelStatusChanged] is used to surface that once
  /// rather than repeatedly.
  ///
  /// Call this every camera frame, continuously. Internally this watches
  /// hand motion to detect when a sign starts and ends, rather than
  /// firing inference on a fixed frame count.
  bool _warnedMissingPose = false;

  void addFrame({
    required List<List<double>>? poseLandmarks,
    required List<List<double>>? leftHandLandmarks,
    required List<List<double>>? rightHandLandmarks,
  }) {
    if (poseLandmarks == null || poseLandmarks.length < _poseLandmarkCount) {
      if (!_warnedMissingPose) {
        _warnedMissingPose = true;
        onModelStatusChanged?.call(
          false,
          'No pose landmarks supplied -- gesture recognition needs shoulder '
              'positions to normalize hand coordinates. Wire up a pose '
              'landmarker alongside the hand landmarker before relying on '
              'recognition results.',
        );
      }
      return;
    }

    // Pose data just started flowing (either for the first time, or after
    // having dropped out and warned about it above) -- clear the warning
    // and tell the UI things are healthy again, rather than leaving a
    // stale "no pose" message displayed indefinitely even once frames are
    // actually being captured normally.
    if (_warnedMissingPose) {
      _warnedMissingPose = false;
      onModelStatusChanged?.call(true, 'Pose landmarks flowing -- capturing normally.');
    }

    final rawFrame = _buildRawPositionVector(
      poseLandmarks,
      leftHandLandmarks,
      rightHandLandmarks,
    );
    final normalizedFrame = _normalize(rawFrame);

    final motion = _lastFrame == null
        ? 0.0
        : _handMotion(_lastFrame!, normalizedFrame);
    _lastFrame = normalizedFrame;

    if (!_isCapturing) {
      if (motion > _motionStartThreshold) {
        _isCapturing = true;
        _idleFrameCount = 0;
        _activeSegment.clear();
        _activeSegment.add(normalizedFrame);
      }
      // else: still idle, nothing to do.
      return;
    }

    // Currently capturing a sign.
    _activeSegment.add(normalizedFrame);
    _idleFrameCount = motion < _motionIdleThreshold ? _idleFrameCount + 1 : 0;

    final hitMaxLength = _activeSegment.length >= sequenceLength;
    final wentIdle = _idleFrameCount >= _idleFramesToEndSegment;

    if (hitMaxLength || wentIdle) {
      _endSegmentAndClassify();
    }
  }

  /// Sum of |delta| across the hand landmarks only (indices 33-74 within
  /// the 75-point block, i.e. positionFeatures indices 99-224), used as
  /// a cheap motion signal to detect sign start/stop. Pose is excluded
  /// since it stays relatively still for isolated signs.
  double _handMotion(Float32List prev, Float32List current) {
    const handStart = _poseLandmarkCount * _coordsPerPoint; // 99
    var total = 0.0;
    for (int i = handStart; i < positionFeatures; i++) {
      total += (current[i] - prev[i]).abs();
    }
    return total;
  }

  /// Finalizes the current segment: right-aligns the captured real
  /// frames within a 200-frame window, zero-padding the front if the
  /// segment ran shorter than 200 frames (confirmed from real training
  /// samples), or keeping the most recent 200 frames if it ran longer.
  /// Then runs inference and resets to idle.
  void _endSegmentAndClassify() {
    final captured = List.of(_activeSegment);
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;

    if (captured.length < _minSegmentFrames) {
      // Too short to be a real sign -- likely noise/jitter. Discard, but
      // still tell the debug UI why nothing happened, rather than looking
      // identical to "nothing was captured at all."
      onSegmentDiscarded?.call(captured.length, _minSegmentFrames);
      return;
    }

    final aligned = _rightAlignAndPad(captured);
    _runInference(aligned);
  }

  /// Builds an exactly-`sequenceLength`-long list of position frames:
  ///   - if `frames` is shorter, pad the FRONT with zero vectors
  ///   - if `frames` is longer, keep the LAST `sequenceLength` frames
  ///     (mirrors the padding side found in real training samples;
  ///     the truncation direction for over-long clips wasn't directly
  ///     observable in the samples checked, so this is the closest
  ///     symmetric assumption -- flag if accuracy looks off on longer
  ///     signs specifically).
  List<Float32List> _rightAlignAndPad(List<Float32List> frames) {
    if (frames.length == sequenceLength) return frames;

    if (frames.length > sequenceLength) {
      return frames.sublist(frames.length - sequenceLength);
    }

    final padCount = sequenceLength - frames.length;
    final zeroFrame = Float32List(positionFeatures); // all zeros
    return [
      for (int i = 0; i < padCount; i++) zeroFrame,
      ...frames,
    ];
  }

  /// Flattens pose + left hand + right hand into one 225-value vector,
  /// in the exact order the model was trained on: pose(0-32), left
  /// hand(33-53), right hand(54-74), each as x,y,z.
  Float32List _buildRawPositionVector(
      List<List<double>>? pose,
      List<List<double>>? left,
      List<List<double>>? right,
      ) {
    final values = Float32List(positionFeatures);
    int i = 0;

    void writeBlock(List<List<double>>? points, int count) {
      for (int j = 0; j < count; j++) {
        final point =
        (points != null && j < points.length) ? points[j] : const [0.0, 0.0, 0.0];
        values[i++] = point[0];
        values[i++] = point.length > 1 ? point[1] : 0.0;
        values[i++] = point.length > 2 ? point[2] : 0.0;
      }
    }

    writeBlock(pose, _poseLandmarkCount);
    writeBlock(left, _handLandmarkCount);
    writeBlock(right, _handLandmarkCount);
    return values;
  }

  /// Shoulder-center subtraction + shoulder-width scaling, per
  /// preprocessing_spec.json. Applied to the whole 75-landmark frame,
  /// not just the pose block, so hands are normalized in the same
  /// reference frame as the body.
  Float32List _normalize(Float32List raw) {
    final leftShoulderOffset = _leftShoulderIdx * _coordsPerPoint;
    final rightShoulderOffset = _rightShoulderIdx * _coordsPerPoint;

    final lx = raw[leftShoulderOffset];
    final ly = raw[leftShoulderOffset + 1];
    final lz = raw[leftShoulderOffset + 2];
    final rx = raw[rightShoulderOffset];
    final ry = raw[rightShoulderOffset + 1];
    final rz = raw[rightShoulderOffset + 2];

    final centerX = (lx + rx) / 2.0;
    final centerY = (ly + ry) / 2.0;
    final centerZ = (lz + rz) / 2.0;

    final dx = rx - lx, dy = ry - ly, dz = rz - lz;
    var shoulderWidth = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (shoulderWidth < 1e-6) shoulderWidth = 1e-6; // guard div-by-zero

    final out = Float32List(raw.length);
    for (int i = 0; i < raw.length; i += 3) {
      out[i] = (raw[i] - centerX) / shoulderWidth;
      out[i + 1] = (raw[i + 1] - centerY) / shoulderWidth;
      out[i + 2] = (raw[i + 2] - centerZ) / shoulderWidth;
    }
    return out;
  }

  /// Builds the final [1, 200, 450] input: for each frame, position (225)
  /// followed by velocity (225) = frame[t] - frame[t-1]. Frame 0's
  /// velocity is zero -- matches real training samples, where frame 0
  /// is either a zero-pad frame (velocity trivially 0) or, for
  /// full-length clips, the first real frame with nothing to diff
  /// against.
  ///
  /// `positionFrames` must already be exactly [sequenceLength] long and
  /// right-aligned (see [_rightAlignAndPad]) before reaching here.
  void _runInference(List<Float32List> positionFrames) {
    final interpreter = _interpreter;
    if (interpreter == null || _labels.isEmpty) return;

    final sequence = List.generate(sequenceLength, (t) {
      final frame = Float32List(featuresPerFrame);
      final pos = positionFrames[t];
      for (int k = 0; k < positionFeatures; k++) {
        frame[k] = pos[k];
      }
      if (t == 0) {
        for (int k = 0; k < velocityFeatures; k++) {
          frame[positionFeatures + k] = 0.0;
        }
      } else {
        final prev = positionFrames[t - 1];
        for (int k = 0; k < velocityFeatures; k++) {
          frame[positionFeatures + k] = pos[k] - prev[k];
        }
      }
      return frame.toList();
    });

    final input = [sequence]; // [1, 200, 450]
    final output = [List.filled(_labels.length, 0.0)]; // [1, 200] logits

    try {
      interpreter.run(input, output);
    } catch (e) {
      onModelStatusChanged?.call(false, 'Inference failed: $e');
      return;
    }

    final probs = _softmax(output[0]);
    var bestIndex = 0;
    var bestScore = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestScore) {
        bestScore = probs[i];
        bestIndex = i;
      }
    }

    final accepted = bestScore >= confidenceThreshold;
    onSegmentClassified?.call(_labels[bestIndex], bestScore, accepted);
    if (accepted) {
      onGestureRecognized?.call(_labels[bestIndex], bestScore);
    }
  }

  /// Model output is raw logits, not probabilities -- softmax first so
  /// [confidenceThreshold] means what it looks like it means.
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
    final sum = exps.fold<double>(0.0, (a, b) => a + b);
    return exps.map((v) => v / sum).toList();
  }

  /// Clears the current in-progress segment without classifying it --
  /// useful when the user explicitly stops/resets a live session.
  void resetBuffer() {
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;
    _lastFrame = null;
  }

  void dispose() {
    _interpreter?.close();
  }
}