import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import 'asl_word_video_screen.dart';

class ASLPracticeScreen extends StatelessWidget {
  const ASLPracticeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        title: const Text('Practice ASL', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: aslCategories.length,
        itemBuilder: (context, index) {
          final category = aslCategories[index];
          final words = wordsInCategory(category);

          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: words.map((w) => _wordChip(context, w)).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _wordChip(BuildContext context, ASLWord word) {
    final hasVideo = word.landmarksAsset != null;

    return GestureDetector(
      onTap: () {
        if (!hasVideo) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video coming soon for this word.')),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ASLWordVideoScreen(word: word)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: hasVideo ? const Color(0xFF2A1B38) : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.word,
              style: TextStyle(
                color: hasVideo ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (hasVideo) ...[
              const SizedBox(width: 6),
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}