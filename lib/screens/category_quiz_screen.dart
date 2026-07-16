import 'dart:math';
import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../data/daily_activity_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';

class CategoryQuizScreen extends StatefulWidget {
  final String category;
  const CategoryQuizScreen({Key? key, required this.category}) : super(key: key);

  @override
  State<CategoryQuizScreen> createState() => _CategoryQuizScreenState();
}

class _CategoryQuizScreenState extends State<CategoryQuizScreen> {
  late List<ASLWord> _questions;
  final Stopwatch _stopwatch = Stopwatch();
  int _currentIndex = 0;
  int _correctCount = 0;
  String? _selectedAnswer;
  bool _answered = false;
  bool _quizFinished = false;
  List<String> _currentOptions = [];

  @override
  void initState() {
    super.initState();
    _questions = List.of(wordsInCategory(widget.category))..shuffle();
    _generateOptions();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    DailyActivityService.logActivity(
      secondsSpent: _stopwatch.elapsed.inSeconds,
      type: 'quiz',
      label: widget.category,
    );
    super.dispose();
  }

  void _generateOptions() {
    final correct = _questions[_currentIndex].word;
    final pool = List<String>.from(
      wordsInCategory(widget.category).map((w) => w.word).where((w) => w != correct),
    );

    if (pool.length < 3) {
      final globalPool = aslWords.map((w) => w.word).where((w) => w != correct && !pool.contains(w)).toList();
      globalPool.shuffle();
      pool.addAll(globalPool.take(3 - pool.length));
    }

    pool.shuffle();
    final options = [correct, ...pool.take(3)];
    options.shuffle(Random());
    setState(() => _currentOptions = options);
  }

  void _selectAnswer(String answer) {
    if (_answered) return;
    final correct = _questions[_currentIndex].word;
    setState(() {
      _selectedAnswer = answer;
      _answered = true;
      if (answer == correct) _correctCount++;
    });

    Future.delayed(const Duration(milliseconds: 1200), _nextQuestion);
  }

  void _nextQuestion() {
    if (!mounted) return;
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _selectedAnswer = null;
      });
      _generateOptions();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    final scorePercent = _correctCount / _questions.length;
    final passed = scorePercent >= 0.7;

    if (passed) {
      await ProgressService.markQuizPassed(widget.category);
    }

    if (!mounted) return;
    setState(() => _quizFinished = true);
  }

  void _retakeQuiz() {
    setState(() {
      _questions.shuffle();
      _currentIndex = 0;
      _correctCount = 0;
      _answered = false;
      _selectedAnswer = null;
      _quizFinished = false;
    });
    _generateOptions();
  }

  /// Builds the gesture the player has to identify. Falls back to a
  /// placeholder for any word that doesn't have a recorded landmark
  /// asset yet.
  Widget _buildQuestionGesture() {
    final asset = _questions[_currentIndex].landmarksAsset;

    if (asset == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No gesture available\nfor this word.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SkeletalGestureViewer(
        // Re-keying on the asset path remounts the widget for each new
        // question, restarting the animation from the beginning.
        key: ValueKey(asset),
        assetPath: asset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_quizFinished) {
      final scorePercent = _correctCount / _questions.length;
      final passed = scorePercent >= 0.7;

      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  passed ? Icons.emoji_events : Icons.refresh,
                  color: passed ? Colors.amber : Colors.grey,
                  size: 72,
                ),
                const SizedBox(height: 20),
                Text(
                  passed ? 'Quiz Passed!' : 'Not Quite',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
                ),
                const SizedBox(height: 10),
                Text(
                  'You got $_correctCount out of ${_questions.length} correct.',
                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 6),
                if (!passed)
                  const Text(
                    'You need at least 70% to pass. Try again!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                const SizedBox(height: 40),
                if (!passed)
                  ElevatedButton(onPressed: _retakeQuiz, child: const Text('Retry Quiz')),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, passed),
                  child: Text(passed ? 'Continue' : 'Back to Collection'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final correct = _questions[_currentIndex].word;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        title: Text(
          '${widget.category} Quiz  (${_currentIndex + 1}/${_questions.length})',
          style: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(height: 220, child: _buildQuestionGesture()),
            const SizedBox(height: 24),
            const Text('Which word is this sign?', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 16),
            ..._currentOptions.map((option) {
              Color bgColor = Colors.grey.shade100;
              Color textColor = const Color(0xFF2A1B38);

              if (_answered) {
                if (option == correct) {
                  bgColor = Colors.green.shade100;
                  textColor = Colors.green.shade800;
                } else if (option == _selectedAnswer) {
                  bgColor = Colors.red.shade100;
                  textColor = Colors.red.shade800;
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _selectAnswer(option),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(14)),
                    child: Text(option, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15)),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}