import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../services/gloss_matcher.dart';
import '../services/tts_service.dart';
import '../services/whisper_service.dart';
import '../services/conversation_history_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';

// ===========================================================================
// TEST MODE: the camera + hand/pose recognition pipeline is temporarily
// swapped for a manual text box, so the "Transcribe Conversation" chat
// history UI can be tested without a working trained model.
//
// To restore the real camera pipeline later: bring back the `camera` and
// `hand_landmarker` imports, the GestureRecognitionService, and the
// _buildSigningPanel() camera/viewfinder implementation from the previous
// version of this file. Everything else (mic, 3D ASL box, chat transcript,
// mute toggle) is untouched and still fully functional.
// ===========================================================================

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
  // --- TEST MODE: manual text entry stands in for camera recognition ---
  final TextEditingController _signedInputController = TextEditingController();
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
    _tts.init();
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

  // ─────────────────────────── TEST MODE: manual "signed" input ───────────────────────────

  void _submitSignedText() {
    final text = _signedInputController.text.trim();
    if (text.isEmpty) return;

    _appendEntry(_EntrySource.signed, text);
    if (!_isMuted) _tts.speak(text);
    _signedInputController.clear();
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
          'Live Conversation (TEST MODE)',
          style: TextStyle(color: _purple, fontWeight: FontWeight.bold, fontSize: 16),
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
                  SizedBox(height: signedHeight, child: _buildSignedTextInputPanel()),
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

  /// TEST MODE stand-in for the camera viewfinder: a text box + send
  /// button that appends into the "signed" side of the conversation,
  /// exactly like real gesture recognition would.
  Widget _buildSignedTextInputPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              const Text(
                'Test input (stands in for camera recognition)',
                style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _signedInputController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Type what would have been signed...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.all(12),
              ),
              onSubmitted: (_) => _submitSignedText(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: _submitSignedText,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Add as Signed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
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
    _signedInputController.dispose();
    _chatScrollController.dispose();
    _tts.dispose();
    super.dispose();
  }
}