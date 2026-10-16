import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../data/daily_activity_service.dart';
import '../widgets/skeletal_gesture_viewer.dart';
import '../widgets/goal_completed_banner.dart';

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
  final Stopwatch _stopwatch = Stopwatch();
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    ProgressService.markWordWatched(widget.word.category, widget.word.word);
    _stopwatch.start();
  }

  /// Logs the time spent on this specific word (not just the category),
  /// then shows a one-time banner if this activity just crossed the
  /// user's daily goal, then actually leaves the screen. Run before the
  /// pop (not in dispose()) so we still have a valid context to show
  /// the banner with.
  Future<void> _exit() async {
    if (_exiting) return;
    _exiting = true;

    _stopwatch.stop();
    final result = await DailyActivityService.logActivity(
      secondsSpent: _stopwatch.elapsed.inSeconds,
      type: 'watched',
      label: widget.word.word,
    );

    if (!mounted) return;

    if (result.justCompletedGoal) {
      showGoalCompletedBanner(context, goalMinutes: result.goalMinutes);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.word.landmarksAsset;

    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _exit();
        },
        child: Scaffold(
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
        ),
    );
  }
}