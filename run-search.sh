#!/bin/zsh
# Runs one job search, if one is due. Invoked by the launchd agent on a heartbeat.
#
# launchd wakes this script every HEARTBEAT_SECONDS; the gate below decides whether
# a search is actually due. StartCalendarInterval is deliberately not used: on some
# machines it silently never fires. The heartbeat plus a persisted "last completed
# slot" also gives catch-up for free — a slot missed while the Mac was asleep or off
# runs at the next heartbeat after wake.
#
#   run-search.sh            run only if a scheduled slot is due
#   run-search.sh --force    run right now, ignoring the schedule

set -euo pipefail

export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/lib/config.zsh"
load_config || exit 1
cd "$PROJECT_DIR"
mkdir -p logs "$REPORTS_DIR"

STATE=".last-run"       # epoch seconds of the most recent slot we completed
ATTEMPTS=".attempts"    # "<slot-epoch> <failure-count>" for the slot in progress
LOCKDIR=".run.lock"

notify() {  # $1 = title, $2 = message
  # Set NOTIFY=0 in config.env, or in the environment, when exercising the gate by
  # hand — otherwise test runs post real notifications to Notification Center.
  [ "${NOTIFY:-1}" = "0" ] && return 0
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

now=$(date +%s)
due=$(most_recent_due_slot "$now")

last=0
[ -f "$STATE" ] && last=$(cat "$STATE")

# Nothing has come due since the last completed run — quiet no-op.
if [ "${1:-}" != "--force" ] && [ "$due" -le "$last" ]; then
  exit 0
fi

# Single-instance guard; mkdir is atomic.
mkdir "$LOCKDIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

claude_bin=$(resolve_claude_bin) || {
  notify "Job search failed" "Claude Code CLI not found — set CLAUDE_BIN in config.env"
  print -u2 "Claude Code CLI not found. Set CLAUDE_BIN in config.env."
  exit 1
}

[ -f "$PROJECT_DIR/profile.md" ] || {
  print -u2 "No profile.md in $PROJECT_DIR — run ./setup.sh first."
  exit 1
}

# Build the prompt: the template with the profile and config values substituted in.
prompt=$(<"$PROJECT_DIR/prompt-template.md")
profile=$(<"$PROJECT_DIR/profile.md")
prompt=${prompt//\{\{PROFILE\}\}/$profile}
prompt=${prompt//\{\{PROJECT_DIR\}\}/$PROJECT_DIR}
prompt=${prompt//\{\{MAX_AGE_DAYS\}\}/$MAX_AGE_DAYS}
prompt=${prompt//\{\{REPORTS_DIR\}\}/$REPORTS_DIR}
prompt=${prompt//\{\{REPORT_PREFIX\}\}/$REPORT_PREFIX}

# How many times have we already failed on this particular slot?
att_slot=0; att_n=0
[ -f "$ATTEMPTS" ] && read -r att_slot att_n < "$ATTEMPTS"
[ "$att_slot" != "$due" ] && att_n=0

LOG="logs/search-$(date +%F).log"
print -- "=== run started $(date) — due slot $(date -r "$due") — attempt $((att_n + 1)) ===" >> "$LOG"

if "$claude_bin" -p "$prompt" \
    --allowedTools "WebSearch,WebFetch,Read,Write,Glob,Grep,Agent,Bash" \
    >> "$LOG" 2>&1; then
  print -- "$due" > "$STATE"
  rm -f "$ATTEMPTS"
  notify "Job search done" "Results written to $PROJECT_DIR/$REPORTS_DIR"
else
  att_n=$((att_n + 1))
  print -- "$due $att_n" > "$ATTEMPTS"
  if [ "$att_n" -ge "$MAX_ATTEMPTS" ]; then
    # Give up on this slot so we don't retry forever on a hard failure.
    print -- "$due" > "$STATE"
    rm -f "$ATTEMPTS"
    notify "Job search FAILED" "Gave up after $MAX_ATTEMPTS tries — see logs/ in $PROJECT_DIR"
  else
    notify "Job search failed" "Attempt $att_n of $MAX_ATTEMPTS — will retry shortly"
  fi
fi
