#!/usr/bin/env bash
# Claude Code status line — pure bash, no jq / python / node.
#
# Reads the session JSON on stdin (schema: code.claude.com/docs/en/statusline)
# and prints the status line to stdout.
#
# Default layout (two lines; the top line appears only when it has content):
#   <branch ±dirty> · v<version> [· ⬆<newer> when an update is available]
#   <Model>[ (1m/think)] · ctx <bar> NN% NNk · 5h <bar> NN% (reset in Xh) · wk <bar> NN% · <session>
# CC_STATUSLINE_VIEW switches default | oneline | minimal; CC_STATUSLINE_BARS the glyphs.
#
# Design intent (why): a status line is read by peripheral vision, not by
# reading digits — so every bar is colored by threshold (green <70% /
# yellow 70-89% / red >=90%) and zero/absent values are hidden.
#
# IMPORTANT (why it's written this oddly): this runs every second, and on
# Windows Claude Code runs it under Git Bash, whose fork() is an expensive MSYS
# emulation. A script that shells out (grep/sed/date/$(...)) dozens of times per
# run exhausts fork resources and dies mid-run ("fork: retry: Resource
# temporarily unavailable") — the status line just goes blank. So we parse JSON
# with bash regex ([[ =~ ]] + BASH_REMATCH), use the $EPOCHSECONDS builtin
# instead of `date`, and return values via `printf -v` / globals instead of
# $(...). The only processes we fork are the two git calls. Keep it that way.
#
# rate_limits (5h/wk) exist only for Pro/Max; on API billing they're absent and
# we fall back to session cost instead.

# --- version & update config ------------------------------------------------
# STATUSLINE_VERSION is kept in sync with package.json by scripts/sync-version.mjs
# on release — don't hand-edit it. The other knobs are overridable via env vars.
STATUSLINE_VERSION="1.1.0"
UPDATE_REPO="brokuka/claude-statusline"
UPDATE_BRANCH="main"
UPDATE_INTERVAL=86400                        # seconds between background update checks
SHOW_GIT="${CC_STATUSLINE_GIT:-1}"           # 0 to hide the git branch/dirty segment
SHOW_VERSION="${CC_STATUSLINE_VERSION:-1}"   # 0 to hide the dim vX.Y.Z tag
SHOW_THINK="${CC_STATUSLINE_THINK:-1}"       # 0 to hide the think:on/off segment
CHECK_UPDATE="${CC_STATUSLINE_UPDATE:-1}"    # 0 to disable the "update available" check
VIEW="${CC_STATUSLINE_VIEW:-default}"        # default (2 lines) | oneline | minimal
BARS="${CC_STATUSLINE_BARS:-line}"           # line | blocks | solid | ascii | dots

# Bar glyphs (filled / track) for the chosen style. Picking them here keeps _bar
# fork-free — it just repeats these two characters.
case "$BARS" in
  blocks) FILL='▓'; TRACK='░' ;;
  solid)  FILL='█'; TRACK='░' ;;
  ascii)  FILL='#'; TRACK='-' ;;
  dots)   FILL='●'; TRACK='○' ;;
  *)      FILL='━'; TRACK='─' ;;             # line (default)
esac
EMPTY=''; for ((_i = 0; _i < 8; _i++)); do EMPTY+="$TRACK"; done   # 8-wide empty bar

IFS= read -r -d '' input || true   # slurp all of stdin, no `cat` fork

ESC=$'\033'; RST="${ESC}[0m"; DIM="${ESC}[2m"; SEP="${DIM} · ${RST}"
NOW=$EPOCHSECONDS; [ -n "$NOW" ] || NOW=$(date +%s)   # builtin; date only as fallback

