import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// A single message within a conversation session, either signed or spoken.
class ConversationEntryData {
  final String source; // 'signed' or 'spoken'
  final String text;
  final DateTime timestamp;

  ConversationEntryData({
    required this.source,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'source': source,
    'text': text,
    'timestamp': Timestamp.fromDate(timestamp),
  };

  factory ConversationEntryData.fromMap(Map<String, dynamic> map) {
    return ConversationEntryData(
      source: map['source'] as String? ?? 'spoken',
      text: map['text'] as String? ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// A saved conversation session: everything exchanged in one visit to
/// LiveConversationScreen, from open to close.
class ConversationSession {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<ConversationEntryData> entries;

  ConversationSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.entries,
  });

  factory ConversationSession.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final data = doc.data() ?? {};
    final rawEntries = (data['entries'] as List?) ?? [];
    return ConversationSession(
      id: doc.id,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      entries: rawEntries
          .map((e) =>
          ConversationEntryData.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// Reads/writes conversation history under:
/// users/{uid}/conversations/{conversationId}
class ConversationHistoryService {
  static CollectionReference<Map<String, dynamic>>? _collection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('conversations');
  }

  /// Saves a completed conversation session. Call this when the user leaves
  /// LiveConversationScreen, passing every entry added to the chat during
  /// that visit. No-ops if there's nothing to save or nobody is signed in.
  static Future<void> saveSession({
    required DateTime startedAt,
    required List<ConversationEntryData> entries,
  }) async {
    if (entries.isEmpty) return;
    final col = _collection();
    if (col == null) return;

    await col.add({
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': Timestamp.fromDate(DateTime.now()),
      'entries': entries.map((e) => e.toMap()).toList(),
    });
  }

  /// Streams all past conversations for the current user, most recent first.
  static Stream<List<ConversationSession>> streamSessions() {
    final col = _collection();
    if (col == null) return const Stream.empty();
    return col.orderBy('startedAt', descending: true).snapshots().map(
          (snap) => snap.docs.map(ConversationSession.fromDoc).toList(),
    );
  }

  /// Deletes a single conversation session by id. No-ops if nobody is
  /// signed in.
  static Future<void> deleteSession(String id) async {
    final col = _collection();
    if (col == null) return;
    await col.doc(id).delete();
  }

  /// Deletes multiple conversation sessions in one batched write. Used for
  /// both multi-select delete and "delete all from a date" (pass every
  /// session id in that date group). No-ops if the list is empty or nobody
  /// is signed in.
  static Future<void> deleteSessions(List<String> ids) async {
    if (ids.isEmpty) return;
    final col = _collection();
    if (col == null) return;

    // Firestore batches are capped at 500 writes; chunk defensively in case
    // a user has an unusually large selection.
    const chunkSize = 450;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final id in chunk) {
        batch.delete(col.doc(id));
      }
      await batch.commit();
    }
  }
}