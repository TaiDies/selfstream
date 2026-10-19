import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/store_build.dart';
import '../platform/platform.dart';
import '../state/global_hotkeys.dart';
import '../state/hotkeys.dart';
import '../state/offline.dart';
import '../state/presence.dart';
import '../state/session.dart';
import '../state/background_setup.dart';
import '../state/settings.dart';
import '../state/updater.dart';
import 'download_controls.dart';
import 'theme_editor.dart';
import 'update_dialog.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.embedded = false});

  /// True when shown as a tab (the shell already has a mini player under it).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final off = context.watch<OfflineStore>();
    final session = context.read<Session>();
    return PageFrame(
      title: 'Settings',
      miniPlayer: !embedded,
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(session.server),
          subtitle: Text('Signed in as ${session.user}'),
        ),
        const Divider(),
        const SectionHeader('Appearance'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in palettes)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  settings.themeId = p.id;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) rebuildAll(context);
                  });
                },
                child: Container(
                  width: 84,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: settings.themeId == p.id ? kAccent : Colors.transparent, width: 2),
                  ),
                  child: Column(children: [
                    Container(
                      height: 34,
                      decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.muted.withValues(alpha: 0.4))),
                      child: Center(child: Container(width: 16, height: 16, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle))),
                    ),
                    const SizedBox(height: 6),
                    Text(p.name, style: TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.open(const ThemeEditorScreen()),
              child: Container(
                width: 84,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (settings.themeId == 'custom' || settings.themeId == 'picture') ? kAccent : Colors.transparent, width: 2),
                ),
                child: Column(children: [
                  Container(
                    height: 34,
                    decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kMuted.withValues(alpha: 0.4))),
                    child: Center(child: Icon(Icons.brush_outlined, size: 18, color: kAccent)),
                  ),
                  const SizedBox(height: 6),
                  Text('Custom', style: TextStyle(fontSize: 12, color: kText, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SectionHeader('Playback'),
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('Streaming quality'),
          subtitle: Text(settings.maxBitRate == 0 ? 'Original (best)' : 'Up to ${settings.maxBitRate} kbps. Saves data on mobile.'),
          onTap: () async {
            final v = await showModalBottomSheet<int>(
              context: context,
              showDragHandle: true,
              builder: (sheet) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final q in const [(0, 'Original (best)'), (320, '320 kbps'), (192, '192 kbps'), (128, '128 kbps')])
                    ListTile(
                      title: Text(q.$2),
                      trailing: settings.maxBitRate == q.$1 ? Icon(Icons.check, color: kAccent) : null,
                      onTap: () => Navigator.of(sheet).pop(q.$1),
                    ),
                ]),
              ),
            );
            if (v != null) settings.maxBitRate = v;
          },
        ),
        if (context.has('like-download'))
        SwitchListTile(
          secondary: const Icon(Icons.cloud_download_outlined),
          title: const Text('Liking downloads to the server'),
          subtitle: const Text('Off: a like is just remembered on your server for every device. Use Download in Liked to keep songs on this phone.'),
          value: settings.likeDownloadsToServer,
          onChanged: (v) => settings.likeDownloadsToServer = v,
        ),
        if (context.has('history'))
        SwitchListTile(
          secondary: const Icon(Icons.insights),
          title: const Text('Record my listening'),
          subtitle: const Text('Feeds Activity and Discover. Stored only on your server.'),
          value: settings.trackListening,
          onChanged: (v) => settings.trackListening = v,
        ),
        const Divider(),
        if (PresenceService.supported && !kStoreBuild) ...[
          const SectionHeader('Discord'),
          SwitchListTile(
            secondary: const Icon(Icons.sports_esports_outlined),
            title: const Text('Show what I am playing'),
            subtitle: Text(context.has('presence')
                ? 'Title, artist, cover and an Open button on your Discord profile. Needs the Discord app open.'
                : 'This server has no Discord application ID set, so it is not available.'),
            value: context.has('presence') && settings.discordPresence,
            onChanged: context.has('presence') ? (v) => settings.discordPresence = v : null,
          ),
          const Divider(),
        ],
        if (isDesktop) ...[
          const SectionHeader('Keyboard shortcuts'),
          _ShortcutsList(settings: settings),
          const Divider(),
        ],
        if (Platform.isWindows) ...[
          const SectionHeader('System-wide shortcuts'),
          SwitchListTile(
            title: const Text('Work from any program'),
            subtitle: const Text('Control Selfstream and like songs while another window is in front'),
            value: settings.globalHotkeysOn,
            onChanged: (v) => settings.globalHotkeysOn = v,
          ),
          if (settings.globalHotkeysOn) _GlobalShortcutsList(settings: settings),
          const Divider(),
        ],
        if (appUpdatesSupported) ...[
          const SectionHeader('Updates'),
          SwitchListTile(
            secondary: const Icon(Icons.system_update_alt),
            title: const Text('Check for updates when the app starts'),
            subtitle: Text(kBuildNumber > 0 ? 'Build $kBuildNumber' : 'Updated by Google Play'),
            value: settings.checkUpdates,
            onChanged: (v) => settings.checkUpdates = v,
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Check now'),
            onTap: () => checkForAppUpdate(context, manual: true),
          ),
          const Divider(),
        ],
        if (!isDesktop) ...[
        const SectionHeader('Storage on this device'),
        const DownloadControls(),
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('Offline songs'),
          subtitle: Text('${off.songs.length} songs · ${fmtBytes(off.bytes)}'),
          trailing: TextButton(
            onPressed: off.songs.isEmpty
                ? null
                : () async {
                    if (await confirm(context, 'Remove all offline songs?', 'They stay on your server.', ok: 'Remove')) await off.clear();
                  },
            child: const Text('Clear'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Notifications & background downloads'),
          subtitle: const Text('Show download progress and keep downloading with the screen off'),
          onTap: () => askBackgroundSetup(context),
        ),
        const Divider(),
        ],
        const SectionHeader('Account'),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () async {
            if (!await confirm(context, 'Sign out?', 'Your playlists and history stay on the server.', ok: 'Sign out')) return;
            if (!context.mounted) return;
            Navigator.of(context).popUntil((r) => r.isFirst);
            await session.signOut();
          },
        ),
        Padding(
          padding: EdgeInsets.all(20),
          child: Text('Selfstream 0.3\nYour music, playlists and listening history live on your own server.', style: TextStyle(color: kMuted, fontSize: 12)),
        ),
      ]),
    );
  }
}


