# Building a server for Selfstream

The app talks to a server in two layers. The first is mandatory, the second is optional and lets the server
add features and describe screens.

1. **Subsonic API** (any Subsonic / OpenSubsonic server): browsing, search, streaming, covers, lyrics, likes.
2. **Selfstream extension** at `/selfstream/api/v1/`: capabilities, server-described screens, playlists, follows,
   listening history and stats, queue sync, search suggestions, "now playing" cards.

If a server does not answer the extension (HTTP 404, or an answer that is not the JSON below), the app falls back to
plain Subsonic mode and hides everything that needs the extension.

---

## 1. Authentication

Both layers use the standard Subsonic token login on every request, as query parameters:

| Parameter | Value |
|---|---|
| `u` | username |
| `s` | a random salt (the app uses 10 characters) |
| `t` | `md5(password + salt)` as lowercase hex |
| `v` | `1.16.1` |
| `c` | client name (`selfstream-app`) |
| `f` | `json` |

Check the login with the usual `GET /rest/ping`. The extension re-uses the same credentials: your server should
validate them the same way (for example by asking the underlying Subsonic server).

All extension answers are JSON. Errors use a non-2xx status and `{"error": "message"}`.

---

## 2. Subsonic endpoints the app uses

Standard Subsonic JSON responses (`{"subsonic-response": {...}}`):

| Endpoint | Used for |
|---|---|
| `ping` | login check |
| `getAlbumList2` (`recent`, `newest`, `random`, `alphabeticalByName`) | Home in plain mode, Albums tab |
| `getArtists`, `getArtist`, `getAlbum` | Artists tab, artist and album pages |
| `search3` | search (songs, albums, artists) |
| `getStarred2`, `star`, `unstar` | Liked songs |
| `getRandomSongs` | "Shuffle my library" |
| `stream` (`id`, optional `maxBitRate`) | audio. Any container the player can decode |
| `getCoverArt` (`id`, `size`) | covers, for songs, albums, artists and playlists |
| `getLyricsBySongId` | lyrics (OpenSubsonic `lyricsList.structuredLyrics`, synced or not) |
| `scrobble` | counts a play of a song after 30 seconds (skipped for songs marked `cloud`) |

### Song objects

The app reads these fields of a song and sends the whole object back unchanged when it needs to refer to it
(for example when adding to a playlist):

`id`, `title`, `artist`, `artistId`, `album`, `albumId`, `duration` (seconds), `track`, `coverArt`, `genre`,
`starred` (timestamp when liked), and the extension fields below.

| Extension field | Meaning |
|---|---|
| `cloud: true` | The item is not stored in the library (the app shows a cloud icon and does not scrobble it). Albums, artists and playlists can carry it too. The app never looks at id formats; it only trusts this flag. |
| `reason` | Optional short text shown under the artist in song lists that ask for it (`showReason`) |

Ids are opaque strings. The same id is used for `stream`, `getCoverArt` and playlists.

---

## 3. The extension

Base path: `/selfstream/api/v1/`. Authentication as above unless marked "none".

### `GET ping` (no authentication needed)

```json
{"selfstream": true, "version": "0.3", "features": ["playlists", "stats"], "authenticated": true, "user": "alice"}
```

### `GET manifest`

What this server offers. The app calls it after sign-in and builds its tabs from the answer.

```json
{
  "name": "My server",
  "version": 1,
  "features": ["playlists", "follows", "discover", "stats", "history", "state", "suggest", "presence", "like-download"],
  "tabs": [
    {"id": "home",     "title": "Home",     "icon": "home",     "kind": "screen", "screen": "home"},
    {"id": "search",   "title": "Search",   "icon": "search",   "kind": "search"},
    {"id": "library",  "title": "Library",  "icon": "library",  "kind": "library"},
    {"id": "discover", "title": "Discover", "icon": "discover", "kind": "screen", "screen": "discover"}
  ],
  "strings": {"searchHint": "Text shown on the empty search page."}
}
```

