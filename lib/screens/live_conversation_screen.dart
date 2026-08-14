import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../data/asl_words.dart';
import '../services/gesture_recognition_service.dart';
import '../services/gloss_matcher.dart';
import '../services/tts_service.dart';
import '../services/whisper_service.dart';
import '../services/conversation_history_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';

const _purple = Color(0xFF2A1B38);

enum _EntrySource { signed, spoken }

class _ConversationEntry {
  final _EntrySource source;
  final String text;
  final DateTime timestamp;
  _ConversationEntry(this.source, this.text) : timestamp = DateTime.now();
}

class LiveConversationScreen extends StatefulWidget {
  const LiveConversationScreen({Key? key}) : super(key: key);

  @override
  State<LiveConversationScreen> createState() => _LiveConversationScreenState();
}

class _LiveConversationScreenState extends State<LiveConversationScreen> {
  // --- Gesture-to-speech side (camera) ---
  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  bool _cameraInitialized = false;
  String? _cameraInitError;
  bool _modelLoaded = false;
  String? _modelStatusMessage;
  int _handsVisible = 0;

  // Pose landmarker: runs alongside the hand landmarker to supply the
  // shoulder-anchored body pose GestureRecognitionService needs for
  // normalization (see the note on addFrame). ML Kit's pose is async per
  // frame, so we cache the latest result and hand whatever we have to
  // addFrame each time a hand-landmark frame comes in, rather than trying
  // to hard-sync the two streams.
  PoseDetector? _poseDetector;
  List<List<double>>? _latestPoseLandmarks;
  bool _processingPoseFrame = false;
  bool _processingHandFrame = false;
  String? _poseErrorMessage;
  String? _lastSegmentDebug;

  final TtsService _tts = TtsService();

  // --- Speech-to-gesture side (mic) -- unchanged, still real ---
  final WhisperService _whisperService = WhisperService();
  bool _isRecording = false;
  bool _isTranscribing = false; // true while waiting on the server after Stop is tapped
  List<ASLWord> _matchedWords = [];
  int _currentWordIndex = 0;

  // --- Shared conversation history ---
  final List<_ConversationEntry> _conversation = [];
  final ScrollController _chatScrollController = ScrollController();
  bool _isMuted = false;

  // --- Persisted history: when this visit to the screen started ---
  final DateTime _sessionStartedAt = DateTime.now();

  // --- Draggable panel sizing ---
  // Height (in px) of the "Transcribe Conversation" panel. Null until the
  // first layout pass, at which point we seed it from the available height.
  double? _transcribeHeight;
  static const double _gap = 16.0;
  static const double _minTranscribeHeight = 160.0;
  static const double _minTopHeight = 160.0; // min combined height for input+ASL box

