#!/usr/bin/env python3
"""
Claude Code status line — compact and color-coded for glanceability.

Reads the session JSON on stdin (schema: code.claude.com/docs/en/statusline)
and prints the status line to stdout.

Default layout (two lines; the top line appears only when it has content):
  <branch ±dirty> · v<version>   [· ⬆<newer> when an update is available]
  <Model>[ (1m/think)] · ctx <bar> NN% NNk · 5h <bar> NN% (reset in Xh) · wk <bar> NN% · <session>

CC_STATUSLINE_VIEW switches default | oneline | minimal; CC_STATUSLINE_BARS the glyphs.

Design intent (why): a status line is read by peripheral vision, not by reading
digits. So every bar is colored by threshold — green <70% / yellow 70-89% /
red >=90% — and zero/absent values are hidden. You glance: all green = ignore,
something red = look at the number.

rate_limits (5h/wk) exist only for Pro/Max subscribers; on API billing they are
absent and we fall back to showing session cost instead.
"""
import json
import os
import sys
import time
import subprocess

# Kept in sync with package.json by scripts/sync-version.mjs on release — don't
# hand-edit. Each CC_STATUSLINE_* env knob is documented on its constant below.
__version__ = "1.1.0"
UPDATE_REPO = "brokuka/claude-statusline"
UPDATE_BRANCH = "main"
UPDATE_INTERVAL = 86400  # seconds between background update checks
# 0 hides the git branch/dirty segment. `install.py --no-git` flips the "1" default.
SHOW_GIT = os.environ.get("CC_STATUSLINE_GIT", "1") == "1"
# 0 hides the dim vX.Y.Z tag on the top line.
SHOW_VERSION = os.environ.get("CC_STATUSLINE_VERSION", "1") == "1"
# 0 hides the think:on/off segment.
SHOW_THINK = os.environ.get("CC_STATUSLINE_THINK", "1") == "1"
# View: default (2 lines) | oneline | minimal.  Bars: line | blocks | solid | ascii | dots.
VIEW = os.environ.get("CC_STATUSLINE_VIEW", "default")
BARS = os.environ.get("CC_STATUSLINE_BARS", "line")
_BAR_GLYPHS = {"blocks": ("▓", "░"), "solid": ("█", "░"), "ascii": ("#", "-"), "dots": ("●", "○")}
FILL, TRACK = _BAR_GLYPHS.get(BARS, ("━", "─"))

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
    # Default line glyphs (━ filled / ─ track) render cleanly in more terminal
    # fonts than shade blocks (▓/░); the BARS style picks the pair.
    pct = max(0, min(100, int(pct)))
    filled = round(pct * width / 100)
    return c(color_for(pct), FILL * filled) + c(DIM, TRACK * (width - filled))


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


def _vgt(a, b):
    """True if version a > b, comparing dotted numeric components."""
    def parts(s):
        out = []
        for chunk in str(s).split("."):
            digits = ""
            for ch in chunk:
                if ch.isdigit():
                    digits += ch
                else:
                    break
            out.append(int(digits or 0))
        return out
    pa, pb = parts(a), parts(b)
    n = max(len(pa), len(pb))
    pa += [0] * (n - len(pa))
    pb += [0] * (n - len(pb))
    return pa > pb


