import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/app_bottom_nav.dart';
import '../data/bubble_visibility.dart';
import 'progress_screen.dart';
import 'notifications_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    bubbleVisible.value = false;
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Settings', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.displayName ?? 'User', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
            const SizedBox(height: 4),
            Text(user?.email ?? '', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: () => _logout(context), child: const Text('Log Out')),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTap: (i) {
          if (i == 0) Navigator.pop(context);
          if (i == 1) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProgressScreen()));
          if (i == 2) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        },
      ),
    );
  }
}