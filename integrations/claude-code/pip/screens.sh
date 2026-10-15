#!/bin/bash
# screens.sh — screenshots of your screen during a Pip meeting, for the agent.
#
#   screens.sh start [meeting-folder]        capture the main screen every 15 s, in the background, until the meeting ends
#   screens.sh key <label> [meeting-folder]  one capture now, always kept (a shared screen, a price list, a slide)
#   screens.sh prune [meeting-folder]        keep the key captures and those where the screen changed, delete the rest,
#                                            write screens/index.md
#   screens.sh stop [meeting-folder]         stop the background capture
#
# The meeting folder defaults to ~/Documents/Pip/current. Captures go to <meeting>/screens/ and never leave your Mac.
# The app that runs this script (your terminal, or the Claude app) needs Screen Recording in System Settings; without it
# macOS gives a picture of the wallpaper only.
#
# Settings (environment): PIP_SCREENS_INTERVAL seconds between captures (15), PIP_SCREENS_WIDTH width in pixels of the
# saved images (1600), PIP_SCREENS_THRESHOLD how different two captures must be to keep both, 0–1 (0.05).

set -u

INTERVAL="${PIP_SCREENS_INTERVAL:-15}"
WIDTH="${PIP_SCREENS_WIDTH:-1600}"
THRESHOLD="${PIP_SCREENS_THRESHOLD:-0.05}"
MAX_SECONDS=$((4 * 3600))

cmd="${1:-}"
[ -n "$cmd" ] && shift

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

resolve_folder() {
  local f="${1:-$HOME/Documents/Pip/current}"
  f="${f/#\~/$HOME}"
  if [ ! -d "$f" ]; then
    echo "screens.sh: no meeting folder at $f (has the meeting started?)" >&2
    exit 1
  fi
  (cd "$f" && pwd -P)
}

capture() { # capture <file>
  screencapture -x -m -t jpg "$1" 2>/dev/null || return 1
  sips --resampleWidth "$WIDTH" "$1" >/dev/null 2>&1 || true
}

meeting_ended() { # meeting_ended <folder>
  local f
  for f in "$1/transcript.md" "$1/agent-feed.md"; do
    [ -f "$f" ] && grep -q -e "End of meeting" -e "Fin de la réunion" "$f" && return 0
  done
  local parent current
  parent="$(dirname "$1")"
  if [ -L "$parent/current" ]; then
    current="$(cd "$parent/current" 2>/dev/null && pwd -P)"
    [ -n "$current" ] && [ "$current" != "$1" ] && return 0
  fi
  return 1
}

capture_loop() { # capture_loop <folder>
  local folder="$1" dir="$1/screens" started
  started=$(date +%s)
  while true; do
    [ -f "$dir/.stop" ] && break
    meeting_ended "$folder" && break
    [ $(( $(date +%s) - started )) -ge "$MAX_SECONDS" ] && break
    capture "$dir/$(date +%H%M%S).jpg"
    sleep "$INTERVAL"
  done
  rm -f "$dir/.pid" "$dir/.stop"
}

stop_loop() { # stop_loop <screens-dir>
  local pid
  if [ -f "$1/.pid" ]; then
    pid="$(cat "$1/.pid")"
    touch "$1/.stop"
    kill "$pid" 2>/dev/null
    rm -f "$1/.pid" "$1/.stop"
    return 0
  fi
  return 1
}

