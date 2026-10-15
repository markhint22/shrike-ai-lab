#!/usr/bin/env python3
"""Return Claude-routed queue lines to the local Qwen fleet (2026-10-07).

The stage runner used to route an item to Claude after ONE zero-landing staged run (now: a retry budget, OVN_STAGE_ZERO_CAP). Lines routed that way carry the prefix
'[AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE]'. This strips that prefix (and a '[CLAUDE]' tag) from every line that is NOT Claude-only, so
the fleet picks it up again (with the new retry budget + failure memory). Claude-only = what the 27B is documented to be bad at or forbidden from:
  - touches a hard-banned file (.queue-hard-banned-files) or vendored addons/
  - mobile code (.kt .kts .swift .pbxproj .brs, or under iptv-android/ iptv-ios/ iptv-roku/)  [27B pass rate 10% on Kotlin; Swift routed away permanently]
  - a manual-test bug (manual-* feature, 'Manual-test bug', bug-escalated)  [the bug-first pipeline owns those]
  - a feature flagged needs-human / product design
  - auth/session/token design and the RevenueCat paywall (AUTH_RE below)
  - features held for an owner decision (HOLD_RE below)
usage: unroute_qwen.py <repo> dry|apply      (run on the Mac; edits via a temp worktree pushed non-force to overnight/feature)
"""
import os, re, shutil, subprocess, sys, time

repo, dry = sys.argv[1], (len(sys.argv) < 3 or sys.argv[2] != "apply")
CLONE = "/Users/mhintermeister/LocalProjects/" + repo
WT = "/tmp/wt-unroute-" + repo
STAGED = "[AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE] "
MOBILE_EXT = re.compile(r"\.(kt|kts|swift|pbxproj|brs)\b|(iptv-android|iptv-ios|iptv-roku)/")
# features held for an owner decision (aiohttp->httpx refactor stays pinned; LLM-comment scrubs; wiring dead helpers; SSRF; stubs; referrals product design)
HOLD_RE = re.compile(r"aiohttp|scrub-|wire-epg-now|wire-track-engagement|add-rate-limiting-to-engagement|wire-killpriority|wire-squadscore|wire-missiondirective|"
                     r"wire-machine-completionist|momentum-tiles|fix-squadscore|needs-human|remove-the-hardcoded-stub|fix-url-safety|route-the-stream-proxy|"
                     r"bound-xmltv-download|bound-downloaded|delete-flankside|delete-unitfaction|delete-killpriority|dead-code-delete")


# auth/session/token design and the RevenueCat paywall stay with Claude: a green test suite does not prove an auth change is safe
AUTH_RE = re.compile(r"token-version|password-reset|make-logout|stop-putting-the-full|revenuecat|playback-token|change-password|logout")


def sh(*a, cwd=None, check=True):
    r = subprocess.run(a, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode:
        raise SystemExit("%s -> %s" % (" ".join(a), r.stderr[:200]))
    return r.stdout


def feat(l):
    m = re.search(r"\[feat:([^\]]+)\]", l)
    return m.group(1) if m else ""


def why_claude_only(l, banned):
    if any(b and b in l for b in banned):
        return "hard-banned file"
    if "addons/" in l:
        return "vendored addons/"
    if MOBILE_EXT.search(l):
        return "mobile code"
    if re.search(r"manual-[0-9a-f]{6,}|Manual-test bug|bug-escalated", l) or feat(l).split("-")[0:2] == ["manual"]:
        return "manual-test bug"
    if AUTH_RE.search(feat(l)):
        return "auth/session/paywall design (fleet-written auth code caused the 2026-10-02 reset-password incident)"
    if HOLD_RE.search(feat(l)) or HOLD_RE.search(l):
        return "held for owner decision"
    return None


for attempt in range(5):
    sh("git", "-C", CLONE, "fetch", "-q", "origin", "overnight/feature")
    sh("git", "-C", CLONE, "worktree", "remove", "--force", WT, check=False); shutil.rmtree(WT, ignore_errors=True)
    sh("git", "-C", CLONE, "worktree", "add", "-q", "--detach", WT, "origin/overnight/feature")
    p = os.path.join(WT, "OVERNIGHT_PROGRESS.md")
    L = open(p, "rb").read().decode("utf-8", "surrogateescape").split("\n")
    bp = os.path.join(WT, ".queue-hard-banned-files")
    banned = [x.strip() for x in open(bp).read().split("\n") if x.strip() and not x.startswith("#")] if os.path.exists(bp) else []
    returned, kept = [], {}
    for i, l in enumerate(L):
        if not (l.startswith("- [ ] ") and l[6:].startswith(STAGED.rstrip())):
            continue
        r = why_claude_only(l, banned)
        if r:
            kept[r] = kept.get(r, 0) + 1
            continue
        nl = l.replace(STAGED, "", 1)
        nl = nl.replace("[CLAUDE] ", "", 1) if nl.startswith("- [ ] [CLAUDE] ") else nl
        L[i] = nl
        returned.append(i)
    print("%s: %d staged-escalated lines -> %d returned to Qwen; kept with Claude: %s" % (repo, len(returned) + sum(kept.values()), len(returned), kept or "none"))
    if dry:
        break
    if not returned:
        break
    open(p, "wb").write("\n".join(L).encode("utf-8", "surrogateescape"))
    nums = sh("git", "diff", "--numstat", cwd=WT).split()
    if nums[:2] != [str(len(returned))] * 2:
        raise SystemExit("unexpected diff %s" % nums)
    sh("git", "add", "OVERNIGHT_PROGRESS.md", cwd=WT)
    sh("git", "-c", "user.name=shrike-fleet", "-c", "user.email=22970726+markhint22@users.noreply.github.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m",
       "chore(queue): return %d staged-escalated item(s) to the local Qwen fleet (retry budget now applies); %d stay Claude-only\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" % (len(returned), sum(kept.values())), cwd=WT)
    r = subprocess.run(["git", "push", "-q", "origin", "HEAD:overnight/feature"], cwd=WT, capture_output=True, text=True)
    if r.returncode == 0:
        print("pushed", sh("git", "rev-parse", "--short", "HEAD", cwd=WT).strip())
        break
    print("push rejected, re-applying on the new tip"); time.sleep(3)
sh("git", "-C", CLONE, "worktree", "remove", "--force", WT, check=False); sh("git", "-C", CLONE, "worktree", "prune", check=False)
