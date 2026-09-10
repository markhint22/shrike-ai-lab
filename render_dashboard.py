#!/usr/bin/env python3
"""render_dashboard.py — turn state/fleet_stats.json into a self-contained
www/fleet_dashboard.html (CLAUDE_QUEUE.md §19). Run right after fleet_stats.py
on the same cron tick. No external assets, no JS framework, no network calls
at render OR view time - the JSON is baked into the page, so it works from a
plain `file://` open or a bare static-file server with no CORS/build step.
Reads the same theme approach as claude.ai Artifacts (prefers-color-scheme,
no fixed light/dark commitment) since this is viewed the same ad-hoc way.

Output lives in a dedicated www/ directory, not state/ - state/ also holds
task_stats.log, outcomes.jsonl, failures/, alerts.log, etc., none of which
should be reachable if www/ is ever pointed at by a static file server (see
serve_dashboard.sh). www/ contains nothing but this one generated file.
"""
import html
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_DIR = os.path.join(SCRIPT_DIR, "state")
WWW_DIR = os.path.join(SCRIPT_DIR, "www")
STATS_FILE = os.path.join(STATE_DIR, "fleet_stats.json")
OUT_FILE = os.path.join(WWW_DIR, "fleet_dashboard.html")


def fmt_num(n):
    if n is None:
        return "—"
    if isinstance(n, float):
        return f"{n:,.1f}"
    return f"{n:,}"


def runway_class(days):
    if days is None:
        return ""
    if days < 1:
        return "runway-low"
    if days < 3:
        return "runway-warn"
    return ""


def pass_rate_class(rate):
    if rate is None:
        return ""
    if rate < 70:
        return "rate-low"
    if rate < 85:
        return "rate-warn"
    return "rate-good"


def render_category_bars(cats):
    if not cats:
        return "<span class='muted'>no attempts recorded</span>"
    rows = []
    for cat, v in sorted(cats.items(), key=lambda kv: -kv[1]["attempted"]):
        rate = v["pass_rate"]
        pct = rate if rate is not None else 0
        rows.append(
            f"<div class='cat-row'>"
            f"<span class='cat-name'>{html.escape(cat)}</span>"
            f"<div class='cat-bar-track'><div class='cat-bar-fill {pass_rate_class(rate)}' "
            f"style='width:{pct}%'></div></div>"
            f"<span class='cat-num'>{fmt_num(rate)}% <span class='muted'>({v['landed']}/{v['attempted']})</span></span>"
            f"</div>"
        )
    return "".join(rows)


def render_repo_card(name, r):
    doable = r.get("doable")
    doable_class = "stat-danger" if (doable is not None and doable < 5) else ""
    unpromoted = r.get("unpromoted")
    unpromoted_class = "stat-warn" if (unpromoted is not None and unpromoted > 30) else ""
    return f"""
    <div class="repo-card">
      <h3>{html.escape(name)}</h3>
      <div class="stat-grid">
        <div class="stat"><span class="stat-label">Doable</span>
          <span class="stat-value {doable_class}">{fmt_num(doable)}</span></div>
        <div class="stat"><span class="stat-label">Done</span>
          <span class="stat-value">{fmt_num(r.get('done'))}</span></div>
        <div class="stat"><span class="stat-label">Landed (24h)</span>
          <span class="stat-value">{fmt_num(r.get('landed_1d'))}</span></div>
        <div class="stat"><span class="stat-label">Landed (7d)</span>
          <span class="stat-value">{fmt_num(r.get('landed_7d'))}</span></div>
        <div class="stat"><span class="stat-label">Runway</span>
          <span class="stat-value {runway_class(r.get('runway_days'))}">{fmt_num(r.get('runway_days'))}d</span></div>
        <div class="stat"><span class="stat-label">Unpromoted</span>
          <span class="stat-value {unpromoted_class}">{fmt_num(unpromoted)}</span></div>
      </div>
      <div class="pass-rate-line">
        <span class="stat-label">Pass rate (7d)</span>
        <span class="stat-value {pass_rate_class(r.get('pass_rate_7d'))}">{fmt_num(r.get('pass_rate_7d'))}%</span>
      </div>
      <div class="categories">{render_category_bars(r.get('by_category_7d', {}))}</div>
    </div>"""


