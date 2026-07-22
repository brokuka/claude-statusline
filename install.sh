#!/usr/bin/env bash
# Installer for the pure-bash Claude Code status line — no python / jq needed.
#
#   ./install.sh                 install into the default config dir
#   ./install.sh --dir PATH      install into a specific config dir
#   ./install.sh --uninstall     remove the statusLine entry (keeps the script)
#   ./install.sh --update        replace the installed script with the latest from GitHub
#   ./install.sh --version       print the bundled version and exit
#   ./install.sh --no-git        hide the git branch/dirty segment (default: shown)
#   ./install.sh --git           show the git branch/dirty segment (restore default)
#   ./install.sh --toggle-git    flip the installed copy's git segment in place
#   ./install.sh --view NAME     layout: default | oneline | minimal
#   ./install.sh --bars NAME     bar style: line | blocks | solid | ascii | dots
#   ./install.sh --hide-version  hide the dim vX.Y.Z tag   (--show-version to restore)
#
# --git / --no-git / --view / --bars / --show-version / --hide-version can
# accompany an install or run on their own to change an already-installed copy in
# place; --toggle-git flips git. All of these preferences survive --update.
#
# Config dir resolution: --dir  ->  $CLAUDE_CONFIG_DIR  ->  ~/.claude
set -euo pipefail

REPO="brokuka/claude-statusline"; BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

DIR=""; UNINSTALL=0; UPDATE=0; SHOWVER=0; GITMODE=""; TOGGLEGIT=0; VIEWVAL=""; BARSVAL=""; VERMODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --update) UPDATE=1; shift ;;
    --version) SHOWVER=1; shift ;;
    --git) GITMODE=on; shift ;;
    --no-git) GITMODE=off; shift ;;
    --toggle-git) TOGGLEGIT=1; shift ;;
    --show-version) VERMODE=on; shift ;;
    --hide-version) VERMODE=off; shift ;;
    --view) VIEWVAL="$2"; shift 2 ;;
    --bars) BARSVAL="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$VIEWVAL" in ""|default|oneline|minimal) ;; *) echo "invalid --view '$VIEWVAL' (default|oneline|minimal)" >&2; exit 1 ;; esac
