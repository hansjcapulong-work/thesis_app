import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../data/asl_words.dart';
import '../services/gesture_recognition_service.dart';
import '../services/gloss_matcher.dart';
import '../services/tts_service.dart';
import '../services/whisper_service.dart';
import '../services/conversation_history_service.dart';
import '../services/avatar_preference_service.dart';
import '../data/avatar_options.dart';
import '../widgets/avatar_gesture_viewer.dart';

const _purple = Color(0xFF2A1B38);

enum _EntrySource { signed, spoken }

/// Which of the two media cards currently gets the large slot in the
/// landscape layout. The other one is shown small beside it. Tapping the
/// expand icon on the small card swaps them.
enum _FocusedCard { camera, avatar }

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
  // TEMP: flip to true to re-enable camera-based gesture recognition.
  // While false, the camera and HandLandmarkerPlugin never
  // initialize -- no camera permission prompt, no native processing --
  // and the viewfinder box just shows a placeholder. Speech-to-gesture is
  // completely unaffected by this flag.
  static const bool _kEnableGestureRecognition = true;

  // --- Gesture-to-speech side (camera) ---
  CameraController? _controller;
  HandLandmarkerPlugin? _plugin;
  final GestureRecognitionService _gestureService = GestureRecognitionService();
  bool _cameraInitialized = false;
  String? _cameraInitError;
  bool _modelLoaded = false;
  String? _modelStatusMessage;
  int _handsVisible = 0;
  bool _processingHandFrame = false;
  String? _lastSegmentDebug;

  final TtsService _tts = TtsService();

  // --- Speech-to-gesture side (mic) -- unchanged, still real ---
  final WhisperService _whisperService = WhisperService();
  bool _isRecording = false;
  bool _isTranscribing = false; // true while waiting on the server after Stop is tapped
  List<ASLWord> _matchedWords = [];
  int _currentWordIndex = 0;

  // --- Avatar chosen in Settings ---
  // Defaults until the saved preference has been read (a few ms); the viewer
  // is only built after speech is matched, so the user never sees the default
  // flash before their own avatar.
  AvatarOption _avatar = avatarById(null);

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

  // --- Landscape layout state ---
  // Which card owns the big slot. Camera by default, matching the mockup.
  _FocusedCard _focusedCard = _FocusedCard.camera;
  // Width of the small card as a fraction of the media area. Driven by the
  // drag divider that sits between the two cards.
  double _smallCardFraction = 0.28;
  static const double _minSmallCardFraction = 0.16;
  static const double _maxSmallCardFraction = 0.48;
  // Width (px) of the side transcript drawer. Null until first layout.
  double? _transcriptWidth;
  bool _transcriptOpen = true;
  static const double _minTranscriptWidth = 200.0;
  static const double _minMediaAreaWidth = 280.0;

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

    AvatarPreferenceService.load().then((option) {
      if (!mounted) return;
      setState(() => _avatar = option);
    });

    // Gesture recognition (camera + hand landmarker) only spins up
    // when explicitly enabled. Leave this off to test speech-to-gesture
    // in isolation without a camera permission prompt or the native
    // pipeline running in the background.
    if (_kEnableGestureRecognition) {
      _initCamera();
    }
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

      // yuv420 is what hand_landmarker's native code expects on Android
      // (it indexes into 3 separate Y/U/V planes); iOS delivers a single
      // BGRA8888 plane instead. This used to also need to satisfy ML
      // Kit's pose detector on the same stream, but the current model
      // (sign_language_model.tflite) is hands-only, so hand_landmarker
      // is the only consumer now.
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
    // await here directly. Instead this is guarded so a new frame isn't
    // dispatched until the previous one's result has come back through
    // landmarkStream (see _onHandsDetected). Camera frames
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
  }

  /// Front camera preview is typically mirrored, so a hand appearing on
  /// the LEFT side of the screen (smaller x) is usually the signer's
  /// actual RIGHT hand, and vice versa -- verified against real predictions
  /// in the gesture test screen. If sign accuracy seems mirrored later
  /// (e.g. after a plugin/platform change), that's the first thing to
  /// re-check, not this logic.
  void _onHandsDetected(List<Hand> hands) {
    if (!mounted) return;
    _processingHandFrame = false; // previous frame's result has landed
    setState(() => _handsVisible = hands.length);

    List<List<double>>? leftLandmarks;
    List<List<double>>? rightLandmarks;

    if (hands.length == 1) {
      final coords = hands.first.landmarks.map((l) => [l.x, l.y, l.z]).toList();
      final wristX = hands.first.landmarks[0].x; // landmark 0 = wrist

      if (wristX < 0.5) {
        rightLandmarks = coords;
      } else {
        leftLandmarks = coords;
      }
    } else if (hands.length >= 2) {
      final sorted = List<Hand>.from(hands)
        ..sort((a, b) => a.landmarks[0].x.compareTo(b.landmarks[0].x));
      // smaller x = actual RIGHT hand, larger x = actual LEFT hand
      // (front camera mirroring) -- confirmed via the single-hand case.
      rightLandmarks = sorted[0].landmarks.map((l) => [l.x, l.y, l.z]).toList();
      leftLandmarks = sorted[1].landmarks.map((l) => [l.x, l.y, l.z]).toList();
    }

    // The current model (sign_language_model.tflite) is hands-only --
    // no pose input needed at all.
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

  /// Short beat between two fingerspelled words (or between a fingerspelled
  /// word and a normal sign) so the letters of one word don't run into the
  /// next -- otherwise "HI" then "JO" reads as "HIJO".
  static const Duration _spellingWordGap = Duration(milliseconds: 300);

  Future<void> _advanceToNextWord() async {
    if (_currentWordIndex >= _matchedWords.length - 1) return;

    final list = _matchedWords;
    final current = _currentWord;
    final next = list[_currentWordIndex + 1];

    final leavingSpelledWord = current != null &&
        current.isFingerspelled &&
        (!next.isFingerspelled || next.letterIndex == 0);

    if (leavingSpelledWord) {
      await Future.delayed(_spellingWordGap);
      // The user may have left the screen or started a new recording
      // during the pause; if so this advance is stale.
      if (!mounted || !identical(list, _matchedWords)) return;
    }

    setState(() => _currentWordIndex++);
  }

  // ─────────────────────────── UI ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Landscape drops the AppBar entirely: horizontal space is scarce, so the
    // back affordance becomes a floating button over the media area instead.
    if (isLandscape) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: LayoutBuilder(builder: _buildLandscapeBody),
          ),
        ),
      );
    }

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

  // ─────────────────────────── Landscape layout ───────────────────────────

  /// Landscape root: [ media area | drag handle | transcript drawer ].
  ///
  /// The media area holds the two cards side by side, separated by their own
  /// drag divider, plus the floating back button and the Press to Speak
  /// control. The transcript drawer can be dragged narrower/wider or pulled
  /// closed entirely, in which case a thin tab is left on the right edge.
  Widget _buildLandscapeBody(BuildContext context, BoxConstraints constraints) {
    final totalWidth = constraints.maxWidth;

    // Upper bound respects both a hard cap (45% of the screen) and the
    // minimum breathing room the media area needs. math.max guards the case
    // where the screen is too narrow to satisfy both.
    final maxTranscriptWidth = math.max(
      _minTranscriptWidth,
      math.min(totalWidth * 0.45, totalWidth - _minMediaAreaWidth),
    );

    _transcriptWidth ??=
        (totalWidth * 0.28).clamp(_minTranscriptWidth, maxTranscriptWidth);
    final transcriptWidth =
    _transcriptWidth!.clamp(_minTranscriptWidth, maxTranscriptWidth);

    // Closed drawer still leaves room for the pull tab.
    const tabWidth = 28.0;
    // Tighter than the portrait _gap -- every px of media width counts here.
    const landscapeGap = 8.0;
    final drawerWidth = _transcriptOpen ? transcriptWidth : tabWidth;
    final mediaWidth = totalWidth - drawerWidth - landscapeGap;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: mediaWidth, child: _buildMediaArea()),
        const SizedBox(width: landscapeGap),
        SizedBox(
          width: drawerWidth,
          child: _transcriptOpen
              ? _buildTranscriptDrawer(maxTranscriptWidth)
              : _buildTranscriptTab(),
        ),
      ],
    );
  }

  /// The two media cards plus the mic control.
  ///
  /// In landscape, height is the scarce axis and width is not, so the back
  /// button lives in a narrow left rail rather than eating a horizontal band
  /// across the top, and both cards stretch to the full available height.
  Widget _buildMediaArea() {
    const railWidth = 40.0;
    const controlsHeight = 52.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: railWidth,
          child: Column(
            children: [
              Material(
                color: _purple,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardsWidth = constraints.maxWidth;
                    final smallWidth = (cardsWidth * _smallCardFraction).clamp(
                      cardsWidth * _minSmallCardFraction,
                      cardsWidth * _maxSmallCardFraction,
                    );
                    final cameraIsBig = _focusedCard == _FocusedCard.camera;

                    final smallCard = _cardShell(
                      isExpanded: false,
                      onToggle: () => setState(
                            () => _focusedCard =
                        cameraIsBig ? _FocusedCard.avatar : _FocusedCard.camera,
                      ),
                      child: cameraIsBig
                          ? _buildAslBox(compact: true)
                          : _buildCameraViewfinder(compact: true),
                    );

                    final bigCard = _cardShell(
                      isExpanded: true,
                      onToggle: () => setState(
                            () => _focusedCard =
                        cameraIsBig ? _FocusedCard.avatar : _FocusedCard.camera,
                      ),
                      child: cameraIsBig ? _buildCameraViewfinder() : _buildAslBox(),
                    );

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: smallWidth, child: smallCard),
                        // Drag divider: widens the small card, shrinks the big one.
                        _buildVerticalDivider(cardsWidth),
                        Expanded(child: bigCard),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(
                height: controlsHeight,
                child: Center(child: _buildMicControl(wide: true)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Grab bar between the two cards.
  Widget _buildVerticalDivider(double cardsWidth) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            final next = _smallCardFraction + details.delta.dx / cardsWidth;
            _smallCardFraction =
                next.clamp(_minSmallCardFraction, _maxSmallCardFraction);
          });
        },
        child: SizedBox(
          width: _gap,
          child: Center(
            child: Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Rounded frame + expand/collapse toggle shared by both media cards.
  Widget _cardShell({
    required Widget child,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  isExpanded ? Icons.close_fullscreen : Icons.open_in_full,
                  size: 16,
                  color: _purple,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Side transcript drawer. Horizontal drag on its left edge resizes it;
  /// dragging it past the minimum (or tapping the chevron) closes it.
  Widget _buildTranscriptDrawer(double maxTranscriptWidth) {
    return Container(
      decoration: const BoxDecoration(
        color: _purple,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(24),
          right: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  // Dragging left (negative dx) should grow the drawer.
                  final next = (_transcriptWidth ?? maxTranscriptWidth) - details.delta.dx;
                  if (next < _minTranscriptWidth - 40) {
                    _transcriptOpen = false;
                    _transcriptWidth = _minTranscriptWidth;
                  } else {
                    _transcriptWidth =
                        next.clamp(_minTranscriptWidth, maxTranscriptWidth);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    width: 4,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                // Compact header: plain InkWells instead of IconButtons,
                // which carry 48px tap padding each and were squeezing the
                // title into an ellipsis. Title also shortens when narrow.
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(() => _isMuted = !_isMuted),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            constraints.maxWidth < 260 ? 'Transcript' : 'Transcribe Conversation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => setState(() => _transcriptOpen = false),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.chevron_right, color: Colors.white70, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _conversation.isEmpty
                      ? const Center(
                    child: Text(
                      'No conversation yet.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                      : LayoutBuilder(
                    builder: (context, constraints) => ListView.builder(
                      controller: _chatScrollController,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _conversation.length,
                      itemBuilder: (context, index) => _buildChatBubble(
                        _conversation[index],
                        maxWidth: constraints.maxWidth * 0.9,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsed drawer: a thin tab to pull the transcript back out.
  Widget _buildTranscriptTab() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _transcriptOpen = true),
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < -2) setState(() => _transcriptOpen = true);
      },
      child: Container(
        decoration: BoxDecoration(
          color: _purple,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chevron_left, color: Colors.white70, size: 20),
            SizedBox(height: 8),
            RotatedBox(
              quarterTurns: 3,
              child: Text(
                'Transcript',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mic button. Shared shape between orientations; [wide] gives it the
  /// pill treatment the landscape mockup uses.
  Widget _buildMicControl({bool wide = false}) {
    if (_isTranscribing) {
      // Landscape sits on white, portrait sits on the purple panel.
      return SizedBox(
        height: 28,
        width: 28,
        child: CircularProgressIndicator(
          color: wide ? _purple : Colors.white,
          strokeWidth: 3,
        ),
      );
    }

    final padding = wide
        ? const EdgeInsets.symmetric(horizontal: 28, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 12);

    if (_isRecording) {
      return _constrainWidth(
        wide,
        ElevatedButton.icon(
          onPressed: _stopListening,
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            padding: padding,
            minimumSize: wide ? Size.zero : null,
            tapTargetSize: wide ? MaterialTapTargetSize.shrinkWrap : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      );
    }

    return _constrainWidth(
      wide,
      ElevatedButton.icon(
        onPressed: _startListening,
        icon: const Icon(Icons.mic),
        label: Text(wide ? 'Press to Speak' : 'Start Speaking'),
        style: ElevatedButton.styleFrom(
          backgroundColor: wide ? _purple : Colors.white,
          foregroundColor: wide ? Colors.white : _purple,
          padding: padding,
          minimumSize: wide ? Size.zero : null,
          tapTargetSize: wide ? MaterialTapTargetSize.shrinkWrap : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );
  }

  /// A global ElevatedButton theme with a `minimumSize`/`fixedSize` of
  /// double.infinity will stretch the mic button across the whole media
  /// column, which is exactly the vertical/horizontal space landscape can't
  /// spare. Capping the width here keeps it a pill regardless of the theme.
  Widget _constrainWidth(bool wide, Widget child) {
    if (!wide) return child;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: child,
    );
  }

  /// Camera preview with corner-bracket viewfinder framing.
  Widget _buildCameraViewfinder({bool compact = false}) {
    // Gesture recognition disabled: skip the camera UI entirely (no
    // permission prompt, no spinner that would otherwise spin forever
    // since _initCamera() never runs) and show a plain placeholder.
    if (!_kEnableGestureRecognition) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.grey.shade200,
          child: const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Gesture recognition disabled for testing',
                style: TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

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
              Builder(
                builder: (context) {
                  final previewSize = _controller!.value.previewSize!;
                  // previewSize is reported in the sensor's own orientation,
                  // which is landscape on virtually every device. In a
                  // portrait layout we swap the axes; in landscape we use it
                  // as-is, otherwise the preview comes out rotated 90°.
                  final isLandscape =
                      MediaQuery.of(context).orientation == Orientation.landscape;
                  return ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: isLandscape ? previewSize.width : previewSize.height,
                        height: isLandscape ? previewSize.height : previewSize.width,
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  );
                },
              ),

            // Corner bracket overlay.
            Padding(
              padding: EdgeInsets.all(compact ? 8 : 16),
              child: const _ViewfinderCorners(),
            ),

            // In compact mode the card is only a couple of hundred px wide,
            // so the hand counter would collide with the expand button.
            if (!compact)
              Positioned(
                top: 10,
                right: 14,
                child: Text(
                  'Hands: $_handsVisible',
                  style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),

            // Debug status strip: makes the recognition pipeline's actual
            // state visible (model load status and whether a sign segment
            // is currently being captured) instead of it silently doing
            // nothing. Left in place intentionally -- keep for now.
            // Too cramped to be readable on the compact card, so it's only
            // drawn when the camera owns the large slot.
            if (!compact) Positioned(
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

  Widget _buildAslBox({bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _purple, width: 2),
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _matchedWords.isEmpty
            ? Center(
          child: Text(
            '3D ASL',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: compact ? 13 : 16,
              letterSpacing: 1,
            ),
          ),
        )
            : Stack(
          children: [
            AvatarGestureViewer(
              key: ValueKey(_avatar.assetPath),
              modelAsset: _avatar.assetPath,
              animationName: _currentWord?.signAnimation,
              durationMs: _currentWord?.signDurationMs,
              sequenceKey: _currentWordIndex,
              onFinished: _advanceToNextWord,
            ),
            if (_currentWord != null && _currentWord!.isFingerspelled)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: _buildSpellingCaption(_currentWord!, compact: compact),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Shows the word being fingerspelled with the current letter
  /// highlighted, e.g.  H E [L] L O
  Widget _buildSpellingCaption(ASLWord w, {bool compact = false}) {
    final letters = (w.spellingOf ?? w.word).toUpperCase().split('');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < letters.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                letters[i],
                style: TextStyle(
                  fontSize: compact ? 13 : 18,
                  fontWeight: FontWeight.bold,
                  color: i == w.letterIndex ? Colors.amberAccent : Colors.white54,
                ),
              ),
            ),
        ],
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
            child: _buildMicControl(),
          ),
        ],
      ),
    );
  }

  /// [maxWidth] lets the landscape drawer cap bubbles to its own width --
  /// the screen-width default is far too wide once the panel is docked
  /// to the side.
  Widget _buildChatBubble(_ConversationEntry entry, {double? maxWidth}) {
    final isSigned = entry.source == _EntrySource.signed;
    return Align(
      alignment: isSigned ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? MediaQuery.of(context).size.width * 0.65,
        ),
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