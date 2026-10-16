import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

/// Path to the single exported avatar model. Every ASL sign is a named
/// animation clip *inside* this one GLB, rather than a separate file
/// per word -- this keeps you to one model load for the whole session.
///
/// NOTE: this must match the path declared under `assets:` in
/// pubspec.yaml EXACTLY, including the folder name -- pubspec.yaml
/// currently declares `assets/model/Anim_Avatar.glb` (singular
/// "model"), so that's what's used here. If you ever reorganize the
/// assets folder, update both this constant and pubspec.yaml together;
/// a mismatch between the two is why the model was failing to load.
///
/// UPDATE: the avatar is now user-selectable (Settings > Avatar). Each of the
/// four avatar GLBs (see data/avatar_options.dart) has the same rig and the
/// same baked clips. This constant is only the fallback used when no
/// [AvatarGestureViewer.modelAsset] is passed.
const String kAvatarModelAsset = 'assets/model/Male1.glb';

/// Name of the clip to play when there's no sign queued up, or between
/// words. NULL FOR NOW -- the current export has no Idle clip, so we
/// can't call playAnimation for one without it failing. Set this once
/// an Idle action actually exists in the GLB; until then the widget
/// just leaves the model on whatever frame the last sign ended on.
const String? kIdleAnimationName = null;

/// Default camera framing so the viewer shows head-to-torso only, no
/// legs. Pulled from the rig's actual bind-pose bone heights in
/// Anim_Avatar.glb (root Armature scale already applied, values in
/// meters): Head ~1.50, shoulders/clavicles ~1.40, Chest ~1.17,
/// waist/SpineLow ~0.91.
///
/// [kTorsoCameraTarget] is (x, y, z) -- the point the camera looks at.
/// [kTorsoCameraOrbit] is (theta, phi, radius) matching model-viewer's
/// cameraOrbit convention: theta = horizontal angle in degrees (0 =
/// facing the model head-on), phi = vertical angle in degrees (90 =
/// eye-level, smaller = looking down from above), radius = distance
/// from the target in meters (smaller = more zoomed in).
///
/// IMPORTANT: <model-viewer>'s default field-of-view is "auto", which
/// resolves to roughly 45 degrees vertical for a portrait-oriented
/// viewport -- not 30. That's wider than it looks, so radius has to
/// come in further than you'd guess to keep the crop at head-to-torso
/// instead of head-to-waist-and-thighs. At radius 0.85 that's about a
/// 0.7m-tall visible window; centered on target y = 1.22 that runs
/// from roughly y = 0.87 (just below the collarbone) up to y = 1.57
/// (a bit of headroom above the scalp), which excludes the waist
/// entirely.
///
/// These are a starting point, not exact -- the actual vertical FOV
/// model-viewer picks for "auto" depends on the widget's aspect ratio
/// on the device, so if the crop isn't quite right once you see it
/// live:
/// - raise/lower the crop: adjust the y value in kTorsoCameraTarget
/// - zoom in/out (tighten/loosen the crop): shrink/grow the radius
///   (3rd value) in kTorsoCameraOrbit -- this is the main lever now
///   that legs are the thing being excluded, since a wider FOV needs a
///   smaller radius than you'd expect to hold the same crop
/// - tilt up/down: nudge phi (2nd value) toward 90 (more level) or
///   lower (looking down)
const List<double> kTorsoCameraTarget = [0.0, 1.22, 0.0];
const List<double> kTorsoCameraOrbit = [0.0, 85.0, 0.85];

/// Renders the rigged 3D avatar and plays a named animation clip per
/// ASL word, exported from Blender as glTF animations baked onto the
/// armature.
///
/// This intentionally mirrors the contract the old SkeletalGestureViewer
/// used, so the call site in LiveConversationScreen barely changes:
/// - [animationName] is this word's clip name inside the GLB (null for
///   words that don't have a hand-animated sign yet).
/// - [durationMs] is how long that clip runs, in milliseconds -- since
///   flutter_3d_controller has no "animation finished" callback, this is
///   what tells the widget when to call [onFinished] and advance to the
///   next word. Get this from the Action's frame range / Blender's fps
///   (e.g. (frame_end - frame_start) / fps * 1000) when you export.
/// - [sequenceKey] must change every time you move to a new word, even
///   if the new word's animationName is also null -- same as before,
///   this is how the widget detects "this is a new word" independent of
///   whether animationName actually changed.
///
/// IMPORTANT: do NOT give this widget a new Key() per word. Keep the
/// same widget instance across a matched-word sequence -- the model
/// only loads once, and switching instances would force a full GLB
/// reload between every word.
class AvatarGestureViewer extends StatefulWidget {
  final String? animationName;
  final int? durationMs;
  final Object sequenceKey;
  final VoidCallback? onFinished;

  /// GLB to render. Changing this requires a fresh viewer instance, so the
  /// parent should also give the widget `ValueKey(modelAsset)` -- that is the
  /// ONE case where re-creating the viewer is intended (not per word).
  final String modelAsset;

  /// Fallback hold time for words with no animationName yet, mirroring
  /// the old viewer's _holdDuration -- freeze on idle, wait, then signal
  /// completion so the sequence keeps moving.
  static const Duration missingSignHoldDuration = Duration(milliseconds: 900);

  /// Fallback if a word has an animationName but somehow no durationMs
  /// (e.g. data entry gap) -- long enough to read most single signs
  /// without stalling the conversation indefinitely.
  static const Duration fallbackClipDuration = Duration(milliseconds: 1500);

