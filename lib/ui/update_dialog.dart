import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/android_updater.dart';
import '../state/settings.dart';
import '../state/updater.dart';
import 'widgets.dart';

/// Can this build update itself (Windows installer, Android test build from your server, or Google Play)?
bool get appUpdatesSupported => Updater.supported || AndroidUpdater.supported;

/// The right check for this platform. [manual] also reports "up to date" and ignores a skipped version.
Future<void> checkForAppUpdate(BuildContext context, {bool manual = false}) {
  if (AndroidUpdater.supported) return checkForAndroidUpdate(context, manual: manual);
  return checkForUpdate(context, manual: manual);
}

Future<void> checkForAndroidUpdate(BuildContext context, {bool manual = false}) async {
  if (AndroidUpdater.fromPlay) {
    final found = await AndroidUpdater.playUpdate();
    if (!found && manual && context.mounted) context.toast('You have the latest version');
    return;
  }
  final settings = context.read<Settings>();
  final api = context.api;
  final u = await AndroidUpdater.check(api);
  if (!context.mounted) return;
  if (u == null) {
    if (manual) context.toast('No newer build on your server');
    return;
  }
  if (!manual && settings.skippedBuild == u.build) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Update available'),
      content: Text('A new build of Selfstream is on your server (build ${u.build}, you have $kBuildNumber).\n\n'
          'Download and install it? Android will ask you to confirm the install.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, 'skip'), child: const Text('Skip this version')),
        TextButton(onPressed: () => Navigator.pop(d, 'later'), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(d, 'update'), child: const Text('Update')),
      ],
    ),
  );
  if (choice == 'skip') settings.skippedBuild = u.build;
  if (choice != 'update' || !context.mounted) return;
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Downloading update'),
      content: ValueListenableBuilder<double>(valueListenable: progress, builder: (_, v, __) => LinearProgressIndicator(value: v == 0 ? null : v)),
    ),
  );
  try {
    final file = await AndroidUpdater.download(api, u, (v) => progress.value = v);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await AndroidUpdater.install(file);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      context.toast('Update failed: $e');
    }
  }
}

/// Asks GitHub for a newer Windows build. [manual] also reports "up to date" and ignores a skipped version.
Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
  if (!Updater.supported) {
    if (manual) context.toast('Updates are only available in the installed Windows app');
    return;
  }
  final settings = context.read<Settings>();
  final u = await Updater.check();
  if (!context.mounted) return;
  if (u == null) {
    if (manual) context.toast('You have the latest version');
    return;
  }
  if (!manual && settings.skippedBuild == u.build) return;
  final choice = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Update available'),
      content: Text('A new version of Selfstream is ready (build ${u.build}, you have $kBuildNumber).\n\n'
          'Update now? The app closes, updates and opens again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, 'skip'), child: const Text('Skip this version')),
        TextButton(onPressed: () => Navigator.pop(d, 'later'), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(d, 'update'), child: const Text('Update')),
      ],
    ),
  );
  if (choice == 'skip') settings.skippedBuild = u.build;
  if (choice != 'update' || !context.mounted) return;
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Downloading update'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, __) => LinearProgressIndicator(value: v == 0 ? null : v),
      ),
    ),
  );
  try {
    final file = await Updater.download(u, (v) => progress.value = v);
    await Updater.install(file);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      context.toast('Update failed: $e');
    }
  }
}
