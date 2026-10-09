#!/usr/bin/env python3
"""prep_e2e.py - make a SCRATCH COPY of the Chickadee Android e2e suite runnable against STAGING with the staging test accounts.

Why: the suite hardcodes the PROD test accounts as string literals in ~15 spec files (and apiClient defaults to the prod API).
Editing the repo is not our job (a gate never modifies a repo), so on the scratch copy only we rewrite each quoted literal to an
environment lookup:
    'shots@chickadeestream.com'        -> process.env.CHICK_EMAIL
    'ShotsPass123'                     -> process.env.CHICK_PASSWORD
    'premium.e2e@chickadeestream.com'  -> process.env.CHICK_PREMIUM_EMAIL
    'PremiumPass123'                   -> process.env.CHICK_PREMIUM_PASSWORD
There is deliberately NO fallback to the prod literal: a missing variable gives an empty credential and a loud login failure
instead of silently driving the prod accounts. The env values come from the creds file (never printed here).

  prep_e2e.py <scratch e2e dir>        prints one JSON line {"files": n, "replacements": n, "left_over": [..]}
Exit 0 always unless the dir is missing (2).
"""
import json
import os
import re
import sys

MAP = [
    ("shots@chickadeestream.com", "CHICK_EMAIL"),
    ("ShotsPass123", "CHICK_PASSWORD"),
    ("premium.e2e@chickadeestream.com", "CHICK_PREMIUM_EMAIL"),
    ("PremiumPass123", "CHICK_PREMIUM_PASSWORD"),
]

# Layout-drift compat patches, plain substring replacements on the scratch copy only. The suite predates the A-Z fast-scroll rail
# added to Discover, which narrows channel rows from bounds [42..1038] to [42..996]; the pixel regex then matched nothing and every
# spec that opens a channel failed with "discover produced no channels".
COMPAT = [
    ("\\[1038,", "\\[(?:1038|996),"),
    # EpgViewModel.addSource now reports "Guide loaded: N channel(s), N program(s)" instead of the old "added. Importing..." text.
    ("page.waitForText('EPG source added. Importing data in background...', {",
     "page.waitForVisible(BasePage.byTextContains('Guide loaded'), {"),
    # Playlist import no longer shows an "Imported N channels" card: the app returns straight to the stream list.
    ("""  const result = await add.waitForResult()
  assert(result.success, `playlist import did not report success: ${result.message}`)
  assert(result.message.startsWith('Imported '), `expected an "Imported N channel(s)" message, got: ${result.message}`)
""", "  await nav.waitForHome({ timeout: 25000 })\n"),
]
COMPAT += [
    # tapFirstRow() assumed the 3rd TextView is the first row; the toolbar title now comes after the content in the tree, so it tapped the
    # screen title. Pick the first TextView that is not screen chrome.
    ("""    const el = await this.driver.$('android=new UiSelector().className("android.widget.TextView").instance(2)')
    if (!(await el.isExisting())) return null
    const text = await el.getText()
    await el.click()
    return text""", """    const chrome = new Set(['Recently Watched', 'Continue Watching', 'Watch History', 'Clear', 'Back', 'No Watch History'])
    for (const el of await this.driver.$$('android=new UiSelector().className("android.widget.TextView")')) {
      const text = await el.getText()
      if (text && !chrome.has(text)) { await el.click(); return text }
    }
    return null"""),
    # History rows arrive after the screen title; a fixed 1.5 s pause raced the (cold, just-installed app) fetch and the spec then
    # tapped the screen title as if it were a row. Wait for real content instead.
    ("""    await this.driver.pause(1500)
  }
  async isPremiumGated()""", """    await this.driver.waitUntil(() => this.isLoaded(), { timeout: 20000, timeoutMsg: 'watch history never loaded' }).catch(() => {})
    await this.driver.pause(500)
  }
  async isPremiumGated()"""),
]
OVERLAY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "overlay")


def main(argv):
    if len(argv) != 1 or not os.path.isdir(argv[0]):
        print(json.dumps({"error": "usage: prep_e2e.py <e2e dir>"}))
        return 2
    root = argv[0]
    files = repl = 0
    left = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d != "node_modules"]
        for fn in fns:
            if not fn.endswith(".mjs"):
                continue
            p = os.path.join(dp, fn)
            try:
                src = open(p, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            out, n = src, 0
            for lit, var in MAP:
                # a whole quoted string literal only ('x' or "x"); never touches a longer string that merely contains it
                out, k = re.subn(r"""(['"])%s\1""" % re.escape(lit), "process.env.%s" % var, out)
                n += k
            for old, new in COMPAT:
                if old in out:
                    out = out.replace(old, new)
                    n += 1
            if n:
                open(p, "w", encoding="utf-8").write(out)
                files += 1
                repl += n
            for lit, _ in MAP:
                if lit in out:
                    left.append(os.path.relpath(p, root))
                    break
    # overlay specs replace repo specs the app has drifted away from (scratch copy only)
    ov = os.path.join(OVERLAY_DIR, "tests")
    overlaid = []
    if os.path.isdir(ov):
        for fn in sorted(os.listdir(ov)):
            if fn.endswith(".mjs") and os.path.isfile(os.path.join(root, "tests", fn)):  # replace only, never add
                with open(os.path.join(ov, fn), encoding="utf-8") as fh, open(os.path.join(root, "tests", fn), "w", encoding="utf-8") as out_fh:
                    out_fh.write(fh.read())
                overlaid.append(fn)
    print(json.dumps({"files": files, "replacements": repl, "left_over": sorted(set(left)), "overlaid": overlaid}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
