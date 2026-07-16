import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'asl_words.dart';

class CategoryProgress {
  final Set<String> watchedWords;
  final bool quizPassed;
  const CategoryProgress({required this.watchedWords, required this.quizPassed});
}

class ProgressService {
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? get _progressCol {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('progress');
  }

  static Future<void> markWordWatched(String category, String word) async {
    final col = _progressCol;
    if (col == null) return;
    await col.doc(category).set({
      'watchedWords': FieldValue.arrayUnion([word]),
    }, SetOptions(merge: true));
  }

  static Future<void> markQuizPassed(String category) async {
    final col = _progressCol;
    if (col == null) return;
    await col.doc(category).set({
      'quizPassed': true,
    }, SetOptions(merge: true));
  }

  static Future<CategoryProgress> categoryProgress(String category) async {
    final col = _progressCol;
    if (col == null) return const CategoryProgress(watchedWords: {}, quizPassed: false);
    final doc = await col.doc(category).get();
    final list = (doc.data()?['watchedWords'] as List?)?.cast<String>() ?? [];
    final quizPassed = doc.data()?['quizPassed'] as bool? ?? false;
    return CategoryProgress(watchedWords: list.toSet(), quizPassed: quizPassed);
  }

  static Future<Map<String, CategoryProgress>> allProgress() async {
    final col = _progressCol;
    if (col == null) return {};
    final snapshot = await col.get();
    final result = <String, CategoryProgress>{};
    for (final doc in snapshot.docs) {
      final list = (doc.data()['watchedWords'] as List?)?.cast<String>() ?? [];
      final quizPassed = doc.data()['quizPassed'] as bool? ?? false;
      result[doc.id] = CategoryProgress(watchedWords: list.toSet(), quizPassed: quizPassed);
    }
    return result;
  }

  /// Progress value from 0.0–1.0. Watching all videos alone caps just under 1.0;
  /// passing the quiz is required to reach a full 100%.
  static double progressValue(int watchedCount, int total, bool quizPassed) {
    if (total == 0) return 0.0;
    return (watchedCount + (quizPassed ? 1 : 0)) / (total + 1);
  }

  static Future<(int, int)> overallProgress() async {
    final all = await allProgress();
    final totalWatched = all.values.fold<int>(0, (sum, p) => sum + p.watchedWords.length);
    final totalWords = aslWords.length;
    return (totalWatched, totalWords);
  }
}