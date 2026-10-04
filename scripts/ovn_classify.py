#!/usr/bin/env python3
"""Classify an overnight-queue item on 4 independent axes so pass-rate can be
analyzed per-dimension and failures attributed to the RIGHT cause:

  LANGUAGE      capability boundary (py/ts/vue/kotlin/swift/gdscript/...) — from file ext (deterministic)
  TYPE          kind of change (syntax/typing/validation/a11y/security/perf/bugfix/feature/refactor/test/docs/config/data)
  COMPLEXITY    T1 trivial one-liner .. T5 cross-cutting/architecture  (heuristic + optional explicit tag)
  VERIFIABILITY test-covered / build-verified / unverifiable  — can the gate catch a bad change?

Compact tag form for prefixing an item:   {py·validation·T2·tested}
CLI:  ovn_classify.py "<item text>"   -> prints  lang type complexity verif file
      ovn_classify.py --tag "<text>"  -> prints just the {..} tag
"""
import re, os, sys

EXT_LANG = {
    '.py': 'py', '.ts': 'ts', '.tsx': 'ts', '.js': 'js', '.jsx': 'js', '.vue': 'vue',
    '.kt': 'kotlin', '.kts': 'kotlin', '.swift': 'swift', '.gd': 'gdscript', '.dart': 'dart',
    '.sh': 'bash', '.yaml': 'yaml', '.yml': 'yaml', '.json': 'json', '.toml': 'toml',
    '.md': 'md', '.sql': 'sql', '.html': 'html', '.css': 'css', '.gradle': 'gradle',
    '.xml': 'xml', '.tres': 'godot', '.tscn': 'godot', '.plist': 'plist',
}
# No CI build/test on the box -> a bad change lands silently (gate can't catch it).
# gdscript moved to TEST_COVERED 2026-08-31: the server now runs a real GUT gate
# for xlite (godot4 + gut_cmdln, "no-asserts" treated as failure, parse errors in
# uncovered files caught via --import), so a bad .gd change is reverted, not landed.
UNVERIFIABLE_LANG = {'swift', 'kotlin', 'dart', 'gradle', 'xml', 'plist'}
TEST_COVERED_LANG = {'py', 'ts', 'js', 'vue', 'gdscript'}
# .tres/.tscn (godot): the --import step verifies they still parse (build-verified),
# so they're no longer bucketed as unverifiable no-behavior.
NOBEHAVIOR_LANG = {'md', 'json', 'yaml', 'toml', 'html', 'css'}

TYPE_RULES = [
    ('a11y',       r'aria-|type="button"|\balt=|role=|screen reader|accessible name|loading="lazy"'),
    ('security',   r'rel="noopener|noreferrer|\bescape|sanitize|\bsecret\b|reverse-tabnabbing|hmac|injection|auth\b'),
    ('validation', r'\bQuery\(|\bField\(|\bge=|\ble=|max_length|min_length|Array\.isArray|\bbounds\b|\bvalidate|guard'),
    ('typing',     r'return type|type hint|->\s*None|->\s*str|Optional\[|annotation'),
    ('perf',       r'\blazy\b|\bcache|caching|manualChunks|debounce|pagination|backoff|circuit'),
    ('test',       r'\btest_|pytest|vitest|\bGUT\b|assertion branch|test suite|test file'),
    ('docs',       r'docstring|README|\bcomment\b|documentation|sitemap|robots'),
    ('config',     r'requirements|package\.json|build\.gradle|vite\.config|\.env\b|dependency|manifest|flavor|theme-color'),
    ('data',       r'\.tres|\.tscn|fixture|\bseed\b|mission_'),
    ('bugfix',     r'crash|TypeError|IndexError|KeyError|NameError|already[- ]done|breaks|real bug|off-by|swallow'),
    ('feature',    r'\bimplement\b|new endpoint|new method|new (router|table|migration|module)|\bbuild \b|support for'),
    ('refactor',  r'\brename\b|extract|dedupe|deduplicate|consolidate|remove dead|orphan'),
    ('syntax',     r'bare `?except|except Exception|duplicate import|indentation|missing `?def'),
]

