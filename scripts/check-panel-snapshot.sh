#!/bin/bash
# Guards against a blank popover (the 1.8.1 regression): builds a debug bundle,
# lets it snapshot its own panel via `--screenshot`, and fails when the image
# is too small to contain any content.
#
# Usage: bash scripts/check-panel-snapshot.sh [min-bytes]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MIN_BYTES="${1:-20000}"
OUT="/private/var/tmp/akkim-panel.png"

bash scripts/package-app.sh debug >/dev/null || { echo "ERR debug package failed"; exit 1; }
rm -f "$OUT"

dist/Akkim.app/Contents/MacOS/Akkim --screenshot >/dev/null 2>&1 &
PID=$!
# The hook waits ~13 s for samples, snapshots, then quits by itself.
for _ in $(seq 1 60); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
kill "$PID" 2>/dev/null || true

[ -f "$OUT" ] || { echo "ERR no panel snapshot written"; exit 2; }
SIZE="$(stat -f %z "$OUT")"
if [ "$SIZE" -lt "$MIN_BYTES" ]; then
  echo "ERR panel snapshot is ${SIZE} bytes (< ${MIN_BYTES}): the popover is blank"
  exit 3
fi
echo "OK panel snapshot ${SIZE} bytes"
