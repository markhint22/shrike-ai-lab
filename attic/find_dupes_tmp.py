import re, sys, os, glob

def find_py_dupes(root):
    results = []
    for path in glob.glob(root + "/**/*.py", recursive=True):
        if "/__pycache__/" in path or "/.venv/" in path or "/node_modules/" in path:
            continue
        try:
            with open(path, errors="ignore") as f:
                lines = f.readlines()
        except Exception:
            continue
        # top-level def/class
        names = {}
        for i, l in enumerate(lines):
            m = re.match(r'^(def|class)\s+(\w+)', l)
            if m:
                key = (m.group(1), m.group(2))
                names.setdefault(key, []).append(i+1)
        for key, locs in names.items():
            if len(locs) > 1:
                results.append((path, key[0], key[1], locs))
    return results

def find_empty_files(root, exts):
    out = []
    for ext in exts:
        for path in glob.glob(root + f"/**/*.{ext}", recursive=True):
            if "/__pycache__/" in path or "/node_modules/" in path:
                continue
            try:
                if os.path.getsize(path) == 0:
                    out.append(path)
            except Exception:
                pass
    return out

if __name__ == "__main__":
    root = sys.argv[1]
    print("=== PY DUPES ===")
    for path, kind, name, locs in find_py_dupes(root):
        print(f"{path}: {kind} {name} @ lines {locs}")
    print("=== EMPTY FILES ===")
    for f in find_empty_files(root, ["py","ts","vue","kt","swift"]):
        print(f)
