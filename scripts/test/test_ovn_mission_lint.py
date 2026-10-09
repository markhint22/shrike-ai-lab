#!/usr/bin/env python3
"""scripts/ovn_mission_lint.py check <mission.tres>: spawn-on-obstacle / out-of-grid / length-mismatch lint for xlite missions (stdlib only).
Fixtures are cut from real shipped missions (mission_46: player (2,2) on a crate; mission_11: enemies on wall cells; mission_03: a clean one with patrol routes,
door cells and high ground). Every check also runs against a MUTANT of the script (one rule broken) and must fail there."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
LINT = os.path.join(SCRIPTS, "ovn_mission_lint.py")
SRC = open(LINT, encoding="utf-8").read()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


HEAD = """[gd_resource type="Resource" script_class="MissionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/mission/mission_data.gd" id="1"]

[resource]
script = ExtResource("1")
"""
# mission_46.tres, verbatim from the xlite repo (2026-10-09): player spawn (2,2) is obstacle index 6 = type 0 (CRATE)
REAL_46 = HEAD + """grid_size = Vector2i(13, 13)
objective_type = 0
obstacles = Array[Vector2i]([Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7), Vector2i(3, 9), Vector2i(9, 3), Vector2i(2, 2), Vector2i(10, 10)])
obstacle_types = Array[int]([1, 1, 0, 0, 2, 2, 0, 0])
player_spawns = Array[Vector2i]([Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)])
enemy_spawns = Array[Vector2i]([Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10), Vector2i(9, 11)])
enemy_types = Array[int]([7, 5, 5, 0])
extraction_zone = Vector2i(11, 1)
extraction_radius = 1
"""
FIXED_46 = REAL_46.replace("Vector2i(1, 2), Vector2i(2, 2)])\nenemy", "Vector2i(1, 2), Vector2i(3, 3)])\nenemy")   # the same mission with the player moved off the crate
# mission_11.tres: all four enemy spawns sit on type-1 (WALL) cells
REAL_11 = HEAD + """grid_size = Vector2i(16, 16)
objective_type = 3
obstacles = Array[Vector2i]([Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(8, 8), Vector2i(9, 8), Vector2i(8, 9), Vector2i(9, 9), Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 13), Vector2i(3, 3), Vector2i(10, 10), Vector2i(6, 6), Vector2i(11, 11)])
obstacle_types = Array[int]([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 2, 2])
player_spawns = Array[Vector2i]([Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)])
enemy_spawns = Array[Vector2i]([Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 13)])
enemy_types = Array[int]([0, 1, 2, 3])
extraction_zone = Vector2i(14, 14)
extraction_radius = 1
"""
# mission_03.tres (a clean one): patrol routes, high ground, door cells, a terrain theme
CLEAN_03 = """[gd_resource type="Resource" script_class="MissionData" format=3]

[ext_resource type="Script" path="res://scripts/mission/mission_data.gd" id="1_gen"]

