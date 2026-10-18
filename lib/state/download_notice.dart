import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'offline.dart';

/// Android: shows download progress as a notification and keeps the app alive while songs are being saved.
/// Every call is wrapped so a notification problem can never break a download.
class DownloadNotice {
  DownloadNotice(this.store);
  final OfflineStore store;

  static const _progressId = 4101;
  static const _doneId = 4102;
  static const _channel = 'dev.selfstream.downloads';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _foreground = false;
  bool _finishing = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_selfstream')));
      _ready = true;
      store.addListener(_changed);
    } catch (_) {}
  }

  void dispose() => store.removeListener(_changed);

  AndroidNotificationDetails _details({required bool progress, int value = 0}) => AndroidNotificationDetails(
        _channel,
        'Downloads',
        channelDescription: 'Progress of songs being saved on this device',
        icon: 'ic_stat_selfstream',
        importance: progress ? Importance.low : Importance.defaultImportance,
        priority: progress ? Priority.low : Priority.defaultPriority,
        showProgress: progress,
        maxProgress: 1000,
        progress: value,
        ongoing: progress,
        onlyAlertOnce: true,
        autoCancel: !progress,
      );

  void _changed() {
    if (!_ready) return;
    if (store.busy) {
      unawaited(_update());
    } else if (_foreground || store.batchTotal > 0) {
      unawaited(_finish());
    }
  }

  Future<void> _update() async {
    final now = DateTime.now();
    if (_foreground && now.difference(_last).inMilliseconds < 800) return;
    _last = now;
    try {
      final total = store.batchTotal == 0 ? 1 : store.batchTotal;
      var part = 0.0;
      for (final v in store.progress.values) {
        part += v;
      }
      final fraction = ((store.batchDone + part) / total).clamp(0.0, 1.0);
      final details = _details(progress: true, value: (fraction * 1000).round());
      const title = 'Downloading songs';
      final body = '${(store.batchDone + 1).clamp(1, total)} of $total';
      if (!_foreground) {
        _foreground = true;
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        try {
          await android?.startForegroundService(
            _progressId,
            title,
            body,
            notificationDetails: details,
            foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
          );
        } catch (_) {
          await _plugin.show(_progressId, title, body, NotificationDetails(android: details));
        }
      } else {
        await _plugin.show(_progressId, title, body, NotificationDetails(android: details));
      }
    } catch (_) {}
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final total = store.batchTotal, failed = store.batchFailed;
      store.resetBatch();
      if (_foreground) {
        _foreground = false;
        try {
          await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.stopForegroundService();
        } catch (_) {}
        await _plugin.cancel(_progressId);
      }
      if (total > 0) {
        final saved = total - failed;
        final body = failed == 0
            ? '$saved ${saved == 1 ? 'song' : 'songs'} saved on this device'
            : '$saved saved, $failed could not be downloaded';
        await _plugin.show(_doneId, failed == 0 ? 'Downloads finished' : 'Downloads finished with errors', body, NotificationDetails(android: _details(progress: false)));
      }
    } catch (_) {
    } finally {
      _finishing = false;
    }
  }
}
