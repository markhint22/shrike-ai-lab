#!/usr/bin/env bash
# test_qa_install_tools_cron.sh - package Q1: ops/install_qa_tools.sh + ops/install_qa_cron.sh + ops/cron.qa.proposed.txt.
# Hermetic: every scenario gets its own sandbox dir from lib_safe_tmp.sh and a sandbox HOME; pip is a stub, gitleaks a fixture tarball, crontab a stub file on PATH.
# Nothing touches the real home, the real crontab or the network. Each MUTANT (a sed-style edit of a copy of an installer) must make exactly the scenario that guards that behaviour FAIL.
# Linux (bwrap) behaviour: run this same file inside scripts/test/run_all_sandboxed.sh with OVN_SANDBOX_TEST_HOOKS=1 OVN_SANDBOX_TARGET=<wrapper>; it needs only sha256sum/tar/crontab-less stubs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OVN_REAL="$(cd "$HERE/../.." && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib_safe_tmp.sh" || exit 1
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
[ -n "$PY" ] || { echo "  SKIP: no python3"; exit 0; }
ROOT="$(safe_mktemp_dir qa_itc)" || exit 1
fails=0; n=0
ok(){ n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk(){ local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
case "$(uname -s)-$(uname -m)" in Linux-x86_64) GA=linux_x64;; Linux-aarch64|Linux-arm64) GA=linux_arm64;; Darwin-arm64) GA=darwin_arm64;; Darwin-x86_64) GA=darwin_x64;; *) GA=none;; esac

# ---------------------------------------------------------------- shared fixtures
FX="$ROOT/fx"; mkdir -p "$FX" "$FX/gl"
cat > "$FX/pipstub.sh" <<'EOF'
#!/bin/sh
# fake `pip install`: $1 = venv bin dir, rest = name==ver specs. Logs every call, writes a tool that prints its version.
bin="$1"; shift
for spec in "$@"; do
  name="${spec%%==*}"; ver="${spec#*==}"
  echo "$spec" >> "${STUB_LOG:?}"
  case " ${STUB_FAIL_INSTALL:-} " in *" $name "*) echo "stub: cannot install $name" >&2; exit 1;; esac
  case " ${STUB_BROKEN:-} " in *" $name "*) printf '#!/bin/sh\necho "boom: broken wheel" >&2\nexit 1\n' > "$bin/$name";;
    *) case "$name" in
         semgrep) printf '#!/bin/sh\necho "%s"\n' "$ver" > "$bin/$name";;
         mutmut) printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Error: no source paths" >&2; exit 1; }\necho "mutmut help"\n' > "$bin/$name";;   # mutmut 3.x: no version flag, even --help needs a project config
         *) printf '#!/bin/sh\necho "%s %s"\n' "$name" "$ver" > "$bin/$name";; esac;; esac
  chmod 755 "$bin/$name"
  # the mutmut probe imports mutmut + libcst with the venv python: a healthy stub provides both, a STUB_BROKEN one does not
  case " ${STUB_BROKEN:-} " in *" $name "*) ;; *) if [ "$name" = mutmut ]; then for sp in "$bin"/../lib/python*/site-packages; do [ -d "$sp" ] && { mkdir -p "$sp/mutmut" "$sp/libcst"; : > "$sp/mutmut/__init__.py"; : > "$sp/libcst/__init__.py"; }; done; fi;; esac
  for sp in "$bin"/../lib/python*/site-packages; do [ -d "$sp" ] && { nn="$(printf %s "$name" | tr - _)"; mkdir -p "$sp/$nn-$ver.dist-info"; printf 'Metadata-Version: 2.1\nName: %s\nVersion: %s\n' "$name" "$ver" > "$sp/$nn-$ver.dist-info/METADATA"; }; done
done
EOF
chmod 755 "$FX/pipstub.sh"
mk_gitleaks_fx(){ # $1=dir $2=content-tag -> a gitleaks tarball + checksums file whose checksum matches; echoes the sha
  local d="$1" tag="$2" w; w="$(safe_mktemp_dir_in "$ROOT" glw)" || return 1
  printf '#!/bin/sh\necho 8.18.4 %s\n' "$tag" > "$w/gitleaks"; chmod 755 "$w/gitleaks"
  tar -czf "$d/gitleaks_8.18.4_${GA}.tar.gz" -C "$w" gitleaks
  local s; s="$(sha "$d/gitleaks_8.18.4_${GA}.tar.gz")"
  printf '%s  gitleaks_8.18.4_%s.tar.gz\n' "$s" "$GA" > "$d/gitleaks_8.18.4_checksums.txt"
  safe_rm_rf "$w"; echo "$s"; }
GL_SHA="$(mk_gitleaks_fx "$FX/gl" good)"