* `kind`: `screen` (drawn from `GET screens/{screen}`), `search` and `library` (built into the app).
* `icon`: `home`, `search`, `library`, `discover`, `activity`, `favorite`. Anything else shows a dot.
* The app shows the tabs in the order given. Order, titles and the set of tabs are entirely up to the server.

**Features** switch parts of the app on. The app hides what a server does not list:

| Feature | Turns on | Endpoints you must provide |
|---|---|---|
| `playlists` | Playlists tab, "Add to playlist" | `playlists*` below |
| `follows` | Following tab, Follow buttons | `follows*` below (and `playlists`) |
| `history` | sends listening reports; setting "Record my listening" | `plays`, `plays/batch` |
| `stats`, `discover` | only used by your own `screens` and manifest tabs | (your screens) |
| `state` | "continue where you left off" queue across devices | `state/{key}` |
| `suggest` | search-as-you-type suggestions | `suggest` |
| `presence` | Windows: Discord "now playing" card | `presence` |
| `like-download` | a setting "Liking downloads to the server" | `star` accepts `ssDownload=0` |

### `GET screens/{id}` : server-described screens

```json
{
  "title": "Discover",
  "settings": false,
  "actions": [{"icon": "refresh", "tooltip": "New mix", "action": {"type": "reload", "params": {"refresh": "1"}}}],
  "sections": [ ... ]
}
```

* `title` may contain `{greeting}`, which the app replaces with "Good morning" and so on.
* `settings: true` adds the settings button in the header.
* The app sends `tz` (minutes from UTC) and the parameters set by `reload` actions or `chips` sections.

**Sections.** Unknown section types are ignored, so new types can be added without breaking older apps.

| `type` | Fields | Shows |
|---|---|---|
| `header` | `title`, optional `subtitle`, `big` (large heading), `action: {label, action}` | section title with an optional link |
| `pills` | `items: [{icon, label}]` | small info chips |
| `buttons` | `items: [{label, icon, action}]` | action chips |
| `link` | `icon`, `title`, `subtitle`, `action` | tappable card |
| `chips` | `param`, `selected`, `options: [{id, label}]` | a selector; choosing one reloads the screen with `param=id` |
| `hero` | `value`, `label`, `note` | one big number |
| `tiles` | `items: [{value, label}]` | grid of small numbers (3 per row) |
| `bars` | `title`, `values: [int]`, `labels: [string]` | a bar chart |
| `songs` | `songs: [song]`, `numbered`, `showReason`, `buttons` (play/shuffle row), `extra: [{label, icon, action}]` | song list |
| `songcards` | `songs: [song]` | horizontal row of song covers |
| `cards` | `items: [{kind, id, title, subtitle, cover, circle}]` | horizontal row of covers; `kind`: `album`, `artist`, `playlist`, `remotePlaylist` |
| `ranks` | `items: [{title, subtitle, fraction (0..1), cover, circle}]` | ranked list with bars |
| `note` | `text`, `icon` | centered message |
| `text` | `text`, `small` | plain paragraph |

`icon` names for sections and buttons: `shuffle`, `schedule`, `fire`, `discover`, `activity`, `headphones`,
`refresh`, `playlist_add`, `home`, `search`, `library`, `play`, `favorite`, `download`.

**Actions** (on buttons, cards, headers, links):

| `type` | Fields | Does |
|---|---|---|
| `play` | `songs`, `shuffle` | plays the songs |
| `tab` | `tab` (a tab id from the manifest) | switches tab |
| `open` | `kind`, `id`, `name` | opens an album, artist, playlist or remote playlist page |
| `reload` | `params` | loads this screen again with these extra parameters |
| `randomSongs` | | plays random songs from the library (`getRandomSongs`) |
| `savePlaylist` | `name`, `songs` | creates a playlist (needs `playlists`) |

Responses are saved on the device, so the last version of each screen shows when there is no connection.

### Playlists (`playlists`)

