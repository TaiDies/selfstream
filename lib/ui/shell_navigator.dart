import 'package:flutter/material.dart';

/// The navigator that lives next to the side bar on wide screens (computers). Pages opened from a tab are
/// pushed onto it, so the side bar stays visible. Null on phones and while the mini player is showing.
final GlobalKey<NavigatorState> shellNavigator = GlobalKey<NavigatorState>();