new_home(){ # -> sets SB (scenario dir) and exports a sandbox HOME inside it
  SB="$(safe_mktemp_dir_in "$ROOT" sc)" || { echo "no sandbox"; exit 1; }
  safe_set_sandbox_home "$SB" || exit 1
  mkdir -p "$SB/bin" "$SB/ovn"; : > "$SB/stub.log"
}
tools(){ # run the tools installer: SCRIPT=$1 rest=args
  local s="$1"; shift
  QA_TOOLS_TEST_HOOKS=1 QA_TOOLS_PIP_STUB="$FX/pipstub.sh" QA_TOOLS_GITLEAKS_DIR="${GLDIR:-$FX/gl}" QA_TOOLS_GITLEAKS_SHA256="${GLSHA:-$GL_SHA}" QA_TOOLS_PYTHON="$PY" STUB_LOG="$SB/stub.log" \
    bash "$s" "$@"; }

# ================================================================ scenarios (each returns 0 only when ALL its assertions hold; reused for the mutants)
sc_tools_happy(){ # $1 = installer script. dry-run, check, apply, manifest, links, idempotence
  local S="$1" bad=0 out rc m1 m2 t
  new_home
  out="$(tools "$S" --dry-run 2>&1)"; rc=$?; [ $rc = 0 ] && [ ! -e "$HOME/qa-venv" ] && case "$out" in *"would pip-install"*) ;; *) bad=1;; esac || bad=1
  tools "$S" --check >/dev/null 2>&1; [ $? = 1 ] || bad=1                      # nothing installed -> check must say NOT ok
  out="$(tools "$S" 2>&1)"; rc=$?; [ $rc = 0 ] || { bad=1; echo "$out" | tail -5 >&2; }
  for t in bandit semgrep pip-audit mutmut schemathesis mypy ruff gitleaks; do [ -x "$HOME/qa-venv/bin/$t" ] || bad=1; [ "$(readlink "$HOME/bin/$t")" = "$HOME/qa-venv/bin/$t" ] || bad=1; done
  tools "$S" --check >/dev/null 2>&1 || bad=1
  "$PY" -I - "$HOME/qa-venv/qa_tools_manifest.json" <<'EOF' || bad=1
import json, sys
m = json.load(open(sys.argv[1]))
assert set(m["tools"]) == {"bandit","semgrep","pip-audit","mutmut","schemathesis","mypy","ruff","gitleaks"}, m["tools"].keys()
assert all(v["status"] == "ok" and v["pin"] and v["sha256"] and v["probe_output"] and v["version"] == v["pin"] for v in m["tools"].values()), m["tools"]
assert m["tools"]["bandit"]["pin"] == "1.8.6" and m["tools"]["gitleaks"]["pin"] == "8.18.4"
EOF
  [ -L "$HOME/qa-venv/bin/semgrep" ] && [ "$(readlink "$HOME/qa-venv/bin/semgrep")" = "../.isolated/semgrep/bin/semgrep" ] && [ -x "$HOME/qa-venv/.isolated/semgrep/bin/semgrep" ] || bad=1   # conflicting deps: own venv
  ls "$HOME"/qa-venv/lib/python*/site-packages 2>/dev/null | grep -q '^semgrep-' && bad=1                                                          # not in the shared venv
  [ -d "$HOME/qa-venv/.isolated/semgrep/lib" ] || bad=1
  m1="$(sha "$HOME/qa-venv/qa_tools_manifest.json")"; : > "$SB/stub.log"
  out="$(tools "$S" 2>&1)"; rc=$?; m2="$(sha "$HOME/qa-venv/qa_tools_manifest.json")"
  [ $rc = 0 ] && [ "$m1" = "$m2" ] && [ ! -s "$SB/stub.log" ] || bad=1             # idempotent: no pip call, manifest untouched
  case "$out" in *installing*|*"installed ("*) bad=1;; esac
  return $bad; }
sc_tools_wrong_version(){ local S="$1" bad=0 out
  new_home; tools "$S" >/dev/null 2>&1 || bad=1; : > "$SB/stub.log"
  QA_PIN_BANDIT=9.9.9 tools "$S" --check >/dev/null 2>&1; [ $? = 1 ] || bad=1      # installed 1.8.6 != pin 9.9.9
  QA_PIN_BANDIT=9.9.9 tools "$S" >/dev/null 2>&1 || bad=1
  [ "$(cat "$SB/stub.log")" = "bandit==9.9.9" ] || bad=1                           # only the drifted tool is reinstalled
  "$HOME/qa-venv/bin/bandit" --version | grep -q 9.9.9 || bad=1
  return $bad; }
sc_tools_broken(){ local S="$1" bad=0 out rc
  new_home
  out="$(STUB_BROKEN="semgrep" tools "$S" 2>&1)"; rc=$?
  [ $rc = 1 ] || bad=1; case "$out" in *"semgrep"*"broken"*) ;; *) bad=1;; esac
  STUB_BROKEN="semgrep" tools "$S" --check >/dev/null 2>&1; [ $? = 1 ] || bad=1
  grep -q '"semgrep": {"pin": "1.181.0", "status": "broken"' "$HOME/qa-venv/qa_tools_manifest.json" || bad=1
  [ -x "$HOME/qa-venv/bin/bandit" ] || bad=1                                        # one failed tool does not block the others
  return $bad; }
