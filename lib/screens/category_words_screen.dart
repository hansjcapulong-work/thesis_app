import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../data/daily_activity_service.dart';
import 'asl_word_video_screen.dart';
import 'category_quiz_screen.dart';
import '../data/bubble_visibility.dart';

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
    bubbleVisible.value = true;
  }

  @override
  void dispose() {
    _stopwatch.stop();
    DailyActivityService.logActivity(
      secondsSpent: _stopwatch.elapsed.inSeconds,
      type: 'browsed',
      label: widget.category,
    );
    bubbleVisible.value = false;
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
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF2A1B38)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const CircleAvatar(backgroundColor: Color(0xFF2A1B38), child: Icon(Icons.person, color: Colors.white)),
                ],
              ),
              Text('${widget.category}\nCollection', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Progress', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  Text('${_watched.length}/$total Signs', style: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : _watched.length / total,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF2A1B38)),
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
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2A1B38)))
                    : ListView.separated(
                  itemCount: words.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final word = words[index];
                    final isWatched = _watched.contains(word.word);
                    final hasVideo = word.landmarksAsset != null;

                    return GestureDetector(
                      onTap: () async {
                        if (!hasVideo) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Video coming soon for this word.')),
                          );
                          return;
                        }
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ASLWordVideoScreen(word: word)),
                        );
                        _loadProgress();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(14)),
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
          color: allWatched ? const Color(0xFF2A1B38) : Colors.grey.shade200,
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