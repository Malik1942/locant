#!/bin/zsh
# Build, sign with Developer ID, notarize and staple the app, package a dmg, notarize and staple that.
# Usage: scripts/release.sh            (version read from the project)
#        NOTARY_PROFILE=locant-notary scripts/release.sh
# Notarization needs a keychain profile created once with:
#   xcrun notarytool store-credentials locant-notary --apple-id <you@icloud.com> --team-id MVAUZXPK9M
# (it asks for an app-specific password from appleid.apple.com; never put it in this script)
#
# specs/v0.9.md R68: the app bundle carries its own ticket, so a copy dragged out of the dmg opens
# offline. Before 0.9 only the dmg was stapled and the first launch depended on Gatekeeper's online
# lookup.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=MVAUZXPK9M
IDENTITY="Developer ID Application: YUE ZHANG ($TEAM_ID)"
PROFILE="${NOTARY_PROFILE:-locant-notary}"
OUT=build/release
DERIVED=build/DerivedData-release
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Locant.xcodeproj/project.pbxproj | head -1)
DMG="$OUT/Locant-$VERSION.dmg"
ZIP="$OUT/Locant-$VERSION.zip"

NOTARIZE=1
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || NOTARIZE=0

rm -rf "$OUT"; mkdir -p "$OUT"

echo "▸ Building Locant $VERSION (Release, hardened runtime, $IDENTITY)"
xcodebuild -scheme Locant -configuration Release -derivedDataPath "$DERIVED" build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  -quiet

APP="$DERIVED/Build/Products/Release/Locant.app"
cp -R "$APP" "$OUT/Locant.app"
APP="$OUT/Locant.app"

echo "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=|TeamIdentifier"
ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null | grep -c get-task-allow || true)
[ "$ENT" = "0" ] || { echo "get-task-allow present; notarization would reject"; exit 1; }
lipo -archs "$APP/Contents/MacOS/Locant"

if [ "$NOTARIZE" = 1 ]; then
  echo "▸ Notarizing the app (profile: $PROFILE)"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

echo "▸ Packaging $DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Locant.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Locant" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [ "$NOTARIZE" = 1 ]; then
  echo "▸ Notarizing the dmg"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "▸ Gatekeeper check"
  spctl -a -t open --context context:primary-signature -vv "$DMG"
else
  echo "▸ Skipped notarization: no keychain profile '$PROFILE'. This dmg is not for publishing."
  echo "  Create the profile once, then rerun:"
  echo "    xcrun notarytool store-credentials $PROFILE --apple-id <you@icloud.com> --team-id $TEAM_ID"
fi

echo "▸ Done: $DMG"
shasum -a 256 "$DMG"
ls -la "$OUT"
