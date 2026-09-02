#!/usr/bin/env bash
# Clone the feature/vibrant-sprites branch, import assets (generates .import files),
# run the GUT suite, and report. Mirrors the branch-hygiene Godot gate. Then commits
# the generated .import files back to the branch if tests pass.
set -uo pipefail
D=/tmp/xlite-art
GODOT=$HOME/godot/godot4
URL=https://github.com/markhint22/xlite.git
BR=feature/vibrant-sprites
rm -rf "$D"
echo "=== clone $BR ==="
git clone -q --branch "$BR" --depth 1 "$URL" "$D" || { echo "CLONE FAILED"; exit 1; }
cd "$D"

echo "=== godot --import ==="
timeout 200 "$GODOT" --headless --path . --import >/tmp/xi.log 2>&1
echo "import rc=$?"
echo "--- import errors (if any) ---"
grep -iE "SCRIPT ERROR|parse error|ERROR: |Failed to load|Cannot open|error at" /tmp/xi.log | head -15 || echo "(none)"
echo "--- new .import files generated ---"
git status --porcelain assets/sprites | head -30 | wc -l

echo "=== GUT tests ==="
timeout 220 "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit "-gjunit_xml_file=/tmp/xg.xml" >/tmp/xg.log 2>&1
echo "gut rc=$?"
echo "--- gut tail ---"
grep -iE "tests|pass|fail|error|assert" /tmp/xg.log | tail -18
echo "--- junit totals ---"
grep -oE 'tests="[0-9]+"|failures="[0-9]+"|errors="[0-9]+"' /tmp/xg.xml 2>/dev/null | tr '\n' ' '; echo
echo "=== unit.gd specifically parses? (targeted) ==="
grep -iE "unit.gd" /tmp/xi.log /tmp/xg.log | grep -iE "error" | head || echo "(no unit.gd errors)"
