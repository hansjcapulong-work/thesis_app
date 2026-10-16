import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../services/gesture_recognition_service.dart';

/// Minimal, isolated test screen for JUST the camera -> model input
/// pipeline described in the README -- no speech-to-gesture, no avatar,
/// no conversation history. Exists so the five preprocessing steps can
/// be verified end-to-end on a real device without anything else in the
/// app being in the way:
///
///   1. Run hand_landmarker on each camera frame -> 21 landmarks/hand,
///      each with real (x, y, z), normalized to [0,1] on x/y.
///   2. Build a (2, 21, 3) array per frame: index 0 = Left, index 1 =
///      Right (zeros for a hand not detected that frame).
///   3. Normalize each hand relative to ITS OWN wrist (landmark 0).
///   4. Collect frames for one "sign attempt," trim leading/trailing
///      no-hand frames, resample to exactly 30 frames.
///   5. Flatten to (30, 126), add batch dim -> (1, 30, 126), run
///      inference.
///
/// Steps 2-5 are exactly what [GestureRecognitionService] already
/// implements -- this screen is just the thinnest possible camera+UI
/// wrapper around it, so there's nothing else that could be masking a
/// bug in the pipeline itself.
class GestureRecognitionTestScreen extends StatefulWidget {
  const GestureRecognitionTestScreen({Key? key}) : super(key: key);

  @override
  State<GestureRecognitionTestScreen> createState() =>
      _GestureRecognitionTestScreenState();
}

