import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/app_bottom_nav.dart';

import '../data/avatar_options.dart';
import '../services/avatar_preference_service.dart';
import '../utils/slide_page_route.dart';
import 'progress_screen.dart';
import 'notifications_screen.dart';
import 'login_screen.dart';

const _purple = Color(0xFF2A1B38);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedAvatarId = kDefaultAvatarId;

  @override
  void initState() {
    super.initState();
    AvatarPreferenceService.load().then((option) {
      if (!mounted) return;
      setState(() => _selectedAvatarId = option.id);
    });
  }

  Future<void> _selectAvatar(AvatarOption option) async {
    if (option.id == _selectedAvatarId) return;
    final previous = _selectedAvatarId;
    setState(() => _selectedAvatarId = option.id); // optimistic
    try {
      await AvatarPreferenceService.save(option.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${option.label} will sign for you in Live Conversation'),
          duration: const Duration(seconds: 2),
        ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedAvatarId = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your avatar. Please try again.')),
      );
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  Widget _buildAvatarPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Avatar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _purple)),
        const SizedBox(height: 4),
        const Text('Choose who signs your spoken words in Live Conversation.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: [
            for (final option in kAvatarOptions)
              _AvatarCard(
                option: option,
                selected: option.id == _selectedAvatarId,
                onTap: () => _selectAvatar(option),
              ),
          ],
        ),
      ],
    );
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user?.displayName ?? 'User', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38))),
            const SizedBox(height: 4),
            Text(user?.email ?? '', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            _buildAvatarPicker(),
            const SizedBox(height: 40),
            ElevatedButton(onPressed: () => _logout(context), child: const Text('Log Out')),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTap: (i) {
          if (i == 3) return;
          if (i == 0) {
            Navigator.pop(context);
            return;
          }
          final Widget target = i == 1 ? const ProgressScreen() : const NotificationsScreen();
          Navigator.pushReplacement(
            context,
            slideToTabRoute(page: target, fromIndex: 3, toIndex: i),
          );
        },
      ),
    );
  }
}

class _AvatarCard extends StatelessWidget {
  final AvatarOption option;
  final bool selected;
  final VoidCallback onTap;

  const _AvatarCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label} avatar',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected ? _purple.withOpacity(0.06) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? _purple : Colors.transparent, width: 2),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: Container(
                        width: double.infinity,
                        color: option.accent.withOpacity(0.12),
                        child: Image.asset(
                          option.previewAsset,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) =>
                              Icon(option.icon, size: 40, color: option.accent),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(option.label,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: _purple)),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle, color: _purple, size: 22),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
