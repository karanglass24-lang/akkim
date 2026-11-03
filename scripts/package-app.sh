#!/bin/bash
# Build both executables and assemble a ready-to-run .app bundle.
#
# Usage:
#   bash scripts/package-app.sh            # release build (default)
#   bash scripts/package-app.sh debug      # debug build
#
# Output:
#   dist/Akkim.app
#
# The bundle layout:
#   Akkim.app/Contents/
#     Info.plist
#     PkgInfo
#     MacOS/Akkim
#     Resources/akkim-helper      (root helper binary, copied by install script)
#     Resources/install-helper.sh
#     Resources/LICENSE                   (MIT notice - required for distribution)
#     Resources/THIRD-PARTY-NOTICES.md    (ChargeWatching attribution)
#
# Notes:
# - Ad-hoc codesign (--sign -) is used. On macOS 13+ a LaunchDaemon installed from
#   an ad-hoc signed helper may require manual approval in System Settings.
# - For distribution, replace the ad-hoc signing with your Developer ID.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

CONFIG="${1:-release}"
APP_NAME="Akkim"
APP_DIR="dist/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RES_DIR="${CONTENTS}/Resources"

echo "==> swift build -c ${CONFIG}"
BUILD_PATH="${AKKIM_BUILD_PATH:-.build}"
swift build -c "${CONFIG}" --build-path "${BUILD_PATH}" || { echo "ERR build failed"; exit 1; }

BUILD_DIR="$(swift build -c "${CONFIG}" --build-path "${BUILD_PATH}" --show-bin-path)"
APP_BIN="${BUILD_DIR}/${APP_NAME}"
HELPER_BIN="${BUILD_DIR}/akkim-helper"

[ -f "${APP_BIN}" ] || { echo "ERR app binary not found: ${APP_BIN}"; exit 2; }
[ -f "${HELPER_BIN}" ] || { echo "ERR helper binary not found: ${HELPER_BIN}"; exit 2; }
[ -f "Resources/Info.plist" ] || { echo "ERR Resources/Info.plist missing"; exit 2; }
[ -f "scripts/install-helper.sh" ] || { echo "ERR scripts/install-helper.sh missing"; exit 2; }
[ -f "LICENSE" ] || { echo "ERR LICENSE missing (MIT notice is required for distribution)"; exit 2; }
[ -f "THIRD-PARTY-NOTICES.md" ] || { echo "ERR THIRD-PARTY-NOTICES.md missing"; exit 2; }

echo "==> assemble ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${APP_BIN}" "${MACOS_DIR}/${APP_NAME}"
cp "${HELPER_BIN}" "${RES_DIR}/akkim-helper"
cp "scripts/install-helper.sh" "${RES_DIR}/install-helper.sh"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"
cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
# MIT requires the copyright + permission notice in every distributed copy.
cp "LICENSE" "${RES_DIR}/LICENSE"
cp "THIRD-PARTY-NOTICES.md" "${RES_DIR}/THIRD-PARTY-NOTICES.md"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

chmod 755 "${MACOS_DIR}/${APP_NAME}" "${RES_DIR}/akkim-helper"
chmod 755 "${RES_DIR}/install-helper.sh"

echo "==> ad-hoc codesign (nested helper first, then the bundle)"
# Sign nested code BEFORE the bundle: re-signing a resource afterwards changes
# its hash and invalidates the bundle seal. Avoid --deep (not recommended).
codesign --force --sign - "${RES_DIR}/akkim-helper" 2>&1 | sed 's/^/    /' || { echo "ERR codesign helper failed"; exit 3; }
codesign --force --sign - "${APP_DIR}" 2>&1 | sed 's/^/    /' || { echo "ERR codesign app failed"; exit 4; }

echo "==> verify"
if ! codesign --verify --deep --strict "${APP_DIR}" 2>&1 | sed 's/^/    /'; then
  echo "ERR signature verification failed"
  exit 5
fi

cat <<DONE

  Built: $(pwd)/${APP_DIR}
  Run:   open "$(pwd)/${APP_DIR}"
  Install helper (first enable triggers admin prompt from the app):
         bash scripts/install-helper.sh install "$(pwd)/${RES_DIR}/akkim-helper"
DONE

exit 0
