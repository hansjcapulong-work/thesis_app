import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around flutter_tts for speaking recognized gestures
/// aloud -- the "gesture-to-speech" output side of your thesis's
/// real-time communication flow.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5); // slightly slower than default for clarity
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _isInitialized = true;
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    await _tts.stop(); // cancel anything currently speaking first
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void dispose() {
    _tts.stop();
  }
}
