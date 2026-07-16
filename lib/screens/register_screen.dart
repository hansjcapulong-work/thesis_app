import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../widgets/custom_text_field.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _isLoading = false;

  bool _hasMinLength = false;
  bool _hasUppercase = false;
  bool _hasLowercase = false;
  bool _hasSymbol = false;

  @override
  void initState() {
    super.initState();
    _pass.addListener(_validatePassword);
  }

  void _validatePassword() {
    final value = _pass.text;
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
      _hasLowercase = RegExp(r'[a-z]').hasMatch(value);
      _hasSymbol = RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/;~`]').hasMatch(value);
    });
  }

  bool get _isPasswordValid =>
      _hasMinLength && _hasUppercase && _hasLowercase && _hasSymbol;

  @override
  void dispose() {
    _pass.removeListener(_validatePassword);
    _username.dispose();
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _username.text.trim();
    final usernameKey = username.toLowerCase();
    final email = _email.text.trim();
    final password = _pass.text.trim();
    final confirm = _confirm.text.trim();

    if (username.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _toast('Please fill in all fields.');
      return;
    }
    if (!email.toLowerCase().endsWith('@gmail.com')) {
      _toast('Please use an official Gmail address (must end in @gmail.com).');
      return;
    }
    if (!_isPasswordValid) {
      _toast('Password does not meet all requirements.');
      return;
    }
    if (password != confirm) {
      _toast('Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final usernameDoc = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(usernameKey)
          .get();

      if (usernameDoc.exists) {
        _toast('That username is already taken.');
        setState(() => _isLoading = false);
        return;
      }

      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      await credential.user!.updateDisplayName(username);

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'username': username,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('usernames').doc(usernameKey).set({
        'email': email,
        'uid': uid,
      });

      await credential.user!.sendEmailVerification();

      _toast('Account created! Check your Gmail to verify your account.');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
      );
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
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      default:
        return e.message ?? 'Registration failed. Please try again.';
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

  Widget _requirementRow(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: met ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: met ? Colors.green : Colors.red,
              fontWeight: met ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(30.0), child: Column(children: [
        const SizedBox(height: 60),
        const Text('Sign In', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
        const SizedBox(height: 30),
        CustomTextField(controller: _username, hintText: 'Username:', icon: Icons.person_outline),
        const SizedBox(height: 20),
        CustomTextField(controller: _email, hintText: 'Gmail:', icon: Icons.email_outlined),
        const SizedBox(height: 20),
        CustomTextField(controller: _pass, hintText: 'Password:', icon: Icons.lock_outline, isPassword: true),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _requirementRow('At least 8 characters', _hasMinLength),
              _requirementRow('At least one uppercase letter', _hasUppercase),
              _requirementRow('At least one lowercase letter', _hasLowercase),
              _requirementRow('At least one symbol (!@#\$%^&* etc.)', _hasSymbol),
            ],
          ),
        ),
        const SizedBox(height: 20),
        CustomTextField(controller: _confirm, hintText: 'Confirm:', icon: Icons.lock_outline, isPassword: true),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: _isLoading ? null : _register,
          child: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sign In'),
        ),
        const SizedBox(height: 60),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Log In')),
      ]))),
    );
  }
}