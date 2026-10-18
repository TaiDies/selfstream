import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:local_notifier/local_notifier.dart';

import 'settings.dart';

/// The few things that work from anywhere in Windows, even when Selfstream is in the background.
enum GlobalAction { playPause, next, previous, volumeUp, volumeDown, like }

const Map<GlobalAction, String> globalTitles = {
  GlobalAction.playPause: 'Play / pause',
  GlobalAction.next: 'Next song',
  GlobalAction.previous: 'Previous song',
  GlobalAction.volumeUp: 'Volume up',
  GlobalAction.volumeDown: 'Volume down',
  GlobalAction.like: 'Like the song (shows a notification)',
};

/// A key plus modifiers, kept as the physical key because that is what the system registers.
class GlobalCombo {
  const GlobalCombo(this.usb, this.label, {this.ctrl = false, this.shift = false, this.alt = false});
  final int usb; // USB HID usage of the physical key
  final String label; // what the key is called on screen
  final bool ctrl;
  final bool shift;
  final bool alt;

  bool get hasModifier => ctrl || shift || alt;

  @override
  bool operator ==(Object other) => other is GlobalCombo && other.usb == usb && other.ctrl == ctrl && other.shift == shift && other.alt == alt;

  @override
  int get hashCode => Object.hash(usb, ctrl, shift, alt);

  String get text => [if (ctrl) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', label].join(' + ');

  Map<String, Object> toJson() => {'u': usb, 'l': label, 'c': ctrl, 's': shift, 'a': alt};

  static GlobalCombo? fromJson(Object? j) {
    if (j is! Map || j['u'] is! int) return null;
    return GlobalCombo(j['u'] as int, '${j['l'] ?? '?'}', ctrl: j['c'] == true, shift: j['s'] == true, alt: j['a'] == true);
  }

  /// The combo for a key press (the modifiers held right now).
  static GlobalCombo fromEvent(KeyEvent e) {
    final kb = HardwareKeyboard.instance;
    final name = e.logicalKey.keyLabel.isNotEmpty ? e.logicalKey.keyLabel.toUpperCase() : (e.logicalKey.debugName ?? 'Key');
    return GlobalCombo(e.physicalKey.usbHidUsage, name == ' ' ? 'Space' : name, ctrl: kb.isControlPressed, shift: kb.isShiftPressed, alt: kb.isAltPressed);
  }

  HotKey toHotKey(GlobalAction a) => HotKey(
        identifier: 'selfstream-${a.name}',
        key: PhysicalKeyboardKey(usb),
        modifiers: [if (ctrl) HotKeyModifier.control, if (alt) HotKeyModifier.alt, if (shift) HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
}

const int _kSpace = 0x2c, _kRight = 0x4f, _kLeft = 0x50, _kDown = 0x51, _kUp = 0x52, _kL = 0x0f;

/// Different from the shortcuts inside the app on purpose: Ctrl + Alt, so they do not clash with other programs.
const Map<GlobalAction, GlobalCombo> defaultGlobalHotkeys = {
  GlobalAction.playPause: GlobalCombo(0x70000 | _kSpace, 'Space', ctrl: true, alt: true),
  GlobalAction.next: GlobalCombo(0x70000 | _kRight, 'Arrow Right', ctrl: true, alt: true),
  GlobalAction.previous: GlobalCombo(0x70000 | _kLeft, 'Arrow Left', ctrl: true, alt: true),
  GlobalAction.volumeUp: GlobalCombo(0x70000 | _kUp, 'Arrow Up', ctrl: true, alt: true),
  GlobalAction.volumeDown: GlobalCombo(0x70000 | _kDown, 'Arrow Down', ctrl: true, alt: true),
  GlobalAction.like: GlobalCombo(0x70000 | _kL, 'L', ctrl: true, alt: true),
};

/// The saved choices on top of the defaults. null = the user cleared that shortcut.
Map<GlobalAction, GlobalCombo?> globalHotkeysFrom(String raw) {
  final out = <GlobalAction, GlobalCombo?>{...defaultGlobalHotkeys};
  if (raw.isEmpty) return out;
  try {
    final m = jsonDecode(raw);
    if (m is Map) {
      for (final a in GlobalAction.values) {
        if (!m.containsKey(a.name)) continue;
        out[a] = m[a.name] == null ? null : (GlobalCombo.fromJson(m[a.name]) ?? defaultGlobalHotkeys[a]);
      }
    }
  } catch (_) {}
  return out;
}

String globalHotkeysToRaw(Map<GlobalAction, GlobalCombo?> map) =>
    jsonEncode({for (final e in map.entries) e.key.name: e.value?.toJson()});

/// Registers the system-wide shortcuts with Windows and keeps them in step with the settings.
class GlobalHotkeyService {
  GlobalHotkeyService({required this.settings, required this.run});
  final Settings settings;
  final void Function(GlobalAction) run;

  /// True while the user is pressing keys to pick a new shortcut: nothing should fire then.
  static bool capturing = false;

  String _applied = '';
  bool _busy = false;
  bool _again = false;

  void start() {
    settings.addListener(_sync);
    _sync();
  }

  Future<void> _sync() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final want = settings.globalHotkeysOn ? settings.globalHotkeys : 'off';
        if (want == _applied) continue;
        _applied = want;
        await hotKeyManager.unregisterAll();
        if (!settings.globalHotkeysOn) continue;
        for (final e in globalHotkeysFrom(settings.globalHotkeys).entries) {
          final c = e.value;
          if (c == null) continue;
          await hotKeyManager.register(c.toHotKey(e.key), keyDownHandler: (_) {
            if (!capturing) run(e.key);
          });
        }
      } while (_again);
    } catch (e) {
      if (kDebugMode) debugPrint('global hotkeys: $e');
      _applied = '';
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    settings.removeListener(_sync);
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
}

bool _notifierReady = false;

/// Windows needs the app registered once before it may show notifications.
Future<void> setupNotifications() async {
  try {
    await localNotifier.setup(appName: 'Selfstream', shortcutPolicy: ShortcutPolicy.requireCreate);
    _notifierReady = true;
  } catch (e) {
    if (kDebugMode) debugPrint('notifications: $e');
  }
}

/// A Windows notification (it plays the system notification sound). Never throws.
Future<void> notify(String title, String body) async {
  if (!_notifierReady) return;
  try {
    await LocalNotification(title: title, body: body).show();
  } catch (e) {
    if (kDebugMode) debugPrint('notification: $e');
  }
}
