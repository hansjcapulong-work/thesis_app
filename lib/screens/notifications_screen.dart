import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';
import '../utils/slide_page_route.dart';
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
          if (i == 2) return;
          if (i == 0) {
            Navigator.pop(context);
            return;
          }
          final Widget target = i == 1 ? const ProgressScreen() : const SettingsScreen();
          Navigator.pushReplacement(
            context,
            slideToTabRoute(page: target, fromIndex: 2, toIndex: i),
          );
        },
      ),
    );
  }
}