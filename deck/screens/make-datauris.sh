#!/usr/bin/env bash
# Converts the real untype UI screenshots in deck/screens/ (captured from the running app with
# `screencapture -l <window-id>`) into JPEG data URIs at deck/assets/<name>.datauri.txt (token {{NAME}}).
# Screenshots must never show transcript text, keys or other personal content: blur it before
# saving the PNG here (the main-window shot has its transcript body blurred).
set -eu
cd "$(dirname "$0")"
mkdir -p ../assets
for png in *.png; do
  name="${png%.png}"
  jpg="$(mktemp -t "$name").jpeg"
  width=$(sips -g pixelWidth "$png" | awk '/pixelWidth/{print $2}')
  if [ "$width" -gt 1800 ]; then
    sips -s format jpeg -s formatOptions 86 --resampleWidth 1800 "$png" --out "$jpg" >/dev/null
  else
    sips -s format jpeg -s formatOptions 86 "$png" --out "$jpg" >/dev/null
  fi
  printf 'data:image/jpeg;base64,%s' "$(base64 -i "$jpg" | tr -d '\n')" > "../assets/$name.datauri.txt"
  rm -f "$jpg"
  echo "$name -> $(wc -c < "../assets/$name.datauri.txt") chars"
done
