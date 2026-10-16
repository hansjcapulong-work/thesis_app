class ASLWord {
  final String word;
  final String category;
  final String? landmarksAsset;
  // Legacy 2D vector-puppet path. Unused now that we're on the 3D avatar,
  // kept only so nothing else that reads it breaks.

  /// Exact animation clip name inside new_animations.glb. Must match the
  /// glTF animation name character-for-character, including the
  /// "Anim_" prefix -- that prefix is baked into the file we were given,
  /// not something we get to choose.
  final String? signAnimation;

  /// Clip length in milliseconds, read directly from the glTF sampler
  /// data (not estimated) so playback timing in AvatarGestureViewer is
  /// accurate.
  final int? signDurationMs;

  /// Alternate spoken phrasings that should resolve to this word
  /// when converting a Whisper transcript into ASL gloss.
  final List<String> aliases;

  /// True for entries that GlossMatcher generates on the fly when a
  /// spoken word has no sign clip of its own: one entry per letter or
  /// digit, played from Anim_Letter_X / Anim_Number_N. Never set on
  /// entries in [aslWords] itself.
  final bool isFingerspelled;

  /// The whole word this letter belongs to (e.g. "hello" for each of
  /// its five letters). Only set when [isFingerspelled] is true; used
  /// by the UI to show the word being spelled.
  final String? spellingOf;

  /// Position of this letter inside [spellingOf] (0-based).
  final int letterIndex;

  const ASLWord({
    required this.word,
    required this.category,
    this.aliases = const [],
    this.landmarksAsset,
    this.signAnimation,
    this.signDurationMs,
    this.isFingerspelled = false,
    this.spellingOf,
    this.letterIndex = 0,
  });

  /// Whether this word has a recorded/exported sign to show.
  bool get hasSign => signAnimation != null;
}

// -----------------------------------------------------------------------
// Covers all 146 signs delivered in new_animations.glb, up from the 48 in
// the earlier Anim_Avatar.glb. Every signAnimation below was verified
// against the clip names inside the .glb, and every signDurationMs was
// read from that file's sampler data (2000ms for all clips except
// Always / Please / Sorry, which run 3000ms).
//
// Aliases are checked to be collision-free: no spoken token maps to two
// different entries, which matters because GlossMatcher uses firstWhere
// and would silently take whichever entry appears earlier in this list.
// -----------------------------------------------------------------------

