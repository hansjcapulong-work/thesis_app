import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../data/daily_activity_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'select_collection_screen.dart';
import 'category_words_screen.dart';
import 'progress_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'calendar_screen.dart';

class PracticeDashboardScreen extends StatefulWidget {
  const PracticeDashboardScreen({Key? key}) : super(key: key);

  @override
  State<PracticeDashboardScreen> createState() => _PracticeDashboardScreenState();
}

class _PracticeDashboardScreenState extends State<PracticeDashboardScreen> {
  Map<String, CategoryProgress> _progress = {};
  bool _loadingProgress = true;
  int _streak = 0;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    DailyActivityService.getCurrentStreak().then((s) {
      if (mounted) setState(() => _streak = s);
    });
  }

  Future<void> _loadProgress() async {
    final data = await ProgressService.allProgress();
    if (!mounted) return;
    setState(() {
      _progress = data;
      _loadingProgress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    int watchedTotal = 0;
    for (final p in _progress.values) {
      watchedTotal += p.watchedWords.length;
    }
    final totalWords = aslWords.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProgress,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    Expanded(
                      child: Text(
                        'Hi, ${user?.displayName ?? 'there'}!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF2A1B38),
                        child: Icon(Icons.person, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Overall Progress', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
                          Text('$watchedTotal/$totalWords Signs', style: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: totalWords == 0 ? 0 : watchedTotal / totalWords,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade300,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF2A1B38)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Continue Lessons', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SelectCollectionScreen())),
                      child: const Text('See all', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _loadingProgress
                    ? Container(height: 84, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(18)))
                    : _CyclingCollectionCard(progress: _progress),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Daily Tracker', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
                      child: const Text('Calendar', style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _WeekTracker(),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _signOfTheDayCard()),
                    const SizedBox(width: 14),
                    Expanded(child: _streakCard(_streak)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTap: (i) {
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen()));
          if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          if (i == 3) Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
    );
  }

  Widget _signOfTheDayCard() {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(18)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sign of\nthe day', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          Spacer(),
          Icon(Icons.back_hand_outlined, color: Colors.white, size: 36),
        ],
      ),
    );
  }

  Widget _streakCard(int streak) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Practice\nStreak', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Text('$streak', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _CyclingCollectionCard extends StatefulWidget {
  final Map<String, CategoryProgress> progress;
  const _CyclingCollectionCard({required this.progress});

  @override
  State<_CyclingCollectionCard> createState() => _CyclingCollectionCardState();
}

class _CyclingCollectionCardState extends State<_CyclingCollectionCard> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % aslCategories.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = aslCategories[_index];
    final total = wordsInCategory(category).length;
    final catProgress = widget.progress[category];
    final watched = catProgress?.watchedWords.length ?? 0;
    final quizPassed = catProgress?.quizPassed ?? false;
    final value = ProgressService.progressValue(watched, total, quizPassed);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryWordsScreen(category: category))),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Container(
          key: ValueKey(category),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(18)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(category, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              _circularProgress(value),
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

class _WeekTracker extends StatefulWidget {
  const _WeekTracker();

  @override
  State<_WeekTracker> createState() => _WeekTrackerState();
}

class _WeekTrackerState extends State<_WeekTracker> {
  Map<String, Map<String, dynamic>> _monthData = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final data = await DailyActivityService.getMonth(now.year, now.month);
    if (!mounted) return;
    setState(() => _monthData = data);
  }

  void _showDayDetail(DateTime day) {
    final key = DailyActivityService.dateKey(day);
    final data = _monthData[key];
    final activities = List<Map<String, dynamic>>.from((data?['activities'] as List?) ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${monthNames[day.month - 1]} ${day.day}, ${day.year}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
            ),
            const SizedBox(height: 12),
            if (activities.isEmpty)
              const Text('No activity recorded this day.', style: TextStyle(color: Colors.grey))
            else ...[
              Text(
                '${(((data?['secondsPracticed'] as int?) ?? 0) / 60).round()} minutes practiced',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ...activities.map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '• ${a['type'] == 'quiz' ? 'Took quiz: ' : 'Watched: '}${a['label']}',
                  style: const TextStyle(color: Color(0xFF2A1B38)),
                ),
              )),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthLabel = monthNames[now.month - 1];
    final weekday = now.weekday;
    final monday = now.subtract(Duration(days: weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(monthLabel, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: days.map((day) {
              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
              final key = DailyActivityService.dateKey(day);
              final completed = _monthData[key]?['completedGoal'] == true;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () => _showDayDetail(day),
                  child: Container(
                    width: 50,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: completed ? const Color(0xFF2A1B38) : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                      border: isToday && !completed ? Border.all(color: const Color(0xFF2A1B38), width: 1.5) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekdayLabels[day.weekday - 1],
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: completed ? Colors.white : Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: completed ? Colors.white : const Color(0xFF2A1B38)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}