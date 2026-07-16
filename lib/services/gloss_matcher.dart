import '../data/asl_words.dart';

class GlossMatcher {
  // WH-question words move to the END of the sentence in ASL grammar,
  // e.g. "what is your name" -> "... name what".
  static const Set<String> _whWords = {
    'what', 'where', 'who', 'why', 'when', 'how',
  };

  // Time words move to the FRONT of the sentence, following ASL's
  // time-topic sentence structure, e.g. "I will go tomorrow" becomes
  // "tomorrow I go".
  static const Set<String> _timeWords = {
    'today', 'tomorrow', 'yesterday',
    'morning', 'afternoon', 'evening', 'night',
    'now', 'later',
  };

  static List<ASLWord> matchTranscript(String transcript) {
    // Normalize transcript: lowercase and remove punctuation
    final normalized = transcript.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final rawWords = normalized.split(' ').where((w) => w.isNotEmpty).toList();

    final reordered = _applyAslWordOrder(rawWords);

    List<ASLWord> matches = [];

    for (var word in reordered) {
      // Try to find a direct match or an alias match
      final match = aslWords.firstWhere(
            (asl) => asl.word.toLowerCase() == word || asl.aliases.contains(word),
        orElse: () => const ASLWord(word: '', category: ''), // Return empty placeholder
      );

      if (match.word.isNotEmpty) {
        matches.add(match);
      }
    }

    return matches;
  }

  /// Reorders spoken-English word order into a closer approximation of
  /// ASL sentence structure:
  ///   1. Time words move to the front (time-topic structure).
  ///   2. WH-question words move to the end.
  /// Everything else keeps its original relative order in between.
  ///
  /// This is intentionally two general, well-documented ASL grammar
  /// rules -- not a full syntax parser -- so it stays predictable and
  /// easy to extend later.
  static List<String> _applyAslWordOrder(List<String> words) {
    final timeWords = <String>[];
    final whWords = <String>[];
    final rest = <String>[];

    for (final w in words) {
      if (_timeWords.contains(w)) {
        timeWords.add(w);
      } else if (_whWords.contains(w)) {
        whWords.add(w);
      } else {
        rest.add(w);
      }
    }

    return [...timeWords, ...rest, ...whWords];
  }
}