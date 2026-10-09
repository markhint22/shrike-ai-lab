#!/usr/bin/env python3
"""qa_timeout.py SECONDS cmd [args...] - portable `timeout` (macOS has none): runs cmd in its own process group, kills the whole
group on expiry, passes stdout/stderr through, exits with the command's status (124 on timeout, 127 if not found).
Opt-in graceful stop: with env QA_TIMEOUT_TERM_GRACE_S=N (> 0) the group gets SIGTERM first and SIGKILL only if it is still running N seconds later (default 0 = SIGKILL
at once, the historical behaviour every other caller relies on). staging_e2e_run.sh uses it so the e2e runner can clean up and write a partial result."""
import os, signal, subprocess, sys
def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    secs = float(sys.argv[1]); cmd = sys.argv[2:]
    try:
        p = subprocess.Popen(cmd, start_new_session=True)
    except FileNotFoundError:
        return 127
    try:
        return p.wait(timeout=secs)
    except subprocess.TimeoutExpired:
        try: grace = float(os.environ.get("QA_TIMEOUT_TERM_GRACE_S", "0") or 0)
        except ValueError: grace = 0.0
        if grace > 0:
            try: os.killpg(p.pid, signal.SIGTERM)
            except OSError: pass
            try:
                p.wait(timeout=grace)
                return 124
            except subprocess.TimeoutExpired:
                pass
        try: os.killpg(p.pid, signal.SIGKILL)
        except OSError: pass
        p.wait()
        return 124
if __name__ == "__main__":
    sys.exit(main())
