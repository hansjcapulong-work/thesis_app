import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../widgets/custom_text_field.dart';
import '../data/bubble_visibility.dart';
import 'register_screen.dart';
import 'dashboard_screen.dart';
import 'forgot_password_screen.dart';
import 'verify_email_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    bubbleVisible.value = false;
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text.trim();

    if (identifier.isEmpty || password.isEmpty) {
      _toast('Please enter your username/email and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      String email;

      if (identifier.contains('@')) {
        email = identifier;
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(identifier.toLowerCase())
            .get();

        if (!doc.exists) {
          _toast('No account found for that username.');
          setState(() => _isLoading = false);
          return;
        }

        email = doc.data()!['email'] as String;
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await credential.user!.reload();
      final user = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (user != null && user.emailVerified) {
        _toast('Logged in successfully!');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      } else {
        _toast('Please verify your email before continuing.');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
        );
      }
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
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect username/email or password.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return e.message ?? 'Login failed. Please try again.';
    }
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
    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(30.0), child: Column(children: [
        const SizedBox(height: 80),
        const Text('Login here', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
        const SizedBox(height: 50),
        CustomTextField(controller: _identifierController, hintText: 'Username or Gmail:', icon: Icons.person_outline),
        const SizedBox(height: 20),
        CustomTextField(controller: _passwordController, hintText: 'Password:', icon: Icons.lock_outline, isPassword: true),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
            child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          child: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Log In'),
        ),
        const SizedBox(height: 60),
        OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('Create Account')),
      ]))),
    );
  }
}