import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Notifications', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: const Center(child: Text('No notifications yet.', style: TextStyle(color: Colors.grey))),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 2,
        onTap: (i) {
          if (i == 0) Navigator.pop(context);
          if (i == 1) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProgressScreen()));
          if (i == 3) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        },
      ),
    );
  }
}