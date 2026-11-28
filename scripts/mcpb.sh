#!/bin/zsh
# R186: build build/release/locant-mcp.mcpb (the bundle the MCP Registry points at), then fill the version,
# release URL and sha256 of packaging/mcp/server.json from it.
# Usage: scripts/mcpb.sh              (version read from the project)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Locant.xcodeproj/project.pbxproj | head -1)
OUT=build/release/locant-mcp.mcpb
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p build/release "$STAGE/server"
sed "s/\"version\": \"[^\"]*\"/\"version\": \"$VERSION\"/" packaging/mcp/manifest.json > "$STAGE/manifest.json"
cp packaging/mcp/server/locant-mcp "$STAGE/server/"
chmod +x "$STAGE/server/locant-mcp"
cp plugins/locant/assets/logo.png "$STAGE/icon.png"
rm -f "$OUT"
# A fixed date keeps the zip, and so its sha256, the same for the same files.
find "$STAGE" -exec touch -t 202601010000 {} +
(cd "$STAGE" && zip -X -q -r - manifest.json icon.png server) > "$OUT"
SHA=$(shasum -a 256 "$OUT" | cut -d' ' -f1)

python3 - "$VERSION" "$SHA" <<'PY'
import json, sys
version, sha = sys.argv[1], sys.argv[2]
path = "packaging/mcp/server.json"
d = json.load(open(path))
d["version"] = version
p = d["packages"][0]
p["version"] = version
p["identifier"] = f"https://github.com/Malik1942/locant/releases/download/v{version}/locant-mcp.mcpb"
p["fileSha256"] = sha
assert len(d["description"]) <= 100
open(path, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY

echo "▸ $OUT  $SHA"
cat <<EOS
▸ Next:
    gh release upload v$VERSION $OUT --repo Malik1942/locant
    mcp-publisher login github      (once; a device code in the browser)
    cd packaging/mcp && mcp-publisher publish
  Check: curl -s "https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.Malik1942/locant"
EOS
