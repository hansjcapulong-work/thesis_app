import 'package:flutter/material.dart';
import '../data/asl_words.dart';
import '../data/progress_service.dart';
import '../widgets/app_bottom_nav.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({Key? key}) : super(key: key);

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  Map<String, CategoryProgress> _progress = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ProgressService.allProgress();
    if (!mounted) return;
    setState(() {
      _progress = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    double totalValue = 0;
    for (final category in aslCategories) {
      final total = wordsInCategory(category).length;
      final p = _progress[category];
      totalValue += ProgressService.progressValue(p?.watchedWords.length ?? 0, total, p?.quizPassed ?? false);
    }
    final overallPercent = aslCategories.isEmpty ? 0.0 : totalValue / aslCategories.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Progress', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2A1B38)))
          : ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Overall Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: overallPercent,
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(overallPercent * 100).round()}% complete across all collections',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('By Collection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
          const SizedBox(height: 14),
          ...aslCategories.map((category) {
            final total = wordsInCategory(category).length;
            final p = _progress[category];
            final value = ProgressService.progressValue(p?.watchedWords.length ?? 0, total, p?.quizPassed ?? false);
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(category, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2A1B38))),
                      Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF2A1B38)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTap: (i) {
          if (i == 0) Navigator.pop(context);
          if (i == 2) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          if (i == 3) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
    );
  }
}