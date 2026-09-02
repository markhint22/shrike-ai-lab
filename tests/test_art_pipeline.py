"""Tests for the xlite art pipeline logic (QA gate, prompt construction, the
orchestrator's failure detection). No GPU / torch needed — build_prompt is importable
without the ML stack and the QA gate is pure numpy/PIL, so this runs in plain CI."""
import os, sys
import numpy as np
import pytest
from PIL import Image

SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts")
sys.path.insert(0, SCRIPTS)

import art_qa_gate
import gen_from_brief
import art_pipeline_run


# ----- helpers -----------------------------------------------------------------
def blob(w, h, cx=32, cy=32, color=(200, 80, 40), size=64):
    """A solid rectangle of `color` on a transparent 64x64 canvas."""
    a = np.zeros((size, size, 4), dtype=np.uint8)
    x0, y0 = cx - w // 2, cy - h // 2
    a[y0:y0 + h, x0:x0 + w, :3] = color
    a[y0:y0 + h, x0:x0 + w, 3] = 255
    return a


def reasons(res):
    return " ".join(res["reasons"])


# ----- QA gate: art_qa_gate.inspect --------------------------------------------
def test_clean_centered_sprite_passes_idle():
    assert art_qa_gate.inspect(blob(24, 24), "idle")["ok"] is True


def test_solid_card_flagged_no_alpha():
    a = np.full((64, 64, 4), 255, dtype=np.uint8)  # fully opaque = background intact
    res = art_qa_gate.inspect(a, "idle")
    assert not res["ok"] and "no_alpha" in reasons(res)


def test_opaque_corners_flagged_bg_residue():
    a = blob(20, 20)
    for (y, x) in [(0, 0), (0, 58), (58, 0), (58, 58)]:
        a[y:y + 6, x:x + 6, :3] = (30, 30, 30)
        a[y:y + 6, x:x + 6, 3] = 255
    res = art_qa_gate.inspect(a, "idle")
    assert not res["ok"] and "bg_residue" in reasons(res)


def test_opaque_border_ring_flagged_edge_frame():
    a = blob(18, 18)
    a[0, :, 3] = 255; a[-1, :, 3] = 255; a[:, 0, 3] = 255; a[:, -1, 3] = 255
    res = art_qa_gate.inspect(a, "idle")
    assert not res["ok"] and "edge_frame" in reasons(res)


def test_empty_sprite_flagged_low_coverage():
    a = np.zeros((64, 64, 4), dtype=np.uint8)
    res = art_qa_gate.inspect(a, "idle")
    assert not res["ok"] and "coverage_low" in reasons(res)


def test_feet_halo_flagged():
    a = blob(24, 20, cy=28)                       # body up top, base clear
    a[54:60, 20:44, :3] = (120, 120, 120)         # low-saturation gray fringe at base
    a[54:60, 20:44, 3] = 120
    res = art_qa_gate.inspect(a, "idle")
    assert "feet_halo" in reasons(res)


def test_dead_standing_pose_flagged():
    res = art_qa_gate.inspect(blob(20, 44), "dead")   # taller than wide = standing
    assert not res["ok"] and "standing_pose" in reasons(res)


def test_dead_lying_pose_passes():
    res = art_qa_gate.inspect(blob(44, 20), "dead")   # wider than tall = lying
    assert res["ok"] is True


def test_downed_standing_pose_flagged():
    res = art_qa_gate.inspect(blob(18, 46), "downed")
    assert not res["ok"] and "standing_pose" in reasons(res)


def test_two_figures_flagged_multiple():
    a = np.zeros((64, 64, 4), dtype=np.uint8)
    for (cx, w) in [(16, 14), (46, 14)]:                 # two separated figures
        a[22:50, cx - w // 2:cx + w // 2, :3] = (200, 80, 40)
        a[22:50, cx - w // 2:cx + w // 2, 3] = 255
    res = art_qa_gate.inspect(a, "downed")
    assert "multiple_figures" in reasons(res)


def test_single_figure_not_flagged_multiple():
    res = art_qa_gate.inspect(blob(44, 20), "dead")      # one lying figure
    assert "multiple_figures" not in reasons(res)


# ----- prompt construction: gen_from_brief.build_prompt ------------------------
def test_dead_prompt_is_side_lying_and_named():
    name, prompt, neg = gen_from_brief.build_prompt("enemy_grunt__dead")
    assert name == "enemy_grunt__dead.png"
    assert "on its side" in prompt and "green ichor" in prompt
    assert "standing" in neg


def test_downed_prompt_is_wounded_side_lying():
    name, prompt, neg = gen_from_brief.build_prompt("player_trooper__downed")
    assert name == "player_trooper__downed.png"
    assert "on its side" in prompt and "clutching" in prompt
    assert "standing" in neg


def test_robot_dead_prompt_uses_wreck_language():
    _, prompt, _ = gen_from_brief.build_prompt("enemy_drone__dead")
    assert "wrecked robot" in prompt and "oil" in prompt


def test_idle_prompt_named_and_backgroundless():
    name, prompt, neg = gen_from_brief.build_prompt("enemy_grunt")
    assert name == "enemy_grunt__idle.png"
    assert "gray background" in prompt and "ground" in neg


@pytest.mark.parametrize("suffix", ["__dead", "__downed"])
def test_pose_prompts_stay_short_for_clip(suffix):
    # CLIP truncates at 77 tokens; keep every pose prompt well under that (word-count
    # proxy — tokens run ~1.3x words, so <=30 words is safe).
    for key in gen_from_brief.BRIEFS["units"]:
        _, prompt, _ = gen_from_brief.build_prompt(key + suffix)
        assert len(prompt.split()) <= 30, f"{key}{suffix}: {len(prompt.split())} words"


# ----- orchestrator failure detection: art_pipeline_run.qa_failures ------------
def test_qa_failures_maps_files_to_keys(tmp_path):
    Image.fromarray(blob(44, 20), "RGBA").save(tmp_path / "enemy_grunt__dead@64.png")   # lying -> pass
    Image.fromarray(blob(18, 46), "RGBA").save(tmp_path / "enemy_boss__dead@64.png")    # standing -> fail
    fails = art_pipeline_run.qa_failures(str(tmp_path), "dead")
    keys = [k for k, _ in fails]
    assert keys == ["enemy_boss__dead"]            # only the standing one, mapped back to its key
