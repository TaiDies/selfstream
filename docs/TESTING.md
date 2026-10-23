# Testing checklist

CI only proves the code compiles and the unit tests pass. These need a real device or server.
Tick them off before a release; "Copy diagnostic info" in Settings helps when something fails.

## Server
- [ ] Clean Proxmox install from the one-line command, then open `/selfstream` and sign in as the Navidrome admin
- [ ] `update` on an existing server keeps music, accounts and `selfstream.db`
- [ ] Docker install on x86 starts and the app can sign in
- [ ] Admin page: accounts list, rename, transfer saved data, lost-data list

## Windows
- [ ] Sign in, play, seek, shuffle, queue, lyrics
- [ ] Taskbar buttons, media keys, OBS overlay
- [ ] Offline downloads (10 at a time, one progress bar), then play with the network off
- [ ] Change username/password in Settings signs you out cleanly

## Android
- [ ] Sign in over https and over plain http (warning shown)
- [ ] Background playback, notification controls, Android Auto
- [ ] Both home-screen widgets: covers, play from playlist, shuffle, live heart
- [ ] Offline mode after signing out
- [ ] Remove a song / unlike shows the 5 s Undo bar

## Accounts
- [ ] Non-admin friend renames themselves and keeps playlists, history and follows
- [ ] Changing a password elsewhere signs the app out within a few minutes