/// The list of shortcuts; tap one, then press the new keys.
class _ShortcutsList extends StatelessWidget {
  const _ShortcutsList({required this.settings});
  final Settings settings;

  Future<void> _change(BuildContext context, HotkeyAction a, Map<HotkeyAction, Combo?> map) async {
    HotkeyService.capturing = true;
    Combo? picked;
    var clear = false;
    try {
      picked = await showDialog<Combo>(
        context: context,
        builder: (d) => Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent) return KeyEventResult.handled;
            final k = e.logicalKey;
            if (k == LogicalKeyboardKey.escape) {
              Navigator.of(d).pop();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
              clear = true;
              Navigator.of(d).pop();
              return KeyEventResult.handled;
            }
            if (Combo.isModifier(k)) return KeyEventResult.handled;
            final kb = HardwareKeyboard.instance;
            Navigator.of(d).pop(Combo(k, ctrl: kb.isControlPressed, shift: kb.isShiftPressed, alt: kb.isAltPressed));
            return KeyEventResult.handled;
          },
          child: AlertDialog(
            title: Text(hotkeyTitles[a]!),
            content: const Text('Press the keys you want to use.\n\nBackspace removes the shortcut. Esc cancels.'),
          ),
        ),
      );
    } finally {
      HotkeyService.capturing = false;
    }
    if (!context.mounted) return;
    if (clear) {
      settings.hotkeys = hotkeysToRaw({...map, a: null});
      return;
    }
    if (picked == null) return;
    for (final other in map.entries) {
      if (other.key != a && other.value == picked) {
        context.toast('${picked.label} is already used for "${hotkeyTitles[other.key]}"');
        return;
      }
    }
    settings.hotkeys = hotkeysToRaw({...map, a: picked});
  }

  @override
  Widget build(BuildContext context) {
    final map = hotkeysFrom(settings.hotkeys);
    return Column(children: [
      for (final a in HotkeyAction.values)
        ListTile(
          dense: true,
          title: Text(hotkeyTitles[a]!),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFaint)),
            child: Text(map[a]?.label ?? 'None', style: TextStyle(color: map[a] == null ? kMuted : kText, fontSize: 13)),
          ),
          onTap: () => _change(context, a, map),
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.restart_alt),
        title: const Text('Reset shortcuts to the defaults'),
        subtitle: Text('Media keys on your keyboard always work.', style: TextStyle(color: kMuted, fontSize: 12)),
        onTap: () => settings.hotkeys = '',
      ),
    ]);
  }
}


