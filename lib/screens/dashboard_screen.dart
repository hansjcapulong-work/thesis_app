import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../data/bubble_visibility.dart';
import 'login_screen.dart';
import 'practice_dashboard_screen.dart';
import 'speech_to_gesture_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime? _lastBackPressed;



  Future<void> _logout(BuildContext context) async {
    bubbleVisible.value = false;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _handleBackPress() {
    final now = DateTime.now();
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      Fluttertoast.showToast(
        msg: 'Press back again to exit',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFF2A1B38),
        textColor: Colors.white,
        fontSize: 14,
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Color(0xFF2A1B38)),
              tooltip: 'Log out',
              onPressed: () => _logout(context),
            ),
          ],
        ),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Hello, ${FirebaseAuth.instance.currentUser?.displayName ?? 'there'}!\nWhat would you\nlike to do today?',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 60),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PracticeDashboardScreen())),
            child: _build3DCard('Practice ASL', 'Learn and practice.', 'images/WOMAN.png', false),
          ),
          const SizedBox(height: 60),
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpeechToGestureScreen())),
            child: _build3DCard('Start\nConversation', 'Real-time communication.', 'images/communicating.png', true),
          ),
        ]))),
      ),
    );
  }

  Widget _build3DCard(String title, String sub, String img, bool isRight) {
    return SizedBox(height: 150, child: Stack(clipBehavior: Clip.none, children: [
      Positioned(top: 15, left: -12, right: 12, bottom: -12, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black, width: 2)))),
      Container(width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF2A1B38), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black, width: 2)), padding: EdgeInsets.only(left: isRight ? 24 : 140, right: isRight ? 140 : 24, top: 25), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11))])),
      Positioned(left: isRight ? null : -25, right: isRight ? -25 : null, top: -35, bottom: -5, child: Image.asset(img)),
    ]));
  }
}