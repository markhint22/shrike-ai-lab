#!/usr/bin/env python3
"""gdtoolkit_run.py - tiny helper run by gate_gdparse.py under the interpreter that has gdtoolkit installed (the box's ~/qa-venv python).
Deliberately stdlib + gdtoolkit only (it runs with `python -I`, so it cannot import qa_common).

    python -I gdtoolkit_run.py parse|lint DIR < files.json      (files.json = JSON list of paths relative to DIR)
    -> one JSON object on stdout: {"version": "<gdtoolkit>", "results": {path: {"ok": bool, "kind": "...", "err": "...", "problems": [[rule, line, text]]}}}

kind: ok | parse_error (lark rejected the source, or it is not valid UTF-8: Godot would refuse the file too) | tool_error (any other exception:
a gdtoolkit bug or an unreadable file - NOT evidence about the file). `lint` also parses (gdlint needs the tree), so a parse error shows there as well.
Uses gdtoolkit's DEFAULT lint config on purpose: the helper never reads a gdlintrc from the repo (repo-controlled config must not silence the gate)."""
import json
import os
import sys


def main(argv):
    if len(argv) != 2 or argv[0] not in ("parse", "lint"):
        print("usage: gdtoolkit_run.py parse|lint DIR < files.json", file=sys.stderr)
        return 2
    mode, root = argv
    files = json.loads(sys.stdin.read() or "[]")
    sys.setrecursionlimit(20000)
    try:
        import lark
        from importlib.metadata import version
        from gdtoolkit.parser import parser
        ver = version("gdtoolkit")
        if mode == "lint":
            from gdtoolkit.linter import lint_code, DEFAULT_CONFIG
    except Exception as ex:  # noqa: BLE001
        print(json.dumps({"version": None, "import_error": "%s: %s" % (type(ex).__name__, ex), "results": {}}))
        return 0
    out = {}
    for rel in files:
        r = {"ok": True, "kind": "ok", "err": "", "problems": []}
        try:
            with open(os.path.join(root, rel), "rb") as f:
                raw = f.read()
            try:
                code = raw.decode("utf-8")
            except UnicodeDecodeError as ex:
                r.update(ok=False, kind="parse_error", err="not valid UTF-8 (%s)" % str(ex)[:80])
                out[rel] = r
                continue
            if mode == "parse":
                parser.parse(code)
            else:
                for p in lint_code(code, DEFAULT_CONFIG):
                    r["problems"].append([p.name, int(p.line), str(p.description)])
        except lark.exceptions.UnexpectedInput as ex:
            line = getattr(ex, "line", None)
            col = getattr(ex, "column", None)
            first = str(ex).strip().splitlines()[0] if str(ex).strip() else type(ex).__name__
            r.update(ok=False, kind="parse_error", err=("line %s col %s: %s" % (line, col, first))[:240])
        except Exception as ex:  # noqa: BLE001
            r.update(ok=False, kind="tool_error", err=("%s: %s" % (type(ex).__name__, str(ex).strip().splitlines()[0] if str(ex).strip() else ""))[:240])
        out[rel] = r
    print(json.dumps({"version": ver, "results": out}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