/// Shortcuts that work from anywhere in Windows. They need Ctrl, Alt or Shift so they cannot take over a plain key.
class _GlobalShortcutsList extends StatelessWidget {
  const _GlobalShortcutsList({required this.settings});
  final Settings settings;

  Future<void> _change(BuildContext context, GlobalAction a, Map<GlobalAction, GlobalCombo?> map) async {
    GlobalHotkeyService.capturing = true;
    HotkeyService.capturing = true;
    GlobalCombo? picked;
    var clear = false;
    try {
      picked = await showDialog<GlobalCombo>(
        context: context,
        builder: (d) => Focus(
          autofocus: true,
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent) return KeyEventResult.handled;
            final k = e.logicalKey;
            if (k == LogicalKeyboardKey.escape) {
              Navigator.of(d).pop();
              return KeyEventResult.handled;
            }
            if (k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) {
              clear = true;
              Navigator.of(d).pop();
              return KeyEventResult.handled;
            }
            if (Combo.isModifier(k)) return KeyEventResult.handled;
            Navigator.of(d).pop(GlobalCombo.fromEvent(e));
            return KeyEventResult.handled;
          },
          child: AlertDialog(
            title: Text(globalTitles[a]!),
            content: const Text('Press the keys you want to use, with Ctrl, Alt or Shift.\n\nBackspace removes the shortcut. Esc cancels.'),
          ),
        ),
      );
    } finally {
      GlobalHotkeyService.capturing = false;
      HotkeyService.capturing = false;
    }
    if (!context.mounted) return;
    if (clear) {
      settings.globalHotkeys = globalHotkeysToRaw({...map, a: null});
      return;
    }
    if (picked == null) return;
    if (!picked.hasModifier) {
      context.toast('Use Ctrl, Alt or Shift together with the key');
      return;
    }
    for (final other in map.entries) {
      if (other.key != a && other.value == picked) {
        context.toast('${picked.text} is already used for "${globalTitles[other.key]}"');
        return;
      }
    }
    settings.globalHotkeys = globalHotkeysToRaw({...map, a: picked});
  }

  @override
  Widget build(BuildContext context) {
    final map = globalHotkeysFrom(settings.globalHotkeys);
    return Column(children: [
      for (final a in GlobalAction.values)
        ListTile(
          dense: true,
          title: Text(globalTitles[a]!),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kFaint)),
            child: Text(map[a]?.text ?? 'None', style: TextStyle(color: map[a] == null ? kMuted : kText, fontSize: 13)),
          ),
          onTap: () => _change(context, a, map),
        ),
      ListTile(
        dense: true,
        leading: const Icon(Icons.restart_alt),
        title: const Text('Reset to the defaults'),
        subtitle: Text('If another program already uses a combination, pick a different one here.', style: TextStyle(color: kMuted, fontSize: 12)),
        onTap: () => settings.globalHotkeys = '',
      ),
    ]);
  }
}
