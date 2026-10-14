"""scripts/test/tmp_track.py - make a python test leave NO tempfile.mkdtemp() directory behind (2026-10-13, tmp-isolation).

Why: the suite ran on the box's inode-limited tmpfs /tmp and nothing cleaned up after it: test_ovn_doc_executor.py alone left 120 dirs / 5,881 inodes per run,
test_qa_block_watch_r10.py 19 / 2,246, test_ovn_supply_r10.py 69 / 529 (about 12k inodes per full run, 59 runs since boot -> 88% of the tmpfs, which then
failed hygiene gates and blocked worktree creation). Only SOME mkdtemp sites had a matching rmtree.

Usage, right after `import tempfile`:   import tmp_track; tmp_track.install()
  - every later tempfile.mkdtemp() is recorded; sweep() removes them all (best-effort, ignore_errors); an atexit hook calls sweep() so an early sys.exit / exception
    still cleans. A test that needs a bounded footprint mid-run (the mutation batteries) may take m = tmp_track.mark() and call tmp_track.sweep(m) itself.
Only directories created through tempfile.mkdtemp() AFTER install() are touched - never anything the test did not make."""
import atexit
import shutil
import tempfile

_MADE = []
_ORIG = tempfile.mkdtemp
_INSTALLED = False


def _tracked_mkdtemp(*a, **k):
    d = _ORIG(*a, **k)
    _MADE.append(d)
    return d


def mark():
    """A position token: sweep(mark_value) removes only the directories created AFTER this call (a scoped footprint for one battery)."""
    return len(_MADE)


def sweep(since=0):
    """Remove every tracked directory created after `since` (default: all); returns how many were removed."""
    n = 0
    while len(_MADE) > since:
        shutil.rmtree(_MADE.pop(), ignore_errors=True)
        n += 1
    return n


def install():
    global _INSTALLED
    if _INSTALLED:
        return
    _INSTALLED = True
    tempfile.mkdtemp = _tracked_mkdtemp
    atexit.register(sweep)
