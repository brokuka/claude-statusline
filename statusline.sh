#!/usr/bin/env bash
# Claude Code status line — pure bash, no jq / python / node.
#
# Reads the session JSON on stdin (schema: code.claude.com/docs/en/statusline)
# and prints the status line to stdout.
#
# Layout (two lines; line 1 omitted when not in a git repo):
#   <branch ±dirty>
#   <Model> · ctx <bar> NN% NNk · 5h <bar> NN% (reset in Xh) · wk <bar> NN% (reset in Xd) · <session>
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
  for ((i = 0; i < f; i++)); do out+="━"; done
  out+="${RST}${DIM}"
  for ((i = 0; i < e; i++)); do out+="─"; done
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

# --- build the data line ----------------------------------------------------
data="${ESC}[1m${model}${RST}"

if [ -n "$ctx_pct" ]; then
  _bar "$ctx_pct"; _int ci "$ctx_pct"; _kfmt "$ctx_tok"
  data+="${SEP}ctx ${BAR} ${ci}% ${DIM}${KT}${RST}"
else
  data+="${SEP}${DIM}ctx ──────── --${RST}"
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

# --- git branch on its own top line (the only forks in this script) ---------
branch=$(git branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  status=$(git status --porcelain 2>/dev/null)
  dirty=0
  if [ -n "$status" ]; then while IFS= read -r l; do [ -n "$l" ] && ((dirty++)); done <<< "$status"; fi
  line1="${ESC}[36m${branch}${RST}"
  ((dirty > 0)) && line1+=" ${ESC}[33m±${dirty}${RST}"
  printf '%s\n' "$line1"
fi
printf '%s\n' "$data"