# h13 (2026-10-04): the "file" classify() extracts is whatever word.word token appears in the text, so a cycle with no real target produced
# 'none', 'sympy.isprime', 'app.services.cache' ... and lang_of() filed them under 'other' (build-verified), manufacturing a misleading "other 40%"
# language row. A token is a real PATH only when it has a directory part, or an extension we know (EXT_LANG + common non-code files), or is a
# well-known extensionless build file; anything else is 'unknown' (excluded from the per-language pass-rate rows by ovn_stats.py).
KNOWN_FILE_EXT = set(EXT_LANG) | {'.txt', '.cfg', '.ini', '.lock', '.env', '.csv', '.png', '.jpg', '.jpeg', '.svg', '.gif', '.webp', '.ico',
                                  '.mjs', '.cjs', '.scss', '.less', '.properties', '.pro', '.proto', '.graphql', '.cfg', '.conf', '.rst', '.tsv',
                                  '.import', '.godot', '.cs', '.java', '.go', '.rs', '.rb', '.php', '.c', '.h', '.cpp'}
KNOWN_BARE_FILES = {'dockerfile', 'makefile', 'procfile', 'gemfile', 'podfile', 'jenkinsfile'}

def is_real_path(path):
    if not path:
        return False
    base = os.path.basename(path)
    if '/' in path.strip('/'):
        return True
    return os.path.splitext(base)[1].lower() in KNOWN_FILE_EXT or base.lower() in KNOWN_BARE_FILES

def lang_of(path):
    if not is_real_path(path):
        return 'unknown'
    return EXT_LANG.get(os.path.splitext(path)[1].lower(), 'other')

def type_of(text):
    for name, pat in TYPE_RULES:
        if re.search(pat, text, re.I):
            return name
    return 'other'

def complexity_of(text, explicit=None):
    if explicit:
        return explicit
    t = text.lower()
    if re.search(r'one line\.|only that line|attribute only|only that (tag|button|svg|img|anchor|field|param)', t) \
       or re.search(r'add `?type="button"|add `?aria-|add `?loading="lazy"|add `?rel="noopener|->\s*none:|->\s*str:', t) \
       or re.search(r'bare `?except|to `?except exception|deprecated `?datetime\.utcnow', t):
        return 'T1'
    if re.search(r'implement (real|the)|multi-file|across |wire |new (router|table|migration|module)|end-to-end', t):
        return 'T4'
    if re.search(r'\bimplement\b|compute|heuristic|parse|algorithm|harden|reconcile|new branch|reduce|refactor', t):
        return 'T3'
    return 'T2'

def verif_of(lang, path):
    if lang == 'unknown':
        return 'unknown'   # no identifiable file: nothing to say about whether a gate can catch a bad change
    if lang in UNVERIFIABLE_LANG:
        return 'unverifiable'
    if 'test' in path.lower():
        return 'test-covered'
    if lang in NOBEHAVIOR_LANG:
        return 'unverifiable'
    if lang in TEST_COVERED_LANG:
        return 'test-covered'
    return 'build-verified'

def classify(text, explicit_complexity=None):
    m = re.search(r'`([^`]+\.[A-Za-z0-9]{1,8})`', text)
    if not m:
        m = re.search(r'\b([A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]{1,8})\b', text)
    path = m.group(1) if m else ''
    lang = lang_of(path)   # '' (no file-shaped token at all, e.g. a bare 'none') and non-path tokens are both 'unknown' (h13)
    return {'lang': lang, 'type': type_of(text), 'complexity': complexity_of(text, explicit_complexity),
            'verif': verif_of(lang, path), 'file': path}

def tag(c):
    return "{%s·%s·%s·%s}" % (c['lang'], c['type'], c['complexity'], c['verif'])

if __name__ == '__main__':
    args = sys.argv[1:]
    tagonly = False
    if args and args[0] == '--tag':
        tagonly = True; args = args[1:]
    text = ' '.join(args)
    c = classify(text)
    print(tag(c) if tagonly else "%s %s %s %s %s" % (c['lang'], c['type'], c['complexity'], c['verif'], c['file']))