[resource]
script = ExtResource("1_gen")
grid_size = Vector2i(13, 13)
obstacles = Array[Vector2i]([Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 2), Vector2i(4, 4), Vector2i(5, 2), Vector2i(6, 2), Vector2i(6, 4), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11), Vector2i(4, 9), Vector2i(4, 11), Vector2i(5, 11), Vector2i(6, 9), Vector2i(6, 10), Vector2i(6, 11), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 7), Vector2i(9, 8), Vector2i(10, 4), Vector2i(10, 8), Vector2i(11, 4), Vector2i(11, 5), Vector2i(11, 6), Vector2i(11, 7), Vector2i(11, 8), Vector2i(6, 6), Vector2i(6, 7), Vector2i(8, 9), Vector2i(9, 9)])
obstacle_types = Array[int]([1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0])
player_spawns = Array[Vector2i]([Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, 2)])
enemy_spawns = Array[Vector2i]([Vector2i(1, 12), Vector2i(2, 12), Vector2i(0, 11), Vector2i(4, 10), Vector2i(5, 10)])
enemy_types = Array[int]([0, 0, 0, 5, 0])
extraction_zone = Vector2i(11, 11)
high_ground_cells = Array[Vector2i]([Vector2i(7, 7)])
enemy_patrol_routes = [[], [], [], [Vector2i(6, 12), Vector2i(4, 12)], []]
door_cells = Array[Vector2i]([Vector2i(5, 4), Vector2i(5, 9), Vector2i(9, 6)])
terrain_theme = "industrial"
"""


def sub(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)


def lint(script, text, name="m.tres"):
    d = tempfile.mkdtemp(prefix="mlint-")
    p = os.path.join(d, name)
    with open(p, "w") as f:
        f.write(text)
    r = subprocess.run([sys.executable, script, "check", p], capture_output=True, text=True)
    return r.returncode, [l for l in r.stdout.split("\n") if l]


# ---------------------------------------------------------------- checks (script path -> bool), run against the real script and its mutants
def chk_spawn_on_obstacle(script):
    rc46, out46 = lint(script, REAL_46)
    rc11, out11 = lint(script, REAL_11)
    return (rc46 == 1 and out46 == ["player_spawns 2,2 on-obstacle"]
            and rc11 == 1 and out11 == ["enemy_spawns 12,12 on-obstacle", "enemy_spawns 13,12 on-obstacle", "enemy_spawns 12,13 on-obstacle", "enemy_spawns 13,13 on-obstacle"])


def chk_clean(script):
    return lint(script, CLEAN_03) == (0, []) and lint(script, FIXED_46) == (0, [])


def chk_rubble_hazard_walkable(script):
    """RUBBLE (2) and HAZARD (3) are walkable: an enemy on them is allowed (mission_12/20/24/31/37 do it on purpose)."""
    rubble = sub(FIXED_46, "Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10), Vector2i(9, 11)", "Vector2i(3, 9), Vector2i(9, 3), Vector2i(11, 10), Vector2i(9, 11)")
    hazard = sub(rubble, "obstacle_types = Array[int]([1, 1, 0, 0, 2, 2, 0, 0])", "obstacle_types = Array[int]([1, 1, 0, 0, 3, 3, 0, 0])")
    return lint(script, rubble) == (0, []) and lint(script, hazard) == (0, [])


def chk_default_crate(script):
    """An obstacle_types array shorter than obstacles defaults the missing entries to CRATE (blocking), like mission_data.gd's type_for_index."""
    short = sub(sub(REAL_46, "obstacle_types = Array[int]([1, 1, 0, 0, 2, 2, 0, 0])", "obstacle_types = Array[int]([1, 1])"),
                "Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10), Vector2i(9, 11)", "Vector2i(3, 9), Vector2i(11, 10), Vector2i(10, 11), Vector2i(9, 11)")
    rc, out = lint(script, short)
    return rc == 1 and "enemy_spawns 3,9 on-obstacle" in out and "player_spawns 2,2 on-obstacle" in out and not any("length-mismatch" in l for l in out)


def chk_out_of_grid(script):
    a = sub(FIXED_46, "Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10), Vector2i(9, 11)", "Vector2i(13, 5), Vector2i(10, 11), Vector2i(-1, 0), Vector2i(12, 12)")
    rc, out = lint(script, a)
    edge = lint(script, sub(FIXED_46, "Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10), Vector2i(9, 11)", "Vector2i(12, 12), Vector2i(0, 12), Vector2i(12, 0), Vector2i(0, 0)"))
    o = lint(script, sub(FIXED_46, "Vector2i(10, 10)])\nobstacle_types", "Vector2i(10, 13)])\nobstacle_types"))
    return (rc == 1 and out == ["enemy_spawns 13,5 out-of-grid", "enemy_spawns -1,0 out-of-grid"] and edge == (0, []) and o[0] == 1 and o[1] == ["obstacles 10,13 out-of-grid"])


def chk_length_mismatch(script):
    types_long = sub(FIXED_46, "obstacle_types = Array[int]([1, 1, 0, 0, 2, 2, 0, 0])", "obstacle_types = Array[int]([1, 1, 0, 0, 2, 2, 0, 0, 1])")
    en_long = sub(FIXED_46, "enemy_types = Array[int]([7, 5, 5, 0])", "enemy_types = Array[int]([7, 5, 5, 0, 1])")
    routes = sub(CLEAN_03, "[[], [], [], [Vector2i(6, 12), Vector2i(4, 12)], []]", "[[], [], [], [Vector2i(6, 12), Vector2i(4, 12)], [], []]")
    en_short = sub(FIXED_46, "enemy_types = Array[int]([7, 5, 5, 0])", "enemy_types = Array[int]([7])")
    a, b, c = lint(script, types_long), lint(script, en_long), lint(script, routes)
    return (a == (1, ["obstacle_types - length-mismatch: 9 entries for 8 obstacles"]) and b == (1, ["enemy_types - length-mismatch: 5 entries for 4 enemy_spawns"])
            and c == (1, ["enemy_patrol_routes - length-mismatch: 6 routes for 5 enemy_spawns"]) and lint(script, en_short) == (0, [])
            and lint(script, sub(FIXED_46, "enemy_types = Array[int]([7, 5, 5, 0])", "enemy_types = Array[int]([])")) == (0, []))   # mission_43/44/45 ship an empty enemy_types


