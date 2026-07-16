import 'package:flutter/foundation.dart';

/// Global switch controlling whether the floating goal bubble is visible.
/// Turned on when entering the main app (Dashboard) and turned off on
/// intro/login/register screens and on logout.
final ValueNotifier<bool> bubbleVisible = ValueNotifier<bool>(false);