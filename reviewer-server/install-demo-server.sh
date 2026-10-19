#!/usr/bin/env bash
# A bare Navidrome music server with a small demo library, for app store reviewers.
# It is plain Navidrome: no selfstream server, nothing extra. Run as root on a fresh Debian/Ubuntu machine or
# Proxmox container (on Proxmox use ct/reviewer-demo.sh, which creates the container and runs this inside it).
# Optional: PORT=4533  REVIEW_USER=reviewer  REVIEW_PASS=...
#   CF_TUNNEL_TOKEN=...  expose it through your own Cloudflare Tunnel (stable https address)
#   TUNNEL=quick         expose it through a temporary trycloudflare.com address (changes when restarted)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run this as root."; exit 1; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /nonexistent)
RAW=${DEMO_RAW:-https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

rand() { head -c 64 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
PORT=${PORT:-4533}
REVIEW_USER=${REVIEW_USER:-reviewer}
REVIEW_PASS=${REVIEW_PASS:-$(rand 14)}
ADMIN_PASS=$(rand 20)

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq curl ca-certificates tar python3 >/dev/null

# the demo library and the account script: next to this file if present, otherwise downloaded
if [ -d "$HERE/demo-music" ]; then MUSIC_SRC="$HERE/demo-music"; else
  curl -fsSL "$RAW/demo-music.tar.gz" -o "$WORK/demo-music.tar.gz" && tar -xzf "$WORK/demo-music.tar.gz" -C "$WORK"; MUSIC_SRC="$WORK/demo-music"; fi
if [ -f "$HERE/create-users.sh" ]; then USERS="$HERE/create-users.sh"; else
  curl -fsSL "$RAW/create-users.sh" -o "$WORK/create-users.sh"; USERS="$WORK/create-users.sh"; fi
[ -d "$MUSIC_SRC" ] || { echo "Could not get the demo music."; exit 1; }

case "$(uname -m)" in x86_64) arch=amd64;; aarch64) arch=arm64;; armv7l) arch=armv7;; *) echo "Unsupported CPU"; exit 1;; esac
# the newest Navidrome release: from the redirect of the "latest" page, else the API, else a known good version
ver=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/navidrome/navidrome/releases/latest 2>/dev/null | sed -E 's#.*/tag/v?##' || true)
case "$ver" in [0-9]*) ;; *) ver="";; esac
if [ -z "$ver" ]; then
  json=$(curl -fsSL https://api.github.com/repos/navidrome/navidrome/releases/latest 2>/dev/null || true)
  ver=$(printf '%s' "$json" | sed -nE 's/.*"tag_name": *"v?([0-9][^"]*)".*/\1/p' | head -n1)
fi
ver=${ver:-0.55.2}
id navidrome-demo >/dev/null 2>&1 || useradd --system --home /var/lib/navidrome-demo --shell /usr/sbin/nologin navidrome-demo
mkdir -p /opt/navidrome-demo /var/lib/navidrome-demo /srv/demo-music
curl -fsSL "https://github.com/navidrome/navidrome/releases/download/v${ver}/navidrome_${ver}_linux_${arch}.tar.gz" -o "$WORK/navidrome.tar.gz"
tar -xzf "$WORK/navidrome.tar.gz" -C /opt/navidrome-demo navidrome
cp -r "$MUSIC_SRC/." /srv/demo-music/
chown -R navidrome-demo:navidrome-demo /var/lib/navidrome-demo /srv/demo-music

cat > /etc/systemd/system/navidrome-demo.service <<EOF
[Unit]
Description=Navidrome demo server
After=network.target

[Service]
User=navidrome-demo
Environment=ND_MUSICFOLDER=/srv/demo-music
Environment=ND_DATAFOLDER=/var/lib/navidrome-demo
Environment=ND_PORT=$PORT
Environment=ND_ADDRESS=0.0.0.0
Environment=ND_ENABLEUSEREDITING=false
ExecStart=/opt/navidrome-demo/navidrome
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now navidrome-demo >/dev/null

for i in $(seq 1 30); do curl -fsS "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1 && break; sleep 1; done
bash "$USERS" "http://127.0.0.1:$PORT" "$ADMIN_PASS" "$REVIEW_USER" "$REVIEW_PASS"

# optional: a public https address through Cloudflare (the reviewers are outside your network)
PUBLIC=""
if [ -n "${CF_TUNNEL_TOKEN:-}" ] || [ "${TUNNEL:-}" = quick ]; then
  case "$(uname -m)" in x86_64) cf=amd64;; aarch64) cf=arm64;; *) cf="";; esac
  if [ -n "$cf" ] && curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf" -o /usr/local/bin/cloudflared; then
    chmod +x /usr/local/bin/cloudflared
    if [ -n "${CF_TUNNEL_TOKEN:-}" ]; then
      cat > /etc/systemd/system/cloudflared-demo.service <<EOF
[Unit]
Description=Cloudflare tunnel for the demo server
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token $CF_TUNNEL_TOKEN
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
      chmod 600 /etc/systemd/system/cloudflared-demo.service
      PUBLIC="(your Cloudflare Tunnel's public hostname; point it at http://localhost:$PORT)"
    else
      cat > /etc/systemd/system/cloudflared-demo.service <<EOF
[Unit]
Description=Temporary Cloudflare tunnel for the demo server
After=network.target

[Service]
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:$PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload && systemctl enable --now cloudflared-demo >/dev/null
    if [ -z "$PUBLIC" ]; then
      for i in $(seq 1 30); do
        PUBLIC=$(journalctl -u cloudflared-demo --no-pager 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1)
        [ -n "$PUBLIC" ] && break; sleep 1
      done
      PUBLIC="${PUBLIC:-(not ready yet: run  journalctl -u cloudflared-demo | grep trycloudflare)}  [temporary: it changes if the container restarts]"
    fi
  else
    echo "Could not set up the Cloudflare tunnel (continuing without it)."
  fi
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')
cat > /root/navidrome-demo-credentials.txt <<EOF
Server (on your network): http://$IP:$PORT${PUBLIC:+
Public address:           $PUBLIC}
Reviewer account:  $REVIEW_USER / $REVIEW_PASS
Admin account:     admin / $ADMIN_PASS      (keep this private)
EOF
chmod 600 /root/navidrome-demo-credentials.txt
echo; cat /root/navidrome-demo-credentials.txt
