import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A single animation frame: normalized (0-1) landmark positions for the
/// left hand, right hand (21 points each), and body pose (33 points),
/// following MediaPipe's landmark layouts. Any of these may be null if
/// that part wasn't visible when the source video was captured.
class GestureFrame {
  final List<Offset>? left;
  final List<Offset>? right;
  final List<Offset>? pose;

  GestureFrame({this.left, this.right, this.pose});

  factory GestureFrame.fromJson(Map<String, dynamic> json) {
    List<Offset>? parsePoints(dynamic raw) {
      if (raw == null) return null;
      return (raw as List)
          .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList();
    }

    return GestureFrame(
      left: parsePoints(json['left']),
      right: parsePoints(json['right']),
      pose: parsePoints(json['pose']),
    );
  }
}

// MediaPipe Pose landmark indices used here.
const int _poseNose = 0;
const int _poseLeftShoulder = 11;
const int _poseRightShoulder = 12;
const int _poseLeftElbow = 13;
const int _poseRightElbow = 14;
const int _poseLeftWrist = 15;
const int _poseRightWrist = 16;
const int _poseLeftHip = 23;
const int _poseRightHip = 24;

/// ===========================================================================
/// EVERYTHING YOU'D WANT TO CUSTOMIZE LIVES HERE.
/// Change colors, proportions, or style below -- nothing else in this
/// file needs to be touched to reskin the character.
/// ===========================================================================
class CharacterStyle {
  // --- Colors ---
  final Color skinColor;
  final Color shirtColor;
  final Color eyeColor;
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color shadowColor;

  // --- Proportions (as a fraction of shoulder width, so they scale
  // naturally with however far the signer stands from the camera) ---
  final double headSizeRatio; // head radius relative to shoulder width
  final double upperArmThicknessRatio;
  final double forearmThicknessRatio;
  final double eyeSizeRatio; // eye radius relative to head radius
  final double eyeSpacingRatio; // eye distance from head center

  // --- Hand style ---
  final double fingerBaseWidth;
  final double fingerTipWidth;
  final double palmOpacity;
  final double shadowBlur;
  final Offset shadowOffset;

  const CharacterStyle({
    this.skinColor = const Color(0xFFE8B98A),
    this.shirtColor = const Color(0xFF2A1B38),
    this.eyeColor = Colors.black87,
    this.backgroundTop = const Color(0xFFF5F5F5),
    this.backgroundBottom = const Color(0xFFE0E0E0),
    this.shadowColor = Colors.black,
    this.headSizeRatio = 0.42,
    this.upperArmThicknessRatio = 0.13,
    this.forearmThicknessRatio = 0.10,
    this.eyeSizeRatio = 0.09,
    this.eyeSpacingRatio = 0.35,
    this.fingerBaseWidth = 11.0,
    this.fingerTipWidth = 5.0,
    this.palmOpacity = 0.95,
    this.shadowBlur = 4.0,
    this.shadowOffset = const Offset(2, 4),
  });

  /// A couple of ready-made alternate looks -- pass one of these to
  /// SkeletalGestureViewer(style: ...), or copy one and tweak further.
  static const CharacterStyle warm = CharacterStyle();

  static const CharacterStyle cool = CharacterStyle(
    skinColor: Color(0xFFD8C3A5),
    shirtColor: Color(0xFF1B3A4B),
    backgroundTop: Color(0xFFEFF5F7),
    backgroundBottom: Color(0xFFDCE8EC),
  );

  static const CharacterStyle highContrast = CharacterStyle(
    skinColor: Color(0xFFFFFFFF),
    shirtColor: Color(0xFF000000),
    eyeColor: Colors.black,
    backgroundTop: Color(0xFFFAFAFA),
    backgroundBottom: Color(0xFFFAFAFA),
  );
}

class SkeletalGestureData {
  final String word;
  final int fps;
  final List<GestureFrame> frames;

  SkeletalGestureData({
    required this.word,
    required this.fps,
    required this.frames,
  });

