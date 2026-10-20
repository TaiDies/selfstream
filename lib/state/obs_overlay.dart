import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import 'player.dart';
import 'settings.dart';

/// A small web page, served by the app on this computer only, that shows the song that is playing:
/// add its link to OBS as a Browser source and the song shows on your stream.
///
/// It listens on 127.0.0.1 (nothing outside this computer can open it) and never puts a login in the page or the link.
class ObsOverlay extends ChangeNotifier {
  ObsOverlay(this.api, this.settings, this.source);

  /// The overlay for the song the app is playing.
  factory ObsOverlay.forPlayer(Api api, PlayerController player, Settings settings) =>
      ObsOverlay(api, settings, PlayerOverlaySource(player));

  final Api api;
  final Settings settings;
  final OverlaySource source;

  static bool get supported => Platform.isWindows;
  static const firstPort = 8765;

  HttpServer? _server;
  int? port;
  String? error;
  bool _disposed = false;
  final Map<String, ({Uint8List bytes, String type})> _covers = {};

  /// The address to paste into OBS. The colours follow the cover unless a fixed colour is chosen.
  String? get link {
    final p = port;
    if (p == null) return null;
    final c = settings.obsAccent;
    if (c == 0) return 'http://localhost:$p/overlay';
    return 'http://localhost:$p/overlay?accent=%23${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  void start() {
    settings.addListener(_sync);
    _sync();
  }

  Future<void> _sync() async {
    if (_disposed) return;
    if (settings.obsOverlay && _server == null) {
      await _bind();
    } else if (!settings.obsOverlay && _server != null) {
      await _close();
    } else {
      notifyListeners(); // the colour changed: the link changes
    }
  }

  Future<void> _bind() async {
    for (var p = firstPort; p < firstPort + 20; p++) {
      try {
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
        if (_disposed || !settings.obsOverlay) {
          await s.close(force: true);
          return;
        }
        _server = s;
        port = p;
        error = null;
        s.listen(_handle, onError: (Object _) {});
        notifyListeners();
        return;
      } on SocketException {
        continue; // that port is taken, try the next one
      }
    }
    error = 'Could not open a port on this computer ($firstPort to ${firstPort + 19} are all in use).';
    notifyListeners();
  }

  Future<void> _close() async {
    final s = _server;
    _server = null;
    port = null;
    await s?.close(force: true);
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final host = req.headers.host ?? '';
      // only this computer's own names: a web page cannot trick the browser into reading it from elsewhere
      if (!(host == 'localhost' || host == '127.0.0.1') || req.method != 'GET') {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      req.response.headers
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      switch (req.uri.path) {
        case '/':
        case '/overlay':
          req.response.headers.contentType = ContentType.html;
          req.response.write(_page);
        case '/state':
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(source.state()));
        case '/cover':
          await _cover(req);
        default:
          req.response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    }
    try {
      await req.response.close();
    } catch (_) {}
  }

  Future<void> _cover(HttpRequest req) async {
    final id = req.uri.queryParameters['c'] ?? '';
    final cached = _covers[id];
    if (cached != null) {
      req.response.headers.set('Content-Type', cached.type);
      req.response.add(cached.bytes);
      return;
    }
    if (id.isEmpty || source.currentCover() != id) {
      req.response.statusCode = HttpStatus.notFound;
      return;
    }
    Uint8List bytes;
    var type = 'image/jpeg';
    final saved = source.savedCoverPath();
    if (saved != null && File(saved).existsSync()) {
      bytes = await File(saved).readAsBytes();
    } else {
      final r = await http.get(api.coverUri(id, size: 400)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        req.response.statusCode = HttpStatus.notFound;
        return;
      }
      bytes = r.bodyBytes;
      type = r.headers['content-type'] ?? type;
    }
    if (!type.startsWith('image/')) type = 'image/jpeg';
    _covers[id] = (bytes: bytes, type: type);
    if (_covers.length > 20) _covers.remove(_covers.keys.first);
    req.response.headers.set('Content-Type', type);
    req.response.add(bytes);
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_sync);
    _server?.close(force: true);
    _server = null;
    super.dispose();
  }
}

/// What the overlay shows. The app's player is one source; tests use another.
abstract class OverlaySource {
  /// {'song': false} or the current song (id, title, artist, album, playing, positionMs, durationMs, cover).
  Map<String, Object?> state();

  /// The cover id of the current song, and the cover file saved on this device (if any).
  String? currentCover();
  String? savedCoverPath();
}