  const AvatarGestureViewer({
    Key? key,
    required this.animationName,
    required this.durationMs,
    this.sequenceKey = 0,
    this.onFinished,
    this.modelAsset = kAvatarModelAsset,
  }) : super(key: key);

  @override
  State<AvatarGestureViewer> createState() => _AvatarGestureViewerState();
}

class _AvatarGestureViewerState extends State<AvatarGestureViewer> {
  final Flutter3DController _controller = Flutter3DController();
  Timer? _timer;
  bool _modelLoaded = false;
  String? _error;

  Timer? _loadTimeoutTimer;

  /// Clip played by the previous word. When the next word uses the SAME
  /// clip (the double L in HELLO, "go go", etc.) the clip is already
  /// sitting on its last frame, and asking the 3D viewer to play it again
  /// may do nothing -- so repeats get an explicit stop first.
  String? _lastPlayedAnimation;

  /// Bumped on every _playForCurrentWord call so a delayed restart from a
  /// previous word can tell it has been superseded and bail out.
  int _playToken = 0;

  @override
  void initState() {
    super.initState();
    _controller.onModelLoaded.addListener(_onModelLoadedChanged);
    // If nothing fires within 15s, something's wrong (bad asset path,
    // pubspec not declaring the asset, WebView/network issue) -- surface
    // that instead of spinning forever with no signal.
    _loadTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _modelLoaded) return;
      setState(() {
        _error = 'Model did not finish loading within 15s. Check that '
            '${widget.modelAsset} is listed under pubspec.yaml assets: with '
            'matching case, and check onModelError below for details.';
      });
    });
  }

  void _onModelLoadedChanged() {
    if (!mounted) return;
    final loaded = _controller.onModelLoaded.value;
    if (loaded && !_modelLoaded) {
      _loadTimeoutTimer?.cancel();
      _applyTorsoCameraFraming();
      setState(() => _modelLoaded = true);
      _playForCurrentWord();
    }
  }

  /// Crops the view to head-and-torso only by moving the camera in on
  /// the chest instead of showing the full standing figure -- see the
  /// constants' doc comment above for what each number controls and
  /// how to tune them if the framing needs adjusting for this specific
  /// rig.
  void _applyTorsoCameraFraming() {
    try {
      _controller.setCameraTarget(
        kTorsoCameraTarget[0],
        kTorsoCameraTarget[1],
        kTorsoCameraTarget[2],
      );
      _controller.setCameraOrbit(
        kTorsoCameraOrbit[0],
        kTorsoCameraOrbit[1],
        kTorsoCameraOrbit[2],
      );
    } catch (e) {
      // Don't let a camera-framing failure block the model from showing
      // at all -- worst case it falls back to the full-body default view.
      debugPrint('AvatarGestureViewer: camera framing failed: $e');
    }
  }

  @override
  void didUpdateWidget(covariant AvatarGestureViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sequenceKey != widget.sequenceKey && _modelLoaded) {
      _playForCurrentWord();
    }
  }

  Future<void> _playForCurrentWord() async {
    _timer?.cancel();
    final token = ++_playToken;

    if (widget.animationName == null) {
      _lastPlayedAnimation = null;
      // No sign for this word yet. If we have a real Idle clip, play it
      // so the avatar doesn't sit frozen mid-gesture; if not (current
      // state -- no Idle clip exists in the GLB), just leave it on
      // whatever frame it's already on rather than erroring out.
      if (kIdleAnimationName != null) {
        try {
          _controller.playAnimation(animationName: kIdleAnimationName);
        } catch (e) {
          // Missing/renamed idle clip shouldn't break the whole sequence.
          debugPrint('AvatarGestureViewer: idle animation failed: $e');
        }
      }
      _timer = Timer(AvatarGestureViewer.missingSignHoldDuration, () {
        if (!mounted) return;
        widget.onFinished?.call();
      });
      return;
    }

    final name = widget.animationName!;

    // Same clip twice in a row (repeated letters): reset it first, give the
    // WebView a beat to apply that, then play.
    if (name == _lastPlayedAnimation) {
      try {
        _controller.stopAnimation();
      } catch (e) {
        debugPrint('AvatarGestureViewer: stopAnimation failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted || token != _playToken) return;
    }
    _lastPlayedAnimation = name;

    try {
      _controller.playAnimation(animationName: name, loopCount: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not play sign animation: $e');
      return;
    }

    final duration = widget.durationMs != null
        ? Duration(milliseconds: widget.durationMs!)
        : AvatarGestureViewer.fallbackClipDuration;

    _timer = Timer(duration, () {
      if (!mounted) return;
      widget.onFinished?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loadTimeoutTimer?.cancel();
    _controller.onModelLoaded.removeListener(_onModelLoadedChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }

    return Stack(
      children: [
        Flutter3DViewer(
          src: widget.modelAsset,
          controller: _controller,
          // This is a fixed head-and-torso sign display, not something
          // the person is meant to spin or zoom -- and if touch stayed
          // on, a pinch-out or drag would undo the torso-crop framing
          // above and pull the legs back into view. Locking it out
          // keeps the crop from _applyTorsoCameraFraming() permanent.
          enableTouch: false,
          onLoad: (modelAddress) {
            debugPrint('AvatarGestureViewer: loaded $modelAddress');
          },
          onError: (errorMessage) {
            if (!mounted) return;
            _loadTimeoutTimer?.cancel();
            setState(() => _error = 'Model failed to load: $errorMessage');
          },
        ),
        if (!_modelLoaded && _error == null) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}