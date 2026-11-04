#!/bin/bash
# Portions of this file are derived from ChargeWatching
# (https://github.com/TY-teo/ChargeWatching), MIT License,
# Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.
# Build a macOS .pkg installer for Akkim.
#
# The package installs the app to /Applications and, in the postinstall script
# (which runs as root), installs the LaunchDaemon helper — so the user grants
# admin once here instead of seeing the osascript prompt on first enable.
#
# Usage: bash scripts/build-pkg.sh [output.pkg]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-dist/Akkim.pkg}"
APP="dist/Akkim.app"
[ -d "$APP" ] || { echo "ERR $APP missing — run scripts/package-app.sh first"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d /tmp/akkim-pkg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# Payload: only the app. The helper is installed from the bundle in postinstall,
# so the logic lives in one place (scripts/install-helper.sh).
mkdir -p "$STAGE/root/Applications"
cp -R "$APP" "$STAGE/root/Applications/"

mkdir -p "$STAGE/scripts"
cat > "$STAGE/scripts/postinstall" <<'EOF'
#!/bin/bash
# Runs as root after the payload is in place.
set -uo pipefail
APP="/Applications/Akkim.app"
HELPER_SRC="$APP/Contents/Resources/akkim-helper"
SCRIPT="$APP/Contents/Resources/install-helper.sh"

echo "==> clearing quarantine"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ -f "$SCRIPT" ] && [ -f "$HELPER_SRC" ]; then
  echo "==> installing LaunchDaemon helper"
  bash "$SCRIPT" install "$HELPER_SRC" || echo "WARN helper install failed (enable it from the app later)"
else
  echo "WARN helper resources missing in the bundle"
fi

exit 0
EOF
chmod 755 "$STAGE/scripts/postinstall"

echo "==> pkgbuild $VERSION"
pkgbuild --root "$STAGE/root" \
         --scripts "$STAGE/scripts" \
         --identifier com.akkim.app \
         --version "$VERSION" \
         --install-location / \
         "$OUT"

echo "==> built $OUT"
ls -l "$OUT"
