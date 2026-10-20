import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'platform/platform.dart';
import 'platform/title_bar.dart';
import 'state/desktop_window.dart';
import 'state/global_hotkeys.dart';
import 'state/audio_handler.dart';
import 'state/caps_holder.dart';
import 'state/library.dart';
import 'state/obs_overlay.dart';
import 'state/offline.dart';
import 'state/player.dart';
import 'state/session.dart';
import 'state/settings.dart';
import 'ui/login_screen.dart';
import 'ui/palette.dart';
import 'ui/shell.dart';
import 'ui/theme_editor.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    await SelfstreamAudio.init();
  } else if (isDesktop) {
    JustAudioMediaKit.ensureInitialized(windows: Platform.isWindows, linux: Platform.isLinux, macOS: Platform.isMacOS);
    await DesktopWindow.init();
    if (Platform.isWindows) await setupNotifications();
  }
  runApp(const SelfstreamApp());
}

class SelfstreamApp extends StatefulWidget {
  const SelfstreamApp({super.key});
  @override
  State<SelfstreamApp> createState() => _SelfstreamAppState();
}

class _SelfstreamAppState extends State<SelfstreamApp> {
  final Session session = Session();

  @override
  void initState() {
    super.initState();
    session.load();
  }

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<Session>.value(
      value: session,
      child: Consumer<Session>(
        builder: (context, s, _) {
          if (s.loaded) {
            final st = s.settings;
            applyPalette(st.themeId, accent: Color(st.customAccent), light: st.customLight, oled: st.customOled, picture: st.customPicture.isNotEmpty && File(st.customPicture).existsSync());
          }
          if (Platform.isWindows) {
            final pal = palette;
            WidgetsBinding.instance.addPostFrameCallback((_) => TitleBar.apply(pal.bg, pal.text, light: pal.light));
          }
          final Widget home;
          if (!s.loaded) {
            home = const Scaffold(body: Center(child: CircularProgressIndicator()));
          } else if (s.signedIn) {
            home = const Shell();
          } else {
            home = const LoginScreen();
          }
          return MaterialApp(
            title: 'Selfstream',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(),
            // providers go above the Navigator so every pushed page can use them
            builder: (context, child) {
              final svc = s.services;
              if (svc == null) return child ?? const SizedBox.shrink();
              return MultiProvider(
                key: ValueKey(svc.hashCode),
                providers: [
                  Provider<Api>.value(value: svc.api),
                  ChangeNotifierProvider<Settings>.value(value: svc.settings),
                  ChangeNotifierProvider<Library>.value(value: svc.library),
                  ChangeNotifierProvider<CapsHolder>.value(value: svc.caps),
                  ChangeNotifierProvider<OfflineStore>.value(value: svc.offline),
                  ChangeNotifierProvider<PlayerController>.value(value: svc.player),
                  if (svc.overlay != null) ChangeNotifierProvider<ObsOverlay>.value(value: svc.overlay!),
                ],
                child: ThemeBackdrop(child: child ?? const SizedBox.shrink()),
              );
            },
            home: home,
          );
        },
      ),
    );
  }
}
