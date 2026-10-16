# Selfstream

A music player app for your own music server. It connects to any **Subsonic / OpenSubsonic** server
(Navidrome, Gonic, Airsonic and others) and, if the server offers the optional **Selfstream extension**, it
shows the extra tabs, screens and features that the server describes.

- **Android** (APK) and **Windows** (exe) builds, one Flutter code base
- Synced lyrics, queue, sleep timer, themes, offline copies of songs on your phone
- Offline view: the last pages you opened are saved, and songs saved on the device still play
- Windows: volume slider, mini player (with lyrics), keep-on-top, optional Discord "now playing" card
- Home, Discover and Activity are **drawn from data the server sends**, so a server can add or change tabs and
  screens without a new app release

The app contains no music and no music sources. What you can play depends entirely on the server you sign in to.

## Install

Download the latest build from the **Releases** page:

| Platform | File |
|---|---|
| Android | `selfstream-<version>-<build>.apk` (allow "install unknown apps") |
| Windows | `selfstream-windows.zip` (unzip, keep the folder together, run `selfstream.exe`) |

Open the app, enter your server address (for example `http://192.168.1.50:4533`) and your login.

## Servers

| Server | What you get |
|---|---|
| Any Subsonic / OpenSubsonic server | Home (album lists), Search, Library (Liked, Albums, Artists, offline songs), player, lyrics |
| A server that also implements the Selfstream extension | Everything above plus whatever it advertises: playlists, follows, Discover, Activity, search suggestions, listening history, queue sync across devices |

How the app talks to a server, and how to build one that offers the extension, is in
**[docs/SERVER.md](docs/SERVER.md)**.

## Building from source

You need Flutter 3.35 (stable). The platform folders are not committed; they are generated:

```bash
flutter create --org dev.selfstream --project-name selfstream --platforms android .
python3 tool/patch_android.py        # adds the audio service, permissions and cleartext HTTP
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Windows: `flutter create --platforms windows .`, then `flutter build windows --release`.

### Signing the Android app

Without any setup the CI builds an APK signed with Flutter's debug key. That installs fine, but an app signed
with a different key cannot update it. For releases, create your own key **and keep it private**:

```bash
keytool -genkeypair -v -keystore release.jks -alias selfstream -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.jks     # paste into the repository secret ANDROID_KEYSTORE_BASE64
```

Add the secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS` under
Settings > Secrets and variables > Actions. The workflow signs with them when they exist. Never commit the key.

## Code layout

```
lib/core    server API client and data classes (no Flutter imports, reusable on every platform)
lib/state   session, library, player, offline store, settings, desktop window, Discord presence
lib/ui      screens and widgets, including the renderer for server-described screens (server_screen.dart)
lib/platform  small platform helpers (Discord IPC for Windows)
tool/       patch script for the generated Android project
```

## Licenses

Check the licenses of the packages in `pubspec.yaml` (notably the Windows audio libraries from `media_kit`)
before you distribute or sell builds. This repository does not yet include a license of its own.