sc_tools_gitleaks_pin(){ local S="$1" bad=0 out rc gd
  new_home; gd="$SB/gl"; mkdir -p "$gd"; mk_gitleaks_fx "$gd" evil >/dev/null
  # tarball is internally consistent with its checksums file, but is NOT the pinned artifact -> must be refused
  out="$(GLDIR="$gd" tools "$S" 2>&1)"; rc=$?
  [ $rc = 1 ] || bad=1; [ ! -e "$HOME/qa-venv/bin/gitleaks" ] || bad=1; case "$out" in *"CHECKSUM MISMATCH vs the pin"*) ;; *) bad=1;; esac
  return $bad; }
sc_tools_gitleaks_release(){ local S="$1" bad=0 out rc gd s
  new_home; gd="$SB/gl"; mkdir -p "$gd"; s="$(mk_gitleaks_fx "$gd" pinned)"
  printf '%s  gitleaks_8.18.4_%s.tar.gz\n' "0000000000000000000000000000000000000000000000000000000000000000" "$GA" > "$gd/gitleaks_8.18.4_checksums.txt"
  # matches the pin we hand it, but the release checksums file disagrees -> refuse
  out="$(GLDIR="$gd" GLSHA="$s" tools "$S" 2>&1)"; rc=$?
  [ $rc = 1 ] || bad=1; [ ! -e "$HOME/qa-venv/bin/gitleaks" ] || bad=1; case "$out" in *"vs the release checksums file"*) ;; *) bad=1;; esac
  return $bad; }
sc_tools_refusals(){ local S="$1" bad=0 rc
  new_home
  QA_VENV="$HOME" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1                          # venv == HOME
  QA_VENV="$SB/outside-venv" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1               # outside HOME (HOME is $SB/home)
  QA_BIN="$HOME" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1
  QA_VENV="$HOME/overnight-queue/repos/x/.venv" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1
  mkdir -p "$HOME/real"; ln -s "$HOME/real" "$HOME/linkvenv"
  QA_VENV="$HOME/linkvenv" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1               # leaf is a symlink
  QA_VENV="$HOME/v" QA_BIN="$HOME/v" tools "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1
  env HOME=/ QA_TOOLS_TEST_HOOKS=1 bash "$S" --check >/dev/null 2>&1; [ $? = 2 ] || bad=1
  return $bad; }
sc_tools_link_conflict(){ local S="$1" bad=0 out rc
  new_home; mkdir -p "$HOME/bin"; printf 'mine\n' > "$HOME/bin/ruff"
  out="$(tools "$S" 2>&1)"; rc=$?
  [ $rc = 0 ] || bad=1; [ "$(cat "$HOME/bin/ruff")" = mine ] || bad=1; case "$out" in *WARNING*"ruff"*) ;; *) bad=1;; esac
  [ -L "$HOME/bin/bandit" ] || bad=1
  return $bad; }
sc_tools_hooks_off(){ local S="$1" bad=0 rc fp
  new_home; fp="$SB/fakepython"
  # a fake python whose `-m venv DIR` makes DIR/bin/python = a script that always fails (so the REAL pip path fails offline and instantly)
  cat > "$fp" <<'FAKEPY'
#!/bin/sh
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then d=""; for a in "$@"; do d="$a"; done; mkdir -p "$d/bin"; printf '#!/bin/sh\nexit 1\n' > "$d/bin/python"; chmod 755 "$d/bin/python"; exit 0; fi
exit 1
FAKEPY
  chmod 755 "$fp"
  # QA_TOOLS_PIP_STUB is a test hook: WITHOUT QA_TOOLS_TEST_HOOKS=1 it is ignored (the real pip path runs and fails), so the stub is never called
  QA_TOOLS_PIP_STUB="$FX/pipstub.sh" QA_TOOLS_PYTHON="$fp" STUB_LOG="$SB/stub.log" bash "$S" --no-link >/dev/null 2>&1; rc=$?
  [ $rc != 0 ] || bad=1; [ ! -s "$SB/stub.log" ] || bad=1
  return $bad; }

# ---------------------------------------------------------------- cron fixtures
cron_fx(){ # new_home + stub crontab + fixture OVN dir holding the scripts the proposal names
  new_home; QS_STORE="$SB/store"; export QS_STORE
  cat > "$SB/bin/crontab" <<'EOF'
#!/bin/sh
S="${QS_STORE:?}"
if [ "$1" = "-l" ]; then
  [ -n "${QS_FAIL:-}" ] && { echo "crontab: boom" >&2; exit 2; }
  [ -f "$S" ] || { echo "no crontab for tester" >&2; exit 1; }
  cat "$S"; exit 0
fi
[ -n "${QS_WRITE_FAIL:-}" ] && { echo "crontab: write error" >&2; exit 1; }
cp "$1" "$S"
if [ -n "${QS_CORRUPT:-}" ] && [ ! -f "$S.once" ]; then echo "# corrupted by cron" >> "$S"; : > "$S.once"; fi
exit 0
EOF
  chmod 755 "$SB/bin/crontab"
  mkdir -p "$SB/ovn/qa"
  for f in qa_tool_health.py soak_probe_cron.sh contract_fuzz_cron.sh phase5_cron.sh promote_manifest.py card_pilot_run.py card_pilot_report.py; do : > "$SB/ovn/qa/$f"; done
  CRON_PATH="$SB/bin:$PATH"
  printf '%s\n' '# my crontab' 'NTFY_SERVER=http://127.0.0.1:8099' '*/10 * * * * echo hi >> /tmp/x.log' '' '# trailing comment' > "$SB/orig"
  cp "$SB/orig" "$SB/store"
}
cron(){ local s="$1"; shift; PATH="$CRON_PATH" OVN_DIR="$SB/ovn" bash "$s" "$@"; }
nbk(){ ls "$HOME/crontab-backups" 2>/dev/null | wc -l | tr -d ' '; }

