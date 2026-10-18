import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// Things the keyboard can do in the computer app.
enum HotkeyAction { playPause, next, previous, seekForward, seekBack, volumeUp, volumeDown, mute, shuffle, repeat, like, miniPlayer, nowPlaying, search }

const Map<HotkeyAction, String> hotkeyTitles = {
  HotkeyAction.playPause: 'Play / pause',
  HotkeyAction.next: 'Next song',
  HotkeyAction.previous: 'Previous song',
  HotkeyAction.seekForward: 'Forward 10 seconds',
  HotkeyAction.seekBack: 'Back 10 seconds',
  HotkeyAction.volumeUp: 'Volume up',
  HotkeyAction.volumeDown: 'Volume down',
  HotkeyAction.mute: 'Mute / unmute',
  HotkeyAction.shuffle: 'Shuffle on / off',
  HotkeyAction.repeat: 'Repeat mode',
  HotkeyAction.like: 'Like the song',
  HotkeyAction.miniPlayer: 'Mini player on / off',
  HotkeyAction.nowPlaying: 'Big player open / close',
  HotkeyAction.search: 'Go to search',
};

/// A key plus the modifier keys held with it.
class Combo {
  const Combo(this.key, {this.ctrl = false, this.shift = false, this.alt = false});
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  @override
  bool operator ==(Object other) => other is Combo && other.key == key && other.ctrl == ctrl && other.shift == shift && other.alt == alt;

  @override
  int get hashCode => Object.hash(key.keyId, ctrl, shift, alt);

  Map<String, Object> toJson() => {'k': key.keyId, 'c': ctrl, 's': shift, 'a': alt};

  static Combo? fromJson(Object? j) {
    if (j is! Map || j['k'] is! int) return null;
    return Combo(LogicalKeyboardKey(j['k'] as int), ctrl: j['c'] == true, shift: j['s'] == true, alt: j['a'] == true);
  }

  /// Does this key press (with the modifiers held right now) match?
  bool matches(KeyEvent e) {
    final kb = HardwareKeyboard.instance;
    return e.logicalKey == key && kb.isControlPressed == ctrl && kb.isShiftPressed == shift && kb.isAltPressed == alt;
  }

  String get label {
    final k = key;
    final name = switch (k) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.arrowLeft => 'Left',
      LogicalKeyboardKey.arrowRight => 'Right',
      LogicalKeyboardKey.arrowUp => 'Up',
      LogicalKeyboardKey.arrowDown => 'Down',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.tab => 'Tab',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.delete => 'Delete',
      LogicalKeyboardKey.home => 'Home',
      LogicalKeyboardKey.end => 'End',
      LogicalKeyboardKey.pageUp => 'Page up',
      LogicalKeyboardKey.pageDown => 'Page down',
      _ => k.keyLabel.isEmpty ? (k.debugName ?? 'Key') : k.keyLabel.toUpperCase(),
    };
    return [if (ctrl) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', name].join(' + ');
  }

  static bool isModifier(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight || k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight ||
      k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight || k == LogicalKeyboardKey.metaLeft || k == LogicalKeyboardKey.metaRight;
}

const Map<HotkeyAction, Combo> defaultHotkeys = {
  HotkeyAction.playPause: Combo(LogicalKeyboardKey.space),
  HotkeyAction.next: Combo(LogicalKeyboardKey.arrowRight, ctrl: true),
  HotkeyAction.previous: Combo(LogicalKeyboardKey.arrowLeft, ctrl: true),
  HotkeyAction.seekForward: Combo(LogicalKeyboardKey.arrowRight, shift: true),
  HotkeyAction.seekBack: Combo(LogicalKeyboardKey.arrowLeft, shift: true),
  HotkeyAction.volumeUp: Combo(LogicalKeyboardKey.arrowUp, ctrl: true),
  HotkeyAction.volumeDown: Combo(LogicalKeyboardKey.arrowDown, ctrl: true),
  HotkeyAction.mute: Combo(LogicalKeyboardKey.keyM),
  HotkeyAction.shuffle: Combo(LogicalKeyboardKey.keyS),
  HotkeyAction.repeat: Combo(LogicalKeyboardKey.keyR),
  HotkeyAction.like: Combo(LogicalKeyboardKey.keyL),
  HotkeyAction.miniPlayer: Combo(LogicalKeyboardKey.keyM, ctrl: true),
  HotkeyAction.nowPlaying: Combo(LogicalKeyboardKey.keyP),
  HotkeyAction.search: Combo(LogicalKeyboardKey.keyF, ctrl: true),
};

/// The shortcuts in use: the defaults with whatever the user changed. A changed entry that is null means "none".
Map<HotkeyAction, Combo?> hotkeysFrom(String raw) {
  final out = <HotkeyAction, Combo?>{...defaultHotkeys};
  if (raw.isEmpty) return out;
  try {
    final m = jsonDecode(raw);
    if (m is Map) {
      for (final a in HotkeyAction.values) {
        if (!m.containsKey(a.name)) continue;
        out[a] = Combo.fromJson(m[a.name]);
      }
    }
  } catch (_) {}
  return out;
}

/// The settings string for [map], keeping only what differs from the defaults.
String hotkeysToRaw(Map<HotkeyAction, Combo?> map) {
  final changed = <String, Object?>{};
  for (final a in HotkeyAction.values) {
    if (map[a] != defaultHotkeys[a]) changed[a.name] = map[a]?.toJson();
  }
  return changed.isEmpty ? '' : jsonEncode(changed);
}

/// Listens to the keyboard while the app is in front and runs the matching action.
/// Letters and Space are ignored while you type in a text box.
class HotkeyService {
  HotkeyService({required this.settings, required this.run});
  final Settings settings;
  final void Function(HotkeyAction) run;

  /// True while the settings page waits for a new shortcut, so pressing it does not run it.
  static bool capturing = false;

  String _raw = '\u0000';
  Map<HotkeyAction, Combo?> _map = const {};

  void start() => HardwareKeyboard.instance.addHandler(_onKey);
  void stop() => HardwareKeyboard.instance.removeHandler(_onKey);

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (capturing || e is KeyUpEvent) return false;
    // the keyboard's own media keys always work
    final k = e.logicalKey;
    if (e is KeyDownEvent) {
      if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause) {
        run(HotkeyAction.playPause);
        return true;
      }
      if (k == LogicalKeyboardKey.mediaTrackNext) {
        run(HotkeyAction.next);
        return true;
      }
      if (k == LogicalKeyboardKey.mediaTrackPrevious) {
        run(HotkeyAction.previous);
        return true;
      }
    }
    if (_typing()) return false;
    if (settings.hotkeys != _raw) {
      _raw = settings.hotkeys;
      _map = hotkeysFrom(_raw);
    }
    for (final entry in _map.entries) {
      final c = entry.value;
      if (c == null || !c.matches(e)) continue;
      final repeatable = entry.key == HotkeyAction.seekForward || entry.key == HotkeyAction.seekBack || entry.key == HotkeyAction.volumeUp || entry.key == HotkeyAction.volumeDown;
      if (e is KeyRepeatEvent && !repeatable) return true;
      run(entry.key);
      return true;
    }
    return false;
  }
}
