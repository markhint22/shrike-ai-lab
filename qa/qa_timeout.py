#!/usr/bin/env python3
"""qa_timeout.py SECONDS cmd [args...] - portable `timeout` (macOS has none): runs cmd in its own process group, kills the whole
group on expiry, passes stdout/stderr through, exits with the command's status (124 on timeout, 127 if not found)."""
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
        try: os.killpg(p.pid, signal.SIGKILL)
        except OSError: pass
        p.wait()
        return 124
if __name__ == "__main__":
    sys.exit(main())