sc_cron_dry_default(){ local S="$1" bad=0 out rc
  cron_fx
  out="$(cron "$S" --file "$ROOT/../x" 2>&1)"; [ $? = 2 ] || bad=1                                  # missing proposal file refuses
  out="$(cron "$S" 2>&1)"; rc=$?
  [ $rc = 0 ] || bad=1; case "$out" in *"DRY RUN"*) ;; *) bad=1;; esac
  cmp -s "$SB/store" "$SB/orig" || bad=1; [ "$(nbk)" = 0 ] || bad=1                                 # dry run: crontab untouched, no backup
  return $bad; }
sc_cron_apply(){ local S="$1" bad=0 out rc bk
  cron_fx
  out="$(cron "$S" --apply 2>&1)"; rc=$?; [ $rc = 0 ] || { bad=1; echo "$out" | tail -4 >&2; }
  [ "$(nbk)" = 1 ] || bad=1; bk="$(ls "$HOME"/crontab-backups/* 2>/dev/null | head -1)"
  [ -n "$bk" ] && cmp -s "$bk" "$SB/orig" || bad=1                                                  # backup is byte-identical to the previous crontab
  case "$(ls -l "$bk" 2>/dev/null | cut -c1-10)" in -rw-------) ;; *) bad=1;; esac
  head -5 "$SB/store" | cmp -s - "$SB/orig" || bad=1                                                # every outside byte kept, in place
  grep -q '^# >>> QA-GATES BEGIN' "$SB/store" && grep -q '^# <<< QA-GATES END <<<$' "$SB/store" || bad=1
  for k in qa/qa_tool_health.py qa/soak_probe_cron.sh qa/phase5_cron.sh qa/promote_manifest.py; do grep -q "^[^#].*$k" "$SB/store" || bad=1; done
  grep -q '^#OFF# 20 4 .*qa/contract_fuzz_cron.sh' "$SB/store" || bad=1                              # contract_fuzz waits for the reviewed baseline: installed OFF
  grep -q '^[^#].*contract_fuzz_cron' "$SB/store" && bad=1
  grep -q '^#OFF# 35 3 .*qa/card_pilot_run.py' "$SB/store" || bad=1                                 # off-by-default stays commented
  grep -q '^[^#].*card_pilot_run' "$SB/store" && bad=1
  return $bad; }
sc_cron_idempotent(){ local S="$1" bad=0 out
  cron_fx; cron "$S" --apply >/dev/null 2>&1 || bad=1; cp "$SB/store" "$SB/after1"
  out="$(cron "$S" --apply 2>&1)"; case "$out" in *"no change"*) ;; *) bad=1;; esac
  cmp -s "$SB/store" "$SB/after1" || bad=1; [ "$(nbk)" = 1 ] || bad=1                               # no second backup either
  [ "$(grep -c 'QA-GATES BEGIN' "$SB/store")" = 1 ] || bad=1
  return $bad; }
sc_cron_enable(){ local S="$1" bad=0
  cron_fx; cron "$S" --apply >/dev/null 2>&1 || bad=1
  cron "$S" --apply --enable card_pilot >/dev/null 2>&1 || bad=1
  grep -q '^35 3 .*card_pilot_run.py' "$SB/store" || bad=1; grep -q '^#OFF# 50 7' "$SB/store" || bad=1
  cron "$S" --apply >/dev/null 2>&1 || bad=1; grep -q '^35 3 .*card_pilot_run.py' "$SB/store" || bad=1   # a plain refresh keeps it on
  cron "$S" --apply --disable card_pilot >/dev/null 2>&1 || bad=1; grep -q '^#OFF# 35 3' "$SB/store" || bad=1
  cron "$S" --enable nosuchid >/dev/null 2>&1; [ $? = 2 ] || bad=1
  return $bad; }
sc_cron_refuse_list_fail(){ local S="$1" bad=0 out rc
  cron_fx
  QS_FAIL=1 cron "$S" --apply >/dev/null 2>&1; rc=$?; [ $rc = 2 ] || bad=1
  cmp -s "$SB/store" "$SB/orig" || bad=1; [ "$(nbk)" = 0 ] || bad=1
  safe_rm_rf "$SB/store"                                                                                  # no crontab at all: refuse too ...
  cron "$S" --apply >/dev/null 2>&1; [ $? = 2 ] || bad=1; [ ! -f "$SB/store" ] || bad=1
  cron "$S" --apply --allow-empty >/dev/null 2>&1; [ $? = 0 ] || bad=1; grep -q 'QA-GATES BEGIN' "$SB/store" || bad=1   # ... unless explicitly allowed
  return $bad; }
