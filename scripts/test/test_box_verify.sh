#!/usr/bin/env bash
# test_box_verify.sh - package L1: ops/box_verify.py (+ .sh) read-only box drift detector. Hermetic: a fake HOME + a copy of the queue tree + stub docker/systemctl/crontab on PATH.
# One HEALTHY world must report zero drift; then each prerequisite that ever broke is broken ONE at a time and the exact item must appear (and only because of that break).
# Mutants (an edited copy of box_verify.py) must each make the scenario that guards that behaviour FAIL. Nothing real is touched; no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OVN_REAL="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
BVPY_REAL="$OVN_REAL/ops/box_verify.py"; BVSH="$OVN_REAL/ops/box_verify.sh"
[ -f "$BVPY_REAL" ] && [ -f "$BVSH" ] || { echo "  FAIL: box_verify.py/.sh missing"; exit 1; }
W="$(safe_mktemp_dir bvtest)" || exit 1
trap 'safe_rm_rf "$W"' EXIT
fails=0; n=0
ok(){ n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk(){ local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
safe_set_sandbox_home "$W" || exit 1
H="$HOME"; O="$H/overnight-queue"; PY="$BVPY_REAL"
mkdir -p "$W/bin" "$W/drive/box-backups" "$W/tmp"

# ------------------------------------------------------------------ the healthy world
# copy_tree SRC DST: copy the queue tree WITHOUT any .git. The box's ~/overnight-queue is itself a git repo (the Mac tree is a subdir of one), so a bare cp -R drags in the box's REAL history
# (its 'local research refuel' commits) and box_verify then never raises supply:refuel_stalled. Hermetic = the fixture owns its own history (git init below).
copy_tree(){ cp -R "$1" "$2" 2>/dev/null; safe_rm_rf "$2/.git" 2>/dev/null; return 0; }
copy_tree "$OVN_REAL" "$O"; safe_rm_rf "$O/state" "$O/logs" "$O/repos" 2>/dev/null   # (a fresh copy: no leftovers of the source's own state)
mkdir -p "$O/state/qa_creds" "$O/state/qa_shadow" "$O/logs" "$O/repos"
# stub crontab (file under W) for the real installers and for box_verify (BV_CRONTAB_FILE)
printf '%s\n' '#!/bin/sh' "F=\"$W/crontab.stub\"" 'case "$1" in -l) [ -f "$F" ] || { echo "no crontab for u" >&2; exit 1; }; cat "$F";; *) cp "$1" "$F";; esac' > "$W/bin/crontab"; chmod 755 "$W/bin/crontab"
printf '%s\n' '#!/bin/sh' 'if [ -f "'"$W"'/docker.fail" ]; then echo "Cannot connect to the Docker daemon" >&2; exit 1; fi' 'cat "'"$W"'/docker.out"' > "$W/bin/docker"; chmod 755 "$W/bin/docker"
printf 'shrike-llama-dflash-35b\tUp 20 hours (healthy)\nshrike-litellm\tUp 8 days\nshrike-webui\tUp 8 days (healthy)\n' > "$W/docker.out"
printf '%s\n' '#!/bin/sh' '[ "$1" = "is-active" ] || exit 2' 'if grep -qx "$2" "'"$W"'/units.down" 2>/dev/null; then echo inactive; exit 3; fi' 'echo active' > "$W/bin/systemctl"; chmod 755 "$W/bin/systemctl"
: > "$W/units.down"
# repos + venvs: a shim python (real python3 + a fake site dir with dist-info metadata so importlib.metadata sees the packages)
mkvenv(){ # repo sub  extra-dev-req-lines...
  local r="$1" s="$2"; shift 2; local d="$O/repos/$r/$s" site="$W/site_$r"
  mkdir -p "$d/.venv/bin" "$site"
  printf '%s\n' '#!/bin/sh' "PYTHONPATH=\"$site\" exec python3 -B \"\$@\"" > "$d/.venv/bin/python"; chmod 755 "$d/.venv/bin/python"
  printf 'fastapi>=0.1\nhttpx\n' > "$d/requirements.txt"
  printf -- '-r requirements.txt\n# test tools\npytest>=7.0.0\npytest-xdist>=3.5.0   # parallel\n%s\n' "${*:-}" > "$d/requirements-dev.txt"
  local p; for p in fastapi httpx pytest pytest-xdist "$@"; do p="${p%%[<>=]*}"; mkdir -p "$site/${p//-/_}-1.0.dist-info"; printf 'Metadata-Version: 2.1\nName: %s\nVersion: 1.0\n' "$p" > "$site/${p//-/_}-1.0.dist-info/METADATA"; done
}
mkvenv billwatch billwatch-backend pytest-mock; mkvenv gitlark backend; mkvenv iptv_apps iptv-backend; mkvenv test-automation-agent backend; mkvenv shrike-monitor backend; mkvenv shrike-notify backend
# android sdk per ops/box_pins.env
SDK="$H/android-sdk"; mkdir -p "$SDK/cmdline-tools/latest/bin" "$SDK/platform-tools"
printf '#!/bin/sh\nexit 0\n' > "$SDK/cmdline-tools/latest/bin/sdkmanager"; chmod 755 "$SDK/cmdline-tools/latest/bin/sdkmanager"; cp "$SDK/cmdline-tools/latest/bin/sdkmanager" "$SDK/platform-tools/adb"
printf 'Pkg.Revision=22.0\n' > "$SDK/cmdline-tools/latest/source.properties"
for p in android-34 android-36; do mkdir -p "$SDK/platforms/$p"; : > "$SDK/platforms/$p/android.jar"; done
for b in 34.0.0 35.0.0 36.0.0; do mkdir -p "$SDK/build-tools/$b"; echo "Pkg.Revision=$b" > "$SDK/build-tools/$b/source.properties"; done
# qa tools installer stub (the real one is exercised separately below)
printf '%s\n' '#!/usr/bin/env bash' 'for t in bandit semgrep pip-audit mutmut schemathesis mypy ruff gitleaks; do echo "install_qa_tools: $t  ${STUB_QA_STATUS:-ok}  pin=1"; done' '[ "${STUB_QA_STATUS:-ok}" = ok ]' > "$O/ops/install_qa_tools.sh"; chmod 755 "$O/ops/install_qa_tools.sh"
# godot + aider
mkdir -p "$H/godot" "$H/aider-venv/bin" "$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.86.2.dist-info"
printf '#!/bin/sh\necho 4.3.stable.official.77dcf97d8\n' > "$H/godot/godot4"; chmod 755 "$H/godot/godot4"; : > "$H/aider-venv/bin/python"; chmod 755 "$H/aider-venv/bin/python"
# backups + mount list
: > "$W/drive/box-backups/heartbeat-daily.log"; : > "$W/drive/box-backups/heartbeat-hourly.log"; echo "/dev/x $W/drive ext4 rw 0 0" > "$W/mounts"
# state
printf 'postgresql://u:p@h/db\n' > "$O/state/billwatch_db_url"; chmod 600 "$O/state/billwatch_db_url"
for r in billwatch gitlark iptv_apps; do echo "https://$r-staging.example" > "$O/state/staging_url_$r"; done
printf '{"email":"qa@example.test","password":"x"}' > "$O/state/qa_creds/iptv_apps.json"; chmod 600 "$O/state/qa_creds/iptv_apps.json"
echo '{}' > "$O/state/qa_shadow/contract_fuzz_baseline_iptv_apps.json"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF
# the crontab: snapshot + both managed blocks through the REAL installers, every line switched ON (a fully healthy install)
BVLINE='47 * * * * cd ~/overnight-queue && OVN_BOX_VERIFY=shadow bash ops/box_verify.sh >> logs/box_verify.log 2>&1'
cp "$O/ops/crontab.box.snapshot.txt" "$W/crontab.stub"
( cd "$O" && PATH="$W/bin:$PATH" OVN_DIR="$O" bash ops/install_supply_cron.sh --apply ) > "$W/inst1.out" 2>&1
( cd "$O" && PATH="$W/bin:$PATH" OVN_DIR="$O" bash ops/install_qa_cron.sh --apply --enable contract_fuzz --enable card_pilot --enable card_pilot_report ) > "$W/inst2.out" 2>&1
echo "$BVLINE" >> "$W/crontab.stub"   # this checker's own hourly line: a healthy box has it (it is an accepted cron_extra until the snapshot is refreshed)
cp "$W/crontab.stub" "$W/crontab.healthy"
chk "fixture: the real installers put both managed blocks into the stub crontab" bash -c "grep -q 'SUPPLY-LINES BEGIN' '$W/crontab.stub' && grep -q 'QA-GATES BEGIN' '$W/crontab.stub'"

bvrun(){ # [env assignments...] -- extra args ; writes $W/out.json (stdout) ; PY selectable
  HOME="$H" BV_HOME="$H" BV_OVN="$O" BV_STATE="$O/state" BV_BACKUPS="$W/drive/box-backups" BV_CRONTAB_FILE="${BV_CRONTAB_FILE:-$W/crontab.stub}" BV_PROC_MOUNTS="$W/mounts" BV_TMP="$W/tmp" \
  BV_DISK_MAX_PCT="${BV_DISK_MAX_PCT:-101}" BV_INODE_MAX_PCT="${BV_INODE_MAX_PCT:-101}" PATH="$W/bin:$PATH" python3 -B "$PY" "$@" > "$W/out.json" 2> "$W/err.txt"; echo $? > "$W/rc"
}
keys(){ python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); sys.stdout.write("".join(i["key"]+"\n" for i in j.get("items",[])))' "$W/out.json" 2>/dev/null; }
cnts(){ python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(j["counts"]["drift"], j["counts"]["accepted"])' "$W/out.json" 2>/dev/null; }
has(){ keys | grep -qxF "$1"; }
hasnot(){ ! has "$1"; }
haspre(){ keys | grep -q "^$1"; }
sevof(){ python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print([i["sev"] for i in j["items"] if i["key"]==sys.argv[2]][0])' "$W/out.json" "$1" 2>/dev/null; }
classof(){ python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print([i["class"] for i in j["items"] if i["key"]==sys.argv[2]][0])' "$W/out.json" "$1" 2>/dev/null; }
only(){ [ "$(keys | wc -l | tr -d ' ')" = "$1" ]; }
# break-and-restore helper: brk <file> <python-expr transforming s> ; rst <file>
saveonce(){ [ -e "$1.bvorig" ] || cp -p "$1" "$1.bvorig"; }
rst(){ [ -e "$1.bvorig" ] && { cp -p "$1.bvorig" "$1"; rm -f "$1.bvorig"; }; return 0; }

echo "== healthy world: zero drift, every check ok"
bvrun --no-record
chk "healthy: ok=true, 0 drift items" python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); assert j["ok"] is True and j["counts"]["drift"]==0, j["items"]' "$W/out.json"
chk "healthy: every one of the 11 checks ran and reported ok" python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); assert len(j["checks"])==11 and all(v=="ok" for v in j["checks"].values()), j["checks"]' "$W/out.json"
chk "healthy: --strict exits 0" bash -c "BV_STATE='$O/state' true; cd '$W' && HOME='$H' BV_HOME='$H' BV_OVN='$O' BV_STATE='$O/state' BV_BACKUPS='$W/drive/box-backups' BV_CRONTAB_FILE='$W/crontab.stub' BV_PROC_MOUNTS='$W/mounts' BV_TMP='$W/tmp' BV_DISK_MAX_PCT=101 BV_INODE_MAX_PCT=101 PATH='$W/bin':\$PATH python3 -B '$PY' --no-record --strict >/dev/null"

echo "== venvs (incident b: xdist/dev reqs missing in rebuilt venvs)"
S="$W/site_billwatch"
mv "$S/pytest_xdist-1.0.dist-info" "$S/xx.gone"
bvrun --no-record
chk "missing pytest-xdist -> item venv:billwatch:missing_pkg:pytest-xdist" has "venv:billwatch:missing_pkg:pytest-xdist"
ok "  severity crit (xdist missing made the iptv suite revert good commits)" "$([ "$(sevof venv:billwatch:missing_pkg:pytest-xdist)" = crit ] && echo 0 || echo 1)"
ok "  class regen" "$([ "$(classof venv:billwatch:missing_pkg:pytest-xdist)" = regen ] && echo 0 || echo 1)"
chk "  nothing else flagged (no false positives in the other 5 venvs)" only 1
mv "$S/xx.gone" "$S/pytest_xdist-1.0.dist-info"
mv "$S/pytest_mock-1.0.dist-info" "$S/xx.gone"; bvrun --no-record
chk "missing dev requirement (pytest-mock from requirements-dev.txt) -> warn item" has "venv:billwatch:missing_pkg:pytest-mock"
mv "$S/xx.gone" "$S/pytest_mock-1.0.dist-info"
mv "$W/site_gitlark/httpx-1.0.dist-info" "$W/xx.gone"; bvrun --no-record
chk "missing package named only via '-r requirements.txt' is found too" has "venv:gitlark:missing_pkg:httpx"
mv "$W/xx.gone" "$W/site_gitlark/httpx-1.0.dist-info"
printf 'ghostpkg>=1; python_version < "3.0"\nfastapi[all]>=0.1\n' >> "$O/repos/gitlark/backend/requirements.txt"; bvrun --no-record
chk "marker-excluded requirement and extras-spec of an installed package are NOT flagged" bash -c "[ \$(python3 -c 'import json;print(json.load(open(\"$W/out.json\"))[\"counts\"][\"drift\"])') = 0 ]"
printf 'fastapi>=0.1\nhttpx\n' > "$O/repos/gitlark/backend/requirements.txt"
mv "$O/repos/iptv_apps/iptv-backend/.venv" "$W/venv.gone"; bvrun --no-record
chk "no .venv -> venv:iptv_apps:missing (crit)" has "venv:iptv_apps:missing"
mv "$W/venv.gone" "$O/repos/iptv_apps/iptv-backend/.venv"
saveonce "$O/repos/shrike-notify/backend/.venv/bin/python"; printf '#!/bin/sh\nexit 3\n' > "$O/repos/shrike-notify/backend/.venv/bin/python"; bvrun --no-record
chk "a venv whose python dies -> venv:shrike-notify:broken" has "venv:shrike-notify:broken"; rst "$O/repos/shrike-notify/backend/.venv/bin/python"
mv "$O/repos/shrike-monitor" "$W/repo.gone"; bvrun --no-record
chk "repo clone missing -> venv:shrike-monitor:repo_missing" has "venv:shrike-monitor:repo_missing"; mv "$W/repo.gone" "$O/repos/shrike-monitor"
chk "provision_test_envs.sh python targets are all covered by box_verify REPOS (drift guard between provisioner and checker)" python3 - "$OVN_REAL" <<'PYEOF'
import re, sys
o = sys.argv[1]
prov = open(o + "/provision_test_envs.sh").read()
targets = re.findall(r'"([a-z_-]+):([A-Za-z0-9._-]+):python"', prov)
bv = open(o + "/ops/box_verify.py").read()
block = re.search(r"REPOS = \((.*?)\)\nBLOCKS", bv, re.S).group(1)
have = set(re.findall(r'\("([a-z_-]+)", "([A-Za-z0-9._-]+)"\)', block))
skip = {"task-manager-platform", "social-media-manager"}   # discontinued
missing = [t for t in targets if t[0] not in skip and t not in have]
assert not missing, missing
PYEOF

echo "== android sdk (incident b: ~/android-sdk missing)"
mv "$SDK" "$W/sdk.gone"; bvrun --no-record
chk "no ~/android-sdk -> android:sdk_missing (crit)" has "android:sdk_missing"; mv "$W/sdk.gone" "$SDK"
mv "$SDK/platforms/android-36" "$W/p.gone"; bvrun --no-record
chk "pinned platform missing -> android:platform:android-36" has "android:platform:android-36"; chk "  only that item" only 1; mv "$W/p.gone" "$SDK/platforms/android-36"
mv "$SDK/build-tools/35.0.0" "$W/b.gone"; bvrun --no-record; chk "pinned build-tools missing -> android:build_tools:35.0.0" has "android:build_tools:35.0.0"; mv "$W/b.gone" "$SDK/build-tools/35.0.0"
echo 'Pkg.Revision=11.0' > "$SDK/cmdline-tools/latest/source.properties"; bvrun --no-record; chk "cmdline-tools at another revision than the pin -> android:cmdline_tools_rev" has "android:cmdline_tools_rev"; echo 'Pkg.Revision=22.0' > "$SDK/cmdline-tools/latest/source.properties"
chmod -x "$SDK/cmdline-tools/latest/bin/sdkmanager"; bvrun --no-record; chk "sdkmanager not executable -> android:sdkmanager_missing" has "android:sdkmanager_missing"; chmod +x "$SDK/cmdline-tools/latest/bin/sdkmanager"

echo "== QA tools / godot / aider"
STUB_QA_STATUS=wrong-version bvrun --no-record; chk "QA tool at a wrong version -> qa_tool:ruff:wrong-version" has "qa_tool:ruff:wrong-version"
STUB_QA_STATUS=missing bvrun --no-record; chk "all QA tools missing -> 8 qa_tool:*:missing items" bash -c "[ \$(python3 -c 'import json;print(sum(1 for i in json.load(open(\"$W/out.json\"))[\"items\"] if i[\"key\"].startswith(\"qa_tool:\")))') = 8 ]"
mkdir -p "$W/realqa/home"; ( HOME="$W/realqa/home" bash "$OVN_REAL/ops/install_qa_tools.sh" --check ) > "$W/realqa.out" 2>&1
python3 - "$W/realqa.out" <<'PYEOF' > "$W/realqa.n"
import re, sys
print(sum(1 for l in open(sys.argv[1]) if re.match(r"install_qa_tools:\s+(\S+)\s+(ok|missing|wrong-version|broken)\b", l)))
PYEOF
chk "the REAL install_qa_tools.sh --check output format is what the parser reads (8 tool rows)" bash -c "[ \$(cat '$W/realqa.n') = 8 ]"
printf '#!/bin/sh\necho 4.2.stable\n' > "$H/godot/godot4"; bvrun --no-record; chk "godot at 4.2 vs pin 4.3 -> godot:version" has "godot:version"; printf '#!/bin/sh\necho 4.3.stable.official.77dcf97d8\n' > "$H/godot/godot4"
mv "$H/godot/godot4" "$W/g.gone"; bvrun --no-record; chk "no godot -> godot:missing" has "godot:missing"; mv "$W/g.gone" "$H/godot/godot4"
mv "$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.86.2.dist-info" "$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.90.0.dist-info"; bvrun --no-record
chk "aider-chat at another version than the pin -> aider:version" has "aider:version"; mv "$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.90.0.dist-info" "$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.86.2.dist-info"
bvrun --no-record; chk "restored: healthy again (the breaks above left nothing behind)" only 0

echo "== cron scripts (incident b: 4 scripts mode 644; incident c: exit 127 for hours) - checked against the LIVE crontab"
F="$O/gpu_autoswap.sh"; chmod -x "$F"; bvrun --no-record
chk "cron runs ./gpu_autoswap.sh but it is not executable -> cron_script_not_exec:gpu_autoswap.sh (crit)" has "cron_script_not_exec:gpu_autoswap.sh"
ok "  severity crit" "$([ "$(sevof cron_script_not_exec:gpu_autoswap.sh)" = crit ] && echo 0 || echo 1)"; chmod +x "$F"
F="$O/scripts/ovn_notify.py"; chmod -x "$F"; bvrun --no-record; chk "a .py run through python3 needs no exec bit (no false positive)" hasnot "cron_script_not_exec:scripts/ovn_notify.py"; chmod +x "$F"
F="$O/qa/qa_daily_shadow.sh"; mv "$F" "$W/s.gone"; bvrun --no-record; chk "a script the crontab runs but the tree lacks -> cron_script_missing:qa/qa_daily_shadow.sh (crit)" has "cron_script_missing:qa/qa_daily_shadow.sh"; mv "$W/s.gone" "$F"
chmod -x "$O/ops/run_suite_sandboxed_cron.sh"; bvrun --no-record; chk "a script run via bash needs no exec bit (ops/run_suite_sandboxed_cron.sh)" hasnot "cron_script_not_exec:ops/run_suite_sandboxed_cron.sh"; chmod +x "$O/ops/run_suite_sandboxed_cron.sh"

echo "== crontab equality, managed blocks, sandboxed-suite line"
grep -v 'run_suite_sandboxed_cron.sh' "$W/crontab.healthy" > "$W/crontab.stub"; bvrun --no-record
chk "sandboxed-suite line gone -> cron_line_missing:sandboxed_suite" has "cron_line_missing:sandboxed_suite"
chk "  and the snapshot comparison reports the missing line too" bash -c "keys=\$(python3 -c 'import json;print(\"\\n\".join(i[\"key\"] for i in json.load(open(\"$W/out.json\"))[\"items\"]))'); echo \"\$keys\" | grep -q '^cron_missing:run_suite_sandboxed_cron.sh:'"
python3 - "$W/crontab.healthy" "$W/crontab.stub" <<'PYEOF'
import sys
out, skip = [], False
for l in open(sys.argv[1]).read().split("\n"):
    if l.startswith("# >>> QA-GATES BEGIN"): skip = True
    if not skip: out.append(l)
    if l.strip() == "# <<< QA-GATES END <<<": skip = False
open(sys.argv[2], "w").write("\n".join(out))
PYEOF
bvrun --no-record; chk "QA-GATES block gone -> cron_block_missing:QA-GATES (crit)" has "cron_block_missing:QA-GATES"; chk "  SUPPLY-LINES still fine" hasnot "cron_block_missing:SUPPLY-LINES"
python3 - "$W/crontab.healthy" "$W/crontab.stub" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
s = s.replace("python3 scripts/ovn_work_supply.py gitlark --max 12", "python3 scripts/ovn_work_supply.py gitlark --max 99")
open(sys.argv[2], "w").write(s)
PYEOF
bvrun --no-record; chk "a block line edited by hand -> cron_block_line_stale:supply_gitlark" has "cron_block_line_stale:supply_gitlark"
python3 - "$W/crontab.healthy" "$W/crontab.stub" <<'PYEOF'
import sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(s.replace("\n20 4 * * * cd $HOME/overnight-queue && bash qa/contract_fuzz_cron.sh", "\n#OFF# 20 4 * * * cd $HOME/overnight-queue && bash qa/contract_fuzz_cron.sh"))
PYEOF
bvrun --no-record; chk "contract_fuzz switched off (the real box today) -> cron_off:contract_fuzz, class human" has "cron_off:contract_fuzz"; ok "  class human" "$([ "$(classof cron_off:contract_fuzz)" = human ] && echo 0 || echo 1)"
cp "$W/crontab.healthy" "$W/crontab.stub"; echo '* * * * * /bin/true # hand edit' >> "$W/crontab.stub"; bvrun --no-record
chk "a stray live line not in the snapshot -> cron_extra:*" bash -c "python3 -c 'import json;print(\"\\n\".join(i[\"key\"] for i in json.load(open(\"$W/out.json\"))[\"items\"]))' | grep -q '^cron_extra:'"
grep -vF 'ops/box_verify.sh' "$W/crontab.healthy" > "$W/crontab.stub"; echo '* * * * * cd ~/overnight-queue && bash ops/box_verify.sh >> logs/box_verify.log 2>&1' >> "$W/crontab.stub"; bvrun --no-record
chk "box_verify's OWN cron line is an accepted exception (documented), not drift (0 drift, 1 accepted)" test "$(cnts)" = "0 1"
cp "$W/crontab.healthy" "$W/crontab.stub"
BV_CRONTAB_FILE="$W/nonexistent" bvrun --no-record; chk "unreadable crontab -> cron:unreadable (crit), never a silent pass" has "cron:unreadable"
printf 'item venv:*  # unit-test exception with a reason\nitem cron_off:nothing\n' > "$W/exc.txt"
BV_EXCEPTIONS="$W/exc.txt" bvrun --no-record; chk "an exceptions line WITHOUT a written reason is itself reported and ignored (exceptions:no_reason)" has "exceptions:no_reason:2"

echo "== state files (incident b: billwatch_db_url; qa_creds / staging urls; human vs regeneratable)"
mv "$O/state/billwatch_db_url" "$W/u.gone"; bvrun --no-record
chk "billwatch_db_url missing -> state:billwatch_db_url_missing" has "state:billwatch_db_url_missing"; ok "  class human (a person must re-fetch it from Railway)" "$([ "$(classof state:billwatch_db_url_missing)" = human ] && echo 0 || echo 1)"
mv "$W/u.gone" "$O/state/billwatch_db_url"; chmod 644 "$O/state/billwatch_db_url"; bvrun --no-record
chk "billwatch_db_url mode 644 -> state:billwatch_db_url_mode (crit, class regen: chmod)" has "state:billwatch_db_url_mode"; ok "  severity crit" "$([ "$(sevof state:billwatch_db_url_mode)" = crit ] && echo 0 || echo 1)"; chmod 600 "$O/state/billwatch_db_url"
: > "$O/state/billwatch_db_url"; bvrun --no-record; chk "empty billwatch_db_url -> state:billwatch_db_url_empty" has "state:billwatch_db_url_empty"; printf 'postgresql://u:p@h/db\n' > "$O/state/billwatch_db_url"
rm -f "$O/state/staging_url_gitlark"; bvrun --no-record; chk "staging_url missing -> state:staging_url_gitlark (human)" has "state:staging_url_gitlark"; echo "https://gitlark-staging.example" > "$O/state/staging_url_gitlark"
mv "$O/state/qa_creds/iptv_apps.json" "$W/c.gone"; bvrun --no-record; chk "qa_creds/iptv_apps.json missing -> state:qa_creds_iptv_apps (human)" has "state:qa_creds_iptv_apps"; mv "$W/c.gone" "$O/state/qa_creds/iptv_apps.json"
chmod 644 "$O/state/qa_creds/iptv_apps.json"; bvrun --no-record; chk "qa_creds readable by others -> state:qa_creds_mode_iptv_apps" has "state:qa_creds_mode_iptv_apps"; chmod 600 "$O/state/qa_creds/iptv_apps.json"
rm -f "$O/state/qa_shadow/contract_fuzz_baseline_iptv_apps.json"; bvrun --no-record; chk "contract-fuzz baseline missing -> state:contract_fuzz_baseline_iptv_apps (human)" has "state:contract_fuzz_baseline_iptv_apps"; echo '{}' > "$O/state/qa_shadow/contract_fuzz_baseline_iptv_apps.json"

echo "== backups, drive, capacity"
python3 -c 'import os,sys,time; t=time.time()-27*3600; os.utime(sys.argv[1],(t,t))' "$W/drive/box-backups/heartbeat-daily.log"; bvrun --no-record
chk "daily heartbeat 27h old (> 26h) -> backup:daily_heartbeat_stale (crit)" has "backup:daily_heartbeat_stale"; chk "  hourly still fresh" hasnot "backup:hourly_heartbeat_stale"
python3 -c 'import os,sys,time; t=time.time()-25*3600; os.utime(sys.argv[1],(t,t))' "$W/drive/box-backups/heartbeat-daily.log"; bvrun --no-record; chk "daily heartbeat 25h old (< 26h) is fine" hasnot "backup:daily_heartbeat_stale"
python3 -c 'import os,sys,time; t=time.time()-4*3600; os.utime(sys.argv[1],(t,t))' "$W/drive/box-backups/heartbeat-hourly.log"; bvrun --no-record; chk "hourly heartbeat 4h old (> 3h) -> backup:hourly_heartbeat_stale" has "backup:hourly_heartbeat_stale"
: > "$W/drive/box-backups/heartbeat-daily.log"; : > "$W/drive/box-backups/heartbeat-hourly.log"
mv "$W/drive/box-backups/heartbeat-hourly.log" "$W/hb.gone"; bvrun --no-record; chk "heartbeat file missing -> backup:hourly_heartbeat_missing" has "backup:hourly_heartbeat_missing"; mv "$W/hb.gone" "$W/drive/box-backups/heartbeat-hourly.log"
echo "/dev/y /other ext4 rw 0 0" > "$W/mounts"; bvrun --no-record; chk "secondary drive not in the mount table -> backup:drive_not_mounted (crit)" has "backup:drive_not_mounted"; echo "/dev/x $W/drive ext4 rw 0 0" > "$W/mounts"
BV_INODE_MAX_PCT=0 bvrun --no-record; chk "/tmp inode use over the limit -> capacity:tmp_inodes (crit)" has "capacity:tmp_inodes"
BV_DISK_MAX_PCT=0 bvrun --no-record; chk "disk use over the limit -> capacity:disk_home" has "capacity:disk_home"
chk "default limits are 85% disk and 70% inodes (as specified)" grep -q '_num("BV_DISK_MAX_PCT", 85)' "$PY"
chk "  inode default 70" grep -q '_num("BV_INODE_MAX_PCT", 70)' "$PY"

echo "== gpu containers, systemd, supply"
printf 'shrike-litellm\tUp 8 days\n' > "$W/docker.out"; bvrun --no-record; chk "llama container not running -> gpu:container_missing:shrike-llama (crit)" has "gpu:container_missing:shrike-llama"
printf 'shrike-llama-dflash-35b\tUp 20 hours (unhealthy)\nshrike-litellm\tUp 8 days\n' > "$W/docker.out"; bvrun --no-record; chk "unhealthy llama container -> gpu:container_unhealthy:*" has "gpu:container_unhealthy:shrike-llama-dflash-35b"
printf 'shrike-llama-dflash-35b\tExited (1) 2 minutes ago\nshrike-litellm\tUp 8 days\n' > "$W/docker.out"; bvrun --no-record; chk "a container that is not Up -> gpu:container_unhealthy" has "gpu:container_unhealthy:shrike-llama-dflash-35b"
printf 'shrike-llama-dflash-35b\tUp 20 hours (healthy)\nshrike-litellm\tUp 8 days\n' > "$W/docker.out"; touch "$W/docker.fail"; bvrun --no-record; chk "docker unreachable -> gpu:docker_unreachable" has "gpu:docker_unreachable"; rm -f "$W/docker.fail"
echo "ovn-ntfy-relay.service" > "$W/units.down"; bvrun --no-record; chk "relay unit inactive -> systemd:ovn-ntfy-relay.service (crit)" has "systemd:ovn-ntfy-relay.service"; chk "  other units fine" only 1; : > "$W/units.down"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 14 * 3600)), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF
bvrun --no-record; chk "explorer's newest row 14h old (> 12h) -> supply:explorer_stale" has "supply:explorer_stale"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
open(sys.argv[1], "w").write("".join(json.dumps({"ts": t, "repo": "xlite", "result": "error"}) + "\n" for _ in range(4)))
PYEOF
bvrun --no-record; chk "explorer's last real passes all error -> supply:explorer_erroring" has "supply:explorer_erroring"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
open(sys.argv[1], "w").write("".join(json.dumps({"ts": t, "repo": "xlite", "result": r}) + "\n" for r in ("error", "error", "error", "skip-cap", "skip-lens-ttl", "empty")))
PYEOF
bvrun --no-record; chk "skip-* rows are not failures and one good pass clears 'erroring'" hasnot "supply:explorer_erroring"
starving(){ python3 -c 'import json,sys,time; json.dump({"checked_at": time.time()-float(sys.argv[3])*3600, "starving": [{"repo": "iptv_apps", "hours": float(sys.argv[2]), "pullable": 0}]}, open(sys.argv[1], "w"))' "$O/state/research_trigger_starving.json" "$1" "${2:-0}"; }
starving 3.6; bvrun --no-record
chk "a lane starving only 3.6h is NOT a refuel stall (no false positive)" hasnot "supply:refuel_stalled"
starving 9.0; bvrun --no-record
chk "a lane starving 9h with no auto-research commit for a day -> supply:refuel_stalled" has "supply:refuel_stalled"
rm -f "$O/state/research_trigger_starving.json"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF


echo "== review fixes (L1 repair round): cron interpreter flags, GPU window, refuel clock, exception scope, own cron line"
cat > "$W/tok.py" <<'PYEOF'
import importlib.util, sys
sp = importlib.util.spec_from_file_location("bv", sys.argv[1]); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
CASES = [
 ("python3 -u scripts/ovn_x.py", [("scripts/ovn_x.py", False)]),
 ("nice -n 10 python3 -B scripts/ovn_y.py", [("scripts/ovn_y.py", False)]),
 ("bash -x ops/z.sh", [("ops/z.sh", False)]),
 ("timeout 9 python3 -W ignore scripts/c.py", [("scripts/c.py", False)]),
 ("flock -n l bash -c 'bash scripts/a.sh'", [("scripts/a.sh", False)]),
 ("flock -n l bash -c 'python3 -u scripts/a.py'", [("scripts/a.py", False)]),
 ("sh -c \"./ops/b.sh\"", [("ops/b.sh", True)]),
 (". ops/x.sh", [("ops/x.sh", False)]),
 ("source ops/x.sh", [("ops/x.sh", False)]),
 ("cd ~/overnight-queue && ./gpu_autoswap.sh >> logs/x.log 2>&1", [("gpu_autoswap.sh", True)]),
 ("cd ~/overnight-queue && python3 a.py && ./b.sh", [("a.py", False), ("b.sh", True)]),
 ("nice -n 19 scripts/ovn_log_cap.sh", [("scripts/ovn_log_cap.sh", True)]),
 ("flock -n state/spec_gate.lock sh -c 'for r in a b; do OVN_X=shadow python3 scripts/ovn_spec_gate.py scan $r; done'", [("scripts/ovn_spec_gate.py", False)]),
 ("env FOO=1 ./e.sh", [("e.sh", True)]),
]
bad = [(l, got, want) for l, want in CASES for got in [m.script_tokens(l)] if got != want]
for b in bad: print("MISMATCH", b)
sys.exit(1 if bad else 0)
PYEOF
chk "script_tokens: interpreter flags, wrappers, bash -c payloads, sourcing and direct runs are classified right (14 cases)" python3 "$W/tok.py" "$PY"
F="$O/scripts/z_fixture_tool.py"; printf 'print(1)\n' > "$F"; chmod 644 "$F"; cp "$W/crontab.healthy" "$W/crontab.stub"; echo '5 * * * * cd ~/overnight-queue && nice -n 10 python3 -u scripts/z_fixture_tool.py update' >> "$W/crontab.stub"; bvrun --no-record
chk "e2e: a crontab line 'nice -n 10 python3 -u scripts/z_fixture_tool.py' on a mode-644 .py raises NO cron_script_not_exec (was a latent CRIT page)" hasnot "cron_script_not_exec:scripts/z_fixture_tool.py"
chk "  (control: the script is really seen by the checker: it is not 'missing' either)" hasnot "cron_script_missing:scripts/z_fixture_tool.py"
F="$O/ops/z_direct.sh"; printf '#!/bin/sh\ntrue\n' > "$F"; chmod 644 "$F"; cp "$W/crontab.healthy" "$W/crontab.stub"; echo '6 * * * * cd ~/overnight-queue && ./ops/z_direct.sh' >> "$W/crontab.stub"; bvrun --no-record
chk "e2e: the same line run DIRECTLY (./ops/z_direct.sh, mode 644) still raises cron_script_not_exec (the real check is intact)" has "cron_script_not_exec:ops/z_direct.sh"
rm -f "$F" "$O/scripts/z_fixture_tool.py"; cp "$W/crontab.healthy" "$W/crontab.stub"

# --- GPU window (art swap stops the 27B on purpose)
printf '%s\n' '#!/bin/sh' 'if [ -f "'"$W"'/pgrep.yes" ]; then exit 0; fi' 'exit 1' > "$W/bin/pgrep"; chmod 755 "$W/bin/pgrep"
printf 'shrike-litellm\tUp 8 days\n' > "$W/docker.out"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 14 * 3600)), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF
bvrun --no-record
chk "no art window, llama down: gpu:container_missing:shrike-llama is reported (the real failure still pages)" has "gpu:container_missing:shrike-llama"
chk "  and supply:explorer_stale (14h old row) is reported" has "supply:explorer_stale"
: > "$O/state/art_window.hold"; bvrun --no-record
chk "state/art_window.hold present (fresh): NO gpu:container_missing (the 27B is down on purpose)" hasnot "gpu:container_missing:shrike-llama"
chk "  and NO supply:explorer_stale (the explorer cannot run while the model is down)" hasnot "supply:explorer_stale"
chk "  and nothing else is flagged" only 0
rm -f "$O/state/art_window.hold"; : > "$O/state/coder_window.hold"; bvrun --no-record; chk "coder_window.hold is a window too" hasnot "gpu:container_missing:shrike-llama"; rm -f "$O/state/coder_window.hold"
: > "$W/pgrep.yes"; bvrun --no-record; chk "art_runner.py running (art.sh run does not create a hold file) is a window too" hasnot "gpu:container_missing:shrike-llama"; rm -f "$W/pgrep.yes"
: > "$O/state/art_window.hold"; python3 -c 'import os,sys,time; t=time.time()-13*3600; os.utime(sys.argv[1],(t,t))' "$O/state/art_window.hold"; bvrun --no-record
chk "a hold older than 12h is NOT a window: gpu:window_overlong is reported" has "gpu:window_overlong"
chk "  and the container check applies again (container_missing back)" has "gpu:container_missing:shrike-llama"
rm -f "$O/state/art_window.hold"
printf 'shrike-llama-dflash-35b\tUp 20 hours (healthy)\nshrike-litellm\tUp 8 days\nshrike-webui\tUp 8 days (healthy)\n' > "$W/docker.out"
python3 - "$O/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF

