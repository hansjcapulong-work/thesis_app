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
/// Currently set to the laptop's Wi-Fi IP while on mobile-hotspot testing
/// (10.86.145.187). This is a DHCP lease, not a fixed address -- it can
/// change if the hotspot is rejoined. If requests suddenly stop reaching
/// the server, re-run `ipconfig` and check this value first.
///
/// Find your laptop's IP:
///   Windows: `ipconfig` -> IPv4 Address under your active WiFi adapter
///   Mac:     `ipconfig getifaddr en0` (or en1 if on a different adapter)
/// It usually looks like 192.168.x.x or 10.x.x.x. Your phone and laptop
/// must be on the same network -- on a hotspot, that means the phone is
/// either hosting it or joined to the same one the laptop is on.
class ServerConfig {
  static const String baseUrl = 'http://192.168.254.113:8000';
}