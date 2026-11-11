#!/bin/sh
# Save the URLs in your YouTube Watch Later playlist, for the pet to open.
# Uses yt-dlp with your Brave login (read by yt-dlp itself, nothing is copied
# anywhere). Output: one URL per line in the pet's links.d folder.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
DIR="$STATE/ciangotchi-links.d"
mkdir -p "$DIR"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
yt-dlp --cookies-from-browser brave+gnomekeyring --flat-playlist \
  --print url "https://www.youtube.com/playlist?list=WL" > "$TMP" 2>/dev/null || exit 1
grep -E '^https://www\.youtube\.com/watch\?v=' "$TMP" | sort -u > "$TMP.out"
# Never replace a good list with an empty one (expired login, network error).
[ -s "$TMP.out" ] && mv "$TMP.out" "$DIR/youtube-watch-later.txt" || rm -f "$TMP.out"
