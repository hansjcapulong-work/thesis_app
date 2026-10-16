import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../data/daily_activity_service.dart';
import '../widgets/avatar_gesture_viewer.dart';
import 'asl_word_video_screen.dart';
import 'category_quiz_screen.dart';

const _purple = Color(0xFF2A1B38);

class CategoryWordsScreen extends StatefulWidget {
  final String category;
  const CategoryWordsScreen({Key? key, required this.category}) : super(key: key);

  @override
  State<CategoryWordsScreen> createState() => _CategoryWordsScreenState();
}

class _CategoryWordsScreenState extends State<CategoryWordsScreen> {
  Set<String> _watched = {};
  bool _quizPassed = false;
  bool _loading = true;
  String _searchQuery = '';
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    DailyActivityService.logActivity(
      secondsSpent: _stopwatch.elapsed.inSeconds,
      type: 'browsed',
      label: widget.category,
    );
    super.dispose();
  }

  Future<void> _loadProgress() async {
    try {
      final progress = await ProgressService.categoryProgress(widget.category);
      if (!mounted) return;
      setState(() {
        _watched = progress.watchedWords;
        _quizPassed = progress.quizPassed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load progress: $e')),
      );
    }
  }

  /// Opens the 3D avatar preview for [word]. If the user taps "Full lesson"
  /// the sheet closes with `true`, and we continue into the existing
  /// ASLWordVideoScreen flow (which is what records the word as watched).
  Future<void> _showSignPreview(ASLWord word) async {
    final openLesson = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SignPreviewSheet(word: word),
    );

    if (openLesson == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ASLWordVideoScreen(word: word)),
      );
      _loadProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = wordsInCategory(widget.category)
        .where((w) => w.word.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    final total = wordsInCategory(widget.category).length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: _purple),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const CircleAvatar(backgroundColor: _purple, child: Icon(Icons.person, color: Colors.white)),
                ],
              ),
              Text('${widget.category}\nCollection', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _purple)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Progress', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text('${_watched.length}/$total Signs', style: const TextStyle(color: _purple, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : _watched.length / total,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: const AlwaysStoppedAnimation(_purple),
                ),
              ),
              const SizedBox(height: 16),
              _quizButton(total),
              const SizedBox(height: 20),
              TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search Words or Collections',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _purple))
                    : ListView.separated(
                  itemCount: words.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final word = words[index];
                    final isWatched = _watched.contains(word.word);
                    final hasVideo = word.hasSign;

                    return GestureDetector(
                      onTap: () {
                        if (!hasVideo) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Video coming soon for this word.')),
                          );
                          return;
                        }
                        _showSignPreview(word);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(word.word, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                            Icon(
                              isWatched ? Icons.check_circle : Icons.play_circle_fill,
                              color: isWatched ? Colors.greenAccent : Colors.white,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quizButton(int total) {
    final allWatched = _watched.length >= total && total > 0;

    if (_quizPassed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green.shade200)),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
            const SizedBox(width: 8),
            Text('Quiz Passed', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: allWatched
          ? () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryQuizScreen(category: widget.category)));
        _loadProgress();
      }
          : () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch all signs in this collection before taking the quiz.')),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: allWatched ? _purple : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, color: allWatched ? Colors.white : Colors.grey.shade500, size: 18),
            const SizedBox(width: 8),
            Text(
              allWatched ? 'Take Quiz' : 'Take Quiz (locked)',
              style: TextStyle(color: allWatched ? Colors.white : Colors.grey.shade500, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that plays [word]'s sign on the 3D avatar, looping with a
/// short pause between repeats until the sheet is dismissed.
class _SignPreviewSheet extends StatefulWidget {
  final ASLWord word;
  const _SignPreviewSheet({required this.word});

  @override
  State<_SignPreviewSheet> createState() => _SignPreviewSheetState();
}

class _SignPreviewSheetState extends State<_SignPreviewSheet> {
  // AvatarGestureViewer replays whenever this changes.
  int _playCount = 0;

  static const Duration _loopPause = Duration(milliseconds: 600);

  void _replayNow() {
    if (!mounted) return;
    setState(() => _playCount++);
  }

  Future<void> _loopAfterPause() async {
    await Future.delayed(_loopPause);
    _replayNow();
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text(
              word.word,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _purple),
            ),
            const SizedBox(height: 12),
            Container(
              height: 320,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: _purple, width: 2),
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey.shade100,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AvatarGestureViewer(
                  animationName: word.signAnimation,
                  durationMs: word.signDurationMs,
                  sequenceKey: _playCount,
                  onFinished: _loopAfterPause,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _replayNow,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Replay'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.school, size: 18),
                    label: const Text('Full lesson'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}