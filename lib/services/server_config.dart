/// Single source of truth for the local dev server's base URL.
///
/// WhisperService (speech-to-text, /transcribe) and
/// GestureRecognitionService (sign classification, /recognize-gesture)
/// both hit the SAME laptop-hosted FastAPI server (server.py) -- just
/// different endpoints. Previously each service kept its own copy of
/// this constant, which meant it was easy to update the IP for one
/// feature and forget the other, so one would silently stop working
/// while the other kept going. Update it here only.
///
/// Find your laptop's IP:
///   Windows: `ipconfig` -> IPv4 Address under your active WiFi adapter
///   Mac:     `ipconfig getifaddr en0` (or en1 if on a different adapter)
/// It usually looks like 192.168.x.x. Your phone and laptop must be on
/// the same WiFi network.
class ServerConfig {
  static const String baseUrl = 'http://192.168.254.139:8000';
}
