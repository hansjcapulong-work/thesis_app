import 'package:flutter/material.dart';

/// Shared app-wide observer that lets any screen know when the user has
/// navigated back to it (via RouteAware's didPopNext), so it can refresh
/// data that might have changed while a different screen was on top.
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();