# Changelog

All notable changes to this project are documented here. Versioning follows
[Semantic Versioning](https://semver.org/); entries are generated from
[Conventional Commits](https://www.conventionalcommits.org/) via
[changelogen](https://github.com/unjs/changelogen) — run `npm run release` to cut one.

## v1.1.0

Versioning, self-update, appearance options, and a plugin marketplace.

### Features

- **Versioning** — single source of truth in `package.json`, propagated into the
  scripts and plugin manifests by `scripts/sync-version.mjs`; `CHANGELOG.md` via
  changelogen.
- **Update check** — the status line checks GitHub once a day in the background
  (never on the per-second render) and shows a dim `⬆<version>` tag when a newer
  release exists. `install.sh --update` (or `/claude-statusline:update`) self-updates
  in place from GitHub; `--version` prints the installed version.
- **Model badge** — `Opus 4.8 (1m/think)`: `1m` when the 1M-context window is active,
  `think` when extended thinking is on (from the session JSON's `thinking.enabled`).
- **Version tag** — a dim `vX.Y.Z` on the top line, toggleable.
- **Views** (`--view`) — `default` (two lines), `oneline` (single line), and
  `minimal` (one compact line: git · version · model · ctx bar · bar-less rate
  windows like `5h:62% (3h)` · timer).
- **Bar styles** (`--bars`) — `line`, `blocks`, `solid`, `ascii`, `dots`.
- **Toggles** — git and version segments hide/show via `--no-git`/`--git` and
  `--hide-version`/`--show-version`, or the `CC_STATUSLINE_*` env vars. All baked
  into the installed copy and preserved across `--update`.
- **Plugin marketplace** — install via `/plugin marketplace add brokuka/claude-statusline`
  then `/plugin install claude-statusline`; `/claude-statusline:setup` wires it up and
  `/claude-statusline:configure` opens a menu for layout, bar style, and toggles.

## v1.0.0

Initial release: a compact, color-coded status line for Claude Code in bash (zero
runtime deps) and python flavors, with an installer that merges a `statusLine` entry
into `settings.json` without touching other settings.
