#!/usr/bin/env python3
"""UTF-8-boundary-safe byte-budget truncation for OVERNIGHT_PROGRESS.md slices.

A plain `head -c N` / `tail -c N` byte cut can land mid-way through a multibyte
UTF-8 sequence (e.g. an em-dash, U+2014, is 3 bytes: 0xe2 0x80 0x94). When that
happens the truncated text is no longer valid UTF-8, and the downstream aider
call's own JSON-encoding step (json.dumps over stdin-decoded text) raises
UnicodeDecodeError and aborts the whole cycle with NEEDS-DECISION - confirmed
live against test-automation-agent's OVERNIGHT_PROGRESS.md (2026-09-17/18).

Fix: do the same byte-count truncation, then decode as UTF-8 with
errors='ignore' so any partial multibyte sequence at the cut boundary is
dropped instead of raising. This never changes output for any input that was
already valid UTF-8 within the budget - only the (rare, boundary-crossing)
partial-sequence bytes are dropped.

Usage:
  ovn_progress_slice.py head N            # first N bytes of stdin, UTF-8-safe
  ovn_progress_slice.py tail N FILE       # last N bytes of FILE, UTF-8-safe
"""
import sys


def do_head(n):
    data = sys.stdin.buffer.read(n)
    sys.stdout.write(data.decode('utf-8', 'ignore'))


def do_tail(n, path):
    with open(path, 'rb') as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - n))
        data = f.read()
    sys.stdout.write(data.decode('utf-8', 'ignore'))


def main():
    if len(sys.argv) < 3:
        sys.stderr.write('usage: ovn_progress_slice.py head N | tail N FILE\n')
        sys.exit(2)
    mode = sys.argv[1]
    n = int(sys.argv[2])
    if mode == 'head':
        do_head(n)
    elif mode == 'tail':
        if len(sys.argv) < 4:
            sys.stderr.write('usage: ovn_progress_slice.py tail N FILE\n')
            sys.exit(2)
        do_tail(n, sys.argv[3])
    else:
        sys.stderr.write('unknown mode: %s\n' % mode)
        sys.exit(2)


if __name__ == '__main__':
    main()
