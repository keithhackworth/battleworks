#!/bin/bash
set -e

cd /home/studio/battleworks

BASE=assets/ui/dogtags/steel/new_dogtag.png
SIZE=$(identify -format '%wx%h' "$BASE")
WIDTH=$(identify -format '%w' "$BASE")
INSET=$(( (WIDTH * 7 + 500) / 1000 ))
OPACITY=0.75

mkdir -p /tmp/dogtag-tests

# Generate the inset alpha mask
convert "$BASE" \
  -alpha extract \
  -threshold 98% \
  -virtual-pixel black \
  -morphology Erode "Disk:${INSET}" \
  -alpha copy \
  PNG32:/tmp/dogtag-mask.png

# Generate each dog tag
for i in {1..9}; do
  WEAR="assets/ui/textures/wear_texture_${i}.png"

  convert "$BASE" \
    \( "$WEAR" \
       -resize "${SIZE}^" \
       -gravity center -background none \
       -extent "$SIZE" +repage \
       -alpha set \
       -channel A -evaluate multiply "$OPACITY" +channel \
       /tmp/dogtag-mask.png \
       -compose DstIn -composite \
    \) \
    -gravity center \
    -compose Over -composite \
    "$BASE" -alpha on \
    -compose CopyOpacity -composite \
    "/tmp/dogtag-tests/tag_${i}.png"

  echo "Generated tag_${i}.png"
done

# Generate contact sheet
montage /tmp/dogtag-tests/tag_{1..9}.png \
  -thumbnail 800x270 \
  -tile 2x5 \
  -geometry +10+10 \
  -background '#202020' \
  /tmp/dogtag-preview.png

echo "Done: /tmp/dogtag-preview.png"