def main():
    try:
        with open(STATS_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except OSError:
        print(f"no {STATS_FILE} yet - run fleet_stats.py first", file=sys.stderr)
        return 1

    generated_at = data.get("generated_at", "unknown")
    fleet = data.get("fleet", {})
    repos = data.get("repos", {})

    cards = "".join(
        render_repo_card(name, r) for name, r in sorted(repos.items())
    )

    html_out = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Shrike Fleet Dashboard</title>
<style>
  :root {{
    color-scheme: light dark;
    --bg: #0b0d10; --card: #14171c; --border: #262b33; --text: #e6e9ee;
    --muted: #8b92a0; --accent: #5b8cff; --good: #3ddc84; --warn: #f5c451; --danger: #ff6b6b;
  }}
  @media (prefers-color-scheme: light) {{
    :root {{ --bg: #f5f6f8; --card: #ffffff; --border: #e1e4e9; --text: #1a1d23; --muted: #666d7a; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 2rem 1.25rem 4rem; background: var(--bg); color: var(--text);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  }}
  h1 {{ font-size: 1.4rem; margin: 0 0 0.25rem; }}
  .subtitle {{ color: var(--muted); font-size: 0.85rem; margin-bottom: 1.75rem; }}
  .fleet-summary {{
    display: flex; gap: 1.5rem; flex-wrap: wrap; margin-bottom: 2rem;
    padding: 1rem 1.25rem; background: var(--card); border: 1px solid var(--border); border-radius: 10px;
  }}
  .fleet-stat {{ display: flex; flex-direction: column; }}
  .fleet-stat .label {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; }}
  .fleet-stat .value {{ font-size: 1.3rem; font-weight: 600; }}
  .grid {{
    display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 1rem;
  }}
  .repo-card {{
    background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 1.1rem 1.25rem;
  }}
  .repo-card h3 {{ margin: 0 0 0.75rem; font-size: 1.05rem; }}
  .stat-grid {{
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 0.6rem 0.5rem; margin-bottom: 0.75rem;
  }}
  .stat {{ display: flex; flex-direction: column; }}
  .stat-label {{ color: var(--muted); font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.03em; }}
  .stat-value {{ font-size: 1.05rem; font-weight: 600; }}
  .stat-danger {{ color: var(--danger); }}
  .stat-warn {{ color: var(--warn); }}
  .pass-rate-line {{
    display: flex; justify-content: space-between; align-items: baseline;
    padding-top: 0.6rem; border-top: 1px solid var(--border); margin-bottom: 0.75rem;
  }}
  .rate-good {{ color: var(--good); }}
  .rate-warn {{ color: var(--warn); }}
  .rate-low {{ color: var(--danger); }}
  .runway-warn {{ color: var(--warn); }}
  .runway-low {{ color: var(--danger); }}
  .categories {{ display: flex; flex-direction: column; gap: 0.35rem; }}
  .cat-row {{ display: flex; align-items: center; gap: 0.5rem; font-size: 0.78rem; }}
  .cat-name {{ width: 72px; flex-shrink: 0; color: var(--muted); text-transform: capitalize; }}
  .cat-bar-track {{
    flex: 1; height: 6px; background: var(--border); border-radius: 3px; overflow: hidden;
  }}
  .cat-bar-fill {{ height: 100%; background: var(--accent); }}
  .cat-bar-fill.rate-good {{ background: var(--good); }}
  .cat-bar-fill.rate-warn {{ background: var(--warn); }}
  .cat-bar-fill.rate-low {{ background: var(--danger); }}
  .cat-num {{ width: 110px; text-align: right; flex-shrink: 0; }}
  .muted {{ color: var(--muted); }}
</style>
</head>
<body>
  <h1>Shrike Fleet Dashboard</h1>
  <div class="subtitle">Generated {html.escape(generated_at)} &middot; private, not indexed</div>

  <div class="fleet-summary">
    <div class="fleet-stat"><span class="label">llama requests / day</span>
      <span class="value">{fmt_num(fleet.get('llama_requests_today'))}</span></div>
    <div class="fleet-stat"><span class="label">tokens / day</span>
      <span class="value">{fmt_num(fleet.get('tokens_today'))}</span></div>
    <div class="fleet-stat"><span class="label">context overflows today</span>
      <span class="value">{fmt_num(fleet.get('context_overflow_today'))}</span></div>
  </div>

  <div class="grid">{cards}</div>
</body>
</html>"""

    os.makedirs(WWW_DIR, exist_ok=True)
    tmp = OUT_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(html_out)
    os.replace(tmp, OUT_FILE)
    print(f"wrote {OUT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
