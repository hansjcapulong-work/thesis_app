import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DailyActivityService {
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? get _col {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('dailyActivity');
  }

  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Adds practiced seconds to today's record and logs what was done.
  /// Marks the day as goal-completed once total seconds pass the user's
  /// chosen daily goal (in minutes).
  static Future<void> logActivity({
    required int secondsSpent,
    required String type,
    required String label,
  }) async {
    final col = _col;
    final uid = _uid;
    if (col == null || uid == null || secondsSpent <= 0) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final goalMinutes = (userDoc.data()?['dailyGoalMinutes'] as int?) ?? 0;

    final docRef = col.doc(dateKey(DateTime.now()));

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final currentSeconds = (snap.data()?['secondsPracticed'] as int?) ?? 0;
      final newSeconds = currentSeconds + secondsSpent;
      final completed = goalMinutes > 0 && newSeconds >= goalMinutes * 60;

      final activities = List<Map<String, dynamic>>.from(
        (snap.data()?['activities'] as List?) ?? [],
      );
      activities.add({
        'type': type,
        'label': label,
        'time': DateTime.now().toIso8601String(),
      });

      tx.set(docRef, {
        'secondsPracticed': newSeconds,
        'completedGoal': completed,
        'activities': activities,
      }, SetOptions(merge: true));
    });
  }

  static Future<Map<String, dynamic>?> getDay(DateTime d) async {
    final col = _col;
    if (col == null) return null;
    final doc = await col.doc(dateKey(d)).get();
    return doc.data();
  }

  /// Fetches all recorded days for a given month.
  static Future<Map<String, Map<String, dynamic>>> getMonth(int year, int month) async {
    final col = _col;
    if (col == null) return {};
    final snapshot = await col.get();
    final result = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      final parts = doc.id.split('-');
      if (parts.length == 3 && int.tryParse(parts[0]) == year && int.tryParse(parts[1]) == month) {
        result[doc.id] = doc.data();
      }
    }
    return result;
  }

  /// Counts consecutive completed days going backward from today.
  static Future<int> getCurrentStreak() async {
    final col = _col;
    if (col == null) return 0;
    int streak = 0;
    DateTime day = DateTime.now();
    while (true) {
      final doc = await col.doc(dateKey(day)).get();
      final completed = doc.data()?['completedGoal'] == true;
      if (!completed) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

const List<String> monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];