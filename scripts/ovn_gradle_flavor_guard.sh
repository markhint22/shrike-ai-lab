#!/usr/bin/env bash
# scripts/ovn_gradle_flavor_guard.sh — rewrite an ambiguous unqualified Android Gradle
# unit-test VERIFY task (":app:testDebugUnitTest" / ":app:testReleaseUnitTest") into
# Gradle's own umbrella ":<module>:test" lifecycle task, for any repo whose app module
# declares productFlavors. AGP only accepts the single-variant task name when the module
# has ZERO product flavors — once real flavors exist (confirmed live 2026-09-20:
# iptv_apps/iptv-android/app declares googleTv+fireTv; billwatch-android declares none)
# that exact task name doesn't exist and Gradle fails immediately with "Task '...' is
# ambiguous in project ':app'" before a single test runs, regardless of whether the
# model's actual code change was correct. The planner/recovery prompts have no reliable
# way to know a repo's real flavor names up front, so rather than teach them to guess a
# (possibly wrong) one, deterministically fall back to the umbrella task, which Gradle
# resolves to "run every variant's unit tests" whether or not flavors exist at all.
#
# Shared by ovn_planner.sh and ovn_recover_parked.sh (both LLM-decompose backlog items
# with a freeform VERIFY command) so neither path can hand the fleet a VERIFY command
# that is guaranteed to fail on Gradle's task-resolution step alone.
#
# Usage: printf '%s\n' "$items" | ovn_gradle_flavor_guard.sh <repo_dir>
# Reads item lines on stdin, writes (possibly rewritten) lines to stdout unchanged in
# count/order. Prints one summary line to stderr only when a rewrite was made.
set -uo pipefail
repo_dir="${1:-.}"

buf="$(cat)"

has_flavors=0
if find "$repo_dir" -maxdepth 4 -iname 'build.gradle*' -path '*app*' 2>/dev/null \
     | xargs grep -l 'productFlavors' 2>/dev/null | grep -q .; then
  has_flavors=1
fi

if [ "$has_flavors" -eq 0 ]; then
  printf '%s\n' "$buf"
  exit 0
fi

n="$(printf '%s\n' "$buf" | grep -cE ':[A-Za-z0-9_]+:test(Debug|Release)UnitTest\b' || true)"
if [ "${n:-0}" -gt 0 ]; then
  printf '%s\n' "$buf" | sed -E 's/(:[A-Za-z0-9_]+:)test(Debug|Release)UnitTest\b/\1test/g'
  echo "ovn_gradle_flavor_guard: ${repo_dir} has product flavors -> rewrote ${n} ambiguous VERIFY task(s) to the umbrella :<module>:test" >&2
else
  printf '%s\n' "$buf"
fi
