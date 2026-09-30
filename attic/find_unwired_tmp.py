import re, glob, subprocess, os, sys

root = sys.argv[1]  # e.g. iptv-backend
svc_dir = os.path.join(root, "app/services")

for path in sorted(glob.glob(svc_dir + "/*.py")):
    base = os.path.basename(path)
    if base == "__init__.py":
        continue
    modname = base[:-3]
    with open(path, errors="ignore") as f:
        content = f.read()
    funcs = re.findall(r'^def (\w+)\(', content, re.M)
    if not funcs:
        continue
    # grep whole app/ (not tests) excluding this file for references to modname or any func name
    try:
        out = subprocess.run(
            ["grep", "-rl", modname, os.path.join(root, "app")],
            capture_output=True, text=True
        ).stdout
    except Exception:
        out = ""
    refs = [l for l in out.splitlines() if os.path.abspath(l) != os.path.abspath(path)]
    if not refs:
        print(f"UNWIRED-MODULE: {path}  funcs={funcs}")
