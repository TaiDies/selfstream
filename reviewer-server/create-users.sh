#!/usr/bin/env bash
# Creates the first (admin) account and a normal "reviewer" account on a fresh Navidrome.
# Usage: create-users.sh SERVER_URL ADMIN_PASS REVIEWER_USER REVIEWER_PASS
set -euo pipefail
URL=${1%/}; ADMIN_PASS=$2; RUSER=$3; RPASS=$4
json() { python3 -c "import sys,json; print(json.load(sys.stdin).get('$1',''))"; }

# the first account on a new Navidrome becomes the admin (this call only works once)
curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" "$URL/auth/createAdmin" >/dev/null 2>&1 || true
TOKEN=$(curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}" "$URL/auth/login" | json token)
[ -n "$TOKEN" ] || { echo "Could not sign in as admin. Was this server already set up with a different admin password?"; exit 1; }

curl -fsS -X POST -H 'Content-Type: application/json' -H "x-nd-authorization: Bearer $TOKEN" \
  -d "{\"userName\":\"$RUSER\",\"name\":\"Store Reviewer\",\"email\":\"\",\"password\":\"$RPASS\",\"isAdmin\":false}" "$URL/api/user" >/dev/null \
  || echo "(the $RUSER account may already exist)"

# pick up the music straight away
curl -fsS "$URL/rest/startScan?u=admin&p=$ADMIN_PASS&v=1.16.1&c=demo&f=json&fullScan=true" >/dev/null || true
echo "accounts ready"