def check_update():
    """
    Return the newer version string if an update is available, else "".

    Mirrors the bash flavor: the render never blocks on the network. We read a
    cached (last_check, latest) pair; when it's stale we stamp 'now' immediately
    and kick off a detached curl to refresh it, so the next run picks it up.
    """
    if os.environ.get("CC_STATUSLINE_UPDATE", "1") != "1":
        return ""
    import shutil
    import tempfile
    if not shutil.which("curl"):
        return ""
    cache = os.path.join(tempfile.gettempdir(), "cc-statusline-update")
    last, latest = "", ""
    try:
        with open(cache) as f:
            lines = f.read().splitlines()
        last = lines[0] if lines else ""
        latest = lines[1] if len(lines) > 1 else ""
    except Exception:
        pass
    now = int(time.time())
    try:
        stale = (not last) or (now - int(last) >= UPDATE_INTERVAL)
    except ValueError:
        stale = True
    if stale:
        try:
            with open(cache, "w") as f:
                f.write(f"{now}\n{latest}\n")
        except Exception:
            pass
        url = f"https://raw.githubusercontent.com/{UPDATE_REPO}/{UPDATE_BRANCH}/package.json"
        cmd = (
            f"v=$(curl -fsSL \"{url}\" 2>/dev/null | grep -m1 '\"version\"' | tr -dc '0-9.'); "
            f'[ -n "$v" ] && printf "%s\\n%s\\n" "{now}" "$v" > "{cache}"'
        )
        try:
            subprocess.Popen(
                ["sh", "-c", cmd],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
            )
        except Exception:
            pass
    if latest and _vgt(latest, __version__):
        return latest
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


def rate_seg_compact(window, label):
    """Bar-less '5h:NN% (Xh)' segment for the minimal view; None when absent."""
    if not window:
        return None
    pct = window.get("used_percentage")
    if pct is None:
        return None
    seg = f"{label}:{c(color_for(pct), f'{int(round(pct))}%')}"
    reset = fmt_reset(window.get("resets_at", 0))
    if reset:
        seg += " " + c(DIM, f"({reset})")
    return seg


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return

    parts = []

    # Drop the trailing "(1M context)"-style qualifier — keep just "Opus 4.8".
    # Model + badge: "Opus 4.8 (1m/think)" — 1m = 1M context window, think = thinking on.
    model_name = (data.get("model") or {}).get("display_name", "?").split(" (")[0]
    badge = []
    if ((data.get("context_window") or {}).get("context_window_size") or 0) >= 1_000_000:
        badge.append("1m")
    if SHOW_THINK and (data.get("thinking") or {}).get("enabled"):
        badge.append("think")
    model_seg = c(BOLD, model_name)
    if badge:
        model_seg += " " + c(DIM, f"({'/'.join(badge)})")
    parts.append(model_seg)

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
        parts.append(c(DIM, f"ctx {TRACK * 8} --"))

    cost = data.get("cost") or {}
    rl = data.get("rate_limits") or {}
    # Rate windows: bars in default/oneline, compact "5h:NN% (Xh)" in minimal.
    seg = rate_seg_compact if VIEW == "minimal" else rate_seg
    five = seg(rl.get("five_hour"), "5h")
    week = seg(rl.get("seven_day"), "wk")
    if five:
        parts.append(five)
    if week:
        parts.append(week)
    # API billing (no rate limits) -> show cost instead of the 5h/wk bars.
    if five is None and week is None:
        usd = cost.get("total_cost_usd")
        if usd:
            parts.append(c(DIM, f"${usd:.2f}"))

    elapsed = session_elapsed(data.get("session_id"), cost.get("total_duration_ms", 0) or 0)
    parts.append(c(DIM, fmt_dur_s(elapsed)))

    sep = c(DIM, " · ")
    gitseg = git_seg() if SHOW_GIT else ""
    verseg = c(DIM, f"v{__version__}") if SHOW_VERSION else ""
    lead = [s for s in (gitseg, verseg) if s]  # git · version, when enabled

    # minimal: git/version (when enabled) lead the compact line; no update notice.
    if VIEW == "minimal":
        print(sep.join(lead + parts))
        return

    # Meta segments (git · version · update): their own top line in default,
    # folded into the single line in oneline.
    top = list(lead)
    upd = check_update()
    if upd:
        top.append(c("35", f"⬆{upd}"))

    dataline = sep.join(parts)
    if VIEW == "oneline":
        print(sep.join(top + [dataline]) if top else dataline)
    else:  # default: meta on its own top line (when present), data below
        if top:
            print(sep.join(top))
        print(dataline)


if __name__ == "__main__":
    main()
