import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dashboard_screen.dart';

class SetDailyGoalScreen extends StatefulWidget {
  const SetDailyGoalScreen({Key? key}) : super(key: key);

  @override
  State<SetDailyGoalScreen> createState() => _SetDailyGoalScreenState();
}

class _SetDailyGoalScreenState extends State<SetDailyGoalScreen> {
  int? _selectedMinutes;
  bool _isSaving = false;

  final List<int> _options = [5, 10, 15, 20, 30, 45];

  Future<void> _saveGoal() async {
    if (_selectedMinutes == null) {
      _toast('Please select a daily goal.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'dailyGoalMinutes': _selectedMinutes,
        'dailyGoalSetAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
            (route) => false,
      );
    } catch (e) {
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            const Text(
              'Set your daily goal',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
            ),
            const SizedBox(height: 12),
            const Text(
              'How many minutes would you like to practice ASL each day?',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.6,
                ),
                itemCount: _options.length,
                itemBuilder: (context, index) {
                  final minutes = _options[index];
                  final isSelected = _selectedMinutes == minutes;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedMinutes = minutes),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF2A1B38) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF2A1B38) : Colors.grey.shade300,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$minutes min',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFF2A1B38),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSaving ? null : _saveGoal,
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue'),
            ),
          ],
        ),
      )),
    );
  }
}