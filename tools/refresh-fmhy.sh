#!/bin/sh
# Refresh the pool of FMHY links the pet can open (see Nudge.qml).
# Downloads FMHY's single-page export, pulls every link out of it, drops
# the wiki's own links, social/chat invites and anything marked NSFW, and
# writes one URL per line. Skips the download when the file is under a day old.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
OUT="$STATE/ciangotchi-fmhy.txt"
mkdir -p "$STATE"
if [ -f "$OUT" ] && [ -z "$(find "$OUT" -mmin +1200 2>/dev/null)" ]; then exit 0; fi
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL --max-time 90 https://api.fmhy.net/single-page -o "$TMP" || exit 1
grep -viE 'nsfw|porn|hentai|adult|18\+|sexual| sex ' "$TMP" \
  | grep -oE 'https?://[^] )>"<]+' \
  | sed -E 's/[.,;:]+$//' \
  | grep -viE 'fmhy|FREEMEDIAHECKYEAH|discord\.(com|gg)|t\.me/|reddit\.com/(r|user)/' \
  | sort -u > "$TMP.out"
# Never replace a good list with an empty one.
[ -s "$TMP.out" ] && mv "$TMP.out" "$OUT" || rm -f "$TMP.out"