sc_cron_dup_guard(){ local S="$1" bad=0
  cron_fx; printf '%s\n' '15 * * * * cd ~/overnight-queue && bash qa/soak_probe_cron.sh >> logs/x.log 2>&1' '# 41 * * * * bash qa/phase5_cron.sh' >> "$SB/store"
  cp "$SB/store" "$SB/orig2"
  cron "$S" --apply >/dev/null 2>&1 || bad=1
  [ "$(grep -c 'qa/soak_probe_cron.sh' "$SB/store")" = 1 ] || bad=1                                  # the hand-installed line is the only one
  grep -q '^41 \* .*phase5_cron.sh' "$SB/store" || bad=1                                       # a commented outside line does NOT count
  return $bad; }
sc_cron_lint(){ local S="$1" bad=0 i p line rc
  cron_fx
  i=0
  for line in \
    '0 * * * * cd $HOME/overnight-queue && OVN_QA_WIP_CAP=enforce python3 qa/qa_tool_health.py' \
    '0 * * * * cd $HOME/overnight-queue && OVN_QA_WIP_CAP=hard python3 qa/qa_tool_health.py' \
    '0 * * * * cd $HOME/overnight-queue && python3 qa/contract_fuzz.py check --accept-baseline' \
    '0 * * * * sudo python3 qa/qa_tool_health.py' \
    '0 * * * * rm -rf $HOME/x; python3 qa/qa_tool_health.py' \
    '0 * * * * bash scripts/test/run_all.sh; python3 qa/qa_tool_health.py' \
    '0 * * * * date +%F >> x; python3 qa/qa_tool_health.py' \
    '0 * * * * ./queue.sh pause; python3 qa/qa_tool_health.py' \
    '0 * * * * git push origin HEAD; python3 qa/qa_tool_health.py' \
    '0 * * * * kill 123; python3 qa/qa_tool_health.py' \
    '0 * * * * pkill -f llama; python3 qa/qa_tool_health.py' \
    '0 * * * * docker ps; python3 qa/qa_tool_health.py' \
    '0 * * * * OVN_ALLOW_UNSANDBOXED=1 python3 qa/qa_tool_health.py' \
    '0 * * * * python3 qa/contract_fuzz.py check --apply' \
    '0 * * * * crontab -r; python3 qa/qa_tool_health.py' \
    '0 * * * * bash scripts/test/run_all_sandboxed.sh; python3 qa/qa_tool_health.py' \
    'not a cron line python3 qa/qa_tool_health.py'; do
    i=$((i+1)); p="$SB/bad$i.txt"; printf '#@id t%s\n%s\n' "$i" "$line" > "$p"
    cron "$S" --apply --file "$p" >/dev/null 2>&1; rc=$?; [ $rc = 2 ] || { bad=1; echo "lint hole: $line" >&2; }
  done
  printf '%s\n' '0 * * * * python3 qa/qa_tool_health.py' > "$SB/noid.txt"; cron "$S" --apply --file "$SB/noid.txt" >/dev/null 2>&1; [ $? = 2 ] || bad=1
  printf '%s\n' '#@id a' '0 * * * * python3 qa/qa_tool_health.py' '#@id a' '1 * * * * python3 qa/qa_tool_health.py' > "$SB/dup.txt"; cron "$S" --apply --file "$SB/dup.txt" >/dev/null 2>&1; [ $? = 2 ] || bad=1
  cmp -s "$SB/store" "$SB/orig" || bad=1; [ "$(nbk)" = 0 ] || bad=1                                  # every refusal left the crontab alone
  return $bad; }
sc_cron_missing_script(){ local S="$1" bad=0 out
  cron_fx; rm -f "$SB/ovn/qa/phase5_cron.sh"
  out="$(cron "$S" --apply 2>&1)"; [ $? = 0 ] || bad=1
  case "$out" in *"SKIP phase5_wip_cap_gpu_ledger"*) ;; *) bad=1;; esac
  grep -q 'qa/phase5_cron.sh' "$SB/store" && bad=1
  grep -q 'qa/qa_tool_health.py' "$SB/store" || bad=1
  return $bad; }
sc_cron_write_fail(){ local S="$1" bad=0 rc
  cron_fx
  QS_WRITE_FAIL=1 cron "$S" --apply >/dev/null 2>&1; rc=$?; [ $rc = 1 ] || bad=1
  cmp -s "$SB/store" "$SB/orig" || bad=1; [ "$(nbk)" = 1 ] || bad=1                                  # the backup was taken first
  return $bad; }
sc_cron_readback(){ local S="$1" bad=0 rc
  cron_fx
  QS_CORRUPT=1 cron "$S" --apply >/dev/null 2>&1; rc=$?; [ $rc = 1 ] || bad=1                        # installed crontab differs from what was written
  cmp -s "$SB/store" "$SB/orig" || bad=1                                                             # ... and the original was restored
  return $bad; }
sc_cron_remove(){ local S="$1" bad=0
  cron_fx; cron "$S" --apply >/dev/null 2>&1 || bad=1
  cron "$S" --apply --remove >/dev/null 2>&1 || bad=1
  cmp -s "$SB/store" "$SB/orig" || bad=1                                                             # removal restores the exact original text
  grep -q 'QA-GATES' "$SB/store" && bad=1
  return $bad; }
