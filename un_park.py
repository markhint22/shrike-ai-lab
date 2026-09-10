#!/usr/bin/env python3
# Recover items mislabeled "[HUMAN-ONLY BLOCKED ITEM ...]" by ovn_item_guard's fail-streak.
# Conservative: only touch HUMAN-ONLY-tagged lines.
#   - clearly a human/ops task  -> relabel "[HUMAN] ..." (accurate, still parked)
#   - clearly a doable code task -> UN-PARK (drop the tag, back to the fleet)
#   - ambiguous                  -> leave as-is (don't guess)
import sys, re
prog = sys.argv[1]
TAG = re.compile(r'^- \[ \] \[HUMAN-ONLY BLOCKED ITEM[^\]]*\]\s*')
HUMAN = re.compile(r'(stripe|revenuecat|\bapi[- ]?key\b|app store|play store|\bdns\b|content[- ]?rights?|licens|prod(uction)?[- ]?key|service account|\boauth\b|register .*domain|deploy to |webhook secret|d-?u-?n-?s|apple developer|google play console|purchase .*from|sign ?up (for|at)|provision .*(key|account|token|credential))', re.I)
DOABLE = re.compile(r'(add (a |an |the )?(unit |integration )?(test|tests|module logger|docstring|field constraint)|wrap .*try/?except|\bguard\b|\bvalidate\b|\brejects?\b|constrain|broaden|new pure|replace datetime\.utcnow|\bwire\b|type .* as|\.py\b|\.gd\b|\.ts\b|\.vue\b|raises? .* on|except |import |Literal|schema|pydantic|max_length|422)', re.I)
lines = open(prog).read().split('\n')
out=[]; unparked=0; human=0; left=0
for ln in lines:
    m = TAG.match(ln)
    if not m:
        out.append(ln); continue
    body = ln[m.end():]
    if HUMAN.search(body):
        out.append('- [ ] [HUMAN] ' + body); human += 1
    elif DOABLE.search(body):
        out.append('- [ ] ' + body); unparked += 1
    else:
        out.append(ln); left += 1  # ambiguous — keep parked, don't guess
open(prog,'w').write('\n'.join(out))
print("unparked=%d human=%d ambiguous-left=%d" % (unparked, human, left))
