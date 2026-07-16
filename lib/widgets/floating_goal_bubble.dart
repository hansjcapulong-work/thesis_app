import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/daily_activity_service.dart';
import '../data/bubble_visibility.dart';

const _kBubblePurple = Color(0xFF8B5CF6);

class FloatingGoalBubble extends StatefulWidget {
  const FloatingGoalBubble({Key? key}) : super(key: key);

  @override
  State<FloatingGoalBubble> createState() => _FloatingGoalBubbleState();
}

class _FloatingGoalBubbleState extends State<FloatingGoalBubble> {
  double _top = 300;
  double _left = 0;
  bool _snappedRight = true;
  bool _dragging = false;
  bool _expanded = false;
  bool _positionInitialized = false;

  Timer? _refreshTimer;
  Timer? _tickTimer;
  final Stopwatch _sessionStopwatch = Stopwatch();

  int _goalMinutes = 0;
  int _baselineSeconds = 0; // seconds saved in Firestore before this session started
  bool _loading = true;

  static const double _collapsedSize = 64;
  static const double _expandedWidth = 170;
  static const double _expandedHeight = 190;
  static const double _edgeMargin = 8;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    bubbleVisible.addListener(_onVisibilityChanged);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    bubbleVisible.removeListener(_onVisibilityChanged);
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (bubbleVisible.value) {
      _sessionStopwatch.reset();
      _sessionStopwatch.start();
      _tickTimer?.cancel();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _sessionStopwatch.stop();
      _tickTimer?.cancel();
    }
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(
        user.uid).get();
    final goal = (userDoc.data()?['dailyGoalMinutes'] as int?) ?? 0;

    final today = await DailyActivityService.getDay(DateTime.now());
    final seconds = (today?['secondsPracticed'] as int?) ?? 0;

    if (!mounted) return;
    setState(() {
      _goalMinutes = goal;
      _baselineSeconds = seconds;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: bubbleVisible,
      builder: (context, visible, _) {
        final user = FirebaseAuth.instance.currentUser;
        if (!visible || user == null || _loading || _goalMinutes == 0) {
          return const SizedBox.shrink();
        }
        return _buildBubble(context);
      },
    );
  }

  Widget _buildBubble(BuildContext context) {
    final screenSize = MediaQuery
        .of(context)
        .size;

    if (!_positionInitialized) {
      _top = screenSize.height * 0.55;
      _left = screenSize.width - _collapsedSize - _edgeMargin;
      _positionInitialized = true;
    }

    // Live total = last saved value + however long this session has been running.
    final liveSeconds = _baselineSeconds + _sessionStopwatch.elapsed.inSeconds;
    final goalSeconds = _goalMinutes * 60;
    final remainingSeconds = goalSeconds - liveSeconds;
    final completed = remainingSeconds <= 0;
    final remainingMinutes = completed ? 0 : (remainingSeconds / 60).ceil();
    final practicedMinutes = (liveSeconds / 60).floor();
    final progress = goalSeconds == 0 ? 0.0 : (liveSeconds / goalSeconds).clamp(
        0.0, 1.0);

    final double restingLeft = _snappedRight
        ? screenSize.width - (_expanded ? _expandedWidth : _collapsedSize) -
        _edgeMargin
        : _edgeMargin;

    double displayTop;
    if (_expanded && !_dragging) {
      displayTop = (_top - (_expandedHeight - _collapsedSize) / 2)
          .clamp(20.0, screenSize.height - _expandedHeight - 20);
    } else {
      displayTop = _top.clamp(20.0, screenSize.height - _collapsedSize - 20);
    }

    final double displayLeft = _dragging ? _left : restingLeft;

    return AnimatedPositioned(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      left: displayLeft,
      top: displayTop,
      child: GestureDetector(
        onPanStart: _expanded ? null : (_) => setState(() => _dragging = true),
        onPanUpdate: _expanded
            ? null
            : (details) {
          setState(() {
            _left = (_left + details.delta.dx).clamp(
                0.0, screenSize.width - _collapsedSize);
            _top = (_top + details.delta.dy).clamp(
                20.0, screenSize.height - _collapsedSize - 20);
          });
        },
        onPanEnd: _expanded
            ? null
            : (details) {
          final centerX = _left + _collapsedSize / 2;
          setState(() {
            _dragging = false;
            _snappedRight = centerX > screenSize.width / 2;
          });
        },
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: _expanded ? _expandedWidth : _collapsedSize,
          height: _expanded ? _expandedHeight : _collapsedSize,
          decoration: _expanded
              ? BoxDecoration(
            color: _kBubblePurple,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black, width: 3),
          )
              : null,
          child: _expanded
              ? _expandedContent(
              completed, remainingMinutes, practicedMinutes, progress)
              : _PieClock(
              progress: progress, completed: completed, size: _collapsedSize),
        ),
      ),
    );
  }

  Widget _expandedContent(bool completed, int remainingMinutes,
      int practicedMinutes, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
          const Spacer(),
          _PieClock(progress: progress, completed: completed, size: 100),
          const Spacer(),
          Text(
            completed ? 'Done!' : '$remainingMinutes min left',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$practicedMinutes / $_goalMinutes min today',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
/// The pie-slice "clock" indicator: a black-outlined circle that fills
/// clockwise from 12 o'clock with purple as progress increases. Once
/// completed, it becomes a fully filled purple circle with "Done" text.
class _PieClock extends StatelessWidget {
  final double progress;
  final bool completed;
  final double size;

  const _PieClock({required this.progress, required this.completed, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _PieClockPainter(progress: progress, completed: completed),
          ),
          if (completed)
            Text(
              'Done',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.22,
              ),
            ),
        ],
      ),
    );
  }
}

class _PieClockPainter extends CustomPainter {
  final double progress;
  final bool completed;

  _PieClockPainter({required this.progress, required this.completed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.09;
    final radius = size.width / 2 - strokeWidth / 2;

    if (completed) {
      canvas.drawCircle(center, radius, Paint()..color = _kBubblePurple);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    canvas.drawCircle(center, radius, Paint()..color = Colors.white);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, -pi / 2, 2 * pi * progress, false)
      ..close();
    canvas.drawPath(path, Paint()..color = _kBubblePurple);

    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - radius),
      Paint()
        ..color = Colors.black
        ..strokeWidth = strokeWidth * 0.4,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _PieClockPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.completed != completed;
}