#!/usr/bin/env bash
# ovn_identity_guard.sh - hourly: a repo clone must never carry a fixture/placeholder LOCAL git identity.
# 2026-10-02: repos/gitlark/.git/config had user.name=t / user.email=t@t from Sep 29 21:12; every commit hygiene/promote made through that clone
# (146 of them, incl. the daily release commit) was authored 't <t@t>'. Vercel blocks commits it cannot link to a GitHub account (yesterday's BLOCKED
# previews; today a stuck production deploy), and the history is permanently mis-attributed. A local identity overrides the correct global one.
# Action: unset the local user.name/user.email when the email looks like a fixture, append ONE warn line to state/alerts.log (the single alert channel).
# Never touches anything else; ALWAYS exits 0. Cron: 7 * * * * cd ~/overnight-queue && ./ovn_identity_guard.sh >> logs/ovn_identity_guard.log 2>&1
DIR="${OVN_DIR:-$HOME/overnight-queue}"
RD="${OVN_REPOS_DIR:-$DIR/repos}"
ALERTS="$DIR/state/alerts.log"
BAD='^(t@t|test@.*|.*@example\.(com|org|net|test)|.*@localhost|.*@shrike\.local|.*\.invalid|noreply@t|a@b|x@y)$'
mkdir -p "$DIR/state" 2>/dev/null
for r in "$RD"/*/; do
  r="${r%/}"; [ -d "$r/.git" ] || [ -f "$r/.git" ] || continue
  em="$(git -C "$r" config --local --get user.email 2>/dev/null)"
  nm="$(git -C "$r" config --local --get user.name 2>/dev/null)"
  [ -z "$em$nm" ] && continue
  if printf '%s' "$em" | grep -qiE "$BAD" || { [ -z "$em" ] && printf '%s' "$nm" | grep -qxE 't|test|Test User'; }; then
    git -C "$r" config --local --unset user.name 2>/dev/null; git -C "$r" config --local --unset user.email 2>/dev/null
    echo "$(date '+%F %T') warn | identity-guard | $(basename "$r"): removed fixture local git identity '$nm <$em>' (commits through this clone were being mis-authored)" >> "$ALERTS"
    echo "$(date '+%F %T') $(basename "$r"): removed fixture identity '$nm <$em>'"
  fi
done
exit 0
