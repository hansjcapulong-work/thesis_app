import 'package:flutter/material.dart';
import '../services/whisper_service.dart';
import '../services/gloss_matcher.dart';
import '../data/asl_words.dart';
import '../widgets/skeletal_gesture_viewer.dart';

class SpeechToGestureScreen extends StatefulWidget {
  const SpeechToGestureScreen({Key? key}) : super(key: key);

  @override
  _SpeechToGestureScreenState createState() => _SpeechToGestureScreenState();
}

class _SpeechToGestureScreenState extends State<SpeechToGestureScreen> {
  final WhisperService _whisperService = WhisperService();
  bool _isRecording = false;
  String _transcript = "";
  List<ASLWord> _matchedWords = [];
  int _currentVideoIndex = 0;

  ASLWord? get _currentWord =>
      _matchedWords.isNotEmpty && _currentVideoIndex < _matchedWords.length
          ? _matchedWords[_currentVideoIndex]
          : null;

  bool get _currentWordHasSkeleton => _currentWord?.landmarksAsset != null;

  void _startListening() async {
    final hasPermission = await _whisperService.hasPermission();
    if (!hasPermission) {
      setState(() {
        _transcript = "Microphone permission is required.";
      });
      return;
    }

    setState(() {
      _isRecording = true;
      _transcript = "Listening...";
      _matchedWords = [];
      _currentVideoIndex = 0;
    });

    try {
      await _whisperService.startRecording();

      // Records for 4 seconds, then automatically stops and transcribes.
      // Adjust this duration based on how long your test phrases are.
      await Future.delayed(const Duration(seconds: 4));

      final text = await _whisperService.stopAndTranscribe();
      final matches = GlossMatcher.matchTranscript(text);

      setState(() {
        _transcript = text.isEmpty ? "No speech detected." : text;
        _matchedWords = matches;
        _isRecording = false;
        _currentVideoIndex = 0;
      });
    } catch (e) {
      setState(() {
        _transcript = "Transcription failed: $e";
        _isRecording = false;
      });
    }
  }

  /// Called when the current word's skeletal animation finishes playing
  /// -- advances to the next matched word, if any. SkeletalGestureViewer
  /// is keyed on the asset path, so moving to a new word automatically
  /// remounts it and restarts the animation.
  void _advanceToNextWord() {
    if (_currentVideoIndex < _matchedWords.length - 1) {
      setState(() {
        _currentVideoIndex++;
      });
    }
  }

  Widget _buildGestureDisplay() {
    final word = _currentWord;

    if (word == null) {
      return Container(
        height: 300,
        width: 320,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.videocam, size: 80, color: Colors.grey),
      );
    }

    if (_currentWordHasSkeleton) {
      return Container(
        height: 300,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SkeletalGestureViewer(
            // No key here on purpose: keeping the same widget instance
            // across the whole matched-word sequence is what lets it
            // blend the end of one word into the start of the next
            // instead of snapping. See didUpdateWidget in the viewer.
            assetPath: word.landmarksAsset!,
            onFinished: _advanceToNextWord,
          ),
        ),
      );
    }

    return Container(
      height: 300,
      width: 320,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Text(
          'No gesture available yet\nfor this word.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  /// Renders every matched word in order, highlighting whichever one is
  /// currently animating in the gesture viewer above. Uses a Wrap so
  /// longer phrases naturally flow onto a second line instead of
  /// overflowing horizontally.
  Widget _buildGlossRow() {
    if (_matchedWords.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (int i = 0; i < _matchedWords.length; i++)
            _buildGlossChip(_matchedWords[i].word, isActive: i == _currentVideoIndex),
        ],
      ),
    );
  }

  Widget _buildGlossChip(String word, {required bool isActive}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF2A1B38) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        word,
        style: TextStyle(
          color: isActive ? Colors.white : const Color(0xFF2A1B38),
          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          fontSize: 15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Speech to Gesture"),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        titleTextStyle: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold, fontSize: 18),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildGestureDisplay(),

            const SizedBox(height: 16),
            _buildGlossRow(),

            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _transcript,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),

            if (_isRecording)
              const CircularProgressIndicator(color: Color(0xFF2A1B38))
            else
              ElevatedButton.icon(
                onPressed: _startListening,
                icon: const Icon(Icons.mic),
                label: const Text("Start Speaking"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A1B38),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}