#!/usr/bin/env bash
# Installer for the pure-bash Claude Code status line — no python / jq needed.
#
#   ./install.sh                 install into the default config dir
#   ./install.sh --dir PATH      install into a specific config dir
#   ./install.sh --uninstall     remove the statusLine entry (keeps the script)
#
# Config dir resolution: --dir  ->  $CLAUDE_CONFIG_DIR  ->  ~/.claude
set -euo pipefail

DIR=""; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DIR="${DIR/#\~/$HOME}"
SETTINGS="$DIR/settings.json"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SELF_DIR/statusline.sh"
DEST="$DIR/statusline.sh"

# Remove a top-level "statusLine": {...} block by tracking brace balance, then
# drop any comma left dangling before a closing brace. Reads stdin, writes stdout.
strip_statusline() {
  awk '
    skip==0 && /"statusLine"[[:space:]]*:/ { skip=1; depth += gsub(/{/,"{") - gsub(/}/,"}"); if (depth<=0) skip=0; next }
    skip==1 { depth += gsub(/{/,"{") - gsub(/}/,"}"); if (depth<=0) skip=0; next }
    { print }
  ' | sed -E ':a;N;$!ba;s/,([[:space:]]*})/\1/g'
}

if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$SETTINGS" ] && grep -q '"statusLine"' "$SETTINGS"; then
    cp "$SETTINGS" "$SETTINGS.bak"
    strip_statusline < "$SETTINGS.bak" > "$SETTINGS"
    echo "removed statusLine from $SETTINGS (backup: $SETTINGS.bak)"
  else
    echo "nothing to remove (no statusLine entry)"
  fi
  exit 0
fi

mkdir -p "$DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"

# Command: the script path itself (it's executable and has a shebang). We
# deliberately do NOT prefix "bash": on Windows a bare `bash` can resolve to the
# WSL launcher (C:\Windows\System32\bash.exe), which can't read a /c/... path and
# would silently print nothing. Letting the shell run the script via its shebang
# avoids that.
#
# Prefer a ~-relative path: it matches the docs' Windows example and is the form
# Claude Code's shell reliably expands. Forward slashes keep Git Bash from eating
# backslashes as escapes. Fall back to an absolute path if the script isn't under $HOME.
dest_fwd="${DEST//\\//}"
home_fwd="${HOME//\\//}"
if [ "${dest_fwd#"$home_fwd"/}" != "$dest_fwd" ]; then
  CMD="~/${dest_fwd#"$home_fwd"/}"
else
  CMD="$dest_fwd"
fi
BLOCK=$(printf '  "statusLine": {\n    "type": "command",\n    "command": "%s",\n    "refreshInterval": 1\n  }' "$CMD")

# Merge: start from existing settings (or {}), strip any old statusLine, then
# insert the new block before the final closing brace.
if [ -f "$SETTINGS" ]; then cp "$SETTINGS" "$SETTINGS.bak"; base=$(strip_statusline < "$SETTINGS.bak"); else base="{}"; fi

body="${base%\}*}"                       # everything up to the last '}'
trimmed="${body%"${body##*[![:space:]]}"}"   # right-trim whitespace
[ "${trimmed: -1}" = "{" ] && sep="" || sep=","
mkdir -p "$DIR"
printf '%s%s\n%s\n}\n' "$trimmed" "$sep" "$BLOCK" > "$SETTINGS"

echo "installed script  -> $DEST"
echo "updated settings  -> $SETTINGS"
echo "done. Restart Claude Code (or send one message) to see the status line."
