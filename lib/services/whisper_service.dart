import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Handles microphone recording and sends the audio to a locally-hosted
/// Whisper server running on your laptop (see whisper_server/server.py).
///
/// IMPORTANT: update [serverBaseUrl] below to match your laptop's local
/// IP address. Find it by running `ipconfig` on your laptop and looking
/// for the "IPv4 Address" under your active WiFi adapter (usually looks
/// like 192.168.x.x). Your phone and laptop must be connected to the
/// SAME WiFi network for this to work.
class WhisperService {
  // TODO: replace with your laptop's actual local IP address.
  static const String serverBaseUrl = 'http://192.168.100.106:8000';

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

  /// Stops recording, uploads the audio to your local Whisper server,
  /// and returns the transcribed text.
  Future<String> stopAndTranscribe() async {
    final stoppedPath = await _recorder.stop();
    final filePath = stoppedPath ?? _currentPath;
    if (filePath == null) {
      throw Exception('No recording found.');
    }

    final file = File(filePath);

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$serverBaseUrl/transcribe'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );
    } catch (e) {
      throw Exception(
        'Could not reach the Whisper server at $serverBaseUrl. '
        'Make sure server.py is running and your phone is on the same '
        'WiFi network as your laptop. ($e)',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);

    if (await file.exists()) {
      await file.delete();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Server error (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['transcript'] as String?) ?? '';
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
