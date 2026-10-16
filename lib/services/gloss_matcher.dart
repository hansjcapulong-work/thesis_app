import 'dart:math' as math;

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

  // English function words that ASL doesn't sign. If one of these has no
  // match in aslWords it is SKIPPED rather than fingerspelled -- otherwise
  // "what is the name" would spell I-S and T-H-E. Only applies to words
  // that failed to match; anything with a sign clip still signs normally.
  static const Set<String> _skipWords = {
    'a', 'an', 'the',
    'is', 'are', 'am', 'was', 'were', 'be', 'been', 'being',
    'to', 'of', 'and', 'or', 'but', 'so', 'if', 'then', 'as',
    'it', 'its', 'that', 'this', 'there',
    'will', 'would', 'do', 'does', 'did',
    'have', 'has', 'had', 'can', 'could', 'should',
    'in', 'on', 'at', 'for',
    'just', 'um', 'uh', 'uhm', 'hmm',
  };

  /// How long each fingerspelled letter/digit plays before the next one
  /// starts. Every Anim_Letter_* / Anim_Number_* clip in the GLB is 2000ms
  /// long, which is far too slow for spelling (a 5-letter word = 10s), so
  /// letters are cut short. TUNE THIS by watching the avatar: too low and
  /// the hand never reaches the letter shape, too high and spelling drags.
  static const int letterDurationMs = 1200;

  /// Cap on letters per spelled word (URLs, garbled transcription, etc).
  static const int _maxSpellLength = 15;

  /// Longest multi-word phrase to look for ("looking for", "thank you").
  static const int _maxPhraseTokens = 3;

  // word / alias (lowercased) -> entry. Built once. putIfAbsent keeps the
  // "first entry in aslWords wins" behaviour the old firstWhere had.
  static final Map<String, ASLWord> _lookup = _buildLookup();

  static Map<String, ASLWord> _buildLookup() {
    final map = <String, ASLWord>{};
    for (final entry in aslWords) {
      map.putIfAbsent(entry.word.toLowerCase(), () => entry);
      for (final alias in entry.aliases) {
        map.putIfAbsent(alias.toLowerCase(), () => entry);
      }
    }
    return map;
  }

  static List<ASLWord> matchTranscript(String transcript) {
    final tokens = _tokenize(transcript);
    final units = _groupIntoUnits(tokens);
    final ordered = _applyAslWordOrder(units);

    final out = <ASLWord>[];
    for (final unit in ordered) {
      if (unit.match != null) {
        out.add(unit.match!);
      } else if (!_skipWords.contains(unit.text)) {
        out.addAll(_fingerspell(unit.text));
      }
    }
    return out;
  }

  /// Lowercases, expands contractions (so "don't" becomes "do not" instead
  /// of the unmatchable "dont"), strips punctuation and splits on spaces.
  static List<String> _tokenize(String transcript) {
    var t = transcript.toLowerCase().replaceAll('\u2019', "'");
    t = t
        .replaceAll("can't", 'can not')
        .replaceAll("won't", 'will not')
        .replaceAll("n't", ' not')
        .replaceAll("'m", ' am')
        .replaceAll("'re", ' are')
        .replaceAll("'ve", ' have')
        .replaceAll("'ll", ' will')
        .replaceAll("'d", ' would')
        .replaceAll("'s", '');
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  /// Walks the tokens left to right and, at each position, tries the
  /// longest phrase first (up to [_maxPhraseTokens] tokens) so entries
  /// like "Thank you", "Not yet" or the alias "looking for" can match.
  /// Unmatched tokens become single-token units with no match.
  static List<_Unit> _groupIntoUnits(List<String> tokens) {
    final units = <_Unit>[];
    var i = 0;
    while (i < tokens.length) {
      ASLWord? hit;
      var used = 1;
      final maxN = math.min(_maxPhraseTokens, tokens.length - i);
      for (var n = maxN; n >= 1; n--) {
        final candidate = tokens.sublist(i, i + n).join(' ');
        final m = _lookup[candidate];
        if (m != null) {
          hit = m;
          used = n;
          break;
        }
      }
      units.add(_Unit(tokens.sublist(i, i + used).join(' '), hit));
      i += used;
    }
    return units;
  }

  /// One ASLWord per letter/digit, played from Anim_Letter_X /
  /// Anim_Number_N clips that already exist in the GLB.
  static List<ASLWord> _fingerspell(String token) {
    final chars = token
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .split('')
        .take(_maxSpellLength)
        .toList();
    final spelled = chars.join();

    return [
      for (var i = 0; i < chars.length; i++)
        ASLWord(
          word: chars[i].toUpperCase(),
          category: 'Fingerspelling',
          signAnimation: RegExp(r'[0-9]').hasMatch(chars[i])
              ? 'Anim_Number_${chars[i]}'
              : 'Anim_Letter_${chars[i].toUpperCase()}',
          signDurationMs: letterDurationMs,
          isFingerspelled: true,
          spellingOf: spelled,
          letterIndex: i,
        ),
    ];
  }

  /// Reorders spoken-English word order into a closer approximation of
  /// ASL sentence structure:
  ///   1. Time words move to the front (time-topic structure).
  ///   2. WH-question words move to the end.
  /// Everything else keeps its original relative order in between.
  ///
  /// Works on whole units (a matched phrase or a single word), so a
  /// multi-word sign or a word that will be fingerspelled always moves
  /// as one piece.
  static List<_Unit> _applyAslWordOrder(List<_Unit> units) {
    final time = <_Unit>[];
    final wh = <_Unit>[];
    final rest = <_Unit>[];

    for (final u in units) {
      if (_timeWords.contains(u.text)) {
        time.add(u);
      } else if (_whWords.contains(u.text)) {
        wh.add(u);
      } else {
        rest.add(u);
      }
    }

    return [...time, ...rest, ...wh];
  }
}

/// A run of one or more spoken tokens, plus the sign entry they matched
/// (null if nothing matched and the text should be fingerspelled/skipped).
class _Unit {
  final String text;
  final ASLWord? match;
  const _Unit(this.text, this.match);
}