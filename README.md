# claude-statusline

A compact, color-coded [status line](https://code.claude.com/docs/en/statusline) for
[Claude Code](https://claude.com/claude-code), read by peripheral vision:

```
main ±2 · v1.1.0
Opus 4.8 (1m/think) · ctx ━━━───── 34% 68k · 5h ━━────── 22% (reset in 3h) · wk ━━━━━━── 76% (reset in 2d) · 1h24m
```

(git branch · version — plus an `⬆<version>` tag when an update is available — on
the top line; when none are present it's just the one data line.)

- **`ctx`** — context window used (bar + % + absolute tokens). Always visible, even at 0%.
- **`5h` / `wk`** — 5-hour and weekly rate-limit windows, with a countdown to reset
  *(Pro/Max only; on API billing these are replaced by session cost `$1.37`)*.
- **session timer** at the end — live wall-clock, ticks every second.
- **git branch + dirty count** at the start, only when you're in a repo.
- **model badge** — a dim `(…)` after the model name: `1m` when the 1M-context
  window is active, `think` when extended thinking is on — e.g. `Opus 4.8 (1m/think)`.

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

### Option A — plugin marketplace (one message)

```
/plugin marketplace add brokuka/claude-statusline
/plugin install claude-statusline
/claude-statusline:setup
```

Claude Code can't wire a `statusLine` from a plugin manifest directly, so the
plugin ships a `setup` command that runs the same installer for you. Pass the
Python flavor with `/claude-statusline:setup --python`.

### Option B — clone and run the installer

```bash
git clone https://github.com/brokuka/claude-statusline.git
cd claude-statusline

./install.sh          # Bash flavor (no dependencies)
# or:
python install.py     # Python flavor
```

Either way, the installer copies the script into your Claude Code config dir and
merges a `statusLine` entry into `settings.json` **without touching your other
settings**. Restart Claude Code (or send one message) and the line appears at the
bottom.

Custom config dir (e.g. a named profile) — both installers accept the same flags:

```bash
./install.sh --dir ~/.claude-work
# or honor the env var Claude Code itself uses:
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh
```

> **Windows:** run the installer from **Git Bash** (`./install.sh`). Claude Code runs
> the status line through Git Bash too, so the Bash flavor works out of the box.

## Updating

The status line checks GitHub for a newer version **once a day, in the background**
(never on the per-second render), and when one exists it shows a small `⬆1.1.0` tag
on the git line. It only notifies — it never updates itself. When you want it:

```bash
./install.sh --update      # or: python install.py --update
```

That downloads the latest script straight from GitHub and swaps your installed copy
in place (works even if your clone is gone). The plugin exposes the same thing as
`/claude-statusline:update`. Check your version any time with `./install.sh --version`.

## Toggles

The **git** and **version** segments are shown by default. Toggle either with a
single command — the preference is baked into your installed copy and survives
`--update`:

```bash
./install.sh --no-git         # hide git      (--git to restore)
./install.sh --hide-version   # hide version  (--show-version to restore)
```

Via the plugin these live in the `/claude-statusline:configure` menu. Prefer env
vars instead? Both flavors honor these at runtime (they win over the baked-in default):

| Env var | Default | Effect |
| --- | --- | --- |
| `CC_STATUSLINE_GIT` | `1` | `0` hides the git branch/dirty segment (and skips the git forks) |
| `CC_STATUSLINE_VERSION` | `1` | `0` hides the dim `vX.Y.Z` tag |
| `CC_STATUSLINE_THINK` | `1` | `0` drops `think` from the model badge (extended-thinking indicator) |
| `CC_STATUSLINE_UPDATE` | `1` | `0` disables the daily update check entirely |

## Views & bar styles

Two independent knobs — layout and bar glyphs — baked into your installed copy and
kept across `--update`:

```bash
./install.sh --view oneline    # default | oneline | minimal
./install.sh --bars blocks     # line | blocks | solid | ascii | dots
```

- **`--view`** — `default` (git/version on a top line, data below), `oneline`
  (everything on one line), `minimal` (one compact line: git · version · model ·
  ctx bar · bar-less rate windows `5h:62% (3h)` · timer).
- **`--bars`** — `line` `━━━─────` · `blocks` `▓▓▓░░░░░` · `solid` `███░░░░░` ·
  `ascii` `###-----` · `dots` `●●●○○○○○`.

Via the plugin, `/claude-statusline:configure` pops a menu to pick layout, bar style,
and the git / version toggles in one go. At runtime `CC_STATUSLINE_VIEW` /
`CC_STATUSLINE_BARS` override the baked-in choice.

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

## Releasing (maintainers)

Version lives in `package.json` (the single source of truth) and is driven by
[Conventional Commits](https://www.conventionalcommits.org/) via
[changelogen](https://github.com/unjs/changelogen):

```bash
npm run release
```

That bumps the version, regenerates `CHANGELOG.md`, tags, and runs
`scripts/sync-version.mjs` to bake the new version into `statusline.sh`,
`statusline.py`, and the plugin manifests — then pushes commits and tags. The
runtime update check reads the version straight from `package.json` on `main`, so
there's no separate version file to keep in step.

## License

MIT