def chk_exit_codes(script):
    rc_nogrid, out_nogrid = lint(script, HEAD + "obstacles = Array[Vector2i]([])\n")
    d = tempfile.mkdtemp(prefix="mlint-")
    miss = subprocess.run([sys.executable, script, "check", os.path.join(d, "nope.tres")], capture_output=True, text=True)
    usage = subprocess.run([sys.executable, script], capture_output=True, text=True)
    return rc_nogrid == 2 and out_nogrid and out_nogrid[0].startswith("unparsable") and miss.returncode == 2 and usage.returncode == 2


def chk_other_sections_ignored(script):
    """Only the [resource] section counts: a later [sub_resource] that says `enemy_spawns =` must not override it."""
    t = CLEAN_03 + "\n[sub_resource type=\"Resource\" id=\"x\"]\nenemy_spawns = Array[Vector2i]([Vector2i(3, 2)])\n"
    return lint(script, t) == (0, [])


def mutant_script(old, new):
    assert SRC.count(old) == 1, (old, SRC.count(old))
    d = tempfile.mkdtemp(prefix="lintmut-")
    p = os.path.join(d, "ovn_mission_lint.py")
    with open(p, "w") as f:
        f.write(SRC.replace(old, new))
    return p


def mut(label, chk, old, new):
    ok("%s (real script)" % label, bool(chk(LINT)))
    ok("MUTATION caught: %s" % label, not chk(mutant_script(old, new)))


print("== fixtures cut from real missions")
mut("spawn on a crate/wall obstacle is reported as '<field> <x,y> on-obstacle' (mission_46 player, mission_11 enemies)", chk_spawn_on_obstacle,
    "            elif f in SPAWN_FIELDS and c in blocked:", "            elif False:")
mut("a clean mission (mission_03 with patrols, doors, high ground) and a fixed mission_46 exit 0 with no output", chk_clean,
    "            elif f in SPAWN_FIELDS and c in blocked:", "            elif f in SPAWN_FIELDS:")
mut("RUBBLE / HAZARD cells are walkable", chk_rubble_hazard_walkable, "    return t in BLOCKING or t not in (0, 1, 2, 3)", "    return True")
mut("obstacle_types shorter than obstacles defaults to CRATE (blocking)", chk_default_crate,
    "(types[i] if i < len(types) else 0)", "(types[i] if i < len(types) else 2)")
mut("out-of-grid cells (spawns, negative coordinates, obstacles) are reported; the corner cells are fine", chk_out_of_grid,
    "if not (0 <= c[0] < w and 0 <= c[1] < h):", "if False:")
mut("a parallel array longer than the one it annotates is a length-mismatch; shorter is fine (defaults)", chk_length_mismatch,
    "if n_small > n_big:", "if n_small >= n_big:")
mut("exit 2 when grid_size is missing / the file is unreadable / bad usage", chk_exit_codes, "    if v is None:\n        print(\"unparsable", "    if False:\n        print(\"unparsable")
mut("only the [resource] section is parsed", chk_other_sections_ignored, "        if not in_resource:\n            continue", "        if False:\n            continue")

print("== every real xlite mission parses (when a checkout exists here)")
mdir = os.path.expanduser("~/LocalProjects/xlite/missions")
if os.path.isdir(mdir):
    rcs = {}
    for fn in sorted(os.listdir(mdir)):
        if fn.endswith(".tres"):
            rcs[fn] = subprocess.run([sys.executable, LINT, "check", os.path.join(mdir, fn)], capture_output=True, text=True).returncode
    ok("all %d real missions parse (exit 0 or 1, never 2 / crash)" % len(rcs), rcs and all(v in (0, 1) for v in rcs.values()), {k: v for k, v in rcs.items() if v not in (0, 1)})
else:
    print("  SKIP real-mission parse check (no ~/LocalProjects/xlite checkout on this machine)")

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
