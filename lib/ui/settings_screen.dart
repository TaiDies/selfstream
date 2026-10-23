import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../platform/platform.dart';
import '../state/global_hotkeys.dart';
import '../state/hotkeys.dart';
import '../state/obs_overlay.dart';
import '../state/offline.dart';
import '../state/presence.dart';
import '../state/session.dart';
import '../state/background_setup.dart';
import '../state/caps_holder.dart';
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
    final session = context.watch<Session>();
    return PageFrame(
      title: 'Settings',
      miniPlayer: !embedded,
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(session.server),
          subtitle: Text(session.offlineMode ? 'Offline mode (${session.user})' : 'Signed in as ${session.user}'),
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
        if (PresenceService.supported) ...[
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
        if (ObsOverlay.supported) ...[
          const SectionHeader('Stream overlay (OBS)'),
          SwitchListTile(
            secondary: const Icon(Icons.live_tv_outlined),
            title: const Text('Show my song on stream'),
            subtitle: const Text('A link for OBS that shows the song you are playing, with cover, time and progress. It only works on this computer.'),
            value: settings.obsOverlay,
            onChanged: (v) => settings.obsOverlay = v,
          ),
          if (settings.obsOverlay) const _ObsOverlayPanel(),
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
        if (session.offlineMode)
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('Sign in'),
            subtitle: const Text('You are in offline mode: only what is saved on this device is available'),
            onTap: () async {
              Navigator.of(context).popUntil((r) => r.isFirst);
              await session.signOut();
            },
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Change username or password'),
            subtitle: Text('Your Navidrome login (${session.user})'),
            onTap: () => showDialog<void>(context: context, builder: (_) => ChangeAccountDialog(session: session)),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Copy diagnostic info'),
            subtitle: const Text('For bug reports. Contains no passwords and no full server address'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _diagnostics(context, session)));
              if (context.mounted) context.toast('Copied. Paste it into your bug report');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            subtitle: const Text('You can still open your downloads and saved libraries in offline mode'),
            onTap: () async {
              if (!await confirm(context, 'Sign out?', 'Your playlists and history stay on the server. You can still use offline mode with what is saved on this device.', ok: 'Sign out')) return;
              if (!context.mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
              await session.signOut();
            },
          ),
        ],
        Padding(
          padding: EdgeInsets.all(20),
          child: Text('Selfstream 0.3\nYour music, playlists and listening history live on your own server.', style: TextStyle(color: kMuted, fontSize: 12)),
        ),
      ]),
    );
  }
}


/// The OBS link, its colour and how to add it.
class _ObsOverlayPanel extends StatelessWidget {
  const _ObsOverlayPanel();

  static const _colors = [0xFF1DB954, 0xFFE8825A, 0xFFE0568C, 0xFF4DA3FF, 0xFFA66CFF, 0xFFFFFFFF];

  @override
  Widget build(BuildContext context) {
    final obs = context.watch<ObsOverlay>();
    final settings = context.watch<Settings>();
    final link = obs.link;
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (obs.error != null)
          Text(obs.error!, style: const TextStyle(color: Colors.redAccent))
        else if (link == null)
          Text('Starting...', style: TextStyle(color: kMuted))
        else ...[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(border: Border.all(color: kMuted.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(child: SelectableText(link, style: const TextStyle(fontFamily: 'Consolas'))),
              IconButton(
                tooltip: 'Copy link',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) context.toast('Link copied');
                },
              ),
              IconButton(
                tooltip: 'Preview in your browser',
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () => Process.run('rundll32', ['url.dll,FileProtocolHandler', link]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text('In OBS: Sources, + , Browser. Paste the link, set Width 780 and Height 230 (a smaller source just shows it smaller). It shows while Selfstream is open.',
              style: TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Add &hide=paused to the link to hide it when nothing plays.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Text('Colours', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tooltip(
            message: 'Follow the cover',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => settings.obsAccent = 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const SweepGradient(colors: [Color(0xFFE0568C), Color(0xFFE8825A), Color(0xFF1DB954), Color(0xFF4DA3FF), Color(0xFFA66CFF), Color(0xFFE0568C)]),
                  shape: BoxShape.circle,
                  border: Border.all(color: settings.obsAccent == 0 ? Colors.white : Colors.transparent, width: 2.5),
                ),
              ),
            ),
          ),
          for (final c in _colors)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => settings.obsAccent = c,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: settings.obsAccent == c ? Colors.white : Colors.transparent, width: 2.5),
                ),
              ),
            ),
        ]),
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


/// Change the Navidrome username and/or password (needs the current password).
class ChangeAccountDialog extends StatefulWidget {
  const ChangeAccountDialog({super.key, required this.session});
  final Session session;

  @override
  State<ChangeAccountDialog> createState() => _ChangeAccountDialogState();
}

class _ChangeAccountDialogState extends State<ChangeAccountDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.session.user);
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _current = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    _pass2.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final newName = name.isNotEmpty && name != widget.session.user ? name : null;
    final newPass = _pass.text.isEmpty ? null : _pass.text;
    if (newName == null && newPass == null) {
      setState(() => _error = 'Change the username or enter a new password.');
      return;
    }
    if (newPass != null && newPass != _pass2.text) {
      setState(() => _error = 'The two new passwords are different.');
      return;
    }
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (_current.text != widget.session.currentPassword) {
      setState(() => _error = 'The current password is wrong.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.changeAccount(newUser: newName, newPassword: newPass);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      await widget.session.signOut();
      messenger.showSnackBar(const SnackBar(content: Text('Account updated. Sign in with your new details.'), duration: Duration(seconds: 5)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException ? e.message : '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change account'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'New password (leave empty to keep)')),
          TextField(controller: _pass2, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')),
          TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password'), onSubmitted: (_) => _save()),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}

String _diagnostics(BuildContext context, Session session) {
  final caps = context.read<CapsHolder>();
  var host = '(unknown)';
  try {
    final u = Uri.parse(session.server);
    host = '${u.scheme}://${u.host.isEmpty ? '?' : u.host}';
  } catch (_) {}
  final errors = Api.recentErrors;
  return [
    'Selfstream 0.3 (build ${kBuildNumber == 0 ? 'local' : kBuildNumber})',
    'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'Server: $host (path and port left out)',
    'Selfstream server: ${caps.value.fromServer ? 'yes, "${caps.value.name}"' : 'no (plain Subsonic/Navidrome)'}',
    'Features: ${caps.value.features.isEmpty ? '-' : (caps.value.features.toList()..sort()).join(', ')}',
    'Offline mode: ${session.offlineMode}',
    'Recent errors:',
    if (errors.isEmpty) '  none' else ...errors.map((e) => '  $e'),
  ].join('\n');
}
