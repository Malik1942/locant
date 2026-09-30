#!/bin/zsh
# specs/v0.9.md R69: fill the version and sha256 of packaging/homebrew/locant.rb from the dmg that
# scripts/release.sh built, then say how to put it in the tap.
# Usage: scripts/cask.sh              (version read from the project)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Locant.xcodeproj/project.pbxproj | head -1)
DMG="build/release/Locant-$VERSION.dmg"
CASK=packaging/homebrew/locant.rb

[ -f "$DMG" ] || { echo "no $DMG; run scripts/release.sh first"; exit 1; }
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

sed -i '' \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"

echo "▸ $CASK"
grep -E '^  (version|sha256) ' "$CASK"
if command -v brew >/dev/null; then
  brew style --cask "$CASK" || echo "  (brew style found something above; fix it before copying to the tap)"
fi
cat <<EOF
▸ Next, in the tap repository (Malik1942/homebrew-locant):
    cp $CASK <tap>/Casks/locant.rb
    cd <tap> && git commit -am "locant $VERSION" && git push
  Then anyone can:
    brew install Malik1942/locant/locant
EOF
