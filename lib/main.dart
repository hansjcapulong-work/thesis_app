import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/introduction_screen.dart';
import 'widgets/floating_goal_bubble.dart';
import 'data/bubble_visibility.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  bubbleVisible.value = false; // never show on app cold start until logged into the dashboard
  runApp(const CommunicationApp());
}

class CommunicationApp extends StatelessWidget {
  const CommunicationApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistive Communication App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2A1B38),
        scaffoldBackgroundColor: Colors.white,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2A1B38),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ),
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            const FloatingGoalBubble(),
          ],
        );
      },
      home: const IntroductionScreen(),
    );
  }
}