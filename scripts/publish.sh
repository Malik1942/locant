#!/bin/zsh
# v0.6 R50, v0.9 R69: publish build/release/Locant-<version>.dmg as the GitHub release for tag v<version>.
# Run scripts/release.sh first, then `git tag v0.9.0 && git push origin v0.9.0`, then this.
# Two assets: Locant.dmg, so the site's link releases/latest/download/Locant.dmg never changes, and
# Locant-<version>.dmg, which the Homebrew cask points at (a cask's url must change with the version).
# The release notes are the CHANGELOG.md section for this version when it has one.
# Usage: scripts/publish.sh            (version read from the project; tag v<version>, in full)
#        TAG=v0.9.0 scripts/publish.sh (an explicit tag)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=Malik1942/locant
VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Locant.xcodeproj/project.pbxproj | head -1)
DMG="build/release/Locant-$VERSION.dmg"
TAG="${TAG:-v$VERSION}"

[ -f "$DMG" ] || { echo "no $DMG; run scripts/release.sh first"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "tag $TAG does not exist; create and push it first"; exit 1; }
git ls-remote --exit-code --tags origin "$TAG" >/dev/null || { echo "tag $TAG is not on origin; git push origin $TAG"; exit 1; }
spctl -a -t open --context context:primary-signature "$DMG" 2>/dev/null || { echo "$DMG is not notarized and stapled"; exit 1; }

NOTES=$(awk -v v="$VERSION" '
  $0 ~ "^## " v " " || $0 == "## " v { on = 1; next }
  on && /^## / { exit }
  on { print }
' CHANGELOG.md 2>/dev/null | sed -e '/./,$!d')
[ -n "$NOTES" ] || NOTES="Locant $VERSION."
NOTES="$NOTES

Download Locant.dmg and drag Locant to Applications; over an older copy, the permissions carry over. Or \`brew install Malik1942/locant/locant\`."

STAGE=$(mktemp -d)
cp "$DMG" "$STAGE/Locant.dmg"
cp "$DMG" "$STAGE/Locant-$VERSION.dmg"
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "▸ Release $TAG exists; replacing the assets"
  gh release upload "$TAG" "$STAGE/Locant.dmg" "$STAGE/Locant-$VERSION.dmg" -R "$REPO" --clobber
else
  echo "▸ Creating release $TAG"
  gh release create "$TAG" "$STAGE/Locant.dmg" "$STAGE/Locant-$VERSION.dmg" -R "$REPO" --title "Locant $VERSION" --notes "$NOTES" --latest
fi
rm -rf "$STAGE"
echo "▸ https://github.com/$REPO/releases/latest/download/Locant.dmg"
curl -sI "https://github.com/$REPO/releases/latest/download/Locant.dmg" | head -1
echo "▸ sha256 for the cask (scripts/cask.sh fills it in):"
shasum -a 256 "$DMG"
