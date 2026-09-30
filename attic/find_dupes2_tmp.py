import re, glob, sys, os

def scan(root, exts, patterns):
    results = []
    for ext in exts:
        for path in glob.glob(root + f"/**/*.{ext}", recursive=True):
            if any(x in path for x in ["/node_modules/", "/__pycache__/", "/build/", "/.git/", "/Pods/"]):
                continue
            try:
                with open(path, errors="ignore") as f:
                    lines = f.readlines()
            except Exception:
                continue
            names = {}
            for i, l in enumerate(lines):
                for pat in patterns:
                    m = re.match(pat, l)
                    if m:
                        key = m.group(1)
                        names.setdefault(key, []).append(i+1)
            for key, locs in names.items():
                if len(locs) > 1:
                    results.append((path, key, locs))
    return results

root = sys.argv[1]
lang = sys.argv[2]
if lang == "kt":
    res = scan(root, ["kt"], [r'^\s*(?:private |internal |public )?fun (\w+)\s*\(', r'^\s*class (\w+)'])
elif lang == "swift":
    res = scan(root, ["swift"], [r'^\s*(?:private |internal |public |fileprivate )?func (\w+)\s*\(', r'^\s*(?:class|struct) (\w+)'])
elif lang == "ts":
    res = scan(root, ["ts","vue"], [r'^\s*(?:export )?function (\w+)\s*\(', r'^\s*(?:export )?class (\w+)', r'^\s*(?:const|export const) (\w+)\s*='])
for path, key, locs in res:
    print(f"{path}: {key} @ {locs}")
