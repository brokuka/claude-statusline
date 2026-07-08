#!/usr/bin/env python3
"""
Claude Code status line — compact and color-coded for glanceability.

Reads the session JSON on stdin (schema: code.claude.com/docs/en/statusline)
and prints the status line to stdout.

Layout (two lines; line 1 omitted when not in a git repo):
  <branch ±dirty>
  <Model> · ctx <bar> NN% NNk · 5h <bar> NN% (reset in Xh) · wk <bar> NN% (reset in Xd) · <session>

Design intent (why): a status line is read by peripheral vision, not by reading
digits. So every bar is colored by threshold — green <70% / yellow 70-89% /
red >=90% — and zero/absent values are hidden. You glance: all green = ignore,
something red = look at the number.

rate_limits (5h/wk) exist only for Pro/Max subscribers; on API billing they are
absent and we fall back to showing session cost instead.
"""
import json
import sys
import time
import subprocess

# On Windows the default stdout encoding is the legacy ANSI code page, which
# can't encode the bar/dot glyphs (━ ─ ·) and would crash with UnicodeEncodeError.
# Force UTF-8 so the line renders everywhere.
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdin.reconfigure(encoding="utf-8")
except Exception:
    pass

# --- ANSI helpers -----------------------------------------------------------
DIM, BOLD = "2", "1"
GREEN, YELLOW, RED, CYAN = "32", "33", "31", "36"


def c(code, s):
    return f"\033[{code}m{s}\033[0m"


def color_for(pct):
    return RED if pct >= 90 else YELLOW if pct >= 70 else GREEN


def bar(pct, width=8):
    # Line glyphs (━ filled / ─ track) render cleanly in more terminal fonts
    # than shade blocks (▓/░), which smear into a grey smudge at small sizes.
    pct = max(0, min(100, int(pct)))
    filled = round(pct * width / 100)
    return c(color_for(pct), "━" * filled) + c(DIM, "─" * (width - filled))


# --- formatters -------------------------------------------------------------
def fmt_reset(epoch):
    """Countdown to a rate-limit window reset, coarse (hours, else minutes)."""
    try:
        d = int(float(epoch) - time.time())
    except (TypeError, ValueError):
        return ""
    if d <= 0:
        return ""
    if d >= 48 * 3600:  # collapse long waits to days to keep the line short
        return f"{d // 86400}d"
    h, m = d // 3600, (d % 3600) // 60
    return f"{h}h" if h else f"{m}m"


def fmt_dur_s(seconds):
    """Session elapsed; keep seconds visible under 1h so it ticks live."""
    s = int(seconds)
    h, m, sec = s // 3600, (s % 3600) // 60, s % 60
    if h:
        return f"{h}h{m:02d}m"
    if m:
        return f"{m}m{sec:02d}s"
    return f"{sec}s"


def session_elapsed(session_id, cost_ms):
    """
    Live wall-clock since session start.

    cost.total_duration_ms only refreshes on new messages, so the timer looks
    frozen between them. We instead persist a start epoch per session_id (temp
    file) and compute now - start on every refresh tick, so seconds advance live.
    Seed the start from the reported duration so already-elapsed time isn't lost.
    """
    now = time.time()
    if not session_id:
        return (cost_ms or 0) / 1000
    import os
    import tempfile
    path = os.path.join(tempfile.gettempdir(), f"cc-statusline-start-{session_id}")
    try:
        with open(path) as f:
            return now - float(f.read().strip())
    except Exception:
        pass
    start = now - (cost_ms or 0) / 1000
    try:
        with open(path, "w") as f:
            f.write(str(start))
    except Exception:
        pass
    return now - start


def kfmt(n):
    n = int(n or 0)
    return f"{n / 1000:.0f}k" if n >= 1000 else str(n)


def git_seg():
    """Branch + dirty count, colored; empty string when not in a git repo."""
    try:
        branch = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=1,
        ).stdout.strip()
        if not branch:
            return ""
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True, text=True, timeout=1,
        ).stdout
        dirty = sum(1 for line in status.splitlines() if line.strip())
        seg = c(CYAN, branch)
        if dirty:
            seg += " " + c(YELLOW, f"±{dirty}")
        return seg
    except Exception:
        return ""


def rate_seg(window, label):
    """A '5h'/'wk' segment; None when this window is absent (API billing)."""
    if not window:
        return None
    pct = window.get("used_percentage")
    if pct is None:
        return None
    reset = fmt_reset(window.get("resets_at", 0))
    seg = f"{label} {bar(pct)} {int(round(pct))}%"
    if reset:
        seg += " " + c(DIM, f"(reset in {reset})")
    return seg


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    parts = []

    # Drop the trailing "(1M context)"-style qualifier — keep just "Opus 4.8".
    model_name = (data.get("model") or {}).get("display_name", "?").split(" (")[0]
    parts.append(c(BOLD, model_name))

    cw = data.get("context_window") or {}
    pct = cw.get("used_percentage")
    used_tokens = cw.get("total_input_tokens", 0) or 0
    # Fallback: used_percentage is null before the first API response and right
    # after /compact. Derive it from current_usage (input-only, to match how
    # Claude Code computes used_percentage) so ctx doesn't blink out.
    if pct is None:
        cu = cw.get("current_usage") or {}
        size = cw.get("context_window_size") or 0
        inp = (
            (cu.get("input_tokens", 0) or 0)
            + (cu.get("cache_creation_input_tokens", 0) or 0)
            + (cu.get("cache_read_input_tokens", 0) or 0)
        )
        if size and inp:
            pct, used_tokens = inp * 100 / size, inp
    if pct is not None:
        parts.append(f"ctx {bar(pct)} {int(pct)}% {c(DIM, kfmt(used_tokens))}")
    else:
        # Always keep the ctx slot visible so the eye knows where to look.
        parts.append(c(DIM, "ctx ──────── --"))

    rl = data.get("rate_limits") or {}
    five = rate_seg(rl.get("five_hour"), "5h")
    week = rate_seg(rl.get("seven_day"), "wk")
    if five:
        parts.append(five)
    if week:
        parts.append(week)

    cost = data.get("cost") or {}
    # API billing (no rate limits) -> show cost instead of the 5h/wk bars.
    if five is None and week is None:
        usd = cost.get("total_cost_usd")
        if usd:
            parts.append(c(DIM, f"${usd:.2f}"))

    elapsed = session_elapsed(data.get("session_id"), cost.get("total_duration_ms", 0) or 0)
    parts.append(c(DIM, fmt_dur_s(elapsed)))

    # Two lines: git branch on top (frees horizontal room), data below. The
    # branch line is omitted entirely when we're not inside a git repo.
    branch = git_seg()
    if branch:
        print(branch)
    print(c(DIM, " · ").join(parts))


if __name__ == "__main__":
    main()
