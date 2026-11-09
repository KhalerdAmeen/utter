#!/usr/bin/env bash
# Packages Utter into a shareable DMG: build/Utter.dmg
# - Universal build (Apple Silicon + Intel)
# - Signed with your Developer ID, notarized by Apple and stapled, so it opens
#   with no "unidentified developer" warning.
#
# One-time setup (see README → "Signing & notarization"):
#   xcrun notarytool store-credentials "utter-notary" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
set -euo pipefail
cd "$(dirname "$0")"

PROFILE="${NOTARY_PROFILE:-utter-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
UNIVERSAL=1 bash build.sh

DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"

STAGE="build/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R build/Utter.app "$STAGE/"
ln -s /Applications "${STAGE}/Applications"

cat > "${STAGE}/Read me first.txt" <<'EOF'
UTTER - talk instead of type, in any Mac app

INSTALL
1. Drag Utter into the Applications folder (in this window).
2. Open Utter from Applications.
3. Get a free API key at console.groq.com/keys and paste it into Utter's Settings.
4. Allow the Microphone, and turn on Utter under
   System Settings > Privacy & Security > Accessibility.

USE
Hold Right Option, talk, let go - your words appear wherever you're typing.
Quick tap = hands-free, tap again to finish. Esc cancels.
Select text + hold Shift + Right Option to rewrite it by voice.

Happy dictating!
EOF

DMG="build/Utter.dmg"   # fixed name so the website link always works
rm -f "$DMG"
hdiutil create -volname "Utter" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -z "$DEV_ID" ]]; then
  echo "-> Created ${DMG} (v${VERSION}) WITHOUT notarization: no Developer ID Application certificate found."
  open -R "$DMG"
  exit 0
fi

codesign --force --timestamp --sign "$DEV_ID" "$DMG"
echo "-> DMG signed with ${DEV_ID}"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "-> Notary credentials '${PROFILE}' not set up yet, so skipping notarization."
  echo "   Run once:  xcrun notarytool store-credentials \"${PROFILE}\" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID"
  open -R "$DMG"
  exit 1
fi

echo "-> Sending to Apple for notarization (usually 2-5 minutes)..."
OUT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 || true)"
echo "$OUT"
if grep -q "status: Accepted" <<<"$OUT"; then
  xcrun stapler staple "$DMG"
  spctl -a -t open --context context:primary-signature -v "$DMG"
  echo "-> Notarized and stapled: ${DMG} (v${VERSION})."
  if [[ "${1:-}" == "--publish" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
      echo "-> GitHub CLI not installed. Run: brew install gh && gh auth login   (then re-run with --publish)"
      exit 1
    fi
    gh release create "v${VERSION}" "$DMG" --repo KhalerdAmeen/utter \
      --title "Utter ${VERSION}" --notes "Utter ${VERSION} for macOS 13+ (Apple Silicon and Intel). Signed and notarized by Apple. Happy dictating!"
    echo "-> Published v${VERSION}. The website's Download button now serves it."
  else
    echo "   Publish it: re-run with --publish, or upload it to a GitHub Release on KhalerdAmeen/utter."
    open -R "$DMG"
  fi
else
  SUB_ID="$(grep -m1 -oE 'id: [0-9a-f-]{36}' <<<"$OUT" | awk '{print $2}' || true)"
  echo "-> Notarization was NOT accepted. Apple's log:"
  if [[ -n "$SUB_ID" ]]; then xcrun notarytool log "$SUB_ID" --keychain-profile "$PROFILE" || true; fi
  exit 1
fi
