#!/usr/bin/env bash
# Regression: un_park.py recovers items mislabeled "[HUMAN-ONLY BLOCKED ITEM ...]" by the fail-streak guard.
# Conservative contract: human/ops-looking -> relabel "[HUMAN]" (still parked); clearly doable code -> un-park (drop tag);
# ambiguous -> untouched. Only `- [ ] [HUMAN-ONLY BLOCKED ITEM...]` lines are ever touched. Runs on temp files only.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../un_park.py" "$HERE/../un_park.py" "$HERE/un_park.py"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "un_park.py not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TAG='[HUMAN-ONLY BLOCKED ITEM after 3 fails]'
F="$T/p.md"
one(){ # $1 = body text -> prints resulting single line (file contains one tagged item)
  printf -- '- [ ] %s %s\n' "$TAG" "$1" > "$F"; python3 "$SUT" "$F" > "$T/out"; head -1 "$F"; }

# ---- routing: each HUMAN keyword -> relabel ----
for kw in "Configure Stripe live keys" "Set up RevenueCat entitlements" "Provision the api key for X" "Obtain an API-key from vendor" \
          "Submit to the App Store review" "Upload to the Play Store" "Point the DNS at Railway" "Clear content rights for assets" \
          "Review the licensing terms" "Generate a production key" "Create a service account for CI" "Finish the OAuth consent screen" \
          "Register the domain shrike.dev" "Deploy to Vercel prod" "Rotate the webhook secret" "Apply for a D-U-N-S number" \
          "Enroll in the Apple Developer program" "Open Google Play Console listing" "Purchase seats from vendor" "Sign up for a new account" \
          "Provision a token for ntfy"; do
  r="$(one "$kw")"
  [ "$r" = "- [ ] [HUMAN] $kw" ] && ok "human keyword relabelled: $kw" 1 || { ok "human keyword relabelled: $kw (got: $r)" 0; }
done
# ---- routing: each DOABLE shape -> un-park ----
for d in "Add a unit test for parse_dates" "Add integration tests around the router" "Add the docstring to helper" "Add a module logger to app/x" \
         "Wrap the call in try/except" "Guard the null path" "Validate the email field" "Reject empty names" "Constrain the limit param" \
         "Broaden the exception handling" "Replace datetime.utcnow with aware now" "Wire the new handler" "Type the result as Literal" \
         "Fix bug in app/util.py" "Fix scene in player.gd" "Fix store in api.ts" "Fix view in Main.vue" "Raises ValueError on bad input" \
         "Remove import os" "Tighten pydantic models" "Add max_length to name" "Return 422 for bad body"; do
  r="$(one "$d")"
  [ "$r" = "- [ ] $d" ] && ok "doable shape un-parked: $d" 1 || { ok "doable shape un-parked: $d (got: $r)" 0; }
done
# ---- ambiguous stays ----
r="$(one "Think about the roadmap somehow")"
ok "ambiguous item left exactly as-is (tag kept)" "$([ "$r" = "- [ ] $TAG Think about the roadmap somehow" ] && echo 1 || echo 0)"
# ---- precedence: HUMAN wins over DOABLE ----
r="$(one "Add a test for stripe webhook in app/pay.py")"
ok "human keyword beats doable keyword (stripe + .py -> [HUMAN])" "$([ "$r" = "- [ ] [HUMAN] Add a test for stripe webhook in app/pay.py" ] && echo 1 || echo 0)"
# ---- tag variants ----
printf -- '- [ ] [HUMAN-ONLY BLOCKED ITEM]   Add a test for x\n- [ ] [HUMAN-ONLY BLOCKED ITEM x9 | why: y]\tGuard z\n' > "$F"; python3 "$SUT" "$F" > "$T/out"
ok "bare tag and tag with extra text both stripped, leading whitespace consumed" "$([ "$(cat "$F")" = "$(printf -- '- [ ] Add a test for x\n- [ ] Guard z')" ] && echo 1 || echo 0)"

# ---- mixed file: counts, untouched lines, trailing newline, idempotency ----
cat > "$F" <<MIXEOF
# Header
## Next Steps
- [ ] plain open item (no tag) with stripe in it
- [x] [HUMAN-ONLY BLOCKED ITEM] checked-off tagged line is never touched stripe
  - [ ] [HUMAN-ONLY BLOCKED ITEM] indented tagged line is not matched either guard
- [ ] $TAG Set up Stripe webhooks
- [ ] $TAG Add a test for app/foo.py
- [ ] $TAG Add a test for app/bar.py
- [ ] $TAG Ponder the vibes
- [ ] [HUMAN] already relabelled item stripe

trailing notes
MIXEOF
cp "$F" "$T/before"
out="$(python3 "$SUT" "$F")"; rc=$?
ok "mixed: rc 0 + counters 'unparked=2 human=1 ambiguous-left=1'" "$([ $rc = 0 ] && [ "$out" = "unparked=2 human=1 ambiguous-left=1" ] && echo 1 || echo 0)"
ok "mixed: untagged / checked / indented / already-[HUMAN] lines byte-identical" "$(diff <(sed -n '1,5p;10,12p' "$T/before") <(sed -n '1,5p;10,12p' "$F") >/dev/null && echo 1 || echo 0)"
ok "mixed: doable lines un-parked in place (line order preserved)" "$([ "$(sed -n '7p' "$F")" = '- [ ] Add a test for app/foo.py' ] && [ "$(sed -n '8p' "$F")" = '- [ ] Add a test for app/bar.py' ] && echo 1 || echo 0)"
ok "mixed: human line relabelled, ambiguous line untouched" "$([ "$(sed -n '6p' "$F")" = '- [ ] [HUMAN] Set up Stripe webhooks' ] && [ "$(sed -n '9p' "$F")" = "- [ ] $TAG Ponder the vibes" ] && echo 1 || echo 0)"
ok "mixed: line count and trailing newline preserved" "$([ "$(wc -l < "$F")" = "$(wc -l < "$T/before")" ] && [ "$(tail -c1 "$F" | od -An -c | tr -d ' ')" = '\n' ] && echo 1 || echo 0)"
cp "$F" "$T/after1"
out="$(python3 "$SUT" "$F")"
ok "idempotent: second run only sees the ambiguous leftover, file unchanged" "$([ "$out" = "unparked=0 human=0 ambiguous-left=1" ] && cmp -s "$F" "$T/after1" && echo 1 || echo 0)"

# ---- no tagged lines at all / empty file / missing file / no args ----
printf -- '- [ ] nothing tagged\n' > "$F"; cp "$F" "$T/b2"; out="$(python3 "$SUT" "$F")"
ok "no tagged lines -> zero counters, file unchanged" "$([ "$out" = "unparked=0 human=0 ambiguous-left=0" ] && cmp -s "$F" "$T/b2" && echo 1 || echo 0)"
: > "$F"; out="$(python3 "$SUT" "$F")"
ok "empty file handled" "$([ "$out" = "unparked=0 human=0 ambiguous-left=0" ] && echo 1 || echo 0)"
python3 "$SUT" "$T/missing.md" >/dev/null 2>&1; ok "missing file -> nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"
python3 "$SUT" >/dev/null 2>&1; ok "no args -> nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