# --- refuel clock: only a real refuel commit counts (a git repo in the fixture queue tree)
# regression (box leak): a SOURCE tree that is itself a git repo with a fresh refuel commit must not leak that history into the fixture
SRC_LEAK="$W/srcleak"; mkdir -p "$SRC_LEAK"; echo x > "$SRC_LEAK/f"
( cd "$SRC_LEAK" && git init -q -b main . && git add f && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git commit -q -m "chore(roadmap): local research refuel leak-probe" ) >/dev/null 2>&1
copy_tree "$SRC_LEAK" "$W/dstleak"
chk "copy_tree strips the source's .git (a real refuel commit must not leak into the fixture)" test ! -e "$W/dstleak/.git"
chk "  and the file content was copied" test -f "$W/dstleak/f"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
( cd "$O" && git init -q -b main . && git add -A >/dev/null 2>&1 && git commit -q -m "chore: fixture tree" ) >/dev/null 2>&1
gcommit(){ ( cd "$O" && GIT_COMMITTER_DATE="$(( $(date +%s) - $1 * 3600 )) +0000" GIT_AUTHOR_DATE="$(( $(date +%s) - $1 * 3600 )) +0000" git commit -q --allow-empty -m "$2" ); }
gcommit 30 "chore(roadmap): auto-research 2026-10-17 - 3 ready feature(s) for xlite"
gcommit 1 "fix(auto-research): cover all active repos, tolerant reply parser"
gcommit 1 "feat(mac-jobs): live checkout isolation (auto-research launchd job)"
gcommit 1 "Merge origin/claude/feature (auto-research allowlist spelled once)"
starving 9.0; bvrun --no-record
chk "9h starving; the only recent commits MENTION auto-research (code/merge) and the last real refuel is 30h old -> supply:refuel_stalled" has "supply:refuel_stalled"
gcommit 2 "chore(roadmap): auto-research 2026-10-18 - 7 ready feature(s) for gitlark"
bvrun --no-record; chk "a real Mac refuel commit 2h ago ('chore(roadmap): auto-research ...') clears it" hasnot "supply:refuel_stalled"
( cd "$O" && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
bvrun --no-record; chk "  (control: with that commit dropped it stalls again)" has "supply:refuel_stalled"
gcommit 3 "chore(roadmap): local research refuel for xlite - 1 evidence-grounded item(s) (no Claude)"
bvrun --no-record; chk "the BOX's own 'local research refuel' commit 3h ago counts too (a lane fed by local research does not alert)" hasnot "supply:refuel_stalled"
( cd "$O" && git reset -q --hard HEAD~1 ) >/dev/null 2>&1
starving 9.0 5; bvrun --no-record
chk "research_trigger_starving.json last checked 5h ago (> 3h): supply:starving_report_stale (warn) instead of trusting its old hours" has "supply:starving_report_stale"
chk "  and no refuel_stalled is derived from stale data" hasnot "supply:refuel_stalled"
rm -f "$O/state/research_trigger_starving.json"; mv "$O/.git" "$W/qgit.gone"

# --- exception scope + own cron line (these run the COPY of box_verify.py inside the fixture tree, so the snapshot next to it can be edited)
PYCOPY="$O/ops/box_verify.py"; SNAP="$O/ops/crontab.box.snapshot.txt"; saveonce "$SNAP"
cp "$W/crontab.healthy" "$W/crontab.stub"
HB='53 6 * * * [ -n "$(find /run/media/x/box-backups/heartbeat-daily.log -mmin -1560 2>/dev/null)" ] || echo stale'
echo "$HB" >> "$SNAP"; echo "$HB" >> "$W/crontab.stub"; PY="$PYCOPY" bvrun --no-record
chk "control: a heartbeat line present in snapshot AND live is clean" only 0
grep -vF 'heartbeat-daily.log' "$W/crontab.stub" > "$W/crontab.stub2"; cp "$W/crontab.stub2" "$W/crontab.stub"; PY="$PYCOPY" bvrun --no-record
chk "the snapshot has the heartbeat line but the live crontab LOST it: cron_missing is reported, NOT accepted by the heartbeat cronline exception" haspre "cron_missing:"
rst "$SNAP"; saveonce "$SNAP"
cp "$W/crontab.healthy" "$W/crontab.stub"; PY="$PYCOPY" bvrun --no-record
chk "control: the box_verify line live but not in the snapshot is the accepted exception (0 drift, 1 accepted: that exception still works for cron_extra)" test "$(cnts)" = "0 1"
echo "$BVLINE" >> "$SNAP"; grep -vF 'box_verify.sh' "$W/crontab.healthy" > "$W/crontab.stub"; PY="$PYCOPY" bvrun --no-record
chk "live crontab has NO box_verify line: cron_line_missing:box_verify (the detector's own absence is flagged; the snapshot comparison alone would not see it)" has "cron_line_missing:box_verify"
chk "  and, with the line in the snapshot, cron_missing:box_verify.sh:* is reported too, NOT accepted by the box_verify cronline exception" haspre "cron_missing:box_verify.sh:"
rst "$SNAP"; cp "$W/crontab.healthy" "$W/crontab.stub"
bvrun --no-record; chk "restored: healthy again after the review-fix scenarios" only 0

echo "== a crashing check is loud, the others still run"
saveonce "$O/qa/qa_tool_health.py"; printf 'raise RuntimeError("boom")\n' > "$O/qa/qa_tool_health.py"; bvrun --no-record
chk "state check crashes -> check_error:state item (not a silent pass)" has "check_error:state"
chk "  the other checks still ran (11 checks reported)" python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); assert len(j["checks"])==11 and j["checks"]["state"]=="crashed", j["checks"]' "$W/out.json"
rst "$O/qa/qa_tool_health.py"

