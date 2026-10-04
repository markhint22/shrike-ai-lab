#!/usr/bin/env python3
# Extract "- [ ]" queue-item lines from a subagent .output JSONL transcript,
# WITHOUT loading the whole transcript into the caller's context. Prints only a
# count; writes the clean item lines to <out>.
import json, re, sys, html

src, out = sys.argv[1], sys.argv[2]
lines_found = []
seen = set()

def harvest(text):
    for ln in text.split("\n"):
        ln = ln.rstrip()
        if ln.startswith("- [ ]"):
            ln = html.unescape(ln)  # &gt; -> >, &lt; -> <, &amp; -> &
            if ln not in seen:
                seen.add(ln); lines_found.append(ln)

def walk(o):
    if isinstance(o, str):
        harvest(o)
    elif isinstance(o, dict):
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)

with open(src, encoding="utf-8", errors="ignore") as f:
    for raw in f:
        raw = raw.strip()
        if not raw: continue
        try:
            walk(json.loads(raw))
        except Exception:
            harvest(raw)  # fallback: treat as plain text

with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines_found) + ("\n" if lines_found else ""))
print(f"{len(lines_found)} items -> {out}")
