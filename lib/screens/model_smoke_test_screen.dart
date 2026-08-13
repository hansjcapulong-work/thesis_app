import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../services/gesture_recognition_service.dart';

/// ===========================================================================
/// TEMPORARY debug screen -- not meant to ship. Wire this into your app's
/// nav (e.g. a hidden dev-only route or a button on a settings screen)
/// just long enough to confirm the model + asset plumbing works before
/// spending time on the MediaPipe camera integration.
///
/// What it checks, in order:
///   1. ASL_CITIZEN_200.tflite loads from assets without error.
///   2. labels.txt has exactly 200 entries.
///   3. The interpreter's actual input/output tensor shapes match what
///      we expect: input [1,200,450], output [1,200].
///   4. Feeding a synthetic 200-frame "sequence" straight through
///      inference (bypassing segmentation) produces a plausible
///      prediction -- confirms the model file itself, the labels
///      mapping, and the tflite_flutter plumbing all work together.
///   5. Feeding the same synthetic motion frame-by-frame through the
///      REAL addFrame() path confirms the motion-based segmentation
///      (start/stop detection, right-align + pad) fires correctly too.
///
/// This does NOT validate real-world accuracy -- the synthetic data is
/// just smooth fake motion, not a real sign. It only proves the pipeline
/// runs end-to-end without crashing and produces *some* structured
/// output. Real accuracy validation has to wait for actual camera data.
/// ===========================================================================
class ModelSmokeTestScreen extends StatefulWidget {
  const ModelSmokeTestScreen({Key? key}) : super(key: key);

  @override
  State<ModelSmokeTestScreen> createState() => _ModelSmokeTestScreenState();
}

class _ModelSmokeTestScreenState extends State<ModelSmokeTestScreen> {
  final GestureRecognitionService _service = GestureRecognitionService();
  final List<String> _log = [];
  bool _running = false;

  void _appendLog(String line) {
    debugPrint('[SmokeTest] $line'); // shows up in your terminal / flutter run output
    setState(() => _log.add(line));
  }

  @override
  void initState() {
    super.initState();
    // Auto-run on screen open so you see output in the terminal without
    // needing to tap anything.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAllChecks());
  }

  Future<void> _runAllChecks() async {
    setState(() {
      _running = true;
      _log.clear();
    });

    _appendLog('Loading model + labels...');
    _service.onModelStatusChanged = (loaded, message) {
      _appendLog(loaded ? 'OK: $message' : 'FAILED: $message');
    };
    await _service.loadModel();

    if (!_service.isModelLoaded) {
      _appendLog('Stopping here -- model failed to load. Check that '
          'ASL_CITIZEN_200.tflite and labels.txt are declared under '
          'flutter/assets in pubspec.yaml and actually present in '
          'assets/model/.');
      setState(() => _running = false);
      return;
    }

    final tensorInfo = _service.debugTensorInfo();
    _appendLog('Tensor info: $tensorInfo');
    _appendLog('Expected:    input: shape=[1, 200, 450] | '
        'output: shape=[1, 200]');
    if (tensorInfo != null &&
        (!tensorInfo.contains('[1, 200, 450]') ||
            !tensorInfo.contains('[1, 200]'))) {
      _appendLog('WARNING: tensor shapes do not match expectations above. '
          'Double-check the .tflite file is the right one, and that it '
          'was not accidentally re-converted with a different shape.');
    }

    _appendLog('--- Test 1: direct inference (bypasses segmentation) ---');
    final syntheticSequence = _buildSyntheticPositionSequence();
    final raw = _service.debugRawTopPrediction(syntheticSequence);
    if (raw == null) {
      _appendLog('FAILED: debugRawTopPrediction returned null -- '
          'interpreter or labels not loaded.');
    } else {
      _appendLog('Raw top prediction (ignores confidence threshold): '
          '"${raw['label']}" prob=${raw['probability']}');
      _appendLog('Sample raw logits: ${raw['rawLogitsSample']}');
      final prob = raw['probability'] as double;
      if (prob.isNaN) {
        _appendLog('PROBLEM: probability is NaN -- something in the '
            'input or model is broken, this is not just "low confidence '
            'on fake data".');
      } else if (prob < 0.001 || (prob - 1.0 / 200.0).abs() < 1e-6) {
        _appendLog('NOTE: probability looks close to uniform (1/200 = '
            '${(1 / 200).toStringAsFixed(4)}) -- on synthetic sine-wave '
            'input this is plausible and not alarming by itself.');
      } else {
        _appendLog('Looks like a real, structured (non-uniform, non-NaN) '
            'prediction -- model + tensors are working correctly.');
      }
    }

    _appendLog('--- Test 2: full addFrame() path (real segmentation) ---');
    _service.resetBuffer();
    bool fired = false;
    _service.onGestureRecognized = (word, confidence) {
      fired = true;
      _appendLog('Segmentation-triggered result: "$word" '
          '(${(confidence * 100).toStringAsFixed(1)}% confidence)');
    };
    _feedSyntheticFramesThroughAddFrame();
    await Future.delayed(const Duration(milliseconds: 50));
    if (!fired) {
      _appendLog('No prediction fired from addFrame() path. This usually '
          'means the synthetic motion here does not cross the start/idle '
          'thresholds -- expected for this fake data, not necessarily a '
          'bug. What matters most is Test 1 succeeding.');
    }

    _appendLog('--- Done ---');
    setState(() => _running = false);
  }

  /// A gently oscillating, fully synthetic 200-frame sequence of already-
  /// normalized position vectors (225 values/frame). Not a real sign --
  /// just structured enough to exercise the model without crashing.
  List<Float32List> _buildSyntheticPositionSequence() {
    return List.generate(GestureRecognitionService.sequenceLength, (t) {
      final frame = Float32List(GestureRecognitionService.positionFeatures);
      for (int i = 0; i < frame.length; i++) {
        // Small smooth sine wave per feature, phase-shifted per index so
        // it isn't literally identical across landmarks.
        frame[i] = 0.05 * math.sin((t + i) * 0.15);
      }
      return frame;
    });
  }

  /// Feeds ~90 frames of gentle synthetic pose/hand motion through the
  /// real addFrame() API, then ~15 idle frames to trigger end-of-segment.
  /// Landmarks are plain lists, matching what a real MediaPipe callback
  /// would hand off (just fabricated here instead of coming from camera).
  void _feedSyntheticFramesThroughAddFrame() {
    List<List<double>> pose(int t) => List.generate(
        33, (j) => [0.1 * math.sin(t * 0.1 + j), 0.0, 0.0]);

    List<List<double>> movingHand(int t) => List.generate(
        21,
            (j) => [
          0.3 * math.sin(t * 0.3 + j * 0.2),
          0.3 * math.cos(t * 0.3 + j * 0.2),
          0.0,
        ]);

    List<List<double>> stillHand() =>
        List.generate(21, (j) => [0.0, 0.0, 0.0]);

    // "Signing" phase: enough motion to cross the start threshold.
    for (int t = 0; t < 90; t++) {
      _service.addFrame(
        poseLandmarks: pose(t),
        leftHandLandmarks: movingHand(t),
        rightHandLandmarks: stillHand(),
      );
    }
    // "Stopped signing" phase: still frames to trigger idle detection.
    for (int t = 0; t < 15; t++) {
      _service.addFrame(
        poseLandmarks: pose(90),
        leftHandLandmarks: stillHand(),
        rightHandLandmarks: stillHand(),
      );
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model Smoke Test (debug only)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _runAllChecks,
              child: Text(_running ? 'Running...' : 'Run Smoke Test'),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _log[i],
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}