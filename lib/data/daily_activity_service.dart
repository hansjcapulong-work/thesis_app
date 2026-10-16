import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoalUpdateResult {
  final bool justCompletedGoal;
  final int goalMinutes;
  const GoalUpdateResult({required this.justCompletedGoal, required this.goalMinutes});
}

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
  /// chosen daily goal (in minutes). Returns a result telling the caller
  /// whether the goal was *just* reached by this call (i.e. it was not
  /// already completed before), so the UI can show a one-time notification
  /// instead of repeating it on every subsequent activity that day.
  static Future<GoalUpdateResult> logActivity({
    required int secondsSpent,
    required String type,
    required String label,
  }) async {
    final col = _col;
    final uid = _uid;
    if (col == null || uid == null || secondsSpent <= 0) {
      return const GoalUpdateResult(justCompletedGoal: false, goalMinutes: 0);
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final goalMinutes = (userDoc.data()?['dailyGoalMinutes'] as int?) ?? 0;

    final docRef = col.doc(dateKey(DateTime.now()));

    bool justCompleted = false;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final currentSeconds = (snap.data()?['secondsPracticed'] as int?) ?? 0;
      final wasCompleted = snap.data()?['completedGoal'] == true;
      final newSeconds = currentSeconds + secondsSpent;
      final completed = goalMinutes > 0 && newSeconds >= goalMinutes * 60;

      justCompleted = completed && !wasCompleted;

      final activities = List<Map<String, dynamic>>.from(
        (snap.data()?['activities'] as List?) ?? [],
      );
      activities.add({
        'type': type,
        'label': label,
        'time': DateTime.now().toIso8601String(),
      });

      if (justCompleted) {
        activities.add({
          'type': 'goal',
          'label': goalMinutes > 0 ? 'Reached $goalMinutes min daily goal' : 'Daily goal completed',
          'time': DateTime.now().toIso8601String(),
        });
      }

      tx.set(docRef, {
        'secondsPracticed': newSeconds,
        'completedGoal': completed,
        'activities': activities,
      }, SetOptions(merge: true));
    });

    return GoalUpdateResult(justCompletedGoal: justCompleted, goalMinutes: goalMinutes);
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