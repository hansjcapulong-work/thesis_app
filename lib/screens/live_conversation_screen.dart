import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../data/asl_words.dart';
import '../services/gesture_recognition_service.dart';
import '../services/gloss_matcher.dart';
import '../services/tts_service.dart';
import '../services/whisper_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';

const _purple = Color(0xFF2A1B38);

enum _EntrySource { signed, spoken }

class _ConversationEntry {
  final _EntrySource source;
  final String text;
  _ConversationEntry(this.source, this.text);
}

/// Two-way live conversation screen: camera + viewfinder at the top
/// (Deaf person signs, recognized words are spoken aloud), a bordered
/// "3D ASL" box in the middle showing the animated sign for whatever
/// was just spoken, and a scrollable dark chat transcript at the
/// bottom logging both directions of the conversation.
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
  int _handsVisible = 0;

  // --- Speech-to-gesture side (mic) ---
  final WhisperService _whisperService = WhisperService();
  final TtsService _tts = TtsService();
  bool _isRecording = false;
  List<ASLWord> _matchedWords = [];
  int _currentWordIndex = 0;

  // --- Shared conversation history ---
  final List<_ConversationEntry> _conversation = [];
  final ScrollController _chatScrollController = ScrollController();
  bool _isMuted = false;

  ASLWord? get _currentWord =>
      _matchedWords.isNotEmpty && _currentWordIndex < _matchedWords.length
          ? _matchedWords[_currentWordIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _gestureService.onModelStatusChanged = (isLoaded, message) {
      if (!mounted) return;
      setState(() => _modelLoaded = isLoaded);
    };
    _gestureService.onGestureRecognized = (word, confidence) {
      if (!mounted) return;
      _appendEntry(_EntrySource.signed, word);
      if (!_isMuted) _tts.speak(word);
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

  // ─────────────────────────── Camera / gesture-to-speech ───────────────────────────

  Future<void> _initCamera() async {
    try {
      await _gestureService.loadModel();

      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);

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
    if (_plugin == null || _controller == null) return;
    try {
      _plugin!.processFrame(image, _controller!.description.sensorOrientation);
    } catch (e) {
      debugPrint('Error processing camera frame: $e');
    }
  }

  /// NOTE: position-based left/right fallback -- see earlier flag about
  /// this plugin's handedness labeling. Swap if hands seem mislabeled.
  void _onHandsDetected(List<Hand> hands) {
    if (!mounted) return;
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

    _gestureService.addFrame(
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
      await Future.delayed(const Duration(seconds: 4));

      final text = await _whisperService.stopAndTranscribe();
      final matches = GlossMatcher.matchTranscript(text);

      setState(() {
        _matchedWords = matches;
        _isRecording = false;
        _currentWordIndex = 0;
      });

      _appendEntry(_EntrySource.spoken, text.isEmpty ? 'No speech detected.' : text);
    } catch (e) {
      setState(() => _isRecording = false);
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
          child: Column(
            children: [
              Expanded(flex: 4, child: _buildCameraViewfinder()),
              const SizedBox(height: 16),
              Expanded(flex: 3, child: _buildAslBox()),
              const SizedBox(height: 16),
              Expanded(flex: 4, child: _buildTranscribePanel()),
            ],
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
              CameraPreview(_controller!),

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
          ],
        ),
      ),
    );
  }

  /// Bordered box showing the animated sign for whatever was last
  /// spoken -- "3D ASL" label when idle.
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

  /// Dark scrollable chat-style transcript of the full conversation,
  /// plus the mic control.
  Widget _buildTranscribePanel() {
    return Container(
      decoration: const BoxDecoration(
        color: _purple,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
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
            child: _isRecording
                ? const CircularProgressIndicator(color: Colors.white)
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
    _chatScrollController.dispose();
    _controller?.stopImageStream();
    _controller?.dispose();
    _plugin?.dispose();
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