const List<ASLWord> aslWords = [
  // Greetings
  ASLWord(word: 'Hello', category: 'Greetings', aliases: ['hi', 'hey'], signAnimation: 'Anim_Hello', signDurationMs: 2000),
  ASLWord(word: 'Goodbye', category: 'Greetings', aliases: ['bye', 'bye bye', 'see you'], signAnimation: 'Anim_Goodbye', signDurationMs: 2000),
  ASLWord(word: 'Please', category: 'Greetings', signAnimation: 'Anim_Please', signDurationMs: 3000),
  ASLWord(word: 'Thank you', category: 'Greetings', aliases: ['thanks', 'thank'], signAnimation: 'Anim_Thank_you', signDurationMs: 2000),
  ASLWord(word: 'Sorry', category: 'Greetings', aliases: ['apologize', 'my bad'], signAnimation: 'Anim_Sorry', signDurationMs: 3000),
  ASLWord(word: 'Yes', category: 'Greetings', signAnimation: 'Anim_Yes', signDurationMs: 2000),
  ASLWord(word: 'No', category: 'Greetings', aliases: ['not'], signAnimation: 'Anim_No', signDurationMs: 2000),
  ASLWord(word: 'Fine', category: 'Greetings', aliases: ['ok', 'okay', 'alright'], signAnimation: 'Anim_Fine', signDurationMs: 2000),

  // Pronouns
  ASLWord(word: 'Me', category: 'Pronouns', aliases: ['i'], signAnimation: 'Anim_Me', signDurationMs: 2000),
  ASLWord(word: 'My', category: 'Pronouns', aliases: ['mine'], signAnimation: 'Anim_My', signDurationMs: 2000),
  ASLWord(word: 'We', category: 'Pronouns', aliases: ['us'], signAnimation: 'Anim_We', signDurationMs: 2000),
  ASLWord(word: 'You', category: 'Pronouns', aliases: ['yourself'], signAnimation: 'Anim_You', signDurationMs: 2000),
  ASLWord(word: 'Your', category: 'Pronouns', aliases: ['yours'], signAnimation: 'Anim_Your', signDurationMs: 2000),

  // Question Words
  ASLWord(word: 'How', category: 'Question Words', signAnimation: 'Anim_How', signDurationMs: 2000),
  ASLWord(word: 'What', category: 'Question Words', signAnimation: 'Anim_What', signDurationMs: 2000),
  ASLWord(word: 'When', category: 'Question Words', signAnimation: 'Anim_When', signDurationMs: 2000),
  ASLWord(word: 'Why', category: 'Question Words', signAnimation: 'Anim_Why', signDurationMs: 2000),

  // Family & People
  ASLWord(word: 'Family', category: 'Family & People', signAnimation: 'Anim_Family', signDurationMs: 2000),
  ASLWord(word: 'Friend', category: 'Family & People', aliases: ['friends'], signAnimation: 'Anim_Friend', signDurationMs: 2000),
  ASLWord(word: 'Mother', category: 'Family & People', aliases: ['mom', 'mommy', 'mama', 'mum'], signAnimation: 'Anim_Mother', signDurationMs: 2000),
  ASLWord(word: 'Father', category: 'Family & People', aliases: ['dad', 'daddy', 'papa'], signAnimation: 'Anim_Father', signDurationMs: 2000),
  ASLWord(word: 'Sister', category: 'Family & People', aliases: ['sisters'], signAnimation: 'Anim_Sister', signDurationMs: 2000),
  ASLWord(word: 'Brother', category: 'Family & People', aliases: ['brothers'], signAnimation: 'Anim_Brother', signDurationMs: 2000),
  ASLWord(word: 'Baby', category: 'Family & People', aliases: ['babies', 'infant'], signAnimation: 'Anim_Baby', signDurationMs: 2000),
  ASLWord(word: 'Children', category: 'Family & People', aliases: ['child', 'kid', 'kids'], signAnimation: 'Anim_Children', signDurationMs: 2000),
  ASLWord(word: 'Boy', category: 'Family & People', aliases: ['boys', 'son'], signAnimation: 'Anim_Boy', signDurationMs: 2000),
  ASLWord(word: 'Girl', category: 'Family & People', aliases: ['girls', 'daughter'], signAnimation: 'Anim_Girl', signDurationMs: 2000),
  ASLWord(word: 'Man', category: 'Family & People', aliases: ['men', 'guy'], signAnimation: 'Anim_Man', signDurationMs: 2000),
  ASLWord(word: 'Woman', category: 'Family & People', aliases: ['women', 'lady'], signAnimation: 'Anim_Woman', signDurationMs: 2000),
  ASLWord(word: 'Doctor', category: 'Family & People', aliases: ['doctors'], signAnimation: 'Anim_Doctor', signDurationMs: 2000),
  ASLWord(word: 'Teacher', category: 'Family & People', aliases: ['teachers'], signAnimation: 'Anim_Teacher', signDurationMs: 2000),

  // Feelings & States
  ASLWord(word: 'Good', category: 'Feelings & States', aliases: ['great', 'nice'], signAnimation: 'Anim_Good', signDurationMs: 2000),
  ASLWord(word: 'Bad', category: 'Feelings & States', signAnimation: 'Anim_Bad', signDurationMs: 2000),
  ASLWord(word: 'Happy', category: 'Feelings & States', aliases: ['glad'], signAnimation: 'Anim_Happy', signDurationMs: 2000),
  ASLWord(word: 'Sad', category: 'Feelings & States', aliases: ['unhappy'], signAnimation: 'Anim_Sad', signDurationMs: 2000),
  ASLWord(word: 'Angry', category: 'Feelings & States', aliases: ['mad', 'upset'], signAnimation: 'Anim_Angry', signDurationMs: 2000),
  ASLWord(word: 'Scared', category: 'Feelings & States', aliases: ['afraid', 'frightened', 'fear'], signAnimation: 'Anim_Scared', signDurationMs: 2000),
  ASLWord(word: 'Sick', category: 'Feelings & States', aliases: ['ill'], signAnimation: 'Anim_Sick', signDurationMs: 2000),
  ASLWord(word: 'Tired', category: 'Feelings & States', aliases: ['sleepy', 'exhausted'], signAnimation: 'Anim_Tired', signDurationMs: 2000),
  ASLWord(word: 'Hungry', category: 'Feelings & States', aliases: ['starving'], signAnimation: 'Anim_Hungry', signDurationMs: 2000),
  ASLWord(word: 'Thirsty', category: 'Feelings & States', signAnimation: 'Anim_Thirsty', signDurationMs: 2000),
  ASLWord(word: 'Busy', category: 'Feelings & States', signAnimation: 'Anim_Busy', signDurationMs: 2000),
  ASLWord(word: 'Love', category: 'Feelings & States', aliases: ['loves', 'loved'], signAnimation: 'Anim_Love', signDurationMs: 2000),
  ASLWord(word: 'Like', category: 'Feelings & States', aliases: ['likes', 'liked'], signAnimation: 'Anim_Like', signDurationMs: 2000),
  ASLWord(word: 'Feel', category: 'Feelings & States', aliases: ['feels', 'felt', 'feeling'], signAnimation: 'Anim_Feel', signDurationMs: 2000),
  ASLWord(word: 'Need', category: 'Feelings & States', aliases: ['needs', 'needed'], signAnimation: 'Anim_Need', signDurationMs: 2000),
  ASLWord(word: 'Want', category: 'Feelings & States', aliases: ['wants', 'wanted'], signAnimation: 'Anim_Want', signDurationMs: 2000),
  ASLWord(word: 'Safe', category: 'Feelings & States', signAnimation: 'Anim_Safe', signDurationMs: 2000),
  ASLWord(word: 'Understand', category: 'Feelings & States', aliases: ['understands', 'understood'], signAnimation: 'Anim_Understand', signDurationMs: 2000),
  ASLWord(word: 'Know', category: 'Feelings & States', aliases: ['knows', 'knew'], signAnimation: 'Anim_Know', signDurationMs: 2000),

  // Verbs & Actions
  ASLWord(word: 'Drink', category: 'Verbs & Actions', aliases: ['drinks', 'drank', 'drinking'], signAnimation: 'Anim_Drink', signDurationMs: 2000),
  ASLWord(word: 'Eat', category: 'Verbs & Actions', aliases: ['eats', 'ate', 'eating'], signAnimation: 'Anim_Eat', signDurationMs: 2000),
  ASLWord(word: 'Help', category: 'Verbs & Actions', aliases: ['helps', 'helped', 'helping'], signAnimation: 'Anim_Help', signDurationMs: 2000),
  ASLWord(word: 'Stop', category: 'Verbs & Actions', aliases: ['stops', 'stopped'], signAnimation: 'Anim_Stop', signDurationMs: 2000),
  ASLWord(word: 'Take', category: 'Verbs & Actions', aliases: ['takes', 'took', 'taking'], signAnimation: 'Anim_Take', signDurationMs: 2000),
  ASLWord(word: 'Finish', category: 'Verbs & Actions', aliases: ['done', 'finished', 'finishes'], signAnimation: 'Anim_Finish', signDurationMs: 2000),
  ASLWord(word: 'Go', category: 'Verbs & Actions', aliases: ['goes', 'went', 'going'], signAnimation: 'Anim_Go', signDurationMs: 2000),
  ASLWord(word: 'Come', category: 'Verbs & Actions', aliases: ['comes', 'came', 'coming'], signAnimation: 'Anim_Come', signDurationMs: 2000),
  ASLWord(word: 'Give', category: 'Verbs & Actions', aliases: ['gives', 'gave', 'giving'], signAnimation: 'Anim_Give', signDurationMs: 2000),
  ASLWord(word: 'Bring', category: 'Verbs & Actions', aliases: ['brings', 'brought'], signAnimation: 'Anim_Bring', signDurationMs: 2000),
  ASLWord(word: 'Buy', category: 'Verbs & Actions', aliases: ['buys', 'bought', 'purchase'], signAnimation: 'Anim_Buy', signDurationMs: 2000),
  ASLWord(word: 'Ask', category: 'Verbs & Actions', aliases: ['asks', 'asked', 'asking', 'question'], signAnimation: 'Anim_Ask', signDurationMs: 2000),
  ASLWord(word: 'See', category: 'Verbs & Actions', aliases: ['sees', 'saw', 'look', 'watch', 'looking'], signAnimation: 'Anim_See', signDurationMs: 2000),
  ASLWord(word: 'Hear', category: 'Verbs & Actions', aliases: ['hears', 'heard', 'listen', 'listening'], signAnimation: 'Anim_Hear', signDurationMs: 2000),
  ASLWord(word: 'Find', category: 'Verbs & Actions', aliases: ['finds', 'found', 'looking for'], signAnimation: 'Anim_Find', signDurationMs: 2000),
  ASLWord(word: 'Forget', category: 'Verbs & Actions', aliases: ['forgets', 'forgot', 'forgotten'], signAnimation: 'Anim_Forget', signDurationMs: 2000),
  ASLWord(word: 'Keep', category: 'Verbs & Actions', aliases: ['keeps', 'kept'], signAnimation: 'Anim_Keep', signDurationMs: 2000),
  ASLWord(word: 'Learn', category: 'Verbs & Actions', aliases: ['learns', 'learned', 'study', 'studying'], signAnimation: 'Anim_Learn', signDurationMs: 2000),
  ASLWord(word: 'Live', category: 'Verbs & Actions', aliases: ['lives', 'lived', 'living'], signAnimation: 'Anim_Live', signDurationMs: 2000),
  ASLWord(word: 'Work', category: 'Verbs & Actions', aliases: ['works', 'worked', 'working'], signAnimation: 'Anim_Work', signDurationMs: 2000),
  ASLWord(word: 'Play', category: 'Verbs & Actions', aliases: ['plays', 'played', 'playing'], signAnimation: 'Anim_Play', signDurationMs: 2000),
  ASLWord(word: 'Cook', category: 'Verbs & Actions', aliases: ['cooks', 'cooked', 'cooking'], signAnimation: 'Anim_Cook', signDurationMs: 2000),
  ASLWord(word: 'Dance', category: 'Verbs & Actions', aliases: ['dances', 'danced', 'dancing'], signAnimation: 'Anim_Dance', signDurationMs: 2000),
  ASLWord(word: 'Sit', category: 'Verbs & Actions', aliases: ['sits', 'sat', 'sitting'], signAnimation: 'Anim_Sit', signDurationMs: 2000),
  ASLWord(word: 'Sleep', category: 'Verbs & Actions', aliases: ['sleeps', 'slept', 'sleeping'], signAnimation: 'Anim_Sleep', signDurationMs: 2000),
  ASLWord(word: 'Fall', category: 'Verbs & Actions', aliases: ['falls', 'fell', 'fallen'], signAnimation: 'Anim_Fall', signDurationMs: 2000),
  ASLWord(word: 'Cry', category: 'Verbs & Actions', aliases: ['cries', 'cried', 'crying'], signAnimation: 'Anim_Cry', signDurationMs: 2000),
  ASLWord(word: 'Laugh', category: 'Verbs & Actions', aliases: ['laughs', 'laughed', 'laughing'], signAnimation: 'Anim_Laugh', signDurationMs: 2000),

  // Nouns
  ASLWord(word: 'Name', category: 'Nouns', aliases: ['names', 'called'], signAnimation: 'Anim_Name', signDurationMs: 2000),
  ASLWord(word: 'Water', category: 'Nouns', signAnimation: 'Anim_Water', signDurationMs: 2000),
  ASLWord(word: 'Food', category: 'Nouns', aliases: ['meal', 'meals'], signAnimation: 'Anim_Food', signDurationMs: 2000),
  ASLWord(word: 'Bread', category: 'Nouns', signAnimation: 'Anim_Bread', signDurationMs: 2000),
  ASLWord(word: 'Fruit', category: 'Nouns', aliases: ['fruits'], signAnimation: 'Anim_Fruit', signDurationMs: 2000),
  ASLWord(word: 'Book', category: 'Nouns', aliases: ['books'], signAnimation: 'Anim_Book', signDurationMs: 2000),
  ASLWord(word: 'Paper', category: 'Nouns', aliases: ['papers'], signAnimation: 'Anim_Paper', signDurationMs: 2000),
  ASLWord(word: 'Key', category: 'Nouns', aliases: ['keys'], signAnimation: 'Anim_Key', signDurationMs: 2000),
  ASLWord(word: 'Money', category: 'Nouns', aliases: ['cash', 'dollars', 'peso', 'pesos'], signAnimation: 'Anim_Money', signDurationMs: 2000),
  ASLWord(word: 'Clothes', category: 'Nouns', aliases: ['clothing', 'shirt', 'dress'], signAnimation: 'Anim_Clothes', signDurationMs: 2000),
  ASLWord(word: 'Chair', category: 'Nouns', aliases: ['chairs', 'seat'], signAnimation: 'Anim_Chair', signDurationMs: 2000),
  ASLWord(word: 'Table', category: 'Nouns', aliases: ['tables', 'desk'], signAnimation: 'Anim_Table', signDurationMs: 2000),
  ASLWord(word: 'Bed', category: 'Nouns', aliases: ['beds'], signAnimation: 'Anim_Bed', signDurationMs: 2000),
  ASLWord(word: 'Door', category: 'Nouns', aliases: ['doors'], signAnimation: 'Anim_Door', signDurationMs: 2000),
  ASLWord(word: 'Car', category: 'Nouns', aliases: ['cars'], signAnimation: 'Anim_Car', signDurationMs: 2000),
  ASLWord(word: 'Bus', category: 'Nouns', aliases: ['buses'], signAnimation: 'Anim_Bus', signDurationMs: 2000),
  ASLWord(word: 'Game', category: 'Nouns', aliases: ['games'], signAnimation: 'Anim_Game', signDurationMs: 2000),
  ASLWord(word: 'Idea', category: 'Nouns', aliases: ['ideas'], signAnimation: 'Anim_Idea', signDurationMs: 2000),
  ASLWord(word: 'Job', category: 'Nouns', aliases: ['jobs'], signAnimation: 'Anim_Job', signDurationMs: 2000),
  ASLWord(word: 'Animal', category: 'Nouns', aliases: ['animals'], signAnimation: 'Anim_Animal', signDurationMs: 2000),
  ASLWord(word: 'Cat', category: 'Nouns', aliases: ['cats'], signAnimation: 'Anim_Cat', signDurationMs: 2000),
  ASLWord(word: 'Dog', category: 'Nouns', aliases: ['dogs'], signAnimation: 'Anim_Dog', signDurationMs: 2000),

  // Body
  ASLWord(word: 'Eye', category: 'Body', aliases: ['eyes'], signAnimation: 'Anim_Eye', signDurationMs: 2000),
  ASLWord(word: 'Face', category: 'Body', aliases: ['faces'], signAnimation: 'Anim_Face', signDurationMs: 2000),
  ASLWord(word: 'Hair', category: 'Body', signAnimation: 'Anim_Hair', signDurationMs: 2000),
  ASLWord(word: 'Hand', category: 'Body', aliases: ['hands'], signAnimation: 'Anim_Hand', signDurationMs: 2000),

  // Colors
  ASLWord(word: 'Black', category: 'Colors', signAnimation: 'Anim_Black', signDurationMs: 2000),
  ASLWord(word: 'Blue', category: 'Colors', signAnimation: 'Anim_Blue', signDurationMs: 2000),
  ASLWord(word: 'Green', category: 'Colors', signAnimation: 'Anim_Green', signDurationMs: 2000),
  ASLWord(word: 'Red', category: 'Colors', signAnimation: 'Anim_Red', signDurationMs: 2000),
  ASLWord(word: 'Yellow', category: 'Colors', signAnimation: 'Anim_Yellow', signDurationMs: 2000),

  // Places
  ASLWord(word: 'School', category: 'Places', aliases: ['schools'], signAnimation: 'Anim_School', signDurationMs: 2000),
  ASLWord(word: 'Restroom', category: 'Places', aliases: ['bathroom', 'toilet', 'cr'], signAnimation: 'Anim_Restroom', signDurationMs: 2000),
  ASLWord(word: 'Home', category: 'Places', signAnimation: 'Anim_Home', signDurationMs: 2000),
  ASLWord(word: 'House', category: 'Places', aliases: ['houses'], signAnimation: 'Anim_House', signDurationMs: 2000),
  ASLWord(word: 'Hospital', category: 'Places', aliases: ['hospitals', 'clinic'], signAnimation: 'Anim_Hospital', signDurationMs: 2000),
  ASLWord(word: 'Store', category: 'Places', aliases: ['stores', 'shop', 'market'], signAnimation: 'Anim_Store', signDurationMs: 2000),
  ASLWord(word: 'City', category: 'Places', aliases: ['cities', 'town'], signAnimation: 'Anim_City', signDurationMs: 2000),
  ASLWord(word: 'Inside', category: 'Places', aliases: ['indoors'], signAnimation: 'Anim_Inside', signDurationMs: 2000),

  // Time & Sequence
  ASLWord(word: 'Now', category: 'Time & Sequence', signAnimation: 'Anim_Now', signDurationMs: 2000),
  ASLWord(word: 'Again', category: 'Time & Sequence', signAnimation: 'Anim_Again', signDurationMs: 2000),
  ASLWord(word: 'Always', category: 'Time & Sequence', signAnimation: 'Anim_Always', signDurationMs: 3000),
  ASLWord(word: 'Not yet', category: 'Time & Sequence', aliases: ['not_yet'], signAnimation: 'Anim_Not_yet', signDurationMs: 2000),
  ASLWord(word: 'Today', category: 'Time & Sequence', signAnimation: 'Anim_Today', signDurationMs: 2000),
  ASLWord(word: 'Tomorrow', category: 'Time & Sequence', signAnimation: 'Anim_Tomorrow', signDurationMs: 2000),
  ASLWord(word: 'Yesterday', category: 'Time & Sequence', signAnimation: 'Anim_Yesterday', signDurationMs: 2000),
  ASLWord(word: 'Morning', category: 'Time & Sequence', signAnimation: 'Anim_Morning', signDurationMs: 2000),
  ASLWord(word: 'Afternoon', category: 'Time & Sequence', signAnimation: 'Anim_Afternoon', signDurationMs: 2000),
  ASLWord(word: 'Evening', category: 'Time & Sequence', aliases: ['tonight'], signAnimation: 'Anim_Evening', signDurationMs: 2000),
  ASLWord(word: 'Night', category: 'Time & Sequence', aliases: ['nights'], signAnimation: 'Anim_Night', signDurationMs: 2000),
  ASLWord(word: 'Day', category: 'Time & Sequence', aliases: ['days'], signAnimation: 'Anim_Day', signDurationMs: 2000),
  ASLWord(word: 'Time', category: 'Time & Sequence', signAnimation: 'Anim_Time', signDurationMs: 2000),

  // Connectors
  ASLWord(word: 'Because', category: 'Connectors', signAnimation: 'Anim_Because', signDurationMs: 2000),
  ASLWord(word: 'With', category: 'Connectors', signAnimation: 'Anim_With', signDurationMs: 2000),
  ASLWord(word: 'Without', category: 'Connectors', signAnimation: 'Anim_Without', signDurationMs: 2000),
  ASLWord(word: 'About', category: 'Connectors', signAnimation: 'Anim_About', signDurationMs: 2000),
  ASLWord(word: 'All', category: 'Connectors', aliases: ['everything'], signAnimation: 'Anim_All', signDurationMs: 2000),
  ASLWord(word: 'Every', category: 'Connectors', aliases: ['each'], signAnimation: 'Anim_Every', signDurationMs: 2000),

  // Descriptions
  ASLWord(word: 'More', category: 'Descriptions', signAnimation: 'Anim_More', signDurationMs: 2000),
  ASLWord(word: 'Really', category: 'Descriptions', aliases: ['very'], signAnimation: 'Anim_Really', signDurationMs: 2000),
  ASLWord(word: 'Big', category: 'Descriptions', aliases: ['large', 'huge'], signAnimation: 'Anim_Big', signDurationMs: 2000),
  ASLWord(word: 'Small', category: 'Descriptions', aliases: ['little', 'tiny'], signAnimation: 'Anim_Small', signDurationMs: 2000),
  ASLWord(word: 'Hot', category: 'Descriptions', aliases: ['warm'], signAnimation: 'Anim_Hot', signDurationMs: 2000),
  ASLWord(word: 'Cold', category: 'Descriptions', aliases: ['chilly'], signAnimation: 'Anim_Cold', signDurationMs: 2000),
  ASLWord(word: 'Fast', category: 'Descriptions', aliases: ['quick', 'quickly', 'hurry'], signAnimation: 'Anim_Fast', signDurationMs: 2000),
  ASLWord(word: 'Hard', category: 'Descriptions', aliases: ['difficult', 'tough'], signAnimation: 'Anim_Hard', signDurationMs: 2000),
  ASLWord(word: 'Far', category: 'Descriptions', aliases: ['distant'], signAnimation: 'Anim_Far', signDurationMs: 2000),
  ASLWord(word: 'Beautiful', category: 'Descriptions', aliases: ['pretty'], signAnimation: 'Anim_Beautiful', signDurationMs: 2000),
];

List<String> get aslCategories {
  final seen = <String>{};
  final ordered = <String>[];
  for (final w in aslWords) {
    if (seen.add(w.category)) ordered.add(w.category);
  }
  return ordered;
}

List<ASLWord> wordsInCategory(String category) =>
    aslWords.where((w) => w.category == category).toList();