case "$BARSVAL" in ""|line|blocks|solid|ascii|dots) ;; *) echo "invalid --bars '$BARSVAL' (line|blocks|solid|ascii|dots)" >&2; exit 1 ;; esac
[ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DIR="${DIR/#\~/$HOME}"
SETTINGS="$DIR/settings.json"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SELF_DIR/statusline.sh"
DEST="$DIR/statusline.sh"

_ver_of() { sed -n 's/^STATUSLINE_VERSION="\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1; }

# Read/flip the SHOW_GIT default baked into an installed script copy. Uses a temp
# file instead of `sed -i` so it works on both GNU and BSD sed.
_git_default() { sed -n -E 's/^SHOW_GIT="\$\{CC_STATUSLINE_GIT:-([01])\}".*/\1/p' "$1" 2>/dev/null | head -1; }
_set_git() { # $1=file  $2=on|off
  local n=1 t; [ "$2" = off ] && n=0; t="$1.gittmp.$$"
  sed -E "s/^(SHOW_GIT=\"\\\$\\{CC_STATUSLINE_GIT:-)[01](\\}\")/\\1${n}\\2/" "$1" > "$t" && mv "$t" "$1"
  chmod +x "$1" 2>/dev/null || true
}
# Generic: read/patch the default inside  VAR="${ENV:-DEFAULT}"  ($2=VAR $3=ENV).
_kv_default() { sed -n -E "s/^$2=\"\\\$\\{$3:-([^}]*)\\}\".*/\\1/p" "$1" 2>/dev/null | head -1; }
_set_kv() { # $1=file $2=VAR $3=ENV $4=value
  local t="$1.kvtmp.$$"
  sed -E "s/^($2=\"\\\$\\{$3:-)[^}]*(\\}\")/\\1$4\\2/" "$1" > "$t" && mv "$t" "$1"
  chmod +x "$1" 2>/dev/null || true
}
_apply_style() { # $1=file — apply any pending --view/--bars to it
  [ -n "$VIEWVAL" ] && _set_kv "$1" VIEW CC_STATUSLINE_VIEW "$VIEWVAL"
  [ -n "$BARSVAL" ] && _set_kv "$1" BARS CC_STATUSLINE_BARS "$BARSVAL"
  return 0
}
_set_ver() { _set_kv "$1" SHOW_VERSION CC_STATUSLINE_VERSION "$([ "$2" = off ] && echo 0 || echo 1)"; }

if [ "$SHOWVER" = 1 ]; then
  echo "claude-statusline $(_ver_of "$SRC")"
  exit 0
fi

# --toggle-git: flip the installed copy's git segment in place and exit. This is
# what the /claude-statusline:git plugin command runs — no reinstall, no settings
# touched, so it's a cheap on/off switch.
if [ "$TOGGLEGIT" = 1 ]; then
  [ -f "$DEST" ] || { echo "not installed at $DEST" >&2; exit 1; }
  cur=$(_git_default "$DEST"); [ "$cur" = 0 ] && m=on || m=off
  _set_git "$DEST" "$m"
  echo "git segment: $([ "$m" = off ] && echo hidden || echo shown) -> $DEST"
  exit 0
fi

# --git/--no-git/--view/--bars on an existing install: change those settings in
# the installed copy in place and exit — no reinstall, settings.json untouched.
# This is what the /claude-statusline:git and :configure plugin commands run. If
# nothing is installed yet, fall through to a normal install that bakes them in.
if { [ -n "$GITMODE" ] || [ -n "$VERMODE" ] || [ -n "$VIEWVAL" ] || [ -n "$BARSVAL" ]; } && [ "$UPDATE" = 0 ] && [ "$UNINSTALL" = 0 ] && [ -f "$DEST" ]; then
  [ -n "$GITMODE" ] && _set_git "$DEST" "$GITMODE"
  [ -n "$VERMODE" ] && _set_ver "$DEST" "$VERMODE"
  _apply_style "$DEST"
  gitstate=$([ "$(_git_default "$DEST")" = 0 ] && echo hidden || echo shown)
  verstate=$([ "$(_kv_default "$DEST" SHOW_VERSION CC_STATUSLINE_VERSION)" = 0 ] && echo hidden || echo shown)
  echo "updated -> git:${gitstate} version:${verstate} view:$(_kv_default "$DEST" VIEW CC_STATUSLINE_VIEW) bars:$(_kv_default "$DEST" BARS CC_STATUSLINE_BARS)  ($DEST)"
  exit 0
fi

# Self-update: pull the latest script straight from GitHub and swap the installed
# copy in place. Works even when this clone is stale (or gone) — it only needs the
# already-installed DEST to exist. Notifies but never touches settings.json.
if [ "$UPDATE" = 1 ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl not found — cannot self-update" >&2; exit 1; }
  [ -f "$DEST" ] || { echo "not installed at $DEST — run ./install.sh first" >&2; exit 1; }
  cur=$(_ver_of "$DEST")
  # `|| true` so a failed fetch (offline / 404) doesn't trip `set -e -o pipefail`
  # before we can print a friendly message.
  latest=$(curl -fsSL "$RAW/package.json" 2>/dev/null | grep -m1 '"version"' | tr -dc '0-9.' || true)
  echo "current: ${cur:-unknown}"
  echo "latest:  ${latest:-unknown}"
  [ -n "$latest" ] || { echo "could not reach GitHub (not published yet, or offline)" >&2; exit 1; }
  if [ "$cur" = "$latest" ]; then echo "already up to date."; exit 0; fi
  prev_git=$(_git_default "$DEST")                 # remember preferences before overwrite
  prev_ver=$(_kv_default "$DEST" SHOW_VERSION CC_STATUSLINE_VERSION)
  prev_view=$(_kv_default "$DEST" VIEW CC_STATUSLINE_VIEW)
  prev_bars=$(_kv_default "$DEST" BARS CC_STATUSLINE_BARS)
  tmp="$DEST.new"
  if curl -fsSL "$RAW/statusline.sh" -o "$tmp"; then
    mv "$tmp" "$DEST"; chmod +x "$DEST"
    # Carry the user's preferences across the update: an explicit flag wins,
    # otherwise re-apply whatever was set before.
    if [ -n "$GITMODE" ]; then _set_git "$DEST" "$GITMODE"
    elif [ "$prev_git" = 0 ]; then _set_git "$DEST" off; fi
    if [ -n "$VERMODE" ]; then _set_ver "$DEST" "$VERMODE"
    elif [ "$prev_ver" = 0 ]; then _set_ver "$DEST" off; fi
    [ -n "$VIEWVAL" ] && _set_kv "$DEST" VIEW CC_STATUSLINE_VIEW "$VIEWVAL" || { [ -n "$prev_view" ] && [ "$prev_view" != default ] && _set_kv "$DEST" VIEW CC_STATUSLINE_VIEW "$prev_view"; }
    [ -n "$BARSVAL" ] && _set_kv "$DEST" BARS CC_STATUSLINE_BARS "$BARSVAL" || { [ -n "$prev_bars" ] && [ "$prev_bars" != line ] && _set_kv "$DEST" BARS CC_STATUSLINE_BARS "$prev_bars"; }
    rm -f "${TMPDIR:-/tmp}/cc-statusline-update"   # clear the cached "update available" notice
    echo "✓ updated $DEST -> ${latest}"
  else
    rm -f "$tmp"; echo "download failed" >&2; exit 1
  fi
  exit 0
fi

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
[ -n "$GITMODE" ] && _set_git "$DEST" "$GITMODE"   # apply --git/--no-git to the fresh copy
[ -n "$VERMODE" ] && _set_ver "$DEST" "$VERMODE"   # apply --show/--hide-version
_apply_style "$DEST"                                # apply --view/--bars to the fresh copy

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
[ -n "$GITMODE" ] && echo "git segment       -> $([ "$GITMODE" = off ] && echo hidden || echo shown)"
[ -n "$VERMODE" ] && echo "version tag       -> $([ "$VERMODE" = off ] && echo hidden || echo shown)"
{ [ -n "$VIEWVAL" ] || [ -n "$BARSVAL" ]; } && echo "style             -> view:$(_kv_default "$DEST" VIEW CC_STATUSLINE_VIEW) bars:$(_kv_default "$DEST" BARS CC_STATUSLINE_BARS)"
echo "done. Restart Claude Code (or send one message) to see the status line."
