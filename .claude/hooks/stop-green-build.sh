#!/bin/bash
# Green-build gate for the Claude Code Stop hook. The command is the one
# CONTRIBUTING.md and .github/workflows/ci.yml run. Exit 0 ends the turn.
# Exit 2 sends the failure back and keeps the turn going. stop_hook_active
# means this hook already continued the turn, so it exits 0 and cannot loop.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

input="$(cat || true)"
if ! active="$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
raw = sys.stdin.read()
if not raw.strip():
    print("false")
    raise SystemExit(0)
try:
    data = json.loads(raw)
except Exception:
    print("false")
    raise SystemExit(0)
flag = data.get("stop_hook_active", False)
print("true" if flag is True or flag == "true" else "false")
')"; then
  active=false
fi

if [[ "$active" == "true" ]]; then
  exit 0
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
xcodebuild -project Locant.xcodeproj -scheme Locant -destination 'platform=macOS' test \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet >"$log" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  exit 0
fi

{
  printf 'The Locant tests failed (xcodebuild exit %s). Fix them before stopping.\n' "$status"
  tail -n 150 "$log"
} >&2
exit 2
