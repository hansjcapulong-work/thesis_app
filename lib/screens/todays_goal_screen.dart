import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/daily_activity_service.dart';

class TodaysGoalScreen extends StatefulWidget {
  const TodaysGoalScreen({Key? key}) : super(key: key);

  @override
  State<TodaysGoalScreen> createState() => _TodaysGoalScreenState();
}

class _TodaysGoalScreenState extends State<TodaysGoalScreen> {
  int _goalMinutes = 0;
  int _secondsPracticed = 0;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final goal = (userDoc.data()?['dailyGoalMinutes'] as int?) ?? 0;

    final today = await DailyActivityService.getDay(DateTime.now());
    final seconds = (today?['secondsPracticed'] as int?) ?? 0;

    if (!mounted) return;
    setState(() {
      _goalMinutes = goal;
      _secondsPracticed = seconds;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF2A1B38))));
    }

    final goalSeconds = _goalMinutes * 60;
    final remainingSeconds = goalSeconds - _secondsPracticed;
    final completed = remainingSeconds <= 0;
    final progressValue = goalSeconds == 0 ? 0.0 : (_secondsPracticed / goalSeconds).clamp(0.0, 1.0);
    final remainingMinutes = completed ? 0 : (remainingSeconds / 60).ceil();
    final practicedMinutes = (_secondsPracticed / 60).floor();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        title: const Text("Today's Goal", style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: progressValue,
                      strokeWidth: 14,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(completed ? Colors.green : const Color(0xFF2A1B38)),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        completed ? Icons.check_circle : Icons.access_time_filled,
                        color: completed ? Colors.green : const Color(0xFF2A1B38),
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        completed ? 'Goal Complete!' : '$remainingMinutes min left',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '$practicedMinutes / $_goalMinutes minutes practiced today',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}