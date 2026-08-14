import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'server_config.dart';

/// Handles microphone recording and sends the audio to a locally-hosted
/// Whisper server running on your laptop (see whisper_server/server.py).
///
/// Server address now lives in [ServerConfig.baseUrl] (server_config.dart)
/// -- it's shared with GestureRecognitionService since both hit the same
/// laptop server. Update the IP there, not here.
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
      Uri.parse('${ServerConfig.baseUrl}/transcribe'),
    );
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
    } catch (e) {
      throw Exception(
        'Could not reach the server at ${ServerConfig.baseUrl}. '
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