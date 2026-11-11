#!/usr/bin/env bash
# Convert the text grids in tools/sprites/ into white-on-transparent PNGs
# in assets/sprites/. Grid size is read from the file (any rectangle works).
# Grid letters: X = body pixel, A = accent pixel (hair, aura), . = empty.
# A grid with accent pixels also gets assets/sprites/accent/<name>.png, a
# second layer that is tinted with the form's own colour.
# Requires ImageMagick. Dev-only: the PNGs are committed, users never run this.
set -euo pipefail
cd "$(dirname "$0")/sprites"
out="../../assets/sprites"
mkdir -p "$out/accent"

layer() {  # layer <txt> <tr-map for "XA."> <png>
  local w h pbm="${1%.txt}.pbm"   # next to the grids, gitignored
  w=$(head -1 "$1" | tr -d '\n' | wc -c)
  h=$(grep -c . "$1")
  { echo "P1"; echo "$w $h"; tr 'XA.' "$2" < "$1"; } > "$pbm"
  magick "$pbm" -transparent white -fill '#FFFFFF' -opaque black "PNG32:$3"
  rm "$pbm"
}

for txt in ./*.txt; do
  name="${txt#./}"; name="${name%.txt}"
  layer "$txt" 100 "$out/$name.png"
  if grep -q A "$txt"; then layer "$txt" 010 "$out/accent/$name.png"; fi
done
echo "generated $(ls ./*.txt | wc -l) sprites"
