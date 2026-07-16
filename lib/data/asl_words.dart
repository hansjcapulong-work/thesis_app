class ASLWord {
  final String word;
  final String category;
  final String? landmarksAsset;
  // leave null until you have the extracted landmarks JSON for this word

  /// Alternate spoken phrasings that should resolve to this word
  /// when converting a Whisper transcript into ASL gloss.
  /// e.g. for "Hello": ['hi', 'hey', 'greetings']
  final List<String> aliases;

  const ASLWord({
    required this.word,
    required this.category,
    this.aliases = const [],
    this.landmarksAsset,
  });
}

const List<ASLWord> aslWords = [
  // Greetings
  ASLWord(word: 'Hello', category: 'Greetings', aliases: ['hi', 'hey'], landmarksAsset: 'assets/gesture_landmarks/hello.json'),
  ASLWord(word: 'Bye', category: 'Greetings', aliases: ['goodbye', 'bye bye', 'see you']),
  ASLWord(word: 'Please', category: 'Greetings'),
  ASLWord(word: 'Thank you', category: 'Greetings', aliases: ['thanks', 'thank']),

  // Pronouns
  ASLWord(word: 'Yourself', category: 'Pronouns', aliases: ['you']),
  ASLWord(word: 'Mine/My', category: 'Pronouns', aliases: ['mine', 'my', 'i'], landmarksAsset: 'assets/gesture_landmarks/my.json'),
  ASLWord(word: 'We/Us', category: 'Pronouns', aliases: ['we', 'us']),
  ASLWord(word: 'He/She/It', category: 'Pronouns', aliases: ['he', 'she', 'it']),

  // Question Words
  ASLWord(word: 'Who', category: 'Question Words'),
  ASLWord(word: 'Where', category: 'Question Words'),
  ASLWord(word: 'Why', category: 'Question Words'),

  // Family & People
  ASLWord(word: 'Mom', category: 'Family & People', aliases: ['mother', 'mommy']),
  ASLWord(word: 'Dad', category: 'Family & People', aliases: ['father', 'daddy']),
  ASLWord(word: 'Child', category: 'Family & People', aliases: ['kid']),
  ASLWord(word: 'Person', category: 'Family & People'),
  ASLWord(word: 'Baby', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/baby.json'),
  ASLWord(word: 'Boy', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/boy.json'),
  ASLWord(word: 'Brother', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/brother.json'),
  ASLWord(word: 'Children', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/children.json'),
  ASLWord(word: 'Father', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/father.json'),
  ASLWord(word: 'Girl', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/girl.json'),
  ASLWord(word: 'Man', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/man.json'),
  ASLWord(word: 'Mother', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/mother.json'),
  ASLWord(word: 'Sister', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/sister.json'),
  ASLWord(word: 'Woman', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/woman.json'),
  ASLWord(word: 'Name', category: 'Family & People', landmarksAsset: 'assets/gesture_landmarks/name.json'),

  // Feelings & States
  ASLWord(word: 'Sleepy', category: 'Feelings & States', aliases: ['tired']),
  ASLWord(word: 'Mad', category: 'Feelings & States', aliases: ['angry']),
  ASLWord(word: 'Sad', category: 'Feelings & States', aliases: ['unhappy'], landmarksAsset: 'assets/gesture_landmarks/sad.json'),
  ASLWord(word: 'Happy', category: 'Feelings & States', aliases: ['glad']),
  ASLWord(word: 'Fine', category: 'Feelings & States', aliases: ['ok', 'okay', 'good'], landmarksAsset: 'assets/gesture_landmarks/fine.json'),
  ASLWord(word: 'Hate', category: 'Feelings & States', aliases: ['dislike']),
  ASLWord(word: 'Like', category: 'Feelings & States', aliases: ['love', 'want'], landmarksAsset: 'assets/gesture_landmarks/like.json'),
  ASLWord(word: 'Hot', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/hot.json'),
  ASLWord(word: 'Sick', category: 'Feelings & States', aliases: ['ill']),
  ASLWord(word: 'Hungry', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/hungry.json'),
  ASLWord(word: 'Thirsty', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/thirsty.json'),
  ASLWord(word: 'Angry', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/angry.json'),
  ASLWord(word: 'Busy', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/busy.json'),
  ASLWord(word: 'Scared', category: 'Feelings & States', aliases: ['afraid'], landmarksAsset: 'assets/gesture_landmarks/scared.json'),
  ASLWord(word: 'Tired', category: 'Feelings & States', landmarksAsset: 'assets/gesture_landmarks/tired.json'),

  // Verbs & Actions
  ASLWord(word: 'Drink', category: 'Verbs & Actions'),
  ASLWord(word: 'Find', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/find.json'),
  ASLWord(word: 'Cry', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/cry.json'),
  ASLWord(word: 'Go', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/go.json'),
  ASLWord(word: 'Stay', category: 'Verbs & Actions'),
  ASLWord(word: 'Say', category: 'Verbs & Actions'),
  ASLWord(word: 'Wait', category: 'Verbs & Actions'),
  ASLWord(word: 'Give', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/give.json'),
  ASLWord(word: 'Have', category: 'Verbs & Actions'),
  ASLWord(word: 'Sleep', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/sleep.json'),
  ASLWord(word: 'Call on phone', category: 'Verbs & Actions', aliases: ['call', 'phone']),
  ASLWord(word: 'Ask', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/ask.json'),
  ASLWord(word: 'Bring', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/bring.json'),
  ASLWord(word: 'Buy', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/buy.json'),
  ASLWord(word: 'Clean', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/clean.json'),
  ASLWord(word: 'Come', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/come.json'),
  ASLWord(word: 'Cook', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/cook.json'),
  ASLWord(word: 'Dance', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/dance.json'),
  ASLWord(word: 'Fall', category: 'Verbs & Actions', aliases: ['trip', 'tumble'], landmarksAsset: 'assets/gesture_landmarks/fall.json'),
  ASLWord(word: 'Feel', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/feel.json'),
  ASLWord(word: 'Forget', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/forget.json'),
  ASLWord(word: 'Hear', category: 'Verbs & Actions', aliases: ['listen'], landmarksAsset: 'assets/gesture_landmarks/hear.json'),
  ASLWord(word: 'Keep', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/keep.json'),
  ASLWord(word: 'Know', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/know.json'),
  ASLWord(word: 'Laugh', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/laugh.json'),
  ASLWord(word: 'Learn', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/learn.json'),
  ASLWord(word: 'Live', category: 'Verbs & Actions', aliases: ['reside'], landmarksAsset: 'assets/gesture_landmarks/live.json'),
  ASLWord(word: 'Play', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/play.json'),
  ASLWord(word: 'See', category: 'Verbs & Actions', aliases: ['look'], landmarksAsset: 'assets/gesture_landmarks/see.json'),
  ASLWord(word: 'Sit', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/sit.json'),
  ASLWord(word: 'Wash', category: 'Verbs & Actions', landmarksAsset: 'assets/gesture_landmarks/wash.json'),
  ASLWord(word: 'Work', category: 'Verbs & Actions', aliases: ['job'], landmarksAsset: 'assets/gesture_landmarks/work.json'),

  // Nouns
  ASLWord(word: 'Food', category: 'Nouns', aliases: ['eat'], landmarksAsset: 'assets/gesture_landmarks/food.json'),
  ASLWord(word: 'Water', category: 'Nouns'),
  ASLWord(word: 'Bed', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/bed.json'),
  ASLWord(word: 'Book', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/book.json'),
  ASLWord(word: 'Bread', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/bread.json'),
  ASLWord(word: 'Bus', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/bus.json'),
  ASLWord(word: 'Car', category: 'Nouns', aliases: ['drive'], landmarksAsset: 'assets/gesture_landmarks/car.json'),
  ASLWord(word: 'Chair', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/chair.json'),
  ASLWord(word: 'Clothes', category: 'Nouns', aliases: ['clothing'], landmarksAsset: 'assets/gesture_landmarks/clothes.json'),
  ASLWord(word: 'Door', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/door.json'),
  ASLWord(word: 'Fruit', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/fruit.json'),
  ASLWord(word: 'Game', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/game.json'),
  ASLWord(word: 'Idea', category: 'Nouns', aliases: ['thought'], landmarksAsset: 'assets/gesture_landmarks/idea.json'),
  ASLWord(word: 'Job', category: 'Nouns', aliases: ['work'], landmarksAsset: 'assets/gesture_landmarks/job.json'),
  ASLWord(word: 'Key', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/key.json'),
  ASLWord(word: 'Money', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/money.json'),
  ASLWord(word: 'Paper', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/paper.json'),
  ASLWord(word: 'Table', category: 'Nouns', landmarksAsset: 'assets/gesture_landmarks/table.json'),

  // Time & Sequence
  ASLWord(word: 'Later', category: 'Time & Sequence'),
  ASLWord(word: 'Now', category: 'Time & Sequence'),
  ASLWord(word: 'Before', category: 'Time & Sequence'),
  ASLWord(word: 'After', category: 'Time & Sequence'),
  ASLWord(word: 'Afternoon', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/afternoon.json'),
  ASLWord(word: 'Day', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/day.json'),
  ASLWord(word: 'Evening', category: 'Time & Sequence', aliases: ['night'], landmarksAsset: 'assets/gesture_landmarks/evening.json'),
  ASLWord(word: 'Every', category: 'Time & Sequence', aliases: ['each'], landmarksAsset: 'assets/gesture_landmarks/every.json'),
  ASLWord(word: 'Morning', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/morning.json'),
  ASLWord(word: 'Night', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/night.json'),
  ASLWord(word: 'Time', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/time.json'),
  ASLWord(word: 'Today', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/today.json'),
  ASLWord(word: 'Tomorrow', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/tomorrow.json'),
  ASLWord(word: 'Yesterday', category: 'Time & Sequence', landmarksAsset: 'assets/gesture_landmarks/yesterday.json'),

  // Quantity & Negation
  ASLWord(word: 'All', category: 'Quantity & Negation', landmarksAsset: 'assets/gesture_landmarks/all.json'),
  ASLWord(word: 'Any', category: 'Quantity & Negation'),
  ASLWord(word: 'No', category: 'Quantity & Negation'),
  ASLWord(word: 'Not', category: 'Quantity & Negation', aliases: ["don't", 'dont']),

  // Connectors
  ASLWord(word: 'Because', category: 'Connectors'),
  ASLWord(word: 'About', category: 'Connectors', aliases: ['concerning', 'regarding'], landmarksAsset: 'assets/gesture_landmarks/about.json'),
  ASLWord(word: 'Inside', category: 'Connectors', aliases: ['in'], landmarksAsset: 'assets/gesture_landmarks/inside.json'),

  // Colors
  ASLWord(word: 'Black', category: 'Colors', landmarksAsset: 'assets/gesture_landmarks/black.json'),
  ASLWord(word: 'Blue', category: 'Colors', landmarksAsset: 'assets/gesture_landmarks/blue.json'),
  ASLWord(word: 'Green', category: 'Colors', landmarksAsset: 'assets/gesture_landmarks/green.json'),
  ASLWord(word: 'Red', category: 'Colors', landmarksAsset: 'assets/gesture_landmarks/red.json'),
  ASLWord(word: 'Yellow', category: 'Colors', landmarksAsset: 'assets/gesture_landmarks/yellow.json'),

  // Animals
  ASLWord(word: 'Animal', category: 'Animals', aliases: ['creature'], landmarksAsset: 'assets/gesture_landmarks/animal.json'),
  ASLWord(word: 'Cat', category: 'Animals', landmarksAsset: 'assets/gesture_landmarks/cat.json'),
  ASLWord(word: 'Dog', category: 'Animals', landmarksAsset: 'assets/gesture_landmarks/dog.json'),

  // Body Parts
  ASLWord(word: 'Eye', category: 'Body Parts', landmarksAsset: 'assets/gesture_landmarks/eye.json'),
  ASLWord(word: 'Face', category: 'Body Parts', landmarksAsset: 'assets/gesture_landmarks/face.json'),
  ASLWord(word: 'Hair', category: 'Body Parts', landmarksAsset: 'assets/gesture_landmarks/hair.json'),
  ASLWord(word: 'Hand', category: 'Body Parts', landmarksAsset: 'assets/gesture_landmarks/hand.json'),

  // Places
  ASLWord(word: 'City', category: 'Places', aliases: ['town'], landmarksAsset: 'assets/gesture_landmarks/city.json'),
  ASLWord(word: 'Home', category: 'Places', landmarksAsset: 'assets/gesture_landmarks/home.json'),
  ASLWord(word: 'Hospital', category: 'Places', landmarksAsset: 'assets/gesture_landmarks/hospital.json'),
  ASLWord(word: 'House', category: 'Places', landmarksAsset: 'assets/gesture_landmarks/house.json'),
  ASLWord(word: 'Store', category: 'Places', aliases: ['shop'], landmarksAsset: 'assets/gesture_landmarks/store.json'),

  // Descriptions
  ASLWord(word: 'Beautiful', category: 'Descriptions', aliases: ['pretty', 'gorgeous'], landmarksAsset: 'assets/gesture_landmarks/beautiful.json'),
  ASLWord(word: 'Big', category: 'Descriptions', aliases: ['large'], landmarksAsset: 'assets/gesture_landmarks/big.json'),
  ASLWord(word: 'Cold', category: 'Descriptions', aliases: ['chilly'], landmarksAsset: 'assets/gesture_landmarks/cold.json'),
  ASLWord(word: 'Far', category: 'Descriptions', aliases: ['distant'], landmarksAsset: 'assets/gesture_landmarks/far.json'),
  ASLWord(word: 'Fast', category: 'Descriptions', aliases: ['quick'], landmarksAsset: 'assets/gesture_landmarks/fast.json'),
  ASLWord(word: 'Hard', category: 'Descriptions', aliases: ['difficult'], landmarksAsset: 'assets/gesture_landmarks/hard.json'),
  ASLWord(word: 'Small', category: 'Descriptions', aliases: ['little'], landmarksAsset: 'assets/gesture_landmarks/small.json'),
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