sc_cron_disable_persists(){ local S="$1" bad=0 id
  cron_fx; cron "$S" --apply >/dev/null 2>&1 || bad=1
  cron "$S" --apply --disable tool_health >/dev/null 2>&1 || bad=1
  grep -q '^#OFF# .*qa/qa_tool_health.py' "$SB/store" || bad=1
  cron "$S" --apply >/dev/null 2>&1 || bad=1                                                         # a plain refresh keeps a default-on line DISABLED
  grep -q '^#OFF# .*qa/qa_tool_health.py' "$SB/store" || bad=1; grep -q '^[^#].*qa_tool_health.py' "$SB/store" && bad=1
  grep -q '^[^#].*qa/soak_probe_cron.sh' "$SB/store" || bad=1                                        # the other default-on lines are untouched
  cron "$S" --apply --enable tool_health >/dev/null 2>&1 || bad=1                                    # --enable turns it back on, and that persists
  grep -q '^[^#].*qa_tool_health.py' "$SB/store" || bad=1
  cron "$S" --apply >/dev/null 2>&1; grep -q '^[^#].*qa_tool_health.py' "$SB/store" || bad=1
  return $bad; }
sc_cron_remove_exact(){ local S="$1" bad=0 tail
  for tail in "" "\n" "\n\n"; do                                                                    # original ends with 0, 1, 2 blank lines
    cron_fx; printf "$tail" >> "$SB/store"; cp "$SB/store" "$SB/orig"
    cron "$S" --apply >/dev/null 2>&1 || bad=1
    cron "$S" --apply >/dev/null 2>&1; cron "$S" --apply --remove >/dev/null 2>&1 || bad=1
    cmp -s "$SB/store" "$SB/orig" || { bad=1; echo "remove not byte-exact for tail '$tail'" >&2; }
  done
  return $bad; }
sc_cron_markers(){ local S="$1" bad=0 out
  cron_fx; printf '%s\n' '# >>> QA-GATES BEGIN hand edited' '0 * * * * echo x' >> "$SB/store"; cp "$SB/store" "$SB/orig2"
  out="$(cron "$S" --apply 2>&1)"; [ $? = 2 ] || bad=1; cmp -s "$SB/store" "$SB/orig2" || bad=1     # BEGIN without END
  case "$out" in *"unbalanced"*) ;; *) bad=1;; esac
  return $bad; }
sc_cron_backup_dir(){ local S="$1" bad=0
  cron_fx
  QA_CRON_BACKUP_DIR="$SB/elsewhere" cron "$S" --apply >/dev/null 2>&1; [ $? = 2 ] || bad=1          # outside HOME ($SB/home)
  QA_CRON_BACKUP_DIR="$HOME" cron "$S" --apply >/dev/null 2>&1; [ $? = 2 ] || bad=1
  cmp -s "$SB/store" "$SB/orig" || bad=1
  return $bad; }
sc_cron_real_proposal(){ local S="$1" bad=0 out f
  new_home; mkdir -p "$SB/bin"; QS_STORE="$SB/store"; export QS_STORE;
  # the REAL proposal against the REAL qa/ tree: every referenced script exists and passes the shadow-only lint
  cat > "$SB/bin/crontab" <<'EOF'
#!/bin/sh
S="${QS_STORE:?}"; if [ "$1" = "-l" ]; then [ -f "$S" ] && cat "$S" || { echo "no crontab for t" >&2; exit 1; }; exit 0; fi; cp "$1" "$S"
EOF
  chmod 755 "$SB/bin/crontab"; : > "$SB/store"
  out="$(PATH="$SB/bin:$PATH" OVN_DIR="$OVN_REAL" bash "$S" 2>&1)"; [ $? = 0 ] || { bad=1; echo "$out" | tail -5 >&2; }
  case "$out" in *SKIP*) bad=1; echo "a proposed script is missing from the repo: $out" >&2;; esac
  for f in tool_health soak_probe contract_fuzz phase5_wip_cap_gpu_ledger promote_manifest card_pilot card_pilot_report; do case "$out" in *"$f"*) ;; *) bad=1;; esac; done
  return $bad; }

