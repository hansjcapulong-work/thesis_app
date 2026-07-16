import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';

class ASLWordVideoScreen extends StatefulWidget {
  final ASLWord word;
  const ASLWordVideoScreen({Key? key, required this.word}) : super(key: key);

  @override
  State<ASLWordVideoScreen> createState() => _ASLWordVideoScreenState();
}

class _ASLWordVideoScreenState extends State<ASLWordVideoScreen> {
  // Bumping this counter changes the SkeletalGestureViewer's key, which
  // forces it to remount and restart the animation from frame 0 --
  // our replacement for YoutubePlayerController.seekTo(Duration.zero).
  int _replayCount = 0;

  @override
  void initState() {
    super.initState();
    ProgressService.markWordWatched(widget.word.category, widget.word.word);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.word.landmarksAsset;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        title: Text(widget.word.word, style: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          if (asset != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SkeletalGestureViewer(
                  key: ValueKey('$asset-$_replayCount'),
                  assetPath: asset,
                ),
              ),
            )
          else
            Container(
              height: 260,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text(
                  'Gesture coming soon\nfor this word.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          const SizedBox(height: 30),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Category: ${widget.word.category}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
          const SizedBox(height: 20),
          if (asset != null)
            ElevatedButton.icon(
              onPressed: () => setState(() => _replayCount++),
              icon: const Icon(Icons.replay),
              label: const Text('Replay Sign'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A1B38),
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }
}