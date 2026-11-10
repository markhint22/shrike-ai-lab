#!/usr/bin/env python3
"""ovn_plan_path_ok.py - is this scout-PLAN token a real source file of the repo? (package Z8b-F, 2026-11-10)

The ALREADY-DONE credit paths (run_overnight.sh scout credit, scripts/ovn_credit_already_satisfied.sh) pull every `name.ext` looking token out of the scout's free text and
`grep -F` the open items for it. Numbers and domains match the same regex (`7199.96`, `3599.96`, `db.example`, `IsoGrid.has`) and an open item that merely MENTIONS such a string
(a test asserting a 7199.96 s duration) was matched and credited. A path token must now (1) end in a known source extension and (2) exist in the repo tree (git-tracked, or on disk;
a bare basename matches a tracked file with that basename).

CLI: ovn_plan_path_ok.py <repo_dir> <token>   -> exit 0 = real path (or any internal error: fail open = old behaviour), exit 1 = garbage token. OVN_PLAN_PATH_STRICT=off => always 0.
"""
import os
import subprocess
import sys

KNOWN_EXT = {"py", "ts", "tsx", "js", "jsx", "mjs", "cjs", "vue", "gd", "kt", "kts", "java", "swift", "sh", "bash", "sql", "json", "yml", "yaml", "toml", "html", "css", "scss",
             "xml", "gradle", "tscn", "tres", "cfg", "ini", "txt", "md", "go", "rs", "rb", "c", "h", "cpp", "hpp", "cs", "php", "properties"}


def ok(repo, tok):
    tok = (tok or "").strip().strip("`'\"()[],;:")
    if not tok or "." not in os.path.basename(tok):
        return False
    ext = tok.rsplit(".", 1)[1].lower()
    if ext not in KNOWN_EXT:
        return False
    rel = tok[2:] if tok.startswith("./") else tok
    if os.path.isfile(os.path.join(repo, rel)):
        return True
    try:
        r = subprocess.run(["git", "-C", repo, "ls-files", "--", rel, "*/" + rel], capture_output=True, text=True, timeout=20)
        if r.returncode == 0 and r.stdout.strip():
            return True
        if r.returncode != 0:
            return True      # not a git tree / git failed: no evidence either way, keep the old behaviour
    except (OSError, subprocess.SubprocessError):
        return True
    return False


def main(argv):
    if os.environ.get("OVN_PLAN_PATH_STRICT", "on").strip().lower() == "off" or len(argv) < 3:
        return 0
    return 0 if ok(argv[1], argv[2]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
