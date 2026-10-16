import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'introduction_screen.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';

class AppEntryPoint extends StatefulWidget {
  const AppEntryPoint({Key? key}) : super(key: key);

  @override
  State<AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<AppEntryPoint> {
  @override
  void initState() {
    super.initState();
    _decideStartScreen();
  }

  Future<void> _decideStartScreen() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenIntro = prefs.getBool('hasSeenIntro') ?? false;
    final currentUser = FirebaseAuth.instance.currentUser;

    Widget nextScreen;
    if (!hasSeenIntro) {
      // Never seen the 3 intro screens -> show them first.
      nextScreen = const IntroductionScreen();
    } else if (currentUser != null) {
      // Already logged in -> skip Login entirely.
      nextScreen = const DashboardScreen();
    } else {
      // Seen intro, but not logged in.
      nextScreen = const LoginScreen();
    }

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    // Brief loading state while prefs + auth are checked.
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF2A1B38))),
    );
  }
}