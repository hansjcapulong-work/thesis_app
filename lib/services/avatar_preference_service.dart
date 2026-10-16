import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/avatar_options.dart';

/// Remembers which avatar the user picked in Settings. Stored per signed-in
/// account on this device, so two people sharing a phone each keep their own.
class AvatarPreferenceService {
  AvatarPreferenceService._();

  static String get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return 'selected_avatar_id_$uid';
  }

  static Future<AvatarOption> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return avatarById(prefs.getString(_key));
    } catch (_) {
      return avatarById(null);
    }
  }

  static Future<void> save(String avatarId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, avatarId);
  }
}
