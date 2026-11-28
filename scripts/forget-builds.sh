#!/bin/zsh
# Make macOS forget every Locant build except the installed one.
# Every build (Xcode, a worktree, a scratch copy, a mounted dmg) registers itself with LaunchServices
# under the same bundle ID. On Nov 23 2026 there were 98 of them: macOS treated a 0.9.0 debug build
# as "the" Locant, and Spotlight's Apps view stopped listing the installed 1.4.0.
# Nothing on disk is deleted. A build registers itself again the next time it is built or opened.
# A copy on a mounted disk image is only listed: eject the image and run this again.
# Usage: scripts/forget-builds.sh       (unregister the extra copies, then restart Spotlight)
#        scripts/forget-builds.sh -n    (only list them)
set -euo pipefail

ID=com.malikzhang.deixis   # the app's bundle ID, kept from the Deixis name
KEEP=/Applications/Locant.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

DRY=0
case "${1:-}" in
  "") ;;
  -n) DRY=1 ;;
  *) echo "usage: scripts/forget-builds.sh [-n]"; exit 2 ;;
esac

# Every bundle path LaunchServices holds under the bundle ID, one per line.
copies() {
  "$LSREGISTER" -dump | awk -v id="$ID" '
    /^-{20,}$/ { if (path != "" && ours) print path; path = ""; ours = 0; next }
    /^path: / && path == "" { path = $0; sub(/^path: +/, "", path); sub(/ \(0x[0-9a-f]+\)$/, "", path) }
    (/^identifier: / || /^codeInfoID: /) && $2 == id { ours = 1 }
    END { if (path != "" && ours) print path }
  ' | sort -u
}

# The copy macOS opens for the bundle ID.
preferred() {
  local app   # not `path`: zsh ties that name to PATH
  app=$(osascript -e "POSIX path of (path to application id \"$ID\")" 2>/dev/null) || app=""
  echo "${${app%/}:-none}"
}

extra=()
for p in "${(@f)$(copies)}"; do
  if [[ -n $p && $p != $KEEP ]]; then extra+=("$p"); fi
done

echo "▸ macOS opens: $(preferred)"
if (( ${#extra} == 0 )); then
  echo "▸ no extra copies registered"
  exit 0
fi
echo "▸ ${#extra} extra copies registered:"
printf '    %s\n' "${extra[@]}"
if (( DRY )); then
  echo "▸ -n: nothing changed"
  exit 0
fi

for p in "${extra[@]}"; do
  "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true
done

# Read the list again and trust that, not lsregister's exit codes. A copy on a mounted disk image
# cannot be unregistered (error -10814), and ejecting the image does not drop it either; once the
# image is ejected, a second run removes it.
mounted=()
stuck=()
for p in "${(@f)$(copies)}"; do
  if [[ -z $p || $p == $KEEP ]]; then continue; fi
  if [[ $p == /Volumes/* ]]; then mounted+=("$p"); else stuck+=("$p"); fi
done
forgotten=$(( ${#extra} - ${#mounted} - ${#stuck} ))

# Spotlight's Apps search kept its old list until the installed copy was registered again and
# Spotlight restarted; unregistering alone brought back only the grid.
if (( forgotten > 0 )); then
  if [[ -d $KEEP ]]; then "$LSREGISTER" -f "$KEEP"; fi
  killall Spotlight 2>/dev/null || true
  echo "▸ forgot $forgotten, registered $KEEP again, restarted Spotlight"
fi
if (( ${#mounted} > 0 )); then
  echo "▸ on a mounted disk image; eject it, then run this again:"
  printf '    %s\n' "${mounted[@]}"
fi
echo "▸ macOS opens: $(preferred)"
if (( ${#stuck} > 0 )); then
  echo "▸ could not unregister:"
  printf '    %s\n' "${stuck[@]}"
  exit 1
fi