# --- fork-free JSON getters (set the named OUT var) -------------------------
_num()   { if [[ $3 =~ \"$2\"[[:space:]]*:[[:space:]]*(-?[0-9]+(\.[0-9]+)?) ]]; then printf -v "$1" %s "${BASH_REMATCH[1]}"; else printf -v "$1" %s ''; fi; }
_str()   { if [[ $3 =~ \"$2\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]];        then printf -v "$1" %s "${BASH_REMATCH[1]}"; else printf -v "$1" %s ''; fi; }
_block() { if [[ $3 =~ \"$2\"[[:space:]]*:[[:space:]]*(\{[^}]*\}) ]];         then printf -v "$1" %s "${BASH_REMATCH[1]}"; else printf -v "$1" %s ''; fi; }
_int()   { local n=${2%%.*}; printf -v "$1" %s "${n:-0}"; }

_bar() { # $1 = percent -> BAR
  local p=${1%%.*} w=8 f e i out col; p=${p:-0}
  ((p > 100)) && p=100; ((p < 0)) && p=0
  f=$(((p * w + 50) / 100)); e=$((w - f))         # +50 = round to nearest
  col=32; ((p >= 70)) && col=33; ((p >= 90)) && col=31
  out="${ESC}[${col}m"
  for ((i = 0; i < f; i++)); do out+="$FILL"; done
  out+="${RST}${DIM}"
  for ((i = 0; i < e; i++)); do out+="$TRACK"; done
  BAR="${out}${RST}"
}

_reset() { # $1 = epoch seconds -> RES (coarse; collapses long waits to days)
  RES=''; local e=${1%%.*} d h m
  [ -n "$e" ] || return
  d=$((e - NOW)); ((d <= 0)) && return
  if ((d >= 172800)); then printf -v RES '%dd' $((d / 86400)); return; fi
  h=$((d / 3600)); m=$(((d % 3600) / 60))
  ((h > 0)) && printf -v RES '%dh' "$h" || printf -v RES '%dm' "$m"
}

_dur() { # $1 = seconds -> DURT (keep seconds under 1h so it ticks live)
  local s=$1 h m sec
  h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
  if ((h > 0)); then printf -v DURT '%dh%02dm' "$h" "$m"
  elif ((m > 0)); then printf -v DURT '%dm%02ds' "$m" "$sec"
  else printf -v DURT '%ds' "$sec"; fi
}

_kfmt() { local n=${1%%.*}; n=${n:-0}; ((n >= 1000)) && printf -v KT '%dk' $((n / 1000)) || printf -v KT '%d' "$n"; }

_pc() { # $1 = percent -> PCS (a threshold-coloured "NN%", for the bar-less minimal view)
  local p=${1%%.*} col=32; p=${p:-0}
  ((p >= 70)) && col=33; ((p >= 90)) && col=31
  PCS="${ESC}[${col}m${p}%${RST}"
}

_vgt() { # returns 0 (true) if $1 > $2, comparing dotted numeric versions. Fork-free.
  local a=$1 b=$2 xi yi
  while [ -n "$a$b" ]; do
    xi=${a%%.*}; [ "$xi" = "$a" ] && a='' || a=${a#*.}
    yi=${b%%.*}; [ "$yi" = "$b" ] && b='' || b=${b#*.}
    xi=${xi%%[!0-9]*}; yi=${yi%%[!0-9]*}
    ((10#${xi:-0} > 10#${yi:-0})) && return 0
    ((10#${xi:-0} < 10#${yi:-0})) && return 1
  done
  return 1
}

_check_update() { # sets UPD to the newer version (or ''). Never blocks the render.
  UPD=''
  [ "$CHECK_UPDATE" = 1 ] || return
  command -v curl >/dev/null 2>&1 || return          # builtin lookup; no fork
  local cache="${TMPDIR:-/tmp}"; cache="${cache%/}/cc-statusline-update"
  local last='' latest=''
  [ -r "$cache" ] && { read -r last; read -r latest; } < "$cache"
  # Stale (or never checked)? Refresh once in the background — fire-and-forget so
  # the 1s render never waits on the network. Stamp $NOW into the cache first so
  # we don't respawn a curl every single second while it's in flight.
  if [ -z "$last" ] || (( NOW - last >= UPDATE_INTERVAL )); then
    printf '%s\n%s\n' "$NOW" "$latest" > "$cache"
    # Pull the version straight out of the raw package.json (grep+tr keeps just
    # the digits/dots). This runs backgrounded once a day, so the extra forks are
    # free — the per-second render never gets here.
    ( v=$(curl -fsSL "https://raw.githubusercontent.com/${UPDATE_REPO}/${UPDATE_BRANCH}/package.json" 2>/dev/null | grep -m1 '"version"' | tr -dc '0-9.')
      [ -n "$v" ] && printf '%s\n%s\n' "$NOW" "$v" > "$cache" ) >/dev/null 2>&1 &
  fi
  [ -n "$latest" ] && _vgt "$latest" "$STATUSLINE_VERSION" && UPD="$latest"
}

# --- parse ------------------------------------------------------------------
# Pull the flat rate-limit blocks first and strip them, so the remaining
# "used_percentage" unambiguously belongs to context_window (no field-order guess).
_block five five_hour "$input"
_block week seven_day "$input"
rest=$input
[ -n "$five" ] && rest=${rest//"$five"/}
[ -n "$week" ] && rest=${rest//"$week"/}

_str model display_name "$input"; model=${model%% (*}; [ -n "$model" ] || model='?'
_str sid session_id "$input"

_num ctx_pct used_percentage "$rest"
_num ctx_tok total_input_tokens "$rest"
_num cwsize context_window_size "$rest"
if [ -z "$ctx_pct" ]; then                        # fallback via current_usage
  _block cu current_usage "$input"
  _num size context_window_size "$rest"
  _num a input_tokens "$cu"; _num b cache_creation_input_tokens "$cu"; _num d cache_read_input_tokens "$cu"
  _int a "$a"; _int b "$b"; _int d "$d"; _int size "$size"
  inp=$((a + b + d))
  if ((size > 0)) && ((inp > 0)); then ctx_pct=$((inp * 100 / size)); ctx_tok=$inp; fi
fi

_num fh used_percentage "$five"; _num fhr resets_at "$five"
_num wk used_percentage "$week"; _num wkr resets_at "$week"
_num cost total_cost_usd "$input"
_num dur_ms total_duration_ms "$input"; _int dur_ms "$dur_ms"

# --- session timer (persist a start epoch so seconds tick between messages) --
cache="${TMPDIR:-/tmp}"; cache="${cache%/}/cc-statusline-start-${sid}"
if [ -n "$sid" ] && [ -r "$cache" ]; then read -r start < "$cache"
elif [ -n "$sid" ]; then start=$((NOW - dur_ms / 1000)); printf '%s' "$start" > "$cache"
else start=$((NOW - dur_ms / 1000)); fi
elapsed=$((NOW - start))

# --- git segment (shared by every view; the only place this script forks) ---
GITSEG=''
if [ "$SHOW_GIT" = 1 ]; then
  branch=$(git branch --show-current 2>/dev/null)
  if [ -n "$branch" ]; then
    status=$(git status --porcelain 2>/dev/null)
    dirty=0
    if [ -n "$status" ]; then while IFS= read -r l; do [ -n "$l" ] && ((dirty++)); done <<< "$status"; fi
    GITSEG="${ESC}[36m${branch}${RST}"
    ((dirty > 0)) && GITSEG+=" ${ESC}[33m±${dirty}${RST}"
  fi
fi

# --- version tag (shown in every view when enabled) -------------------------
VERSEG=''
[ "$SHOW_VERSION" = 1 ] && VERSEG="${DIM}v${STATUSLINE_VERSION}${RST}"

# --- model + badge: "Opus 4.8 (1m/think)" -----------------------------------
# 1m = 1M context window (context_window_size), think = extended thinking on.
badge=''
if [ -n "$cwsize" ]; then s=${cwsize%%.*}; ((${s:-0} >= 1000000)) && badge='1m'; fi
if [ "$SHOW_THINK" = 1 ]; then
  _block thk thinking "$input"
  if [ -n "$thk" ] && [[ $thk =~ \"enabled\"[[:space:]]*:[[:space:]]*true ]]; then
    [ -n "$badge" ] && badge+='/think' || badge='think'
  fi
fi
MODELSEG="${ESC}[1m${model}${RST}"
[ -n "$badge" ] && MODELSEG+=" ${DIM}(${badge})${RST}"

# --- minimal: compact single line ------------------------------------------
# git (if enabled) + model + ctx bar + bar-less rate windows + timer, one line.
# Version/update meta is dropped to keep it minimal.
if [ "$VIEW" = minimal ]; then
  # git and version (when enabled) lead the compact line, then the model badge
  lead="$GITSEG"
  [ -n "$VERSEG" ] && { [ -n "$lead" ] && lead+="${SEP}${VERSEG}" || lead="$VERSEG"; }
  [ -n "$lead" ] && data="${lead}${SEP}${MODELSEG}" || data="${MODELSEG}"
  if [ -n "$ctx_pct" ]; then
    _bar "$ctx_pct"; _int ci "$ctx_pct"; _kfmt "$ctx_tok"
    data+="${SEP}ctx ${BAR} ${ci}% ${DIM}${KT}${RST}"
  else
    data+="${SEP}${DIM}ctx ${EMPTY} --${RST}"
  fi
  if [ -n "$fh" ]; then _pc "$fh"; _reset "$fhr"; data+="${SEP}5h:${PCS}"; [ -n "$RES" ] && data+=" ${DIM}(${RES})${RST}"; fi
  if [ -n "$wk" ]; then _pc "$wk"; _reset "$wkr"; data+="${SEP}wk:${PCS}"; [ -n "$RES" ] && data+=" ${DIM}(${RES})${RST}"; fi
  if [ -z "$fh" ] && [ -z "$wk" ] && [ -n "$cost" ] && [[ $cost =~ [1-9] ]]; then printf -v cf '%.2f' "$cost"; data+="${SEP}${DIM}\$${cf}${RST}"; fi
  _dur "$elapsed"; data+="${SEP}${DIM}${DURT}${RST}"
  printf '%s\n' "$data"
  exit 0
fi

# --- build the data line (default / oneline) --------------------------------
data="${MODELSEG}"

if [ -n "$ctx_pct" ]; then
  _bar "$ctx_pct"; _int ci "$ctx_pct"; _kfmt "$ctx_tok"
  data+="${SEP}ctx ${BAR} ${ci}% ${DIM}${KT}${RST}"
else
  data+="${SEP}${DIM}ctx ${EMPTY} --${RST}"
fi

if [ -n "$fh" ]; then
  _bar "$fh"; _int fi "$fh"; _reset "$fhr"
  data+="${SEP}5h ${BAR} ${fi}%"; [ -n "$RES" ] && data+=" ${DIM}(reset in ${RES})${RST}"
fi
if [ -n "$wk" ]; then
  _bar "$wk"; _int wi "$wk"; _reset "$wkr"
  data+="${SEP}wk ${BAR} ${wi}%"; [ -n "$RES" ] && data+=" ${DIM}(reset in ${RES})${RST}"
fi
# API billing (no rate limits) -> show cost instead, but only if nonzero.
if [ -z "$fh" ] && [ -z "$wk" ] && [ -n "$cost" ] && [[ $cost =~ [1-9] ]]; then
  printf -v cf '%.2f' "$cost"; data+="${SEP}${DIM}\$${cf}${RST}"
fi

_dur "$elapsed"; data+="${SEP}${DIM}${DURT}${RST}"

# --- meta segments: git branch, version, update (default / oneline only) ----
line1="$GITSEG"
[ -n "$VERSEG" ] && { [ -n "$line1" ] && line1+="${SEP}${VERSEG}" || line1="$VERSEG"; }
_check_update
if [ -n "$UPD" ]; then
  useg="${ESC}[35m⬆${UPD}${RST}"                       # magenta up-arrow + new version
  [ -n "$line1" ] && line1+="${SEP}${useg}" || line1="$useg"
fi

# --- output -----------------------------------------------------------------
if [ "$VIEW" = oneline ]; then
  if [ -n "$line1" ]; then printf '%s%s%s\n' "$line1" "$SEP" "$data"; else printf '%s\n' "$data"; fi
else                                                    # default: meta line, then data
  [ -n "$line1" ] && printf '%s\n' "$line1"
  printf '%s\n' "$data"
fi
