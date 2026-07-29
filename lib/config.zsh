# Shared configuration loading and schedule maths.
# Sourced by run-search.sh and setup.sh; not meant to be run directly.

PROJECT_DIR="${PROJECT_DIR:-${0:A:h:h}}"

# Defaults, overridden by config.env.
SCHEDULE="Sun 08:00, Wed 15:00"
HEARTBEAT_SECONDS=900
MAX_ATTEMPTS=3
MAX_AGE_DAYS=7
REPORTS_DIR="reports"
REPORT_PREFIX="job-search"
CLAUDE_BIN=""
NOTIFY=1

load_config() {
  local f="$PROJECT_DIR/config.env"
  if [ ! -f "$f" ]; then
    print -u2 "No config.env found in $PROJECT_DIR — run ./setup.sh first."
    return 1
  fi
  source "$f"
}

# Locate the Claude Code CLI: config first, then PATH, then the usual install spots.
resolve_claude_bin() {
  if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then
    print -- "$CLAUDE_BIN"; return 0
  fi
  local c
  for c in "$(command -v claude 2>/dev/null)" "$HOME/.local/bin/claude" \
           /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [ -n "$c" ] && [ -x "$c" ] && { print -- "$c"; return 0 }
  done
  return 1
}

# Split SCHEDULE ("Sun 08:00, Wed 15:00") into "<Day> <HH> <MM>" lines.
schedule_slots() {
  local part day hhmm
  for part in ${(s:,:)SCHEDULE}; do
    part="${part## }"; part="${part%% }"
    [ -z "$part" ] && continue
    day="${part%% *}"
    hhmm="${part##* }"
    print -- "$day ${hhmm%%:*} ${hhmm##*:}"
  done
}

# Epoch of the most recent occurrence of one slot, at or before $4.
slot_epoch() {  # $1=Day $2=HH $3=MM $4=now
  local ts
  ts=$(date -v-"$1" -v$((10#$2))H -v$((10#$3))M -v0S +%s) || return 1
  (( ts > $4 )) && ts=$((ts - 604800))
  print -- "$ts"
}

# Epoch of the most recent slot of any kind that has come due at or before $1.
most_recent_due_slot() {  # $1=now
  local line day hh mm ts best=0
  for line in ${(f)"$(schedule_slots)"}; do
    day=${${(z)line}[1]}; hh=${${(z)line}[2]}; mm=${${(z)line}[3]}
    ts=$(slot_epoch "$day" "$hh" "$mm" "$1") || continue
    (( ts > best )) && best=$ts
  done
  print -- "$best"
}
