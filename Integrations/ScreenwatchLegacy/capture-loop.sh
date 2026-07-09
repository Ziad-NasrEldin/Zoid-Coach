#!/bin/bash

set -u

BASE="$HOME/screenwatch"
INTERVAL=5
IDLE_SKIP_SECS=90
RETAIN_DAYS=30
WIDTH=1568
WEBP_QUALITY=35
JPEG_QUALITY=55

FFMPEG=""
for candidate in "$(command -v ffmpeg 2>/dev/null)" /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
  if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -hide_banner -encoders 2>/dev/null | grep -q 'libwebp\| webp'; then
    FFMPEG="$candidate"
    break
  fi
done

last_prune_day=""
mkdir -p "$BASE"
date +%s > "$BASE/run-start"

get_meta() {
  osascript <<'EOS' 2>>"$BASE/daemon.log"
tell application "System Events"
  set p to first application process whose frontmost is true
  set appName to name of p
  set winTitle to ""
  try
    set winTitle to name of front window of p
  end try
end tell
return appName & tab & winTitle
EOS
}

get_url() {
  case "$1" in
    "Google Chrome"|"Brave Browser"|"Arc"|"Microsoft Edge"|"Vivaldi")
      osascript -e "tell application \"$1\" to get URL of active tab of front window" 2>/dev/null ;;
    "Safari")
      osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null ;;
  esac
}

while true; do
  sleep "$INTERVAL"

  idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "${idle:-0}" -ge "$IDLE_SKIP_SECS" ]; then continue; fi

  day=$(date +%F)
  dir="$BASE/days/$day"
  mkdir -p "$dir"
  ts=$(date +%H-%M-%S)
  epoch=$(date +%s)

  meta=$(get_meta)
  app=$(printf '%s' "$meta" | cut -f1)
  win=$(printf '%s' "$meta" | cut -f2)
  url=$(get_url "$app")

  state="$app|$win|$url"
  saved=0
  if [ "$state" != "${last_state:-}" ] || [ $(( ${tick:-0} % 6 )) -eq 0 ]; then
    tmp="$dir/tmp-capture.png"
    if screencapture -x -m -t png "$tmp" 2>>"$BASE/daemon.log"; then
      if [ -n "$FFMPEG" ]; then
        "$FFMPEG" -y -loglevel error -i "$tmp" -vf "scale=$WIDTH:-2" -quality "$WEBP_QUALITY" "$dir/$ts.webp" 2>>"$BASE/daemon.log"
        out="$dir/$ts.webp"
      else
        sips -s format jpeg -s formatOptions "$JPEG_QUALITY" --resampleWidth "$WIDTH" "$tmp" --out "$dir/$ts.jpg" >/dev/null 2>&1
        out="$dir/$ts.jpg"
      fi
      rm -f "$tmp"
      [ -s "$out" ] && saved=1
    fi
  fi
  last_state="$state"
  tick=$(( ${tick:-0} + 1 ))

  APP="$app" WIN="$win" URL="$url" TS="$ts" EPOCH="$epoch" IMG="$saved" python3 - >> "$dir/log.jsonl" <<'EOF'
import json, os
print(json.dumps({
  "t": os.environ["TS"], "epoch": int(os.environ["EPOCH"]),
  "app": os.environ["APP"], "window": os.environ["WIN"],
  "url": os.environ["URL"], "img": os.environ["IMG"] == "1",
}))
EOF

  if [ "$day" != "$last_prune_day" ]; then
    find "$BASE/days" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETAIN_DAYS" -exec rm -rf {} + 2>/dev/null
    last_prune_day="$day"
  fi
done
