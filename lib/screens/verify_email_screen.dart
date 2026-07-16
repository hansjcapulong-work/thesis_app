import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'login_screen.dart';
import 'set_daily_goal_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({Key? key}) : super(key: key);
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isResending = false;
  bool _isVerified = false;
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified() async {
    if (_isVerified) return;
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && user.emailVerified) {
        _autoCheckTimer?.cancel();
        if (!mounted) return;
        setState(() => _isVerified = true);

        await Future.delayed(const Duration(milliseconds: 900));

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SetDailyGoalScreen()),
              (route) => false,
        );
      }
    } catch (_) {
      // Silent fail — will just retry on the next timer tick.
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      _toast('Verification email resent!');
    } catch (e) {
      _toast('Failed to resend. Please try again shortly.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _logout() async {
    _autoCheckTimer?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _toast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFF2A1B38),
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.mark_email_unread_outlined, size: 64, color: Color(0xFF2A1B38)),
            const SizedBox(height: 24),
            const Text('Verify your email', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
            const SizedBox(height: 12),
            Text(
              'We sent a verification link to:\n$email\n\nCheck your inbox (and spam folder) and tap the link. This screen will continue automatically once verified.',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 50),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _isVerified
                    ? Column(
                  key: const ValueKey('verified'),
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 56),
                    SizedBox(height: 12),
                    Text('Verified!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                )
                    : Column(
                  key: const ValueKey('waiting'),
                  children: const [
                    CircularProgressIndicator(color: Color(0xFF2A1B38)),
                    SizedBox(height: 12),
                    Text('Waiting for verification...', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 50),
            OutlinedButton(
              onPressed: _isResending || _isVerified ? null : _resendEmail,
              child: _isResending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Resend Verification Email'),
            ),
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: _isVerified ? null : _logout,
                child: const Text('Log out', style: TextStyle(color: Colors.grey)),
              ),
            ),
          ],
        ),
      )),
    );
  }
}