echo "== recording: alerts de-duplicated, notes for the ONE hourly update, modes, no-record, off"
rec(){ HOME="$H" BV_HOME="$H" BV_OVN="$O" BV_STATE="$O/state" BV_BACKUPS="$W/drive/box-backups" BV_CRONTAB_FILE="$W/crontab.stub" BV_PROC_MOUNTS="$W/mounts" BV_TMP="$W/tmp" BV_DISK_MAX_PCT=101 BV_INODE_MAX_PCT=101 PATH="$W/bin:$PATH" python3 -B "$PY" "$@" > "$W/out.json" 2> "$W/err.txt"; echo $? > "$W/rc"; }
AL="$O/state/alerts.log"; NT="$O/state/notify_notes.jsonl"; SL="$O/state/box_verify_shadow.log"; rm -f "$AL" "$NT" "$SL" "$O/state/box_verify.json" "$O/state/box_verify_state.json"
rm -f "$O/state/staging_url_gitlark" "$O/state/qa_creds/iptv_apps.json"; chmod 644 "$O/state/billwatch_db_url"
rec
chk "run 1 (shadow, 3 drift items): exactly 3 would-be alert lines in state/box_verify_shadow.log, level info, tagged box-verify" bash -c "[ \$(grep -c '| box-verify |' '$SL') = 3 ] && [ \$(grep -c '\] info | box-verify |' '$SL') = 3 ]"
chk "  SHADOW IS SILENT (incident review #3): no alerts.log line (queue.sh status/ack read it) and no hourly-digest note" bash -c "[ ! -e '$AL' ] && [ ! -e '$NT' ]"
chk "  one concise line per item: key, message, class, fix" bash -c "grep -q 'box-verify | state:staging_url_gitlark: .*\[human\] fix:' '$SL'"
chk "  state/box_verify.json written, mode shadow, 3 drift, valid JSON" python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); assert j["mode"]=="shadow" and j["counts"]["drift"]==3 and j["counts"]["new_alerts"]==3, j["counts"]' "$O/state/box_verify.json"
rec
chk "run 2 (nothing changed): NO new lines (de-duplicated)" bash -c "[ \$(grep -c '| box-verify |' '$SL') = 3 ] && [ ! -e '$AL' ] && [ ! -e '$NT' ]"
echo "https://gitlark-staging.example" > "$O/state/staging_url_gitlark"; chmod 600 "$O/state/billwatch_db_url"; rm -f "$O/state/staging_url_billwatch"
rec
chk "run 3 (one fixed, one NEW): only the NEW item alerts (4 lines total)" bash -c "[ \$(grep -c '| box-verify |' '$SL') = 4 ] && tail -1 '$SL' | grep -q 'state:staging_url_billwatch'"
echo "https://billwatch-staging.example" > "$O/state/staging_url_billwatch"; rec
rm -f "$O/state/staging_url_billwatch"; rec
chk "a key that cleared and then reappears alerts again at once (forgotten when it cleared)" bash -c "[ \$(grep -c 'state:staging_url_billwatch' '$SL') = 2 ]"
BV_NOW=$(python3 -c 'import time;print(int(time.time())+25*3600)') rec
chk "an unresolved key is re-announced after BV_REALERT_H (default 24h)" bash -c "[ \$(grep -c 'state:staging_url_billwatch' '$SL') = 3 ] && [ \$(grep -c 'state:qa_creds_iptv_apps' '$SL') = 2 ]"
chk "  (and shadow still wrote nothing to alerts.log / notes in any of those runs)" bash -c "[ ! -e '$AL' ] && [ ! -e '$NT' ]"
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify_state.json"; OVN_BOX_VERIFY=enforce rec
chk "enforce mode (2 human warn items + 1 crit): alerts.log level WARN / CRIT - checks identical, shadow log untouched" bash -c "grep -q '\] WARN | box-verify | state:staging_url_billwatch' '$AL' && grep -q '\] WARN | box-verify | state:qa_creds_iptv_apps' '$AL' && [ ! -e '$SL' ]" 
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify_state.json"; chmod 644 "$O/state/billwatch_db_url"; OVN_BOX_VERIFY=enforce rec
chk "enforce + a crit item (billwatch_db_url mode): CRIT line and ONE urgent note naming only the note-worthy item (human warn items never make a note)" bash -c "grep -q '\] CRIT | box-verify | state:billwatch_db_url_mode' '$AL' && python3 -c 'import json,sys; r=[json.loads(l) for l in open(sys.argv[1])]; assert len(r)==1 and r[0][\"prio\"]==\"urgent\" and r[0][\"title\"]==\"Box drift: 1 item\" and \"billwatch_db_url_mode\" in r[0][\"text\"] and \"staging_url\" not in r[0][\"text\"] and r[0][\"source\"]==\"box_verify\", r' '$NT'"
OVN_BOX_VERIFY=enforce rec
chk "  the note is refreshed every enforce run while a note-worthy item exists (each hourly update still lists it), the alert is not repeated" bash -c "[ \$(wc -l < '$NT' | tr -d ' ') = 2 ] && [ \$(grep -c 'billwatch_db_url_mode' '$AL') = 1 ]"
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify_state.json"; chmod 600 "$O/state/billwatch_db_url"; OVN_BOX_VERIFY=enforce rec
chk "enforce with ONLY class=human warn items outstanding: alerts.log lines yes, hourly-digest note NO (the digest stays 'all good')" bash -c "grep -q 'state:staging_url_billwatch' '$AL' && [ ! -e '$NT' ]"
chk "  proven end to end: ovn_notify compose_update on that state still says 'all good'" bash -c "cd '$O' && python3 -B -c \"import sys; sys.path.insert(0,'scripts'); import os; os.environ['OVN_NOTIFY_STATE']='$O/state'; import ovn_notify as n; t,b,c=n.compose_update(window=3600); print(t); assert 'all good' in t and c==0, (t,c)\" >/dev/null 2>&1"
chmod 644 "$O/state/billwatch_db_url"; rm -f "$AL" "$NT" "$SL" "$O/state/box_verify_state.json"; OVN_BOX_VERIFY=enforce rec; chmod 600 "$O/state/billwatch_db_url"
chk "the hourly update path picks the note up (ovn_notify.py compose_update lists 'Box drift')" bash -c "cd '$O' && OVN_NOTIFY_STATE='$O/state' python3 -B scripts/ovn_notify.py update --dry-run 2>&1 | grep -q 'Box drift'"
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify.json" "$O/state/box_verify_state.json"; cp -R "$O/state" "$W/state.before"
OVN_BOX_VERIFY=off rec
chk "OVN_BOX_VERIFY=off: prints mode off, writes NOTHING (no json, no alerts, no notes)" bash -c "grep -q '\"mode\": \"off\"' '$W/out.json' && [ ! -e '$AL' ] && [ ! -e '$SL' ] && [ ! -e '$NT' ] && [ ! -e '$O/state/box_verify.json' ]"
rec --no-record
chk "--no-record: reports drift on stdout but writes nothing" bash -c "[ ! -e '$AL' ] && [ ! -e '$SL' ] && [ ! -e '$NT' ] && [ ! -e '$O/state/box_verify.json' ] && grep -q '\"recorded\": false' '$W/out.json'"
rec --strict; chk "--strict exits 1 when drift exists" bash -c "[ \$(cat '$W/rc') = 1 ]"
rec; chk "default (cron) exit code is 0 even with drift" bash -c "[ \$(cat '$W/rc') = 0 ]"
chk "READ-ONLY: a --no-record run leaves the whole state dir byte-identical" bash -c "rm -f '$AL' '$NT' '$SL' '$O/state/box_verify.json' '$O/state/box_verify_state.json'; diff -r '$W/state.before' '$O/state' >/dev/null"
find "$O" -name __pycache__ -newer "$W/mounts" 2>/dev/null | grep -q . ; chk "no __pycache__ written into the queue tree by a run" test $? -eq 1