sc_cron_proposal_pins(){ local S="$1" bad=0 P PR line scope man promo r
  # the proposal next to the installer under test (mutants get a mutated copy) must keep: (1) the phase5 WIP-cap scope, (2) that scope == the promote_manifest repo loop,
  # (3) both inside the repos daily_promote.sh really promotes (OVN_PROMOTE_REPOS default), (4) contract_fuzz installed OFF until the reviewed baseline
  P="$(dirname "$S")/cron.qa.proposed.txt"; PR="$OVN_REAL/daily_promote.sh"
  line="$(grep -E '^[^#].*qa/phase5_cron\.sh' "$P")"
  scope="$(printf '%s\n' "$line" | sed -n 's/.*OVN_QA_WIP_CAP_SCOPE=\([A-Za-z0-9._,-]*\).*/\1/p')"
  [ -n "$scope" ] || { echo "phase5 line has no OVN_QA_WIP_CAP_SCOPE: $line" >&2; return 1; }
  man="$(grep -E '^[^#].*promote_manifest\.py' "$P" | sed -n 's/.*for r in \([A-Za-z0-9._ -]*\); do.*/\1/p' | tr ' ' '\n' | sort | paste -sd, -)"
  [ "$(printf '%s' "$scope" | tr ',' '\n' | sort | paste -sd, -)" = "$man" ] || { echo "WIP-cap scope [$scope] != promote_manifest loop [$man]" >&2; bad=1; }
  promo="$(sed -n 's/^REPOS="${OVN_PROMOTE_REPOS:-\(.*\)}"$/\1/p' "$PR")"; [ -n "$promo" ] || { echo "cannot read the daily_promote.sh default repo list" >&2; return 1; }
  for r in $(printf '%s' "$scope" | tr ',' ' '); do case " $promo " in *" $r "*) ;; *) echo "scope repo $r is not promoted by daily_promote.sh [$promo]" >&2; bad=1;; esac; done
  grep -q '^#@id contract_fuzz off$' "$P" || { echo "contract_fuzz is not installed OFF" >&2; bad=1; }
  return $bad; }

# ================================================================ run: real scripts
TS="$OVN_REAL/ops/install_qa_tools.sh"; CS="$OVN_REAL/ops/install_qa_cron.sh"
echo "--- install_qa_tools.sh"
for s in tools_happy tools_wrong_version tools_broken tools_gitleaks_pin tools_gitleaks_release tools_refusals tools_link_conflict tools_hooks_off; do "sc_$s" "$TS" >/dev/null 2>"$ROOT/err.$s"; ok "$s" $?; [ -s "$ROOT/err.$s" ] && sed 's/^/        /' "$ROOT/err.$s" | head -8; done
echo "--- pins"
chk "every pip pin is an exact x.y.z" "$PY" -I -c "
import re,sys
s=open('$TS').read()
pins=dict(re.findall(r'^PIN_([A-Z_]+)=(\S+)\$',s,re.M))
assert len(pins)==8, pins
assert all(re.fullmatch(r'\d+\.\d+\.\d+',v) for v in pins.values()), pins
sh=re.findall(r'^\s+(?:linux|darwin)_\w+\)\s+echo ([0-9a-f]{64});;',s,re.M)
assert len(sh)==4 and len(set(sh))==4, sh
"
echo "--- install_qa_cron.sh"
for s in cron_dry_default cron_apply cron_idempotent cron_enable cron_refuse_list_fail cron_dup_guard cron_lint cron_missing_script cron_write_fail cron_readback cron_remove cron_remove_exact cron_disable_persists cron_markers cron_backup_dir cron_real_proposal cron_proposal_pins; do "sc_$s" "$CS" >/dev/null 2>"$ROOT/err.$s"; ok "$s" $?; [ -s "$ROOT/err.$s" ] && sed 's/^/        /' "$ROOT/err.$s" | head -8; done
chk "unsafe-rm lint clean on both installers" "$PY" -I "$HERE/lint_unsafe_rm.py" "$TS" "$CS"

