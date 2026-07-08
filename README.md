# claude-statusline

A compact, color-coded [status line](https://code.claude.com/docs/en/statusline) for
[Claude Code](https://claude.com/claude-code), read by peripheral vision:

```
main ±2
Opus 4.8 · ctx ━━━───── 34% 68k · 5h ━━────── 22% (reset in 3h) · wk ━━━━━━── 76% (reset in 2d) · 1h24m
```

(git branch on top; when you're not in a repo it's just the one data line.)

- **`ctx`** — context window used (bar + % + absolute tokens). Always visible, even at 0%.
- **`5h` / `wk`** — 5-hour and weekly rate-limit windows, with a countdown to reset
  *(Pro/Max only; on API billing these are replaced by session cost `$1.37`)*.
- **session timer** at the end — live wall-clock, ticks every second.
- **git branch + dirty count** at the start, only when you're in a repo.

Every bar is colored by threshold so you don't have to read the numbers:
**green < 70% · yellow 70–89% · red ≥ 90%**. All green → ignore it. Something red → look.

## Two flavors — pick one

Both produce the exact same output. Use whichever runtime you'd rather depend on.

| | Runtime dependency | Files |
| --- | --- | --- |
| **Bash** (default) | none — Bash only (bundled with Git on Windows) | `statusline.sh` + `install.sh` |
| **Python** | Python 3.7+ (preinstalled on most macOS/Linux) | `statusline.py` + `install.py` |

The Bash flavor needs **nothing installed at runtime**; that's the recommended one.

## Install

```bash
git clone https://github.com/brokuka/claude-statusline.git
cd claude-statusline

./install.sh          # Bash flavor (no dependencies)
# or:
python install.py     # Python flavor
```

The installer copies the script into your Claude Code config dir and merges a
`statusLine` entry into `settings.json` **without touching your other settings**.
Restart Claude Code (or send one message) and the line appears at the bottom.

Custom config dir (e.g. a named profile) — both installers accept the same flags:

```bash
./install.sh --dir ~/.claude-work
# or honor the env var Claude Code itself uses:
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh
```

> **Windows:** run the installer from **Git Bash** (`./install.sh`). Claude Code runs
> the status line through Git Bash too, so the Bash flavor works out of the box.

## Uninstall

```bash
./install.sh --uninstall      # or: python install.py --uninstall
```

Removes the `statusLine` entry (and leaves a `settings.json.bak` backup); the script
file stays.

## Customize

Everything lives in one small, commented script — `statusline.sh` (or `.py`):

| Want to change | Where (`.sh` / `.py`) |
| --- | --- |
| Bar width | `w=8` in `bar()` / `width=8` in `bar()` |
| Color thresholds | `bar()` / `color_for()` (defaults 70 / 90) |
| Segment order / which segments show | the build-up of `data` / the `parts` list |
| Reset countdown wording | `fmt_reset()` / `rate_seg()` |
| Session timer format | `fmt_dur()` / `fmt_dur_s()` |

Edit the copy in your config dir, or edit here and re-run the installer.

## How it works

Claude Code pipes [session JSON](https://code.claude.com/docs/en/statusline#available-data)
to the script on stdin; the script prints the line(s) to stdout. `refreshInterval: 1`
re-runs it every second so the timer and reset countdowns stay live while you work.

The session timer is computed from a per-session start epoch cached in your temp dir
(`cc-statusline-start-<session_id>`), because Claude Code's `cost.total_duration_ms`
only updates on new messages — reading it directly would look frozen between turns.

## License

MIT
