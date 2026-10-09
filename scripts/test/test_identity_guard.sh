#!/usr/bin/env bash
# ovn_identity_guard.sh: a fixture LOCAL git identity (t <t@t>) is removed with one alert; a real identity is left alone; always exit 0.
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/../../ovn_identity_guard.sh"; [ -f "$SUT" ] || SUT="$HERE/../ovn_identity_guard.sh"
[ -f "$SUT" ] || { echo "  SKIP: ovn_identity_guard.sh not found"; exit 0; }
command -v git >/dev/null || { echo "  SKIP: no git"; exit 0; }
P=0; F=0; ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export OVN_DIR="$T/q" ; mkdir -p "$OVN_DIR/repos" "$OVN_DIR/state"
for r in bad real nameonly noid; do git init -q "$OVN_DIR/repos/$r"; done
git -C "$OVN_DIR/repos/bad" config user.name t;  git -C "$OVN_DIR/repos/bad" config user.email t@t
git -C "$OVN_DIR/repos/real" config user.name "Mark Hintermeister"; git -C "$OVN_DIR/repos/real" config user.email "22970726+markhint22@users.noreply.github.com"
git -C "$OVN_DIR/repos/nameonly" config user.name t
git -C "$OVN_DIR/repos/noid" config core.autocrlf false
env -i PATH="$PATH" HOME="$T" OVN_DIR="$OVN_DIR" bash "$SUT" > "$T/out" 2>&1; rc=$?
ok "exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
ok "fixture identity t <t@t> removed from the bad repo" "$([ -z "$(git -C "$OVN_DIR/repos/bad" config --local --get user.email)" ] && [ -z "$(git -C "$OVN_DIR/repos/bad" config --local --get user.name)" ] && echo 1 || echo 0)"
ok "name-only fixture 't' removed" "$([ -z "$(git -C "$OVN_DIR/repos/nameonly" config --local --get user.name)" ] && echo 1 || echo 0)"
ok "NEGATIVE CONTROL: a real identity is left untouched" "$([ "$(git -C "$OVN_DIR/repos/real" config --local --get user.email)" = "22970726+markhint22@users.noreply.github.com" ] && echo 1 || echo 0)"
ok "a repo with no identity is left alone (other config kept)" "$([ "$(git -C "$OVN_DIR/repos/noid" config --local --get core.autocrlf)" = "false" ] && echo 1 || echo 0)"
ok "exactly one alert line per removal (2)" "$([ "$(grep -c 'identity-guard' "$OVN_DIR/state/alerts.log")" = "2" ] && echo 1 || echo 0)"
: > "$OVN_DIR/state/alerts.log"
env -i PATH="$PATH" HOME="$T" OVN_DIR="$OVN_DIR" bash "$SUT" > /dev/null 2>&1
ok "second run is a no-op (no repeated alerts)" "$([ ! -s "$OVN_DIR/state/alerts.log" ] && echo 1 || echo 0)"
echo "identity guard: $P passed, $F failed"; [ "$F" -eq 0 ]
