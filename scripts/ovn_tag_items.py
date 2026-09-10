#!/usr/bin/env python3
# Prefix each unchecked, non-human item in OVERNIGHT_PROGRESS.md with its
# classification tag {lang·type·complexity·verif} so type/complexity SHOW per task.
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ovn_classify as C
TAGGED = re.compile(r'- \[ \] (\[[A-Z]+\] )?\{')
SKIP = re.compile(r'HUMAN-ONLY|human/|retired-|BLOCKED ITEM', re.I)
def process(path):
    lines = open(path, encoding='utf-8').read().splitlines()
    out, n = [], 0
    for ln in lines:
        if ln.startswith('- [ ]') and not TAGGED.match(ln) and not SKIP.search(ln):
            tag = C.tag(C.classify(ln))
            m = re.match(r'(- \[ \] (?:\[[A-Z]+\] )?)(.*)', ln)
            if m:
                out.append(m.group(1) + tag + ' ' + m.group(2)); n += 1; continue
        out.append(ln)
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    return n
if __name__ == '__main__':
    tot = 0
    for p in sys.argv[1:]:
        if os.path.exists(p):
            k = process(p); tot += k
    print('GENERATED_TAGS=%d' % tot)