case "$cmd" in
  start)
    folder="$(resolve_folder "${1:-}")" || exit 1
    dir="$folder/screens"
    mkdir -p "$dir"
    if [ -f "$dir/.pid" ] && kill -0 "$(cat "$dir/.pid")" 2>/dev/null; then
      echo "already capturing into $dir (pid $(cat "$dir/.pid"))"
      exit 0
    fi
    rm -f "$dir/.stop"
    capture_loop "$folder" >/dev/null 2>&1 &
    echo $! > "$dir/.pid"
    disown 2>/dev/null || true
    echo "capturing every ${INTERVAL}s into $dir (pid $(cat "$dir/.pid"))"
    ;;

  key)
    label="${1:-}"
    [ -z "$label" ] && { echo "screens.sh key <label> [meeting-folder]" >&2; exit 2; }
    folder="$(resolve_folder "${2:-}")" || exit 1
    dir="$folder/screens"
    mkdir -p "$dir"
    safe="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)"
    file="$dir/$(date +%H%M%S)-key-${safe:-key}.jpg"
    if capture "$file"; then echo "$file"; else echo "screens.sh: capture failed" >&2; exit 1; fi
    ;;

  stop)
    folder="$(resolve_folder "${1:-}")" || exit 1
    if stop_loop "$folder/screens"; then echo "stopped"; else echo "nothing was running"; fi
    ;;

  prune)
    folder="$(resolve_folder "${1:-}")" || exit 1
    dir="$folder/screens"
    [ -d "$dir" ] || { echo "no screens folder in $folder"; exit 0; }
    stop_loop "$dir" >/dev/null 2>&1 || true
    if ! command -v python3 >/dev/null 2>&1; then
      echo "screens.sh: python3 not found, keeping every capture" >&2
      THRESHOLD=-1
    fi
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    python3 -I - "$dir" "$THRESHOLD" "$tmp" <<'PY'
import os, struct, subprocess, sys

screens, threshold, tmp = sys.argv[1], float(sys.argv[2]), sys.argv[3]
files = sorted(f for f in os.listdir(screens) if f.lower().endswith(".jpg"))

def pixels(name):
    """The capture as a 48x27 BMP, read as raw bytes (no image library needed)."""
    out = os.path.join(tmp, name + ".bmp")
    subprocess.run(["sips", "-z", "27", "48", "-s", "format", "bmp", os.path.join(screens, name), "--out", out],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    with open(out, "rb") as fh:
        data = fh.read()
    offset = struct.unpack_from("<I", data, 10)[0]
    return data[offset:]

def difference(a, b):
    n = min(len(a), len(b))
    if n == 0:
        return 1.0
    return sum(abs(a[i] - b[i]) for i in range(n)) / (255.0 * n)

# A periodic capture is kept when it differs from the last kept periodic one AND from the last key one
# (so a key capture is not duplicated by the next periodic one). Key captures are always kept.
kept, dropped, last_periodic, last_key = [], [], None, None
for name in files:
    is_key = "-key-" in name
    reason = None
    try:
        px = pixels(name)
    except Exception:
        px = None
    if is_key:
        reason = "key: " + name.split("-key-", 1)[1].rsplit(".", 1)[0]
    elif last_periodic is None and last_key is None:
        reason = "first"
    elif threshold < 0:
        reason = "kept (no python3)"
    elif px is None:
        reason = "kept (could not compare)"
    else:
        refs = [r for r in (last_periodic, last_key) if r is not None]
        d = min(difference(px, r) for r in refs)
        if d >= threshold:
            reason = "screen changed (%d%%)" % round(d * 100)
    if reason:
        kept.append((name, reason))
        if px is not None:
            if is_key:
                last_key = px
            else:
                last_periodic = px
    else:
        dropped.append(name)

for name in dropped:
    os.remove(os.path.join(screens, name))

def when(name):
    t = name[:6]
    return "%s:%s:%s" % (t[0:2], t[2:4], t[4:6]) if t.isdigit() else name

with open(os.path.join(screens, "index.md"), "w") as fh:
    fh.write("# Screens\n\n| Time | File | Why kept |\n|---|---|---|\n")
    for name, reason in kept:
        fh.write("| %s | %s | %s |\n" % (when(name), name, reason))

print("kept %d of %d captures (deleted %d), see %s" % (len(kept), len(files), len(dropped), os.path.join(screens, "index.md")))
PY
    ;;

  *)
    usage
    ;;
esac