  ASLWord? get _currentWord =>
      _matchedWords.isNotEmpty && _currentWordIndex < _matchedWords.length
          ? _matchedWords[_currentWordIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _gestureService.onModelStatusChanged = (isLoaded, message) {
      if (!mounted) return;
      setState(() {
        _modelLoaded = isLoaded;
        _modelStatusMessage = message;
      });
    };
    _gestureService.onGestureRecognized = (word, confidence) {
      if (!mounted) return;
      _appendEntry(_EntrySource.signed, word);
      if (!_isMuted) _tts.speak(word);
    };
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
        _lastSegmentDebug = 'Segment discarded: only $captured frames (need $minRequired+)';
      });
    };
    _tts.init();
    _initCamera();
  }

  void _appendEntry(_EntrySource source, String text) {
    setState(() => _conversation.add(_ConversationEntry(source, text)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Persists everything exchanged during this visit to the screen. Fires
  /// once, when the screen is closed. Silently no-ops if the conversation
  /// was empty or nobody is signed in.
  void _saveConversationIfNeeded() {
    if (_conversation.isEmpty) return;
    ConversationHistoryService.saveSession(
      startedAt: _sessionStartedAt,
      entries: _conversation
          .map((e) => ConversationEntryData(
        source: e.source == _EntrySource.signed ? 'signed' : 'spoken',
        text: e.text,
        timestamp: e.timestamp,
      ))
          .toList(),
    );
  }

  // ─────────────────────────── Camera / gesture-to-speech ───────────────────────────

  Future<void> _initCamera() async {
    try {
      await _gestureService.loadModel();

      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
            (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Reverted from ImageFormatGroup.nv21: it fixed ML Kit's pose
      // converter (no more IllegalArgumentException), but collapsed the
      // Android CameraImage to a single plane on this device, which broke
      // hand_landmarker -- its native code indexes into 3 separate Y/U/V
      // planes and threw `RangeError: Only valid value is 0: 1` the moment
      // plane[1] didn't exist. Both consumers share one camera stream, so
      // the format has to work for both: staying on the standard 3-plane
      // yuv420 (what hand_landmarker expects) and making the manual NV21
      // conversion below correct is the only option that doesn't break one
      // to fix the other.
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      _plugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );

      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
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
    if (_plugin == null || _controller == null) return;
    // hand_landmarker's processFrame is fire-and-forget into a native
    // background thread with no returned Future, so there's nothing to
    // await here directly. Instead this is guarded the same way pose is:
    // don't dispatch a new frame until the previous one's result has come
    // back through landmarkStream (see _onHandsDetected). Camera frames
    // can arrive faster than native inference completes, and calling
    // processFrame again before that happens is what produced the
    // "Tensors are designed for single writes" warning -- overlapping
    // native calls reusing the same input tensor.
    if (!_processingHandFrame) {
      _processingHandFrame = true;
      try {
        _plugin!.processFrame(image, _controller!.description.sensorOrientation);
      } catch (e) {
        _processingHandFrame = false;
        debugPrint('Error processing camera frame: $e');
      }
    }
    _processPoseFrame(image);
  }

  /// Runs ML Kit pose detection on the current frame and caches the
  /// result. Guarded by [_processingPoseFrame] so frames don't queue up
  /// faster than detection can keep up -- if a pose result is still
  /// pending, this frame is skipped and the previous cached pose (if any)
  /// keeps being used until a fresher one lands.
  Future<void> _processPoseFrame(CameraImage image) async {
    final detector = _poseDetector;
    final controller = _controller;
    if (detector == null || controller == null || _processingPoseFrame) return;

    _processingPoseFrame = true;
    try {
      final inputImage = _inputImageFromCameraImage(image, controller.description);
      if (inputImage == null) return;

      final poses = await detector.processImage(inputImage);
      if (poses.isEmpty) return;

      // TODO(verify): ML Kit's Pose landmarks come back in image pixel
      // coordinates, while hand_landmarker's Hand.landmarks appear to be
      // normalized 0..1 (see _onHandsDetected). Dividing by image
      // width/height here is an assumption to line the two coordinate
      // spaces up before they both feed the same shoulder-relative
      // normalization in GestureRecognitionService -- confirm against a
      // real frame (e.g. log both sources side-by-side) rather than
      // trusting this blind, since a mismatch here would silently degrade
      // recognition rather than crash.
      final pose = poses.first;
      final width = image.width.toDouble();
      final height = image.height.toDouble();

      // Order here must match the 33-point BlazePose/MediaPipe topology
      // GestureRecognitionService expects (indices 0-32, shoulders at
      // 11/12 -- see _leftShoulderIdx/_rightShoulderIdx). This mapping
      // assumes google_mlkit_pose_detection's PoseLandmarkType names below
      // match your installed package version exactly -- enum member names
      // have shifted between versions before (e.g. mouth landmarks). If
      // this file fails to compile on "leftMouth"/"rightMouth", check
      // PoseLandmarkType's actual members for your pinned version and
      // adjust here rather than guessing.
      final ordered = <PoseLandmarkType>[
        PoseLandmarkType.nose,
        PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter,
        PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter,
        PoseLandmarkType.leftEar, PoseLandmarkType.rightEar,
        PoseLandmarkType.leftMouth, PoseLandmarkType.rightMouth,
        PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftElbow, PoseLandmarkType.rightElbow,
        PoseLandmarkType.leftWrist, PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftPinky, PoseLandmarkType.rightPinky,
        PoseLandmarkType.leftIndex, PoseLandmarkType.rightIndex,
        PoseLandmarkType.leftThumb, PoseLandmarkType.rightThumb,
        PoseLandmarkType.leftHip, PoseLandmarkType.rightHip,
        PoseLandmarkType.leftKnee, PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle, PoseLandmarkType.rightAnkle,
        PoseLandmarkType.leftHeel, PoseLandmarkType.rightHeel,
        PoseLandmarkType.leftFootIndex, PoseLandmarkType.rightFootIndex,
      ];

      final landmarks = ordered.map((type) {
        final lm = pose.landmarks[type];
        if (lm == null) return [0.0, 0.0, 0.0];
        return [lm.x / width, lm.y / height, lm.z];
      }).toList();

      if (!mounted) return;
      _latestPoseLandmarks = landmarks;
      if (_poseErrorMessage != null) setState(() => _poseErrorMessage = null);
    } catch (e) {
      debugPrint('Error processing pose frame: $e');
      // Surfaced on-screen (see the debug strip) rather than only in
      // debugPrint, so this doesn't require pulling logcat every time to
      // see what's actually failing. Throttled to avoid a setState on
      // every single failed frame (which would otherwise fire at camera
      // frame rate while pose stays broken).
      if (mounted && _poseErrorMessage != e.toString()) {
        setState(() => _poseErrorMessage = e.toString());
      }
    } finally {
      _processingPoseFrame = false;
    }
  }

  /// Standard camera_image -> InputImage conversion for ML Kit. Android's
  /// default camera format (`yuv420`, same format hand_landmarker consumes)
  /// delivers 3 SEPARATE planes (Y, U, V) with their own row strides --
  /// concatenating those byte arrays directly does NOT produce valid NV21,
  /// since NV21 requires U/V interleaved in a specific order. This does a
  /// real conversion instead. iOS delivers BGRA8888 as a single plane
  /// already, no conversion needed.
  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      final nv21 = _yuv420ToNv21(image);
      if (nv21 == null) return null;

      return InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width, // NV21 Y-plane row stride == width once converted
        ),
      );
    }

    // iOS: single BGRA8888 plane.
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Converts a 3-plane YUV_420_888 CameraImage (Android's default, and
  /// what hand_landmarker expects to keep receiving) into a proper NV21
  /// byte buffer for ML Kit: full-resolution Y plane, followed by
  /// half-resolution interleaved VU bytes. Row strides and pixel strides
  /// on the U/V planes are respected rather than assumed, since some
  /// devices pad rows or interleave U/V with a pixel stride of 2 already.
  ///
  /// Returns null if the image doesn't have the expected 3-plane shape
  /// (shouldn't happen with the default Android camera format, but safer
  /// than crashing if a device does something unexpected).
  Uint8List? _yuv420ToNv21(CameraImage image) {
    if (image.planes.length < 3) {
      throw StateError(
        'Expected 3 camera planes (Y/U/V), got ${image.planes.length}. '
            'Camera format/device isn\'t giving the standard yuv420 layout '
            'this conversion assumes.',
      );
    }

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    if (width.isOdd || height.isOdd) {
      throw StateError(
        'Odd camera dimensions ${width}x$height -- 4:2:0 chroma math '
            '(width/2, height/2) assumes even dimensions.',
      );
    }

    final ySize = width * height;
    final uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    // --- Y plane: copy row by row, stripping any row-stride padding. ---
    var pos = 0;
    for (int row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      if (rowStart + width > yPlane.bytes.length) {
        throw StateError(
          'Y plane too small: row=$row bytesPerRow=${yPlane.bytesPerRow} '
              'width=$width planeLength=${yPlane.bytes.length}. '
              'yPlane.bytesPerRow may be misreported on this device.',
        );
      }
      nv21.setRange(pos, pos + width, yPlane.bytes, rowStart);
      pos += width;
    }

    // --- Interleave V and U into NV21's VU order. ---
    // NV21 wants one V byte then one U byte per 2x2 pixel block, i.e.
    // (width/2 * height/2) VU pairs. U and V planes are typically the
    // same dimensions with their own row/pixel strides on Android.
    final uvRowStride = vPlane.bytesPerRow;
    final uvPixelStride = vPlane.bytesPerPixel;
    final uPixelStride = uPlane.bytesPerPixel;
    if (uvPixelStride == null || uPixelStride == null) {
      throw StateError(
        'U/V plane.bytesPerPixel is null on this device (U=$uPixelStride '
            'V=$uvPixelStride) -- can\'t safely assume a pixel stride '
            '(1 = fully planar, 2 = semi-planar/interleaved) without it, '
            'since guessing wrong silently corrupts the image instead of '
            'throwing.',
      );
    }
    final chromaHeight = height ~/ 2;
    final chromaWidth = width ~/ 2;

    for (int row = 0; row < chromaHeight; row++) {
      for (int col = 0; col < chromaWidth; col++) {
        final vIndex = row * uvRowStride + col * uvPixelStride;
        final uIndex = row * uPlane.bytesPerRow + col * uPixelStride;
        if (vIndex >= vPlane.bytes.length || uIndex >= uPlane.bytes.length) {
          throw StateError(
            'Chroma index out of range at row=$row col=$col: '
                'vIndex=$vIndex/${vPlane.bytes.length} '
                'uIndex=$uIndex/${uPlane.bytes.length} '
                '(uvRowStride=$uvRowStride uvPixelStride=$uvPixelStride '
                'uBytesPerRow=${uPlane.bytesPerRow}). Stride assumptions '
                'don\'t match this device\'s actual plane layout.',
          );
        }
        nv21[pos++] = vPlane.bytes[vIndex];
        nv21[pos++] = uPlane.bytes[uIndex];
      }
    }

    if (pos != nv21.length) {
      throw StateError('NV21 buffer size mismatch: wrote $pos, expected ${nv21.length}.');
    }

    return nv21;
  }

  /// NOTE: position-based left/right fallback -- see earlier flag about
  /// this plugin's handedness labeling. Swap if hands seem mislabeled.
  void _onHandsDetected(List<Hand> hands) {
    if (!mounted) return;
    _processingHandFrame = false; // previous frame's result has landed
    setState(() => _handsVisible = hands.length);

    List<List<double>>? leftLandmarks;
    List<List<double>>? rightLandmarks;

    if (hands.length == 1) {
      leftLandmarks = hands.first.landmarks.map((l) => [l.x, l.y, 0.0]).toList();
    } else if (hands.length >= 2) {
      final sorted = List<Hand>.from(hands)
        ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));
      leftLandmarks = sorted[0].landmarks.map((l) => [l.x, l.y, 0.0]).toList();
      rightLandmarks = sorted[1].landmarks.map((l) => [l.x, l.y, 0.0]).toList();
    }

    // Pose landmarks come from the separate ML Kit pose stream, cached in
    // _latestPoseLandmarks each time a new pose result lands (see
    // _processPoseFrame). If no pose has been detected yet -- e.g. the
    // detector hasn't returned a first result, or the person is out of
    // frame -- this stays null and the service safely drops the frame
    // rather than corrupting normalization.
    _gestureService.addFrame(
      poseLandmarks: _latestPoseLandmarks,
      leftHandLandmarks: leftLandmarks,
      rightHandLandmarks: rightLandmarks,
    );
  }

  // ─────────────────────────── Mic / speech-to-gesture ───────────────────────────

  void _startListening() async {
    final hasPermission = await _whisperService.hasPermission();
    if (!hasPermission) {
      _appendEntry(_EntrySource.spoken, 'Microphone permission is required.');
      return;
    }

    setState(() {
      _isRecording = true;
      _matchedWords = [];
      _currentWordIndex = 0;
    });

    try {
      await _whisperService.startRecording();
    } catch (e) {
      setState(() => _isRecording = false);
      _appendEntry(_EntrySource.spoken, 'Could not start recording: $e');
    }
  }

  void _stopListening() async {
    setState(() {
      _isRecording = false;
      _isTranscribing = true;
    });

    try {
      final text = await _whisperService.stopAndTranscribe();
      final matches = GlossMatcher.matchTranscript(text);

      setState(() {
        _matchedWords = matches;
        _isTranscribing = false;
        _currentWordIndex = 0;
      });

      _appendEntry(_EntrySource.spoken, text.isEmpty ? 'No speech detected.' : text);
    } catch (e) {
      setState(() => _isTranscribing = false);
      _appendEntry(_EntrySource.spoken, 'Transcription failed: $e');
    }
  }

  void _advanceToNextWord() {
    if (_currentWordIndex < _matchedWords.length - 1) {
      setState(() => _currentWordIndex++);
    }
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _purple),
        title: const Text(
          'Live Conversation',
          style: TextStyle(color: _purple, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalHeight = constraints.maxHeight;

              // Seed the transcribe panel height on first layout (roughly
              // the same 4/11 ratio the old flex:4 gave it).
              _transcribeHeight ??= (totalHeight * 4 / 11).clamp(
                _minTranscribeHeight,
                totalHeight - _minTopHeight - _gap * 2,
              );

              final maxTranscribeHeight =
              (totalHeight - _minTopHeight - _gap * 2).clamp(_minTranscribeHeight, double.infinity);
              final transcribeHeight =
              _transcribeHeight!.clamp(_minTranscribeHeight, maxTranscribeHeight);

              final topHeight = totalHeight - transcribeHeight - _gap * 2;
              // Preserve the original 4:3 ratio between the input box and the ASL box.
              final signedHeight = topHeight * 4 / 7;
              final aslHeight = topHeight * 3 / 7;

              return Column(
                children: [
                  SizedBox(height: signedHeight, child: _buildCameraViewfinder()),
                  const SizedBox(height: _gap),
                  SizedBox(height: aslHeight, child: _buildAslBox()),
                  const SizedBox(height: _gap),
                  SizedBox(
                    height: transcribeHeight,
                    child: _buildTranscribePanel(totalHeight, maxTranscribeHeight),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Camera preview with corner-bracket viewfinder framing.
  Widget _buildCameraViewfinder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: Colors.grey.shade200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraInitError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_cameraInitError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ),
              )
            else if (!_cameraInitialized)
              const Center(child: CircularProgressIndicator(color: _purple))
            else
              LayoutBuilder(
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
              ),

            // Corner bracket overlay.
            const Padding(
              padding: EdgeInsets.all(16),
              child: _ViewfinderCorners(),
            ),

            Positioned(
              top: 10,
              right: 14,
              child: Text(
                'Hands: $_handsVisible',
                style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),

            // Debug status strip: makes the recognition pipeline's actual
            // state visible (model load status, whether pose data is
            // flowing, and whether a sign segment is currently being
            // captured) instead of it silently doing nothing. Remove or
            // hide behind a debug flag once things are confirmed working.
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _modelLoaded ? Icons.check_circle : Icons.error_outline,
                          size: 12,
                          color: _modelLoaded ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _modelStatusMessage ?? 'Loading model...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _latestPoseLandmarks != null ? Icons.accessibility_new : Icons.person_off,
                          size: 12,
                          color: _latestPoseLandmarks != null ? Colors.greenAccent : Colors.redAccent,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _gestureService.isCapturingSegment ? Icons.fiber_manual_record : Icons.pause_circle_outline,
                          size: 12,
                          color: _gestureService.isCapturingSegment ? Colors.redAccent : Colors.white54,
                        ),
                        if (_gestureService.isCapturingSegment) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${_gestureService.activeSegmentLength}',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                    if (_poseErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Pose error: $_poseErrorMessage',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 9),
                        ),
                      ),
                    if (_lastSegmentDebug != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Last segment: $_lastSegmentDebug',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 9),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAslBox() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _purple, width: 2),
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _matchedWords.isEmpty
            ? const Center(
          child: Text(
            '3D ASL',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
          ),
        )
            : SkeletalGestureViewer(
          assetPath: _currentWord?.landmarksAsset,
          sequenceKey: _currentWordIndex,
          onFinished: _advanceToNextWord,
        ),
      ),
    );
  }

  Widget _buildTranscribePanel(double totalHeight, double maxTranscribeHeight) {
    return Container(
      decoration: const BoxDecoration(
        color: _purple,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Drag handle: vertical drag resizes the panel.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) {
              setState(() {
                // Dragging up (negative dy) should grow the panel, so subtract dy.
                final next = (_transcribeHeight ?? maxTranscribeHeight) - details.delta.dy;
                _transcribeHeight = next.clamp(_minTranscribeHeight, maxTranscribeHeight);
              });
            },
            child: Container(
              // Slightly bigger tap/drag target than the visible bar.
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.transparent,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Transcribe Conversation',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                IconButton(
                  icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
                  onPressed: () => setState(() => _isMuted = !_isMuted),
                  tooltip: _isMuted ? 'Unmute spoken output' : 'Mute spoken output',
                ),
              ],
            ),
          ),
          Expanded(
            child: _conversation.isEmpty
                ? const Center(
              child: Text('No conversation yet.', style: TextStyle(color: Colors.white38, fontSize: 13)),
            )
                : ListView.builder(
              controller: _chatScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _conversation.length,
              itemBuilder: (context, index) => _buildChatBubble(_conversation[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _isTranscribing
                ? const CircularProgressIndicator(color: Colors.white)
                : _isRecording
                ? ElevatedButton.icon(
              onPressed: _stopListening,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            )
                : ElevatedButton.icon(
              onPressed: _startListening,
              icon: const Icon(Icons.mic),
              label: const Text('Start Speaking'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _purple,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(_ConversationEntry entry) {
    final isSigned = entry.source == _EntrySource.signed;
    return Align(
      alignment: isSigned ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
        decoration: BoxDecoration(
          color: isSigned ? Colors.white.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSigned ? 'Signed' : 'Spoken',
              style: TextStyle(
                color: isSigned ? Colors.white54 : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.text,
              style: TextStyle(
                color: isSigned ? Colors.white : _purple,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveConversationIfNeeded();
    _chatScrollController.dispose();
    _controller?.stopImageStream();
    _controller?.dispose();
    _plugin?.dispose();
    _poseDetector?.close();
    _gestureService.dispose();
    _tts.dispose();
    super.dispose();
  }
}

/// Four L-shaped corner brackets forming a viewfinder frame, matching
/// the design mockup.
class _ViewfinderCorners extends StatelessWidget {
  const _ViewfinderCorners();

  @override
  Widget build(BuildContext context) {
    const thickness = 3.0;
    const length = 28.0;
    const color = Colors.black87;

    Widget corner({required bool top, required bool left}) {
      return Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: left ? 0 : null,
        right: left ? null : 0,
        child: SizedBox(
          width: length,
          height: length,
          child: Stack(
            children: [
              Positioned(
                top: top ? 0 : null,
                bottom: top ? null : 0,
                left: 0,
                right: 0,
                child: Container(height: thickness, color: color),
              ),
              Positioned(
                left: left ? 0 : null,
                right: left ? null : 0,
                top: 0,
                bottom: 0,
                child: Container(width: thickness, color: color),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        corner(top: true, left: true),
        corner(top: true, left: false),
        corner(top: false, left: true),
        corner(top: false, left: false),
      ],
    );
  }
}