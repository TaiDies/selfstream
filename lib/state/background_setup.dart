import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'android_updater.dart' show kPlayBuild;
import 'settings.dart';

/// Android: asks (once, and again from Settings) for the two things background downloads need:
/// permission to show notifications, and to be left alone by battery saving.
Future<void> askBackgroundSetup(BuildContext context) async {
  if (!Platform.isAndroid) return;
  final settings = context.read<Settings>();
  settings.askedBackground = true;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.download_for_offline_outlined),
      title: const Text('Downloads in the background'),
      content: const Text(
        'To keep saving songs while the screen is off, Selfstream needs two permissions:\n\n'
        '• Notifications, to show download progress.\n'
        '• No battery optimization, so Android does not pause downloads when the app is closed.\n\n'
        'You can change this later in Settings.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
      ],
    ),
  );
  if (go != true) return;
  try {
    await Permission.notification.request();
  } catch (_) {}
  try {
    if (kPlayBuild) {
      // Google Play does not allow the one-tap prompt, so open the system list where the app can be set to "Unrestricted".
      await const AndroidIntent(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS').launch();
    } else {
      await Permission.ignoreBatteryOptimizations.request();
    }
  } catch (_) {}
}
