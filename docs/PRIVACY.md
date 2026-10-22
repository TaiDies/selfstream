# Selfstream privacy policy

_Last updated: 2026-10-22_

Selfstream is a music player app. It connects to a music server that **you** choose and run (or that someone you trust runs for you). The developer of the app does not operate that server and does not receive any data from the app.

## What the app does with your data

| Data | Where it goes | Why |
|---|---|---|
| Server address, user name and password | Stored on your device; the password is kept in the system's secure storage (Android Keystore, Windows Credential Manager). Normal requests carry a one-time salted hash instead of the password (the Subsonic token login). The password itself is sent to your server only when you sign in to change your username or password. They are sent only to the server you entered. If that server address starts with http:// instead of https://, what you send and receive can be read by others on the network, so use https for a server on the internet. | To sign in to your server |
| Your music library, playlists, liked songs, search terms | Requested from your server and shown in the app. Searches are sent to your server. | To browse and play your music |
| Listening history (what you played, for how long) | Sent only to your server, and only if the server offers it and the setting “Record my listening” is on. | For your own statistics and recommendations on your server |
| Saved pages, covers and songs you choose to keep offline | Stored on your device only | So the app works without a connection |
| App settings (theme, lyrics style and similar) | Stored on your device only | To remember your preferences |
| Windows version from GitHub: update check | When the app starts it asks GitHub (api.github.com) whether a newer version of Selfstream exists. GitHub receives your IP address and the usual request details, as with any web request. The Microsoft Store version does not do this; the Store updates it. | To offer app updates |
| Discord “now playing” (Windows, only if you turn it on) | The title, artist and cover of what you play are handed to the Discord app on your computer, which shows them on your Discord profile according to your Discord settings. Nothing is sent when the setting is off. | To show what you are listening to |
| OBS song overlay (Windows, only if you turn it on) | A web page served on your own computer only (the loopback address), showing the current song. Nothing leaves your computer. | To show the song on a stream |

## What the app does not do

- It has no advertising, no analytics and no crash-reporting service.
- It does not send anything to the developer. Apart from your own server, the only outside contacts are the optional ones listed above.
- It does not read your contacts, location, microphone, camera or files outside its own storage.

## Your server

What your server stores or shares with other services (for example search or lyric providers) is decided by whoever runs it. Ask them, or read their policy. If you run the server yourself, you control that data.

## Purchases

The app currently has no in-app purchases and no payments. If that ever changes, this policy will be updated before it does.

## Deleting your data

Sign out in the app's settings to remove the saved login from the device. Uninstalling the app removes everything it stored. Data on your server stays there until you delete it from the server.

## Children

The app is not directed at children. It collects no personal data from anyone.

## Changes and contact

If this policy changes, the new version is published at this address with a new date.
Questions: open an issue at https://github.com/TaiDies/selfstream/issues
