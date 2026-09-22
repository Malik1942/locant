#!/bin/zsh
# specs/grok-bot-skill.md §4 test 1: checks the Locant skill (R64) and plugin (R65). The skill's own
# command runs against a throwaway capture folder, never ~/Pictures/Locant. Needs Locant 0.7.1 or later.
set -euo pipefail
cd "${0:A:h}/.."
fail() { print -u2 "FAIL: $*"; exit 1 }

plugin=plugins/locant
skill=$plugin/skills/locant/SKILL.md

# R64: the frontmatter names the skill after its folder and says when to use it.
[[ -f $skill ]] || fail "$skill is missing"
[[ $(sed -n 1p $skill) == --- ]] || fail "SKILL.md must open with --- frontmatter"
name=$(awk 'NR > 1 && /^---$/ { exit } NR > 1 && sub(/^name: /, "") { print }' $skill)
[[ $name == locant ]] || fail "SKILL.md name is '$name'; it must be locant, its folder's name"
awk 'NR > 1 && /^---$/ { exit } /^description: ./ { found = 1 } END { exit !found }' $skill \
  || fail "SKILL.md has no description"

# R64: the skill's command, exactly as written, against a folder holding one capture.
command=$(awk '/^ *```sh$/ { inside = 1; next } inside && /^ *```$/ { exit } inside' $skill)
[[ -n $command ]] || fail "SKILL.md has no sh block"
folder=$(mktemp -d)
trap 'rm -rf $folder' EXIT
id=20260922-120000-test
png=$folder/locant-calculator-$id.png
cp site/assets/icon-dark.png $png
cat > $folder/locant-calculator-$id.json <<EOF
{
  "createdAt" : "2026-09-22T12:00:00-07:00",
  "element" : {
    "frame" : { "h" : 48, "w" : 48, "x" : 1154, "y" : 516 },
    "identifier" : "Eight",
    "identifierSource" : "declared",
    "label" : "8",
    "path" : [
      { "identifier" : null, "role" : "application" },
      { "identifier" : "main", "role" : "window" },
      { "identifier" : "CalculatorKeypadView", "role" : "group" },
      { "identifier" : "Eight", "role" : "button" }
    ],
    "rawRole" : "AXButton",
    "role" : "button",
    "value" : null
  },
  "id" : "$id",
  "image" : {
    "crop" : { "h" : 128, "w" : 128, "x" : 1114, "y" : 476 },
    "heightPt" : 128,
    "path" : "$png",
    "scale" : 2,
    "widthPt" : 128
  },
  "iterations" : [],
  "mode" : "reference",
  "note" : "make this key bigger",
  "ocr" : null,
  "resolved" : false,
  "schemaVersion" : 1,
  "source" : {
    "app" : { "bundleId" : "com.apple.calculator", "name" : "Calculator" },
    "simulator" : null,
    "url" : null,
    "window" : { "title" : "Calculator" }
  }
}
EOF
run() { print -r -- "$1" | sed "s|--mcp|--mcp --folder $folder|" | /bin/sh }
out=$(run $command) || fail "the command failed: ${out[1,300]}"
[[ $out == "## Locant capture"* ]] || fail "the command printed: ${out[1,300]}"
[[ $out == *"Image: $png"* ]] || fail "no image path in the payload"
[[ $out == *'button "8" · id=Eight'* ]] || fail "no element in the payload"
[[ $out == *"make this key bigger"* ]] || fail "no note in the payload"
[[ $out == *"\"id\" : \"$id\""* ]] || fail "no id in the sidecar block"
print "OK  the command prints the latest capture"

# R64 step 5: the skill's resolve request, in place of the command's second request.
latest='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"latest_capture","arguments":{}}}'
[[ $command == *"$latest"* ]] || fail "the command's second request is not latest_capture as the spec writes it"
resolve=$(grep -m 1 '"resolve_capture"' $skill | sed -e 's/^ *//' -e "s/<id>/$id/")
[[ $resolve == '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"resolve_capture"'* ]] \
  || fail "SKILL.md has no resolve_capture request"
out=$(run ${command/"$latest"/$resolve}) || fail "the resolve command failed: ${out[1,300]}"
[[ $out == "Resolved $id. Locant keeps it." ]] || fail "resolve printed: ${out[1,300]}"
[[ $(plutil -extract resolved raw -o - $folder/locant-calculator-$id.json) == true ]] \
  || fail "the sidecar is not resolved"
print "OK  the resolve request marks it resolved"
