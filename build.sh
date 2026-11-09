#!/usr/bin/env bash
# Builds Utter.app with the Xcode command line tools — no Xcode project needed.
#   ./build.sh               → build/Utter.app (this Mac's chip)
#   ./build.sh --install     → also copies to /Applications and launches it
#   UNIVERSAL=1 ./build.sh   → one app that runs on Apple Silicon AND Intel Macs
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Utter"
APP="build/${APP_NAME}.app"
BIN="${APP}/Contents/MacOS/${APP_NAME}"

rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

compile() {  # $1 = arch, $2 = output path
  xcrun --sdk macosx swiftc -O -swift-version 5 -parse-as-library \
    -target "${1}-apple-macos13.0" \
    Sources/*.swift -o "$2"
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  echo "-> Compiling universal (arm64 + x86_64)..."
  compile arm64 "build/${APP_NAME}-arm64"
  compile x86_64 "build/${APP_NAME}-x86_64"
  lipo -create "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64" -output "$BIN"
  rm -f "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64"
else
  ARCH="$(uname -m)"
  echo "-> Compiling for ${ARCH}..."
  compile "$ARCH" "$BIN"
fi

cp Info.plist "${APP}/Contents/Info.plist"

# App icon: drop a 1024x1024 PNG at Assets/AppIcon.png and it gets converted to .icns
if [[ -f Assets/AppIcon.png ]]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$s" "$s" Assets/AppIcon.png --out "${ICONSET}/icon_${s}x${s}.png" >/dev/null
    sips -z "$d" "$d" Assets/AppIcon.png --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "${APP}/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
  echo "-> Icon added"
else
  echo "-> No Assets/AppIcon.png yet (using the default icon)"
fi

# Menu bar icon (template image: macOS tints it for light/dark menu bars)
for f in MenuBarIcon.png "MenuBarIcon@2x.png"; do
  if [[ -f "Assets/$f" ]]; then cp "Assets/$f" "${APP}/Contents/Resources/"; fi
done

# Signing. Preference order:
#   1. SIGN_ID env var, if you set one
#   2. your "Developer ID Application" certificate (needed to notarize + share without warnings)
#   3. a self-signed "Utter Dev" certificate
#   4. ad-hoc
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
if [[ -n "${SIGN_ID:-}" ]]; then
  ID="$SIGN_ID"
elif [[ -n "$DEV_ID" ]]; then
  ID="$DEV_ID"
elif security find-certificate -c "Utter Dev" >/dev/null 2>&1; then
  ID="Utter Dev"
else
  ID="-"
fi

if [[ "$ID" == "Developer ID Application:"* ]]; then
  # Hardened Runtime + secure timestamp = what Apple's notary service requires
  codesign --force --options runtime --timestamp --entitlements Utter.entitlements --sign "$ID" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "-> Signed with ${ID}"
else
  codesign --force --options runtime --entitlements Utter.entitlements --sign "$ID" "$APP"
  echo "-> Signed with '${ID}' (not notarizable; install a Developer ID Application certificate to share)"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  touch "/Applications/${APP_NAME}.app"   # refresh Finder's icon cache
  open "/Applications/${APP_NAME}.app"
  echo "-> Installed to /Applications and launched."
else
  echo "-> Built ${APP}"
fi