  factory SkeletalGestureData.fromJson(Map<String, dynamic> json) {
    return SkeletalGestureData(
      word: json['word'] as String,
      fps: (json['fps'] as num?)?.toInt() ?? 24,
      frames: (json['frames'] as List)
          .map((f) => GestureFrame.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }

  static Future<SkeletalGestureData> loadFromAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return SkeletalGestureData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// Animates a recorded hand + pose landmark sequence as a simple 2D
/// vector character. Pass [style] to customize colors and proportions
/// -- see CharacterStyle above for every available option.
///
/// IMPORTANT: do NOT give this widget a new Key() per word. Keep the
/// same widget instance across a matched-word sequence (only change
/// assetPath) so it can smoothly blend from the end of one word into
/// the start of the next, instead of snapping.
class SkeletalGestureViewer extends StatefulWidget {
  final String assetPath;
  final VoidCallback? onFinished;
  final CharacterStyle style;

  const SkeletalGestureViewer({
    Key? key,
    required this.assetPath,
    this.onFinished,
    this.style = CharacterStyle.warm,
  }) : super(key: key);

  @override
  State<SkeletalGestureViewer> createState() => _SkeletalGestureViewerState();
}

class _SkeletalGestureViewerState extends State<SkeletalGestureViewer> {
  static const int _transitionFrameCount = 8;

  List<GestureFrame> _playbackFrames = [];
  int _frameIndex = 0;
  int _fps = 24;
  Timer? _timer;
  String? _error;
  GestureFrame? _lastShownFrame;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SkeletalGestureViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _load();
    }
  }

  Future<void> _load() async {
    _timer?.cancel();
    final previousFrame = _lastShownFrame;
    setState(() => _error = null);

    try {
      final data = await SkeletalGestureData.loadFromAsset(widget.assetPath);
      if (!mounted) return;

      final newFrames = data.frames;
      List<GestureFrame> playback;

      if (previousFrame != null && newFrames.isNotEmpty) {
        final transition = _buildTransitionFrames(
          previousFrame,
          newFrames.first,
          _transitionFrameCount,
        );
        playback = [...transition, ...newFrames];
      } else {
        playback = newFrames;
      }

      setState(() {
        _playbackFrames = playback;
        _frameIndex = 0;
        _fps = data.fps;
      });
      _startAnimation();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load gesture animation: $e');
    }
  }

  List<GestureFrame> _buildTransitionFrames(
      GestureFrame from,
      GestureFrame to,
      int count,
      ) {
    return List.generate(count, (i) {
      final t = (i + 1) / (count + 1);
      return GestureFrame(
        left: _interpolatePoints(from.left, to.left, t),
        right: _interpolatePoints(from.right, to.right, t),
        pose: _interpolatePoints(from.pose, to.pose, t),
      );
    });
  }

  List<Offset>? _interpolatePoints(List<Offset>? a, List<Offset>? b, double t) {
    if (a == null || b == null || a.length != b.length) {
      return b ?? a;
    }
    return List.generate(a.length, (i) => Offset.lerp(a[i], b[i], t)!);
  }

  void _startAnimation() {
    _timer?.cancel();
    if (_playbackFrames.isEmpty) return;

    final frameDuration = Duration(milliseconds: (1000 / _fps).round());
    _timer = Timer.periodic(frameDuration, (timer) {
      if (_frameIndex >= _playbackFrames.length - 1) {
        timer.cancel();
        _lastShownFrame = _playbackFrames.last;
        widget.onFinished?.call();
        return;
      }
      if (mounted) {
        setState(() {
          _frameIndex++;
          _lastShownFrame = _playbackFrames[_frameIndex];
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_playbackFrames.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [widget.style.backgroundTop, widget.style.backgroundBottom],
        ),
      ),
      child: CustomPaint(
        painter: _CharacterPainter(
          frame: _playbackFrames[_frameIndex],
          style: widget.style,
        ),
        child: Container(),
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  final GestureFrame frame;
  final CharacterStyle style;

  _CharacterPainter({required this.frame, required this.style});

  Offset _scale(Offset p, Size size) => Offset(p.dx * size.width, p.dy * size.height);

  void _drawCapsule(
      Canvas canvas,
      Offset start,
      Offset end,
      double startRadius,
      double endRadius,
      Paint paint,
      ) {
    final direction = end - start;
    final length = direction.distance;
    if (length == 0) {
      canvas.drawCircle(start, startRadius, paint);
      return;
    }
    final unit = direction / length;
    final perp = Offset(-unit.dy, unit.dx);

    final p1 = start + perp * startRadius;
    final p2 = end + perp * endRadius;
    final p3 = end - perp * endRadius;
    final p4 = start - perp * startRadius;

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..lineTo(p4.dx, p4.dy)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawCircle(start, startRadius, paint);
    canvas.drawCircle(end, endRadius, paint);
  }

  void _drawTorso(Canvas canvas, List<Offset> pose) {
    if (pose.length <= _poseRightHip) return;
    final ls = pose[_poseLeftShoulder];
    final rs = pose[_poseRightShoulder];
    final rh = pose[_poseRightHip];
    final lh = pose[_poseLeftHip];

    final path = Path()
      ..moveTo(ls.dx, ls.dy)
      ..lineTo(rs.dx, rs.dy)
      ..lineTo(rh.dx, rh.dy)
      ..lineTo(lh.dx, lh.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = style.shirtColor..style = PaintingStyle.fill);
  }

  void _drawArms(Canvas canvas, List<Offset> pose) {
    if (pose.length <= _poseRightWrist) return;
    final shoulderWidth = (pose[_poseRightShoulder] - pose[_poseLeftShoulder]).distance;
    final upperRadius = shoulderWidth * style.upperArmThicknessRatio;
    final lowerRadius = shoulderWidth * style.forearmThicknessRatio;
    final paint = Paint()..color = style.skinColor..style = PaintingStyle.fill;

    _drawCapsule(canvas, pose[_poseLeftShoulder], pose[_poseLeftElbow], upperRadius, lowerRadius, paint);
    _drawCapsule(canvas, pose[_poseLeftElbow], pose[_poseLeftWrist], lowerRadius, lowerRadius * 0.8, paint);

    _drawCapsule(canvas, pose[_poseRightShoulder], pose[_poseRightElbow], upperRadius, lowerRadius, paint);
    _drawCapsule(canvas, pose[_poseRightElbow], pose[_poseRightWrist], lowerRadius, lowerRadius * 0.8, paint);
  }

  void _drawHead(Canvas canvas, List<Offset> pose) {
    if (pose.length <= _poseRightShoulder) return;
    final nose = pose[_poseNose];
    final shoulderWidth = (pose[_poseRightShoulder] - pose[_poseLeftShoulder]).distance;
    final headRadius = shoulderWidth * style.headSizeRatio;
    final headCenter = Offset(nose.dx, nose.dy - headRadius * 0.25);

    canvas.drawCircle(headCenter, headRadius, Paint()..color = style.skinColor..style = PaintingStyle.fill);

    final eyeOffsetX = headRadius * style.eyeSpacingRatio;
    final eyePaint = Paint()..color = style.eyeColor;
    canvas.drawCircle(headCenter + Offset(-eyeOffsetX, 0), headRadius * style.eyeSizeRatio, eyePaint);
    canvas.drawCircle(headCenter + Offset(eyeOffsetX, 0), headRadius * style.eyeSizeRatio, eyePaint);
  }

  void _drawHand(Canvas canvas, Size size, List<Offset>? points) {
    if (points == null || points.length < 21) return;

    final scaled = points.map((p) => _scale(p, size)).toList();

    _drawPalm(canvas, scaled, style.shadowOffset, isShadow: true);
    _drawFingers(canvas, scaled, style.shadowOffset, isShadow: true);

    _drawPalm(canvas, scaled, Offset.zero, isShadow: false);
    _drawFingers(canvas, scaled, Offset.zero, isShadow: false);

    final jointPaint = Paint()..color = style.skinColor.withOpacity(0.9);
    for (final i in const [0, 5, 9, 13, 17]) {
      canvas.drawCircle(scaled[i], 4, jointPaint);
    }
  }

  void _drawPalm(Canvas canvas, List<Offset> pts, Offset offset, {required bool isShadow}) {
    const palmIndices = [0, 1, 5, 9, 13, 17];
    final path = Path();
    for (int i = 0; i < palmIndices.length; i++) {
      final p = pts[palmIndices[i]] + offset;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();

    final paint = Paint()..style = PaintingStyle.fill;
    if (isShadow) {
      paint.color = style.shadowColor.withOpacity(0.18);
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, style.shadowBlur);
    } else {
      paint.color = style.skinColor.withOpacity(style.palmOpacity);
    }
    canvas.drawPath(path, paint);
  }

  void _drawFingers(Canvas canvas, List<Offset> pts, Offset offset, {required bool isShadow}) {
    const fingers = [
      [1, 2, 3, 4],
      [5, 6, 7, 8],
      [9, 10, 11, 12],
      [13, 14, 15, 16],
      [17, 18, 19, 20],
    ];

    final base = style.fingerBaseWidth;
    final tip = style.fingerTipWidth;
    final step = (base - tip) / 3;
    final widths = [base, base - step, base - step * 2, tip];

    for (final finger in fingers) {
      for (int i = 0; i < finger.length - 1; i++) {
        final a = pts[finger[i]] + offset;
        final b = pts[finger[i + 1]] + offset;

        final paint = Paint()
          ..strokeWidth = widths[i]
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;

        if (isShadow) {
          paint.color = style.shadowColor.withOpacity(0.16);
          paint.maskFilter = MaskFilter.blur(BlurStyle.normal, style.shadowBlur);
        } else {
          paint.color = style.skinColor.withOpacity(style.palmOpacity + 0.03);
        }

        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final posePoints = frame.pose;
    if (posePoints != null && posePoints.length > _poseRightHip) {
      final pose = posePoints.map((p) => _scale(p, size)).toList();
      _drawTorso(canvas, pose);
      _drawArms(canvas, pose);
      _drawHead(canvas, pose);
    }

    _drawHand(canvas, size, frame.left);
    _drawHand(canvas, size, frame.right);
  }

  @override
  bool shouldRepaint(covariant _CharacterPainter oldDelegate) => true;
}