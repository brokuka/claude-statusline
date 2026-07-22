---
description: Pick the status line layout, bar style, git and version segments from a menu
allowed-tools: Bash(bash:*)
---

Let the user choose their status line appearance interactively, then apply it.

Call the **AskUserQuestion** tool with these four single-select questions:

- header **"Layout"**, question "Which layout?":
  - `default` — git & version on a top line, all data below (two lines)
  - `oneline` — everything on a single line
  - `minimal` — one compact line: git · version · model · ctx bar · bar-less rate windows (`5h:62% (3h)`) · timer
- header **"Bars"**, question "Which bar style?":
  - `line` `━━━─────` · `blocks` `▓▓▓░░░░░` · `solid` `███░░░░░` · `dots` `●●●○○○○○`
  - (the 5th style, `ascii` `###-----`, is available if the user picks "Other" and types it)
- header **"Git"**, question "Show the git branch?": `shown` (default) · `hidden`
- header **"Version"**, question "Show the version tag?": `shown` (default) · `hidden`

Then apply all four at once — substitute the layout/bars verbatim, map Git to `--git`
(shown) / `--no-git` (hidden), and Version to `--show-version` / `--hide-version`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" --view <layout> --bars <bars> --git --show-version
```

Report the result and tell the user to send one message (or restart the app) for it
to take effect.
