#!/usr/bin/env bash
# Selfstream reviewer test server - Proxmox VE helper script.
# Creates a small unprivileged Debian LXC with a plain Navidrome + a demo library of original synthesized tracks and
# a ready "reviewer" account, so app store reviewers can sign in and test the player. Nothing else is installed.
#
# Run on the Proxmox VE host shell (one line):
#   bash -c "$(curl -fsSL 'https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server/ct/reviewer-demo.sh?'$(date +%s))"
#
# Optional settings in front of the command, for example:
#   CF_TUNNEL_TOKEN=eyJ... bash -c "..."     public https address through your own Cloudflare Tunnel (stable)
#   TUNNEL=quick bash -c "..."               temporary public https address (trycloudflare.com, changes on restart)
#   CTID=250 CT_STORAGE=local-lvm BRIDGE=vmbr0 IP=192.168.1.60/24 GW=192.168.1.1 bash -c "..."
# Remove it later with:  pct stop <CTID> && pct destroy <CTID>

set -Eeuo pipefail

RAW="${DEMO_RAW:-https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server}"
CTID="${CTID:-}"
CT_HOSTNAME="${CT_HOSTNAME:-selfstream-reviewer}"
CORES="${CORES:-1}"
RAM="${RAM:-512}"
SWAP="${SWAP:-256}"
DISK="${DISK:-3}"
BRIDGE="${BRIDGE:-vmbr0}"
IP="${IP:-dhcp}"
GW="${GW:-}"
DEBIAN_VERSION="${DEBIAN_VERSION:-12}"
CT_STORAGE="${CT_STORAGE:-}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-}"

GN=$'\033[32m'; RD=$'\033[31m'; CL=$'\033[0m'
msg() { echo -e "${GN}==>${CL} $*"; }
die() { echo -e "${RD}ERROR:${CL} $*" >&2; exit 1; }
trap 'die "failed at line $LINENO (exit $?)"' ERR

pick_storage() {
  local list
  list=$(pvesm status -content "$1" 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}')
  if grep -qx "local-lvm" <<<"$list"; then echo "local-lvm"; else head -n1 <<<"$list"; fi
}

[[ $EUID -eq 0 ]] || die "run this as root on the Proxmox host"
command -v pct >/dev/null && command -v pveam >/dev/null || die "this must be run on a Proxmox VE host"

CTID="${CTID:-$(pvesh get /cluster/nextid)}"
CT_STORAGE="${CT_STORAGE:-$(pick_storage rootdir)}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-$(pick_storage vztmpl)}"
[[ -n "$CT_STORAGE" ]] || die "no storage that can hold containers was found (set CT_STORAGE)"
[[ -n "$TEMPLATE_STORAGE" ]] || die "no storage that can hold templates was found (set TEMPLATE_STORAGE)"
[[ "$IP" == "dhcp" || -n "$GW" ]] || die "a static IP also needs GW=<gateway>"
pct status "$CTID" &>/dev/null && die "container ID $CTID already exists"

msg "Creating CT $CTID on '$CT_STORAGE'"
pveam update >/dev/null
TEMPLATE=$(pveam available --section system | awk -v v="debian-${DEBIAN_VERSION}-standard" '$2 ~ v {print $2}' | sort -V | tail -n1)
[[ -n "$TEMPLATE" ]] || die "no debian-${DEBIAN_VERSION} template available (try DEBIAN_VERSION=13)"
pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE" || { msg "Downloading $TEMPLATE"; pveam download "$TEMPLATE_STORAGE" "$TEMPLATE" >/dev/null; }

NET0="name=eth0,bridge=${BRIDGE},ip=${IP}"
[[ -z "$GW" ]] || NET0+=",gw=${GW}"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "$CT_HOSTNAME" --cores "$CORES" --memory "$RAM" --swap "$SWAP" \
  --rootfs "${CT_STORAGE}:${DISK}" --net0 "$NET0" \
  --unprivileged 1 --features nesting=1 --onboot 1 --tags selfstream-reviewer \
  --description "Plain Navidrome with demo music for app store reviewers" >/dev/null
pct start "$CTID"

msg "Waiting for network"
for _ in $(seq 1 30); do pct exec "$CTID" -- getent hosts github.com >/dev/null 2>&1 && break; sleep 2; done
pct exec "$CTID" -- getent hosts github.com >/dev/null 2>&1 || die "the container has no network/DNS. Check BRIDGE/IP, then 'pct destroy $CTID' and retry"

msg "Installing Navidrome and the demo library (a minute or two)"
pct exec "$CTID" -- env LC_ALL=C LANG=C bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates >/dev/null"
pct exec "$CTID" -- env LC_ALL=C LANG=C DEMO_RAW="$RAW" CF_TUNNEL_TOKEN="${CF_TUNNEL_TOKEN:-}" TUNNEL="${TUNNEL:-}" \
  bash -c "curl -fsSL '${RAW}/install-demo-server.sh?$(date +%s)' -o /tmp/install-demo-server.sh && bash /tmp/install-demo-server.sh"

echo
msg "Done. Container $CTID. These are the details for the Microsoft Store notes:"
pct exec "$CTID" -- cat /root/navidrome-demo-credentials.txt
echo
echo "    Credentials are also saved inside the container: pct exec $CTID -- cat /root/navidrome-demo-credentials.txt"
echo "    Remove it later with: pct stop $CTID && pct destroy $CTID"
