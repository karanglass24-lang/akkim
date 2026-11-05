#!/bin/bash
# Portions of this script are derived from ChargeWatching
# (https://github.com/TY-teo/ChargeWatching), MIT License,
# Copyright (c) 2026 TY-teo. See LICENSE and THIRD-PARTY-NOTICES.md.
# Akkim root helper install/uninstall (local personal use, ad-hoc signing + manual LaunchDaemon).
# Usage:
#   bash scripts/install-helper.sh install [helper-binary-path]   # install and start (needs root)
#   bash scripts/install-helper.sh uninstall                    # stop and remove (restore charging)
# Called by the app via osascript "with administrator privileges" (one-time password prompt on first enable).

set -uo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

LABEL="com.akkim.helper"
HELPER="/Library/PrivilegedHelperTools/com.akkim.helper"
PLIST="/Library/LaunchDaemons/com.akkim.helper.plist"
# Previous project name (battery-limit). Leftover installs fight over the same SMC keys.
LEGACY_LABEL="com.batterylimit.helper"
LEGACY_HELPER="/Library/PrivilegedHelperTools/com.batterylimit.helper"
LEGACY_PLIST="/Library/LaunchDaemons/com.batterylimit.helper.plist"
DEFAULT_BIN="$(pwd)/.build/release/akkim-helper"
BIN="${2:-$DEFAULT_BIN}"
CFGDIR="/Users/Shared/Akkim"
LOG="/var/log/akkim-helper.log"

[ "$(id -u)" -eq 0 ] || { echo "ERR need root"; exit 10; }

uninstall() {
  migrate_legacy
  echo "==> bootout $LABEL"
  launchctl bootout "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
  sleep 1
  rm -f "$HELPER" "$PLIST"
  echo "==> removed (charging restored)"
}

# Removes a daemon installed under the old project name (battery-limit).
# Without this both daemons stay running and repeatedly overwrite CHTE/CHIE
# with opposite values.
migrate_legacy() {
  if [ -f "$LEGACY_PLIST" ] || [ -f "$LEGACY_HELPER" ] || launchctl print "system/${LEGACY_LABEL}" >/dev/null 2>&1; then
    echo "==> removing legacy daemon ${LEGACY_LABEL}"
    launchctl bootout "system/${LEGACY_LABEL}" 2>/dev/null || true
    sleep 1
    rm -f "$LEGACY_PLIST" "$LEGACY_HELPER"
    echo "    legacy daemon removed"
  fi
}

install() {
  [ -f "$BIN" ] || { echo "ERR helper binary not found: $BIN"; exit 11; }
  migrate_legacy
  echo "==> source helper: $BIN"
  launchctl bootout "system/${LABEL}" 2>/dev/null || true
  sleep 1

  echo "==> install to $HELPER"
  mkdir -p /Library/PrivilegedHelperTools || { echo "ERR mkdir helpertools"; exit 12; }
  cp "$BIN" "$HELPER" || { echo "ERR cp helper"; exit 13; }
  xattr -dr com.apple.quarantine "$HELPER" 2>/dev/null || true
  # Sign first: a 544 (read-only) binary can no longer be modified by codesign.
  # Keep a valid (e.g. Developer ID) signature; ad-hoc sign only unsigned copies.
  if ! codesign --verify "$HELPER" 2>/dev/null; then
    codesign --force --sign - "$HELPER" 2>&1 | sed 's/^/    codesign: /' || true
  fi
  chown root:wheel "$HELPER"; chmod 544 "$HELPER"

  echo "==> write $PLIST"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>Program</key><string>${HELPER}</string>
  <key>ProgramArguments</key><array><string>${HELPER}</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
  <key>StandardOutPath</key><string>${LOG}</string>
</dict></plist>
PLISTEOF
  chown root:wheel "$PLIST"; chmod 644 "$PLIST"

  echo "==> config dir $CFGDIR"
  mkdir -p "$CFGDIR"
  # root:admin 775/664: the daemon stays root-owned while admin users (the app)
  # can still write. Never world-writable — this file drives a root daemon.
  chown root:admin "$CFGDIR" 2>/dev/null || true
  chmod 775 "$CFGDIR"
  [ -f "$CFGDIR/smc-limit.json" ] || printf '%s' '{"schemaVersion":1,"enabled":false,"limit":80,"deadband":5,"calibrationDays":7,"sailingMode":true,"discharge":false,"heatProtectionC":0,"topUp":false}' > "$CFGDIR/smc-limit.json"
  chown root:admin "$CFGDIR/smc-limit.json" 2>/dev/null || true
  chmod 664 "$CFGDIR/smc-limit.json"

  echo "==> bootstrap"
  BOOT_OUT="$(launchctl bootstrap system "$PLIST" 2>&1)"; BOOT_RC=$?
  echo "    bootstrap rc=$BOOT_RC out=[$BOOT_OUT]"
  if [ $BOOT_RC -ne 0 ]; then
    echo "==> bootstrap failed, trying enable + kickstart"
    launchctl enable "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
    launchctl kickstart -k "system/${LABEL}" 2>&1 | sed 's/^/    /' || true
  fi
  sleep 1
  if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
    echo "==> OK daemon registered:"
    launchctl print "system/${LABEL}" 2>/dev/null | grep -E "state =|pid =" | sed 's/^/    /'
    echo "DONE-OK"
  else
    echo "ERR daemon not registered (see bootstrap output above)"; exit 14
  fi
}

case "${1:-install}" in
  install) install ;;
  uninstall) uninstall ;;
  *) echo "Usage: install|uninstall"; exit 1 ;;
esac
