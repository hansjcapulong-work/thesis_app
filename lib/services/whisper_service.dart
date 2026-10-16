import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Handles microphone recording and sends the audio to Groq's hosted
/// Whisper API (free tier, no credit card) for transcription.
///
/// The public interface is unchanged (hasPermission / startRecording /
/// stopAndTranscribe / cancelRecording / dispose), so
/// live_conversation_screen.dart needs no edits.
///
/// The endpoint is synchronous and OpenAI-compatible: one POST, and the
/// transcript comes back in the response ({"text": "..."}).
///
/// Get a free key at https://console.groq.com/keys, then provide it at run
/// time instead of hardcoding it:
///   flutter run --dart-define=GROQ_API_KEY=gsk_...
class SttConfig {
  static const String endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  static const String apiKey = String.fromEnvironment('GROQ_API_KEY');

  /// Both are OpenAI's Whisper, hosted by Groq:
  ///  - 'whisper-large-v3-turbo': faster, slightly less accurate (default)
  ///  - 'whisper-large-v3': most accurate
  static const String model = 'whisper-large-v3-turbo';

  /// 2-letter code (ISO-639-1). Fixing it improves accuracy and latency on
  /// short clips. Set to null to auto-detect.
  static const String? language = 'en';

  static const Duration timeout = Duration(seconds: 45);
}

class WhisperService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    _currentPath =
    '${dir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _currentPath!,
    );
  }

  /// Stops recording, uploads the audio to Groq, and returns the text.
  Future<String> stopAndTranscribe() async {
    final stoppedPath = await _recorder.stop();
    final filePath = stoppedPath ?? _currentPath;
    if (filePath == null) {
      throw Exception('No recording found.');
    }

    if (SttConfig.apiKey.isEmpty) {
      throw Exception(
        'Missing Groq API key. Get a free one at console.groq.com/keys, '
            'then run the app with --dart-define=GROQ_API_KEY=gsk_...',
      );
    }

    final file = File(filePath);
    final size = await file.exists() ? await file.length() : 0;
    debugPrint('[STT] recorded file: $filePath ($size bytes)');
    if (size < 1024) {
      throw Exception(
        'Recording is empty ($size bytes). Check mic permission, and hold '
            'the mic for a second or two before stopping.',
      );
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(SttConfig.endpoint),
      );
      request.headers['Authorization'] = 'Bearer ${SttConfig.apiKey}';
      request.fields['model'] = SttConfig.model;
      request.fields['response_format'] = 'json';
      if (SttConfig.language != null) {
        request.fields['language'] = SttConfig.language!;
      }
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final http.Response response;
      try {
        final streamed = await request.send().timeout(SttConfig.timeout);
        response = await http.Response.fromStream(streamed);
      } catch (e) {
        throw Exception(
          'Could not reach Groq. Check your phone\'s internet '
              'connection. ($e)',
        );
      }

      debugPrint('[STT] ${response.statusCode}: ${response.body}');

      if (response.statusCode == 401) {
        throw Exception('Groq rejected the API key (401). Check the key.');
      }
      if (response.statusCode == 429) {
        throw Exception(
          'Groq free-tier rate limit reached (429). Wait a few seconds '
              'and try again.',
        );
      }
      if (response.statusCode != 200) {
        throw Exception('Groq error (${response.statusCode}): ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return ((data['text'] as String?) ?? '').trim();
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> cancelRecording() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}