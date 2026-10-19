# Reviewer test server

A plain Navidrome with a small library of **original, synthesized demo tracks** (3 albums, 9 tracks, CC0) and a
ready-made `reviewer` account, so app store reviewers can sign in to Selfstream and test the player. The app is a
client for the user's own Navidrome / Subsonic server and contains no music, which is why it needs a server to show
anything.

## One line, on the Proxmox host

    bash -c "$(curl -fsSL https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server/ct/reviewer-demo.sh)"

It creates a small container, installs Navidrome and the demo music, creates the accounts and prints the address,
user name and password. Add `TUNNEL=quick` in front for a temporary public https address, or
`CF_TUNNEL_TOKEN=...` to use your own Cloudflare Tunnel (stable address, recommended for certification):

    TUNNEL=quick bash -c "$(curl -fsSL https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server/ct/reviewer-demo.sh)"

## Other ways

- Any Debian/Ubuntu machine, as root: `curl -fsSL https://raw.githubusercontent.com/TaiDies/selfstream/main/reviewer-server/install-demo-server.sh | bash`
- Docker: `tar -xzf demo-music.tar.gz`, `docker compose up -d`, then `bash create-users.sh http://localhost:4533 ADMIN_PASSWORD reviewer REVIEWER_PASSWORD`

`CERTIFICATION-NOTES.txt` is the text for the Microsoft Store "Notes for certification" box.
`make_demo_music.py` regenerates the demo tracks (numpy, Pillow, ffmpeg).