class PlayerOverlaySource implements OverlaySource {
  PlayerOverlaySource(this.player);
  final PlayerController player;

  @override
  Map<String, Object?> state() {
    final s = player.current;
    if (s == null) return {'song': false};
    final p = player.player;
    final duration = p.duration?.inMilliseconds ?? (s.duration > 0 ? s.duration * 1000 : 0);
    return {
      'song': true,
      'id': s.id,
      'title': s.title,
      'artist': s.artist,
      'album': s.album,
      'playing': p.playing,
      'positionMs': p.position.inMilliseconds,
      'durationMs': duration,
      'cover': s.coverArt.isEmpty ? null : '/cover?c=${Uri.encodeQueryComponent(s.coverArt)}',
    };
  }

  @override
  String? currentCover() => player.current?.coverArt;

  @override
  String? savedCoverPath() {
    final s = player.current;
    return s == null ? null : player.coverPathFor(s);
  }
}

/// The overlay page. Colours follow the cover. Options in the link: ?accent=%23rrggbb (a fixed colour instead)  ?hide=paused (hide when paused or stopped)
const String _page = r'''<!doctype html><html><head><meta charset="utf-8"><title>Selfstream overlay</title>
<style>
:root{--accent:#1db954;--card:#1a1a1e;--track:#0e0e10;--dim:#3a3a40;--scale:1.5}
html,body{margin:0;width:100%;height:100%;background:transparent;overflow:hidden;font-family:"Segoe UI",system-ui,sans-serif;color:#fff}
#wrap{width:520px;transform:scale(var(--scale));transform-origin:0 0;padding:12px;box-sizing:border-box;
  opacity:0;transition:opacity .5s ease}
#wrap.on{opacity:1}
.row{display:flex;gap:16px;align-items:center}
#disc{position:relative;width:104px;height:104px;flex:none;border-radius:50%;box-shadow:0 0 0 3px var(--accent),0 6px 18px rgba(0,0,0,.45);transition:box-shadow .6s}
#cover{position:absolute;inset:0;border-radius:50%;background:#2a2a2a center/cover no-repeat;animation:spin 12s linear infinite;animation-play-state:paused}
#cover.spin{animation-play-state:running}
@keyframes spin{to{transform:rotate(360deg)}}
#disc:after{content:"";position:absolute;inset:0;border-radius:50%;pointer-events:none;
  background:conic-gradient(from 30deg,rgba(255,255,255,.16),transparent 18%,transparent 50%,rgba(255,255,255,.12) 66%,transparent 82%)}
#hub{position:absolute;left:50%;top:50%;width:22px;height:22px;margin:-11px 0 0 -11px;border-radius:50%;z-index:1;
  background-color:var(--card);box-shadow:0 0 0 3px rgba(0,0,0,.35),inset 0 0 0 3px var(--accent);transition:background-color .6s,box-shadow .6s}
.cards{flex:1;min-width:0;display:flex;flex-direction:column;gap:8px}
.card{background-color:var(--card);border-radius:12px;padding:8px 14px;box-shadow:0 4px 14px rgba(0,0,0,.35);transition:background-color .6s}
#title{font-size:21px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#artist{font-size:15px;opacity:.8;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}
.time{display:flex;align-items:center;gap:10px;font-size:14px;font-weight:600;font-variant-numeric:tabular-nums;padding:6px 14px}
#wave{flex:1;display:flex;align-items:center;gap:2px;height:22px}
#wave i{flex:1;border-radius:2px;background-color:var(--dim);min-width:2px;transition:background-color .6s}
#wave i.d{background-color:var(--accent)}
#bar{height:8px;border-radius:4px;background-color:var(--track);margin:10px 4px 0;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.35);transition:background-color .6s}
#fill{height:100%;width:0;background-color:var(--accent);border-radius:4px;transition:background-color .6s}
</style></head><body>
<div id="wrap"><div class="row"><div id="disc"><div id="cover"></div><div id="hub"></div></div><div class="cards">
 <div class="card"><div id="title"></div><div id="artist"></div></div>
 <div class="card time"><span id="pos">0:00</span><div id="wave"></div><span id="dur">0:00</span></div>
</div></div><div id="bar"><div id="fill"></div></div></div>
<script>
const q=new URLSearchParams(location.search),$=id=>document.getElementById(id);
const fixed=/^#[0-9a-fA-F]{6}$/.test(q.get('accent')||'')?q.get('accent'):null;
const root=document.documentElement.style;
function hsl(h,s,l){return `hsl(${Math.round(h)} ${Math.round(s*100)}% ${Math.round(l*100)}%)`}
function paint(h,s){ // every colour is built from one hue: solid dark panels, a bright accent
  s=Math.max(0.35,Math.min(0.85,s));
  root.setProperty('--accent',hsl(h,Math.max(0.55,s),0.58));root.setProperty('--card',hsl(h,s*0.55,0.17));
  root.setProperty('--track',hsl(h,s*0.5,0.1));root.setProperty('--dim',hsl(h,s*0.35,0.33));
}
function rgb2hs(r,g,b){r/=255;g/=255;b/=255;const mx=Math.max(r,g,b),mn=Math.min(r,g,b),d=mx-mn,l=(mx+mn)/2;
  let h=0;if(d){h=mx===r?((g-b)/d)%6:mx===g?(b-r)/d+2:(r-g)/d+4;h*=60;if(h<0)h+=360}
  return [h,d?d/(1-Math.abs(2*l-1)):0]}
function fromCover(url){
  if(fixed){const c=fixed.slice(1),[h,s]=rgb2hs(parseInt(c.slice(0,2),16),parseInt(c.slice(2,4),16),parseInt(c.slice(4,6),16));paint(h,s);return}
  if(!url){paint(145,0.6);return}
  const img=new Image();img.onload=()=>{try{
    const n=24,cv=document.createElement('canvas');cv.width=cv.height=n;const x=cv.getContext('2d');x.drawImage(img,0,0,n,n);
    const d=x.getImageData(0,0,n,n).data;let R=0,G=0,B=0,W=0;
    for(let i=0;i<d.length;i+=4){const mx=Math.max(d[i],d[i+1],d[i+2]),mn=Math.min(d[i],d[i+1],d[i+2]);
      const w=((mx-mn)/255+0.05)*(mx/255+0.1); // lively pixels count more than grey, black or white ones
      R+=d[i]*w;G+=d[i+1]*w;B+=d[i+2]*w;W+=w}
    const [h,s]=rgb2hs(R/W,G/W,B/W);paint(h,s)}catch(e){paint(145,0.6)}};
  img.onerror=()=>paint(145,0.6);img.src=url;
}
// Shown 1.5 times bigger than its design size, or smaller if the OBS source is too small: it is never cut off.
function fit(){const w=$('wrap'),k=Math.min(1.5,innerWidth/w.offsetWidth,innerHeight/w.offsetHeight);root.setProperty('--scale',k)}
addEventListener('resize',fit);
const hidePaused=q.get('hide')==='paused';
const N=36,bars=[];for(let i=0;i<N;i++){const b=document.createElement('i');$('wave').appendChild(b);bars.push(b)}
const fmt=ms=>{ms=Math.max(0,Math.floor(ms/1000));const m=Math.floor(ms/60),s=ms%60;return m+':'+String(s).padStart(2,'0')};
let st=null,at=0,shownId='';
function seed(str){let h=2166136261;for(const c of str){h^=c.charCodeAt(0);h=Math.imul(h,16777619)}return h>>>0}
function shape(id){let x=seed(id)||1;bars.forEach((b,i)=>{x^=x<<13;x>>>=0;x^=x>>>17;x^=x<<5;x>>>=0;
  const env=0.55+0.45*Math.sin(i/N*Math.PI);b.style.height=(18+((x%1000)/1000)*82*env)+'%'})}
async function poll(){
  try{const r=await fetch('/state',{cache:'no-store'});st=await r.json();at=performance.now()}catch(e){st=null}
  setTimeout(poll,1000);
}
function frame(){
  const wrap=$('wrap');
  if(st&&st.song&&!(hidePaused&&!st.playing)){
    wrap.classList.add('on');
    if(st.id!==shownId){shownId=st.id;$('title').textContent=st.title;$('artist').textContent=st.artist;
      $('cover').style.backgroundImage=st.cover?`url("${st.cover}")`:'none';fromCover(st.cover);shape(st.id)}
    $('cover').classList.toggle('spin',!!st.playing);
    const pos=st.positionMs+(st.playing?performance.now()-at:0),dur=st.durationMs,f=dur>0?Math.min(1,pos/dur):0;
    $('pos').textContent=fmt(pos);$('dur').textContent=fmt(dur);$('fill').style.width=(f*100)+'%';
    bars.forEach((b,i)=>b.classList.toggle('d',(i+0.5)/N<=f));
  }else wrap.classList.remove('on');
  requestAnimationFrame(frame);
}
fit();poll();frame();
</script></body></html>''';
