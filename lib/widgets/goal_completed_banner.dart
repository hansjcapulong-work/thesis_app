import 'package:flutter/material.dart';

/// Call this after logging activity that might complete the daily goal.
/// Shows a purple banner sliding down from the top of the screen for a
/// few seconds, then automatically dismisses itself.
void showGoalCompletedBanner(BuildContext context, {int goalMinutes = 0}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _GoalCompletedBannerWidget(
      goalMinutes: goalMinutes,
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _GoalCompletedBannerWidget extends StatefulWidget {
  final int goalMinutes;
  final VoidCallback onDismiss;

  const _GoalCompletedBannerWidget({required this.goalMinutes, required this.onDismiss});

  @override
  State<_GoalCompletedBannerWidget> createState() => _GoalCompletedBannerWidgetState();
}

class _GoalCompletedBannerWidgetState extends State<_GoalCompletedBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1.2),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(seconds: 3), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _close,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1B38),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Color(0xFF2A1B38), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily goal complete!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (widget.goalMinutes > 0)
                          Text(
                            'You practiced ${widget.goalMinutes} minutes today.',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}