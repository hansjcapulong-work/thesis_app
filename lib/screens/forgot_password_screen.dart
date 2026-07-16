import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _toast('Please enter your email.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('Password reset link sent! Check your email.');

      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _toast(_authErrorMessage(e));
    } catch (e) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for that email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      default:
        return e.message ?? 'Failed to send reset link. Please try again.';
    }
  }

  void _toast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: const Color(0xFF2A1B38),
      textColor: Colors.white,
      fontSize: 14,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
      ),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(30.0), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('Forgot Password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
          const SizedBox(height: 12),
          const Text(
            'Enter the email associated with your account and we\'ll send you a link to reset your password.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 40),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 5, offset: const Offset(0, 3)),
              ],
            ),
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF2A1B38)),
                labelText: 'Email:',
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                floatingLabelStyle: const TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _isLoading ? null : _sendResetLink,
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Send Reset Link'),
          ),
        ],
      ))),
    );
  }
}