# ================================================================ mutants: a mutated copy must FAIL the scenario that guards the behaviour
echo "--- mutants (each must make its scenario FAIL)"
mutant(){ # $1=name $2=which(tools|cron) $3=scenario $4=python replace-old $5=replace-new
  local mdir; mdir="$(safe_mktemp_dir_in "$ROOT" mut)" || { ok "mutant $1 (no sandbox)" 1; return; }
  mkdir -p "$mdir/ops" "$mdir/scripts/test"; cp "$HERE/lib_safe_tmp.sh" "$mdir/scripts/test/"; cp "$OVN_REAL/ops/cron.qa.proposed.txt" "$mdir/ops/"
  local src="$OVN_REAL/ops/install_qa_$2.sh" dst="$mdir/ops/install_qa_$2.sh"
  "$PY" -I - "$src" "$dst" "$4" "$5" <<'EOF'
import sys
s = open(sys.argv[1]).read()
assert sys.argv[3] in s, "mutation target not found: " + sys.argv[3]
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4], 1))
EOF
  [ $? = 0 ] || { ok "mutant $1 applies" 1; return; }
  "sc_$3" "$dst" >/dev/null 2>&1
  if [ $? != 0 ]; then ok "mutant $1 is caught by $3" 0; else ok "mutant $1 SURVIVED $3" 1; fi
}
mutant gl-pin-check-removed tools tools_gitleaks_pin '[ -z "$got" ] || [ "$got" != "$want_pin" ]' 'false'
mutant gl-release-check-removed tools tools_gitleaks_release '[ -z "$rel" ] || [ "$rel" != "$got" ]' 'false'
mutant status-always-ok tools tools_wrong_version '  if [ -n "$ver" ]; then [ "$ver" = "$p" ] && echo ok || echo wrong-version' '  if [ -n "$ver" ]; then echo ok'
mutant broken-not-detected tools tools_broken 'out="$(probe_run "$t")" || { echo broken; return; }' 'out="$(probe_run "$t")" || true'
mutant outside-home-allowed tools tools_refusals 'case "$r" in "$HOME_REAL"/?*) ;; *) refuse "$lbl' 'case "$r" in *) ;; *) refuse "$lbl'
mutant symlink-leaf-allowed tools tools_refusals '[ ! -L "$p" ] || refuse' 'true || refuse'
mutant link-overwrites-files tools tools_link_conflict 'elif [ -e "$l" ]; then echo "install_qa_tools: WARNING' 'elif false; then echo "install_qa_tools: WARNING'
mutant hooks-always-on tools tools_hooks_off 'HOOKS=0; [ "${QA_TOOLS_TEST_HOOKS:-0}" = 1 ] && HOOKS=1' 'HOOKS=1'
mutant mutmut-probed-with-version tools tools_happy 'if [ "$t" = mutmut ]; then out=' 'if false; then out='
mutant semgrep-not-isolated tools tools_happy 'ISOLATED="semgrep"' 'ISOLATED=""'
mutant not-idempotent tools tools_happy 'if [ "$bad" = 1 ] || [ ! -f "$MANIFEST" ]; then' 'if true; then'
pmutant(){ # $1=name $2=old $3=new: a mutated copy of the PROPOSAL must make sc_cron_proposal_pins FAIL
  local mdir; mdir="$(safe_mktemp_dir_in "$ROOT" pmut)" || { ok "pmutant $1 (no sandbox)" 1; return; }
  mkdir -p "$mdir/ops"; cp "$OVN_REAL/ops/install_qa_cron.sh" "$mdir/ops/"
  "$PY" -I - "$OVN_REAL/ops/cron.qa.proposed.txt" "$mdir/ops/cron.qa.proposed.txt" "$2" "$3" <<'PYEND'
import sys
s = open(sys.argv[1]).read()
assert sys.argv[3] in s, "mutation target not found: " + sys.argv[3]
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYEND
  [ $? = 0 ] || { ok "pmutant $1 applies" 1; return; }
  sc_cron_proposal_pins "$mdir/ops/install_qa_cron.sh" >/dev/null 2>&1
  if [ $? != 0 ]; then ok "pmutant $1 is caught by cron_proposal_pins" 0; else ok "pmutant $1 SURVIVED cron_proposal_pins" 1; fi
}
pmutant wipcap-scope-removed 'OVN_QA_WIP_CAP_SCOPE=billwatch,iptv_apps,shrike-labs-website ' ''
pmutant wipcap-scope-adds-xlite 'OVN_QA_WIP_CAP_SCOPE=billwatch,iptv_apps,shrike-labs-website' 'OVN_QA_WIP_CAP_SCOPE=billwatch,iptv_apps,shrike-labs-website,xlite'
pmutant manifest-loop-drifts 'for r in billwatch iptv_apps shrike-labs-website; do' 'for r in billwatch iptv_apps; do'
pmutant fuzz-installed-on '#@id contract_fuzz off' '#@id contract_fuzz'
mutant apply-by-default cron cron_dry_default 'APPLY=0; REMOVE=0' 'APPLY=1; REMOVE=0'
mutant list-failure-ignored cron cron_refuse_list_fail 'if [ $lrc -ne 0 ]; then' 'if false; then'
mutant no-backup cron cron_apply 'cp "$W/cur" "$BK" && cmp -s "$W/cur" "$BK" ||' 'true ||'
mutant lint-removed cron cron_lint 'FORBID = [' 'FORBID = []; _unused = ['
mutant dup-guard-removed cron cron_dup_guard 'dup = [l for l in live_outside if sc and sc in l]' 'dup = []'
mutant readback-unchecked cron cron_readback 'if [ $arc -ne 0 ] || ! cmp -s <(norm "$W/after") <(norm "$W/new"); then' 'if false; then'
mutant outside-text-dropped cron cron_apply 'new = outside[:]' 'new = []'
mutant missing-script-installed cron cron_missing_script 'if sc and not os.path.isfile(os.path.join(ovn, sc)):' 'if False:'
mutant enable-not-persisted cron cron_enable 'or (e["id"] in was_on) or (e["id"] in enable)' 'or (e["id"] in enable)'
mutant disable-not-persisted cron cron_disable_persists 'on = ((not e["off"]) and (e["id"] not in was_off)) or' 'on = (not e["off"]) or'
mutant remove-trims-trailing-blanks cron cron_remove_exact 'new = outside[:]' 'new = outside[:]; remove and [new.pop() for _ in range(len(new)) if new and not new[-1].strip()]'
mutant remove-keeps-separator cron cron_remove_exact 'outside = lines[:bi[0] - 1] + lines[ei[0] + 1:]' 'outside = lines[:bi[0]] + lines[ei[0] + 1:]'
mutant backup-dir-unchecked cron cron_backup_dir 'case "$BKDIR" in "$HOME"/?*|"$HOME_REAL"/?*) ;; *) refuse' 'case "$BKDIR" in *) ;; *) refuse'
mutant unbalanced-markers-accepted cron cron_markers 'if len(bi) != len(ei): die' 'if False: die'

safe_rm_rf "$ROOT" || fails=$((fails+1))
echo "test_qa_install_tools_cron: $n checks, $fails failed"
[ "$fails" = 0 ]