class _GestureRecognitionTestScreenState
    extends State<GestureRecognitionTestScreen> {
  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  final GestureRecognitionService _gestureService = GestureRecognitionService();

  bool _cameraInitialized = false;
  String? _cameraInitError;
  bool _processingHandFrame = false;

  bool _modelLoaded = false;
  String _modelStatusMessage = 'Loading model...';
  String _tensorInfo = '—';

  int _handsVisible = 0;
  String _lastPrediction = '—';
  double _lastConfidence = 0.0;
  String? _lastSegmentDebug;

  @override
  void initState() {
    super.initState();

    _gestureService.onModelStatusChanged = (isLoaded, message) {
      if (!mounted) return;
      setState(() {
        _modelLoaded = isLoaded;
        _modelStatusMessage = message;
        _tensorInfo = _gestureService.tensorInfo;
      });
    };

    // Fires only when a segment's confidence clears the threshold --
    // this is the actual "recognized word" event.
    _gestureService.onGestureRecognized = (word, confidence) {
      if (!mounted) return;
      setState(() {
        _lastPrediction = word;
        _lastConfidence = confidence;
      });
    };

    // Fires for every completed segment regardless of threshold, so
    // low-confidence guesses are still visible here for debugging --
    // onGestureRecognized alone would hide those.
    _gestureService.onSegmentClassified = (topLabel, confidence, accepted) {
      if (!mounted) return;
      setState(() {
        _lastSegmentDebug = accepted
            ? '"$topLabel" ${(confidence * 100).toStringAsFixed(0)}% (accepted)'
            : '"$topLabel" ${(confidence * 100).toStringAsFixed(0)}% '
            '(below ${(GestureRecognitionService.confidenceThreshold * 100).toStringAsFixed(0)}% threshold)';
      });
    };

    _gestureService.onSegmentDiscarded = (captured, minRequired) {
      if (!mounted) return;
      setState(() {
        _lastSegmentDebug =
        'Segment discarded: only $captured usable frames (need $minRequired+)';
      });
    };

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _gestureService.loadModel();

      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _plugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processCameraImage);
      _plugin!.landmarkStream.listen(_onHandsDetected);

      if (!mounted) return;
      setState(() => _cameraInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraInitError = 'Camera setup failed: $e');
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_plugin == null || _controller == null || _processingHandFrame) return;
    _processingHandFrame = true;
    try {
      _plugin!.processFrame(image, _controller!.description.sensorOrientation);
    } catch (e) {
      _processingHandFrame = false;
      debugPrint('Error processing camera frame: $e');
    }
  }

  /// Step 1+2: turn this frame's detected hands into the (2, 21, 3)
  /// shape GestureRecognitionService expects, then hand it off.
  ///
  /// NOTE: hand_landmarker's Hand doesn't expose a handedness label, so
  /// with two hands visible this falls back to sorting by x position
  /// (smaller x = left in a front-camera preview). Verify this against
  /// how the training data was labeled -- if predictions come out
  /// systematically mirrored, this left/right assignment is the first
  /// place to check.
  ///
  /// FIX (single-hand case): previously this always assigned a lone
  /// detected hand to leftLandmarks regardless of which hand it
  /// actually was, which is wrong whenever the visible hand is the
  /// signer's right hand -- the model would receive real right-hand
  /// shaped data sitting in the Left slot, a pattern it never saw in
  /// training (training only ever put mirrored/flipped data in the
  /// Left slot for right-hand-style signs, via the augmentation step
  /// described in the README). Now a lone hand is assigned by
  /// comparing its wrist x-position against the frame center (0.5),
  /// same idea as the two-hand sort below just applied against a fixed
  /// reference point instead of against a second hand.
  ///
  /// IMPORTANT: verify the direction below empirically on-device. Sign
  /// a word you know uses only your right hand -- if the prediction is
  /// correct, this mapping is right. If it's still wrong/confused, flip
  /// the two branches (swap which one assigns to rightLandmarks vs
  /// leftLandmarks). This depends on whether the raw CameraImage fed to
  /// processFrame() is mirrored the same way the on-screen preview is,
  /// which can vary by platform/plugin and isn't something to assume
  /// without testing.
  void _onHandsDetected(List<Hand> hands) {
    if (!mounted) return;
    _processingHandFrame = false;
    setState(() => _handsVisible = hands.length);

    List<List<double>>? leftLandmarks;
    List<List<double>>? rightLandmarks;

    if (hands.length == 1) {
      final coords = hands.first.landmarks.map((l) => [l.x, l.y, l.z]).toList();
      final wristX = hands.first.landmarks[0].x; // landmark 0 = wrist

      // Front camera preview is typically mirrored, so a hand appearing
      // on the LEFT side of the screen (smaller x) is usually the
      // signer's actual RIGHT hand, and vice versa. VERIFY on-device --
      // see note above.
      if (wristX < 0.5) {
        rightLandmarks = coords;
      } else {
        leftLandmarks = coords;
      }
    } else if (hands.length >= 2) {
      final sorted = List<Hand>.from(hands)
        ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));
      // SWAPPED (from the original leftLandmarks=sorted[0] /
      // rightLandmarks=sorted[1]) to match the convention confirmed
      // correct for the single-hand case above: smaller x = actual
      // RIGHT hand (front camera mirroring), larger x = actual LEFT
      // hand. The two-hand case was never independently verified until
      // most two-hand-sign predictions came back wrong live -- this
      // swap fixes that.
      rightLandmarks =
          sorted[0].landmarks.map((l) => [l.x, l.y, l.z]).toList();
      leftLandmarks =
          sorted[1].landmarks.map((l) => [l.x, l.y, l.z]).toList();
    }

    // Steps 2-5 (build vector, per-hand wrist normalization, segment
    // capture, trim, resample to 30, run inference) all happen inside
    // the service -- see gesture_recognition_service.dart.
    _gestureService.addFrame(
      leftHandLandmarks: leftLandmarks,
      rightHandLandmarks: rightLandmarks,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gesture Recognition Test')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCameraView()),
            _buildStatusPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraInitError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _cameraInitError!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!_cameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = _controller!.value.previewSize!;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(_controller!),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _modelLoaded ? Icons.check_circle : Icons.error_outline,
                size: 14,
                color: _modelLoaded ? Colors.greenAccent : Colors.orangeAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _modelStatusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tensorInfo,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const Divider(color: Colors.white24, height: 20),
          Row(
            children: [
              Text(
                'Hands visible: $_handsVisible',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Icon(
                _gestureService.isCapturingSegment
                    ? Icons.fiber_manual_record
                    : Icons.pause_circle_outline,
                size: 14,
                color: _gestureService.isCapturingSegment
                    ? Colors.redAccent
                    : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                _gestureService.isCapturingSegment
                    ? 'capturing (${_gestureService.activeSegmentLength} frames)'
                    : 'idle',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _lastPrediction,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_lastConfidence > 0)
            Text(
              '${(_lastConfidence * 100).toStringAsFixed(1)}% confidence',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
            ),
          if (_lastSegmentDebug != null) ...[
            const SizedBox(height: 6),
            Text(
              _lastSegmentDebug!,
              style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _plugin?.dispose();
    _gestureService.dispose();
    super.dispose();
  }
}