| Request | Body / answer |
|---|---|
| `GET playlists` | `{"playlists": [{id, name, description, kind, coverArt, songCount, duration}]}` |
| `POST playlists` | `{name, description?, songs?: [song]}` -> 201 playlist |
| `GET playlists/{id}` | playlist with `songs`; every song has a `playlistItemId` |
| `PATCH playlists/{id}` | `{name?, description?}` |
| `DELETE playlists/{id}` | |
| `POST playlists/{id}/songs` | `{songs: [song], skipExisting?: bool}` -> `{added, playlist}` |
| `DELETE playlists/{id}/songs/{playlistItemId}` | |
| `PUT playlists/{id}/order` | `{itemIds: [playlistItemId, ...]}` |

### Listening reports (`history`)

`POST plays` with `{"song": {...}, "seconds": 187.2, "duration": 215, "ts": 1760000000.0}`
(`ts` = when it started, Unix seconds). `POST plays/batch` with `{"plays": [ ... up to 500 ... ]}` is used to send
what was collected while offline. The app sends a report at 30 seconds and when the song ends. A play counts as
listened if it reached 30 seconds or half of the song.

### Follows (`follows`)

A follow turns an item the server knows about into a playlist that keeps itself up to date.

| Request | |
|---|---|
| `GET follows` | `{"follows": [{id, kind, remote_id, name, cover, artist, playlist_id, status, total, done, failed}]}` |
| `POST follows` | `{kind: "album"|"artist"|"playlist", id, name, cover?, artist?}` -> 201 follow |
| `DELETE follows/{id}?deletePlaylist=1` | |
| `POST follows/{id}/retry` | |

`status` is `queued`, `working`, `done` or `error`. The app polls `GET follows` every few seconds while any follow is
`queued` or `working`. `done` and `failed` count songs the server saved; the app shows them only if `done > 0`.

### Other endpoints

| Request | Answer |
|---|---|
| `GET state/{key}` / `PUT state/{key}` (`{"value": any}`) | small per-user storage, max 200 kB. The app stores key `queue` |
| `GET suggest?q=` | `{"suggestions": ["...", ...]}` (up to 8) |
| `GET presence?id=&title=&artist=&album=` | `{clientId, details, state, largeImage, largeText, buttons: [{label, url}]}`, the card the Windows app hands to Discord. `largeImage` must be a public URL |
| `GET remote/playlists?q=` and `GET remote/playlists/{id}` | playlists the server can browse outside your library (`cards` of kind `remotePlaylist`) |
| `GET stats?range=week|month|year|all&tz=` | optional; only used by your own `screens` |

The `star` endpoint (Subsonic) may carry `ssDownload=0` when the user turned off "Liking downloads to the server"
(only sent when the server lists `like-download`).

---

## 4. A minimal extension server

Anything that serves the Subsonic API and, next to it, the manifest and one screen is enough. This sketch (FastAPI)
sits in front of an existing Subsonic server that you proxy `/rest/*` to; it adds one extra tab:

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/selfstream/api/v1/ping")
def ping():
    return {"selfstream": True, "version": "0.1", "features": [], "authenticated": True}

@app.get("/selfstream/api/v1/manifest")
def manifest():  # validate the u/t/s login here, as in section 1
    return {"name": "Example", "version": 1, "features": [], "tabs": [
        {"id": "home", "title": "Home", "icon": "home", "kind": "screen", "screen": "home"},
        {"id": "search", "title": "Search", "icon": "search", "kind": "search"},
        {"id": "library", "title": "Library", "icon": "library", "kind": "library"}]}

@app.get("/selfstream/api/v1/screens/home")
def home():
    return {"title": "{greeting}", "settings": True, "sections": [
        {"type": "header", "title": "Hello"},
        {"type": "note", "icon": "headphones", "text": "This page comes from the server."}]}
```

Checklist for a real server:

1. Proxy (or implement) the Subsonic endpoints in section 2.
2. Validate the token login on every extension request.
3. Return a `manifest` listing only the features you really implement.
4. Build your screens from the section types above. Keep each answer small and fast; the app caches them.
5. Mark anything that is not in the library with `"cloud": true`.
6. Add `Access-Control-Allow-Origin` headers only if you also want browser clients.

Versioning: new features, tabs and section types are additions. The app ignores what it does not know.
