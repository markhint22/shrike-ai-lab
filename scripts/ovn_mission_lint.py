#!/usr/bin/env python3
"""scripts/ovn_mission_lint.py - structural lint for xlite mission .tres files (stdlib only, 2026-10-09).

Why: 9 spawns in 8 shipped missions sit on a blocking obstacle cell (an enemy or a player that starts inside a wall/crate). Nothing checked it: the
model-written mission items passed their tests either way. This is the deterministic version, used by ovn_work_supply.py's mission-spawn collector.

usage: ovn_mission_lint.py check <mission.tres>
output: one line per violation `<field> <x,y> <reason>` (`-` instead of coordinates for whole-array problems); exit 1 when there is any, 0 when clean,
        2 when the file cannot be parsed reliably (no `grid_size`).
reasons: on-obstacle (a player/enemy spawn on a blocking obstacle), out-of-grid (a cell outside grid_size), length-mismatch (a parallel array longer
        than the array it annotates - the same rule as scripts/mission/mission_validator.gd). A SHORTER parallel array is valid and is deliberately NOT
        reported: missing entries take defaults (mission_43/44/45 ship an empty enemy_types); only the supply item's VERIFY pins the lengths of a mission it asks to fix.

What counts as blocking follows scripts/mission/mission_data.gd: obstacle_types[i] 0 CRATE and 1 WALL block; 2 RUBBLE and 3 HAZARD are walkable; an index
past the end of obstacle_types (or an unknown value) defaults to CRATE. The .tres format is one `field = value` per line; Vector2i(x, y) cells are read
with a regex, fields whose value spans several lines are ignored (none exist in the 59 shipped missions).
"""
import re
import sys

CELL = re.compile(r"Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)")
BLOCKING = (0, 1)
SPAWN_FIELDS = ("player_spawns", "enemy_spawns")
CELL_FIELDS = ("obstacles", "player_spawns", "enemy_spawns", "high_ground_cells", "door_cells", "road_cells")


def parse(text):
    """{field: raw value string} for every single-line `field = value` in the [resource] section."""
    out = {}
    in_resource = False
    for line in text.split("\n"):
        s = line.strip()
        if s.startswith("["):
            in_resource = s == "[resource]"
            continue
        if not in_resource:
            continue
        m = re.match(r"^([A-Za-z_]\w*)\s*=\s*(.*)$", s)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def cells(raw):
    return [(int(a), int(b)) for a, b in CELL.findall(raw or "")]


def ints(raw):
    body = (raw or "")
    m = re.search(r"\(\s*\[(.*)\]\s*\)", body) or re.search(r"\[(.*)\]", body)
    return [int(x) for x in re.findall(r"-?\d+", m.group(1))] if m else []


def grid_size(fields):
    m = re.search(r"Vector2i\(\s*(\d+)\s*,\s*(\d+)\s*\)", fields.get("grid_size", ""))
    return (int(m.group(1)), int(m.group(2))) if m else None


def _blocks(t):
    return t in BLOCKING or t not in (0, 1, 2, 3)  # unknown values default to CRATE like mission_data.gd


def blocked_cells(fields):
    obs = cells(fields.get("obstacles"))
    types = ints(fields.get("obstacle_types"))
    return {c for i, c in enumerate(obs) if _blocks(types[i] if i < len(types) else 0)}


def violations(fields, spawn_only=False):
    """[(field, (x, y) or None, reason)]. spawn_only keeps just the two reasons the supply collector turns into an item (spawn on obstacle / spawn outside the grid)."""
    gs = grid_size(fields)
    if gs is None:
        return None
    w, h = gs
    out = []
    blocked = blocked_cells(fields)
    for f in CELL_FIELDS:
        if spawn_only and f not in SPAWN_FIELDS:
            continue
        for c in cells(fields.get(f)):
            if not (0 <= c[0] < w and 0 <= c[1] < h):
                out.append((f, c, "out-of-grid"))
            elif f in SPAWN_FIELDS and c in blocked:
                out.append((f, c, "on-obstacle"))
    if not spawn_only:
        for small, big in (("obstacle_types", "obstacles"), ("enemy_types", "enemy_spawns")):
            n_small = len(ints(fields.get(small)))
            n_big = len(cells(fields.get(big)))
            if n_small > n_big:
                out.append((small, None, "length-mismatch: %d entries for %d %s" % (n_small, n_big, big)))
        routes = fields.get("enemy_patrol_routes", "")
        if routes:
            n_routes = len(re.findall(r"\[(?:[^\[\]]*)\]", routes[1:-1])) if routes.startswith("[") and routes.endswith("]") else 0
            n_en = len(cells(fields.get("enemy_spawns")))
            if n_routes > n_en:
                out.append(("enemy_patrol_routes", None, "length-mismatch: %d routes for %d enemy_spawns" % (n_routes, n_en)))
    return out


def lint_text(text, spawn_only=False):
    return violations(parse(text), spawn_only=spawn_only)


def main(argv):
    if len(argv) != 3 or argv[1] != "check":
        print("usage: ovn_mission_lint.py check <mission.tres>")
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print("cannot read %s: %s" % (argv[2], e))
        return 2
    v = lint_text(text)
    if v is None:
        print("unparsable: no grid_size in %s" % argv[2])
        return 2
    for field, cell, reason in v:
        print("%s %s %s" % (field, "%d,%d" % cell if cell else "-", reason))
    return 1 if v else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
