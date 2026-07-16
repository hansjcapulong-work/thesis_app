import 'package:flutter/material.dart';
import 'login_screen.dart';

// 1. Introduction Screen
class IntroductionScreen extends StatelessWidget {
  const IntroductionScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 40.0), child: Align(alignment: Alignment.centerLeft, child: Text('Welcome to\n(Name)', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF1E1E1E))))),
          const Spacer(),
          GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const IntroOneScreen())), child: _arrow()),
        ]),
      ),
    );
  }
}

// 2. Intro 1 Screen
class IntroOneScreen extends StatelessWidget {
  const IntroOneScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Column(children: [
        const Spacer(),
        SizedBox(height: 500, width: double.infinity, child: Image.asset('images/deafillustration.png', fit: BoxFit.contain)),
        const Text('Real-Time ASL Translation', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 40.0), child: Text('Smart communication assistance.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
        const Spacer(),
        GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const IntroTwoScreen())), child: _arrow()),
      ])),
    );
  }
}

// 3. Intro 2 Screen
class IntroTwoScreen extends StatelessWidget {
  const IntroTwoScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(30.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        SizedBox(height: 450, child: Image.asset('images/blindilu.png', fit: BoxFit.contain)),
        const Text('Breaking Communication\nBarriers', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
        const SizedBox(height: 10),
        const Text('Connect and communicate with ease', style: TextStyle(fontSize: 14, color: Colors.grey)),
        const Spacer(),
        ElevatedButton(
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 600),
                pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  const begin = Offset(0.0, 1.0);
                  const end = Offset.zero;
                  const curve = Curves.easeOutCubic;
                  var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                  return SlideTransition(position: animation.drive(tween), child: child);
                },
              ),
                  (route) => false,
            );
          },
          child: const Text('Get Started', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 20),
      ]))),
    );
  }
}

Widget _arrow() => Container(margin: const EdgeInsets.only(bottom: 50), padding: const EdgeInsets.all(12), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, width: 2)), child: const CircleAvatar(backgroundColor: Color(0xFF2A1B38), radius: 24, child: Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20)));