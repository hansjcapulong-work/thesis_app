import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../services/gesture_recognition_service.dart';
import '../services/tts_service.dart';

/// Live camera screen for the ASL-to-speech direction: captures video,
/// extracts hand landmarks in real time via MediaPipe (through the
/// hand_landmarker plugin), buffers them, and once your trained TFLite
/// model is dropped into assets/model/, recognizes signs and speaks
/// them aloud.
///
/// Works today in "no model yet" mode -- camera, landmark tracking, and
/// buffering all run and can be verified before any model exists.
class LiveTranslationScreen extends StatefulWidget {
  const LiveTranslationScreen({Key? key}) : super(key: key);

  @override
  State<LiveTranslationScreen> createState() => _LiveTranslationScreenState();
}

class _LiveTranslationScreenState extends State<LiveTranslationScreen> {
  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  final TtsService _tts = TtsService();

  bool _isInitialized = false;
  String? _initError;
  String _modelStatus = 'Loading model...';
  String _recognizedText = '';
  int _handsVisible = 0;

  @override
  void initState() {
    super.initState();
    _gestureService.onModelStatusChanged = (isLoaded, message) {
      if (!mounted) return;
      setState(() => _modelStatus = message);
    };
    _gestureService.onGestureRecognized = (word, confidence) {
      if (!mounted) return;
      setState(() => _recognizedText = '$_recognizedText $word'.trim());
      _tts.speak(word);
    };
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _gestureService.loadModel();
      await _tts.init();

      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      // numHands: 2 to capture two-handed signs. Lower
      // minHandDetectionConfidence slightly if hands aren't being
      // picked up reliably in your lighting; raise it if you get
      // false positives.
      _plugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );

      await _controller!.initialize();
      await _controller!.startImageStream(_processCameraImage);

      _plugin!.landmarkStream.listen(_onHandsDetected);

      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'Camera/model setup failed: $e');
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_plugin == null) return;
    try {
      _plugin!.processFrame(image, _controller!.description.sensorOrientation);
    } catch (e) {
      debugPrint('Error processing camera frame: $e');
    }
  }

  /// Called every time the plugin finishes analyzing a frame. Splits
  /// detected hands into left/right slots and feeds them into the
  /// recognition service's rolling buffer.
  ///
  /// NOTE: this plugin's example doesn't clearly expose a handedness
  /// label on Hand objects, so this uses a position-based fallback
  /// (leftmost detected hand -> left slot). Check
  /// https://pub.dev/documentation/hand_landmarker/latest/ for a more
  /// reliable handedness field if one exists, and swap this logic out
  /// if your recognition accuracy suggests hands are being mislabeled.
  void _onHandsDetected(List<Hand> hands) {
    if (!mounted) return;
    setState(() => _handsVisible = hands.length);

    List<List<double>>? leftLandmarks;
    List<List<double>>? rightLandmarks;

    if (hands.length == 1) {
      final points = hands.first.landmarks.map((l) => [l.x, l.y, 0.0]).toList();
      // Single hand detected -- assign to left by default. Adjust if
      // your model was trained expecting a specific slot for
      // single-hand signs.
      leftLandmarks = points;
    } else if (hands.length >= 2) {
      final sorted = List<Hand>.from(hands)
        ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));
      leftLandmarks = sorted[0].landmarks.map((l) => [l.x, l.y, 0.0]).toList();
      rightLandmarks = sorted[1].landmarks.map((l) => [l.x, l.y, 0.0]).toList();
    }

    _gestureService.addFrame(
      leftHandLandmarks: leftLandmarks,
      rightHandLandmarks: rightLandmarks,
    );
  }

  void _clearText() {
    setState(() => _recognizedText = '');
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _plugin?.dispose();
    _gestureService.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Translation')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_initError!, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final controller = _controller!;
    final previewSize = controller.value.previewSize!;
    final previewAspectRatio = previewSize.height / previewSize.width;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Live Translation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: previewAspectRatio,
                child: CameraPreview(controller),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.grey.shade900,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _modelStatus,
                  style: TextStyle(
                    color: _gestureService.isModelLoaded ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hands visible: $_handsVisible',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text(
                  _recognizedText.isEmpty ? 'Waiting for signs...' : _recognizedText,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _clearText,
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