echo "== the shell wrapper"
HOME="$H" BV_HOME="$H" BV_OVN="$O" BV_STATE="$O/state" BV_BACKUPS="$W/drive/box-backups" BV_CRONTAB_FILE="$W/crontab.stub" BV_PROC_MOUNTS="$W/mounts" BV_TMP="$W/tmp" BV_DISK_MAX_PCT=101 BV_INODE_MAX_PCT=101 PATH="$W/bin:$PATH" bash "$BVSH" --no-record > "$W/w.out" 2>&1; wrc=$?
chk "box_verify.sh runs the checker and exits 0" bash -c "[ $wrc = 0 ] && grep -q '\"mode\": \"shadow\"' '$W/w.out'"
chk "box_verify.sh and box_verify.py are tracked executable (cron + test_cron_scripts_executable)" bash -c "[ -x '$OVN_REAL/ops/box_verify.sh' ] && [ -x '$OVN_REAL/ops/box_verify.py' ]"
chk "cron.proposed.txt carries the hourly box_verify line (shadow default, not installed by anything)" bash -c "grep -v '^#' '$OVN_REAL/ops/cron.proposed.txt' | grep -q 'ops/box_verify.sh'"

echo "== mutants: each edited copy of box_verify.py must make its guarding check FAIL"
mut(){ python3 - "$BVPY_REAL" "$1" "$2" "$3" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "anchor %r found %d" % (old, s.count(old))
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
cp "$W/crontab.healthy" "$W/crontab.stub"
# M1: exec-bit check removed
mut "$W/m1.py" 'elif direct and not os.access(p, os.X_OK):' 'elif False:' || ok "mutant1 anchor" 1
chmod -x "$O/gpu_autoswap.sh"; PY="$W/m1.py" bvrun --no-record; chmod +x "$O/gpu_autoswap.sh"; PY="$BVPY_REAL"
chk "MUTANT no exec-bit check is caught (cron_script_not_exec disappears)" hasnot "cron_script_not_exec:gpu_autoswap.sh"
# M2: xdist no longer required
mut "$W/m2.py" 'for n in ("pytest", "pytest-xdist"): need.setdefault' 'for n in ("pytest",): need.setdefault' || ok "mutant2 anchor" 1
mv "$S/pytest_xdist-1.0.dist-info" "$S/xx.gone"; sed -i.bak 's/^pytest-xdist.*$//' "$O/repos/billwatch/billwatch-backend/requirements-dev.txt"; PY="$W/m2.py" bvrun --no-record; mv "$S/xx.gone" "$S/pytest_xdist-1.0.dist-info"; mv "$O/repos/billwatch/billwatch-backend/requirements-dev.txt.bak" "$O/repos/billwatch/billwatch-backend/requirements-dev.txt"; PY="$BVPY_REAL"
chk "MUTANT xdist not required is caught (item disappears when xdist is absent)" hasnot "venv:billwatch:missing_pkg:pytest-xdist"
# M3: de-duplication removed (always alert)
mut "$W/m3.py" 'if not rec.get("alerted") or (realert > 0 and NOW - rec["alerted"] >= realert):' 'if True:' || ok "mutant3 anchor" 1
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify_state.json" "$O/state/staging_url_gitlark"
PY="$W/m3.py" rec; PY="$W/m3.py" rec; PY="$BVPY_REAL"; echo "https://gitlark-staging.example" > "$O/state/staging_url_gitlark"
chk "MUTANT no de-duplication is caught (the same key alerts twice)" bash -c "[ \$(grep -c 'state:staging_url_gitlark' '$SL') = 2 ]"
# M4: heartbeat age comparison inverted
mut "$W/m4.py" 'if age > mx:' 'if age < mx:' || ok "mutant4 anchor" 1
python3 -c 'import os,sys,time; t=time.time()-27*3600; os.utime(sys.argv[1],(t,t))' "$W/drive/box-backups/heartbeat-daily.log"; PY="$W/m4.py" bvrun --no-record; PY="$BVPY_REAL"; : > "$W/drive/box-backups/heartbeat-daily.log"
chk "MUTANT inverted heartbeat age is caught (stale heartbeat not reported)" hasnot "backup:daily_heartbeat_stale"
# M5: off mode still records
mut "$W/m5.py" 'if mode == "off":' 'if False:' || ok "mutant5 anchor" 1
rm -f "$O/state/box_verify.json"; OVN_BOX_VERIFY=off PY="$W/m5.py" rec
chk "MUTANT off-mode still records is caught (box_verify.json appears)" test -e "$O/state/box_verify.json"
rm -f "$O/state/box_verify.json"
# M6: enforce does not change severity
mut "$W/m6.py" 'level = ("CRIT" if it["sev"] == "crit" else "WARN") if mode == "enforce" else "info"' 'level = "info"' || ok "mutant6 anchor" 1
rm -f "$AL" "$NT" "$O/state/box_verify_state.json"; rm -f "$O/state/staging_url_gitlark"; OVN_BOX_VERIFY=enforce PY="$W/m6.py" rec; echo "https://gitlark-staging.example" > "$O/state/staging_url_gitlark"
chk "MUTANT enforce severity ignored is caught (no WARN line)" bash -c "! grep -q '\] WARN | box-verify' '$AL'"
# M7: a crashing check swallowed
mut "$W/m7.py" 'add("check_error:%s" % name, ' 'None and add("check_error:%s" % name, ' || ok "mutant7 anchor" 1
saveonce "$O/qa/qa_tool_health.py"; printf 'raise RuntimeError("boom")\n' > "$O/qa/qa_tool_health.py"; PY="$W/m7.py" bvrun --no-record; rst "$O/qa/qa_tool_health.py"; PY="$BVPY_REAL"
chk "MUTANT swallowed check crash is caught (check_error item disappears)" hasnot "check_error:state"
# M8: snapshot comparison never reports extras
mut "$W/m8.py" '("cron_extra", hc - wc,' '("cron_extra", Counter(),' || ok "mutant8 anchor" 1
cp "$W/crontab.healthy" "$W/crontab.stub"; echo '* * * * * /bin/true # hand edit' >> "$W/crontab.stub"; PY="$W/m8.py" bvrun --no-record; PY="$BVPY_REAL"; cp "$W/crontab.healthy" "$W/crontab.stub"
chk "MUTANT snapshot-extra comparison removed is caught" bash -c "! python3 -c 'import json;print(\"\\n\".join(i[\"key\"] for i in json.load(open(\"$W/out.json\"))[\"items\"]))' | grep -q '^cron_extra:'"


echo "== mutants for the L1 repair round (each must make its guarding scenario FAIL)"
cp "$W/crontab.healthy" "$W/crontab.stub"; PYM="$O/ops/bvm.py"
# R1: interpreter detection by the previous word only (the old behaviour)
mut "$PYM" '            interp = any(INTERP_RX.search(b) for b in seg[:i] if not b.startswith("-")) or (i > 0 and seg[i - 1] in (".", "source", "-m"))' '            interp = bool(i and INTERP_RX.search(seg[i - 1]))' || ok "mutant R1 anchor" 1
F="$O/scripts/z_fixture_tool.py"; printf 'print(1)\n' > "$F"; chmod 644 "$F"; echo '5 * * * * cd ~/overnight-queue && nice -n 10 python3 -u scripts/z_fixture_tool.py update' >> "$W/crontab.stub"; PY="$PYM" bvrun --no-record; rm -f "$F"; cp "$W/crontab.healthy" "$W/crontab.stub"
chk "MUTANT previous-word-only interpreter detection is caught (the CRIT false positive comes back for 'python3 -u x.py')" has "cron_script_not_exec:scripts/z_fixture_tool.py"
# R2: GPU window never recognised
mut "$PYM" '    if (_env("BV_GPU_WINDOW") or "on").lower() == "off":' '    if True:' || ok "mutant R2 anchor" 1
printf 'shrike-litellm\tUp 8 days\n' > "$W/docker.out"; : > "$O/state/art_window.hold"; PY="$PYM" bvrun --no-record; rm -f "$O/state/art_window.hold"
printf 'shrike-llama-dflash-35b\tUp 20 hours (healthy)\nshrike-litellm\tUp 8 days\nshrike-webui\tUp 8 days (healthy)\n' > "$W/docker.out"
chk "MUTANT GPU window ignored is caught (container_missing pages during the intentional art swap)" has "gpu:container_missing:shrike-llama"
# R3 / R4: refuel clock matches any mention / stale starving file trusted
mv "$W/qgit.gone" "$O/.git"
mut "$PYM" 'REFUEL_RX = re.compile(r"^chore\(roadmap\): (auto-research\b|local research refuel\b)")' 'REFUEL_RX = re.compile(r"auto-research")' || ok "mutant R3 anchor" 1
starving 9.0; PY="$PYM" bvrun --no-record
chk "MUTANT 'any commit that mentions auto-research resets the clock' is caught (refuel_stalled hidden by a code/merge commit)" hasnot "supply:refuel_stalled"
mut "$PYM" '    if doc is not None and NOW - checked > stale_h * 3600:' '    if False:' || ok "mutant R4 anchor" 1
starving 9.0 5; PY="$PYM" bvrun --no-record
chk "MUTANT starving file staleness not checked is caught (no supply:starving_report_stale)" hasnot "supply:starving_report_stale"
rm -f "$O/state/research_trigger_starving.json"; mv "$O/.git" "$W/qgit.gone"
# R5: cronline exceptions apply to cron_missing again
mut "$PYM" '        if why is None and it["key"].startswith("cron_extra:"):' '        if why is None and it["key"].startswith(("cron_missing:", "cron_extra:")):' || ok "mutant R5 anchor" 1
saveonce "$O/ops/crontab.box.snapshot.txt"; echo "$HB" >> "$O/ops/crontab.box.snapshot.txt"; cp "$W/crontab.healthy" "$W/crontab.stub"; PY="$PYM" bvrun --no-record
ok "MUTANT 'cronline exceptions also hide cron_missing' is caught (a lost heartbeat line is silently accepted: no cron_missing item under the mutant)" "$(haspre cron_missing: && echo 1 || echo 0)"
rst "$O/ops/crontab.box.snapshot.txt"
# R6: the detector's own cron line is no longer required
mut "$PYM" '    if not any("ops/box_verify.sh" in l or "ops/box_verify.py" in l for l in active(lines)):' '    if False:' || ok "mutant R6 anchor" 1
grep -vF 'box_verify.sh' "$W/crontab.healthy" > "$W/crontab.stub"; PY="$PYM" bvrun --no-record; cp "$W/crontab.healthy" "$W/crontab.stub"
chk "MUTANT 'box_verify not required in the crontab' is caught (its own absence is never flagged)" hasnot "cron_line_missing:box_verify"
# R7 / R8 / R9: shadow writes to alerts.log / writes notes / human warn items make notes in enforce
rshadow(){ rm -f "$AL" "$NT" "$SL" "$O/state/box_verify.json" "$O/state/box_verify_state.json"; rm -f "$O/state/staging_url_gitlark"; OVN_BOX_VERIFY="$1" PY="$PYM" rec; echo "https://gitlark-staging.example" > "$O/state/staging_url_gitlark"; }
mut "$PYM" 'append_line(os.path.join(STATE, "alerts.log" if mode == "enforce" else "box_verify_shadow.log"), line)' 'append_line(os.path.join(STATE, "alerts.log"), line)' || ok "mutant R7 anchor" 1
rshadow shadow
chk "MUTANT shadow alerts into alerts.log is caught (queue.sh status/ack would show the info lines)" test -s "$AL"
mut "$PYM" '    noted = [i for i in items if i["sev"] == "crit" or i["class"] != "human"] if mode == "enforce" else []' '    noted = [i for i in items if i["sev"] == "crit" or i["class"] != "human"] if True else []' || ok "mutant R8 anchor" 1
chmod 644 "$O/state/billwatch_db_url"; rshadow shadow; chmod 600 "$O/state/billwatch_db_url"
chk "MUTANT shadow writes hourly-digest notes is caught (a crit item makes a note in shadow)" test -s "$NT"
mut "$PYM" '    noted = [i for i in items if i["sev"] == "crit" or i["class"] != "human"] if mode == "enforce" else []' '    noted = list(items) if mode == "enforce" else []' || ok "mutant R9 anchor" 1
rshadow enforce
chk "MUTANT human warn items make notes in enforce is caught (the digest would stay at warning until a human supplies secrets)" test -s "$NT"
rm -f "$AL" "$NT" "$SL" "$O/state/box_verify.json" "$O/state/box_verify_state.json" "$PYM"

echo "test_box_verify: $((n-fails)) passed, $fails failed"
[ "$fails" = 0 ]
