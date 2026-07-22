---
description: Install the claude-statusline color-coded status line into your Claude Code settings
argument-hint: [--dir PATH] [--no-git] [--view NAME] [--bars NAME] [--python]
allowed-tools: Bash(bash:*), Bash(python:*), Bash(python3:*)
---

Install the status line, forwarding the user's arguments verbatim. Run it, show the
output, and tell the user to send one message (or restart) to see the line. Use the
Python line instead only if the user passed `--python`.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/install.sh" $ARGUMENTS
# --python: python "${CLAUDE_PLUGIN_ROOT}/install.py"
```
