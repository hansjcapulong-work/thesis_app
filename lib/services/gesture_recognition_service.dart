import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'server_config.dart';

/// ===========================================================================
/// CLOUD-HYBRID VERSION.
///
/// On-device: camera -> landmarks -> normalization -> motion-based
/// segmentation. This part MUST stay on-device -- it needs to run in
/// real time on every frame to detect when a sign starts/stops, and
/// round-tripping raw frames to a server for that would add latency
/// this logic isn't built to tolerate.
///
/// Off-device: once a segment finishes (see [_endSegmentAndClassify]),
/// the finished [200, 450] position+velocity sequence is POSTed to the
/// SAME laptop server WhisperService talks to (see server_config.dart),
/// hitting /recognize-gesture instead of /transcribe. This only fires
/// once per completed sign (a few times a minute), not per frame, so
/// the extra network round-trip is cheap relative to what it saves:
/// no more on-device .tflite interpreter running, which was the
/// likely source of the overheating (that, plus the pose/hand
/// landmarkers below, which still run on-device -- see the note on
/// [addFrame]).
///
/// No on-device fallback model is bundled per your call to go
/// cloud-only for now -- if the server is unreachable, segments will
/// simply fail to classify and onModelStatusChanged will report why.
///
/// Server-side expectations (server.py's /recognize-gesture):
///   - Same model file as before: ASL_CITIZEN_200_BiLSTM.tflite
///   - Same class_list.txt validation logic, ported to Python
///   - Request:  {"sequence": [[450 floats] x 200]}
///   - Response: {"label": "...", "confidence": 0.0-1.0}
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

  // Every landmark (pose + both hands) is x,y,z -- 3 coords.
  static const int _coordsPerPoint = 3;
  static const int positionFeatures = totalLandmarks * _coordsPerPoint; // 225
  static const int velocityFeatures = positionFeatures; // 225, frame-to-frame delta
  static const int featuresPerFrame = positionFeatures + velocityFeatures; // 450

  // Shoulder landmarks (within the pose block) used for normalization.
  static const int _leftShoulderIdx = 11;
  static const int _rightShoulderIdx = 12;

  // Server returns a probability (post-softmax on its end), so this
  // threshold means the same thing it did when softmax ran on-device.
  static const double confidenceThreshold = 0.60;

  static const Duration _requestTimeout = Duration(seconds: 15);

  // --- Motion-based segmentation ---------------------------------------
  // This logic runs on-device and doesn't depend on where classification
  // happens.
  //
  // _motionIdleThreshold was raised from the original 0.5 -- with hand
  // landmarker jitter alone (landmarks drift a little frame-to-frame
  // even when your hand is genuinely still), raw per-frame motion often
  // never dropped below 0.5, so segments only ever ended by hitting the
  // 200-frame cap, never by detecting "you stopped signing." Idle
  // detection now also compares a SMOOTHED motion value (rolling
  // average over _motionSmoothingWindow frames, see _smoothedIdleMotion)
  // instead of the raw single-frame value, so a brief jitter spike
  // doesn't reset the idle counter to 0.
  //
  // If idle-based segment ending still isn't triggering for you, set
  // _debugMotion to true below and watch the console while you sign --
  // it prints raw + smoothed motion every frame during capture, so you
  // can see exactly where your "holding still" values land and tune
  // _motionIdleThreshold to match.
  static const double _motionStartThreshold = 1.2;
  static const double _motionIdleThreshold = 0.8;
  static const int _idleFramesToEndSegment = 10;
  static const int _minSegmentFrames = 8;
  static const int _motionSmoothingWindow = 4;

  /// Set true to print raw/smoothed motion values to the console while
  /// a segment is being captured. Turn off once tuned -- it's noisy.
  static const bool _debugMotion = true;

  // Frames captured since the current sign segment started (variable
  // length, capped at sequenceLength). Cleared between segments.
  final List<Float32List> _activeSegment = [];

  bool _isCapturing = false;
  int _idleFrameCount = 0;
  Float32List? _lastFrame;
  bool _serverReachable = false;

  // Rolling buffer of the last few raw motion values, used to compute
  // _smoothedIdleMotion so single-frame jitter spikes don't keep
  // resetting the idle counter.
  final List<double> _recentMotion = [];

  // Guards against overlapping requests if a segment finishes again
  // before the previous classification call has returned.
  bool _classifying = false;

  /// Called with (recognizedWord, confidence) whenever a full 200-frame
  /// window is classified above [confidenceThreshold].
  void Function(String word, double confidence)? onGestureRecognized;

  /// Called after EVERY segment is classified, regardless of whether it
  /// cleared [confidenceThreshold] -- unlike [onGestureRecognized], this
  /// always fires once a segment finishes and the server responds.
  /// `accepted` is true exactly when [onGestureRecognized] also fired.
  void Function(String topLabel, double confidence, bool accepted)? onSegmentClassified;

  /// Called when a segment ends but was too short to bother classifying
  /// (see [_minSegmentFrames]).
  void Function(int capturedFrames, int minRequiredFrames)? onSegmentDiscarded;

  /// Called once after checking the server, and again any time a
  /// classification request fails (e.g. WiFi dropped, server crashed).
  void Function(bool isLoaded, String message)? onModelStatusChanged;

  bool get isModelLoaded => _serverReachable;

  /// True while a sign segment is actively being captured.
  bool get isCapturingSegment => _isCapturing;

  /// Number of frames currently buffered in the in-progress segment.
  int get activeSegmentLength => _activeSegment.length;

  /// Checks that the laptop server is reachable (GET /health, same
  /// endpoint server.py already exposes for WhisperService). Doesn't
  /// load anything locally -- there's no model or class list on-device
  /// anymore, classification happens server-side.
  Future<void> loadModel() async {
    try {
      final response = await http
          .get(Uri.parse('${ServerConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _serverReachable = true;
        onModelStatusChanged?.call(
          true,
          'Connected to gesture server at ${ServerConfig.baseUrl}.',
        );
      } else {
        _serverReachable = false;
        onModelStatusChanged?.call(
          false,
          'Server responded with ${response.statusCode} at /health.',
        );
      }
    } catch (e) {
      _serverReachable = false;
      onModelStatusChanged?.call(
        false,
        'Could not reach the gesture server at ${ServerConfig.baseUrl}. '
            'Make sure server.py is running and your phone is on the same '
            'WiFi network as your laptop. ($e)',
      );
    }
  }

  /// Feeds one frame's worth of landmark data into the segmenter.
  /// Pass null for anything not detected in this frame -- zero-padded.
  ///
  /// [poseLandmarks]: 33 [x, y, z] triples.
  /// [leftHandLandmarks] / [rightHandLandmarks]: 21 [x, y, z] triples each.
  ///
  /// NOTE: pose data is required (not safely nullable) -- see
  /// [_normalize]. Frames without real pose data are dropped here
  /// rather than fed through, same as before.
  ///
  /// Call this every camera frame, continuously. Internally this still
  /// runs entirely on-device: landmark extraction, normalization, and
  /// motion-based segmentation don't change with this cloud-hybrid
  /// setup. Only the final classification step (once per finished
  /// segment) now goes over the network.
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
      // Raw (unsmoothed) motion for start detection -- responsiveness
      // matters more than stability here, and a single-frame false
      // start just gets cleaned up by _minSegmentFrames if it's noise.
      if (motion > _motionStartThreshold) {
        _isCapturing = true;
        _idleFrameCount = 0;
        _recentMotion.clear();
        _activeSegment.clear();
        _activeSegment.add(normalizedFrame);
      }
      return;
    }

    _activeSegment.add(normalizedFrame);

    final smoothedMotion = _smoothedIdleMotion(motion);
    if (_debugMotion) {
      // ignore: avoid_print
      print(
        '[gesture] frame ${_activeSegment.length}: raw=${motion.toStringAsFixed(3)} '
            'smoothed=${smoothedMotion.toStringAsFixed(3)} '
            'idleCount=$_idleFrameCount (threshold=$_motionIdleThreshold)',
      );
    }
    _idleFrameCount =
    smoothedMotion < _motionIdleThreshold ? _idleFrameCount + 1 : 0;

    final hitMaxLength = _activeSegment.length >= sequenceLength;
    final wentIdle = _idleFrameCount >= _idleFramesToEndSegment;

    if (hitMaxLength || wentIdle) {
      if (_debugMotion) {
        // ignore: avoid_print
        print(
          '[gesture] segment ending: ${hitMaxLength ? "hit max length" : "went idle"} '
              '(${_activeSegment.length} frames)',
        );
      }
      _endSegmentAndClassify();
    }
  }

  /// Rolling average of the last [_motionSmoothingWindow] raw motion
  /// values. Filters out single-frame jitter spikes so idle detection
  /// only responds to sustained stillness, not detector noise.
  double _smoothedIdleMotion(double latestRawMotion) {
    _recentMotion.add(latestRawMotion);
    if (_recentMotion.length > _motionSmoothingWindow) {
      _recentMotion.removeAt(0);
    }
    return _recentMotion.reduce((a, b) => a + b) / _recentMotion.length;
  }

  /// Sum of |delta| across the hand landmarks only, used as a cheap
  /// motion signal to detect sign start/stop.
  double _handMotion(Float32List prev, Float32List current) {
    const handStart = _poseLandmarkCount * _coordsPerPoint; // 99
    var total = 0.0;
    for (int i = handStart; i < positionFeatures; i++) {
      total += (current[i] - prev[i]).abs();
    }
    return total;
  }

  /// Finalizes the current segment, right-aligns/pads it, and kicks off
  /// the (async, network-backed) classification call. Resets to idle
  /// immediately -- classification happening asynchronously afterward
  /// doesn't block new segments from starting.
  void _endSegmentAndClassify() {
    final captured = List.of(_activeSegment);
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;
    _recentMotion.clear();

    if (captured.length < _minSegmentFrames) {
      onSegmentDiscarded?.call(captured.length, _minSegmentFrames);
      return;
    }

    final aligned = _rightAlignAndPad(captured);
    // Fire-and-forget: addFrame() callers don't await this, matching
    // the old synchronous call's "not blocking the frame loop" behavior.
    _classifyRemote(aligned);
  }

  /// Builds an exactly-`sequenceLength`-long list of position frames:
  ///   - if `frames` is shorter, pad the FRONT with zero vectors
  ///   - if `frames` is longer, keep the LAST `sequenceLength` frames
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
  /// preprocessing_spec.json.
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
    if (shoulderWidth < 1e-6) shoulderWidth = 1e-6;

    final out = Float32List(raw.length);
    for (int i = 0; i < raw.length; i += 3) {
      out[i] = (raw[i] - centerX) / shoulderWidth;
      out[i + 1] = (raw[i + 1] - centerY) / shoulderWidth;
      out[i + 2] = (raw[i + 2] - centerZ) / shoulderWidth;
    }
    return out;
  }

  /// Builds the [200, 450] position+velocity sequence (same math as the
  /// on-device version -- kept in Dart rather than duplicated in Python
  /// so there's one source of truth for this preprocessing step), then
  /// POSTs it to /recognize-gesture and dispatches the same callbacks
  /// the on-device version used to fire directly.
  Future<void> _classifyRemote(List<Float32List> positionFrames) async {
    if (_classifying) return; // drop overlapping requests rather than queue
    _classifying = true;

    try {
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

      http.Response response;
      try {
        response = await http
            .post(
          Uri.parse('${ServerConfig.baseUrl}/recognize-gesture'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sequence': sequence}),
        )
            .timeout(_requestTimeout);
      } catch (e) {
        onModelStatusChanged?.call(
          false,
          'Could not reach the gesture server at ${ServerConfig.baseUrl}. '
              'Make sure server.py is running and your phone is on the same '
              'WiFi network as your laptop. ($e)',
        );
        return;
      }

      if (response.statusCode != 200) {
        onModelStatusChanged?.call(
          false,
          'Gesture server error (${response.statusCode}): ${response.body}',
        );
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final label = data['label'] as String?;
      final confidence = (data['confidence'] as num?)?.toDouble();

      if (label == null || confidence == null) {
        onModelStatusChanged?.call(
          false,
          'Gesture server returned an unexpected response: ${response.body}',
        );
        return;
      }

      final accepted = confidence >= confidenceThreshold;
      onSegmentClassified?.call(label, confidence, accepted);
      if (accepted) {
        onGestureRecognized?.call(label, confidence);
      }
    } finally {
      _classifying = false;
    }
  }

  /// Clears the current in-progress segment without classifying it.
  void resetBuffer() {
    _activeSegment.clear();
    _isCapturing = false;
    _idleFrameCount = 0;
    _lastFrame = null;
    _recentMotion.clear();
  }

  void dispose() {
    // Nothing to close -- no local interpreter anymore.
  }
}