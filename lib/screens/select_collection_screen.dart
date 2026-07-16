import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import 'category_words_screen.dart';

class SelectCollectionScreen extends StatefulWidget {
  const SelectCollectionScreen({Key? key}) : super(key: key);

  @override
  State<SelectCollectionScreen> createState() => _SelectCollectionScreenState();
}

class _SelectCollectionScreenState extends State<SelectCollectionScreen> {
  Map<String, CategoryProgress> _progress = {};
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final data = await ProgressService.allProgress();
      if (!mounted) return;
      setState(() {
        _progress = data;
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
    final filteredCategories = aslCategories.where((category) {
      final query = _searchQuery.toLowerCase();
      final matchesCategory = category.toLowerCase().contains(query);
      final matchesWord = wordsInCategory(category)
          .any((w) => w.word.toLowerCase().contains(query));
      return matchesCategory || matchesWord;
    }).toList();

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
                  const Text('Select Collection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
                  const CircleAvatar(backgroundColor: Color(0xFF2A1B38), child: Icon(Icons.person, color: Colors.white)),
                ],
              ),
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
                  itemCount: filteredCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final category = filteredCategories[index];
                    final total = wordsInCategory(category).length;
                    final catProgress = _progress[category];
                    final watchedCount = catProgress?.watchedWords.length ?? 0;
                    final quizPassed = catProgress?.quizPassed ?? false;
                    final progress = ProgressService.progressValue(watchedCount, total, quizPassed);

                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CategoryWordsScreen(category: category)),
                        );
                        _loadProgress();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(18)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(category, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            _circularProgress(progress),
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

  Widget _circularProgress(double value) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 4,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
          ),
          Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}