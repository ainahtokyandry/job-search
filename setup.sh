#!/bin/zsh
# Interactive setup: pick a schedule, pick what to search for, install the agent.
# Safe to re-run at any time — it offers your current settings as the defaults.

set -euo pipefail

PROJECT_DIR="${0:A:h}"
source "$PROJECT_DIR/lib/config.zsh"
cd "$PROJECT_DIR"

CONFIG="$PROJECT_DIR/config.env"
PROFILE="$PROJECT_DIR/profile.md"
AGENT_LABEL="com.jobsearch.agent"
BAR_LABEL="com.jobsearch.menubar"
AGENTS_DIR="$HOME/Library/LaunchAgents"

bold() { print -- "\033[1m$1\033[0m" }
dim()  { print -- "\033[2m$1\033[0m" }
warn() { print -- "\033[33m$1\033[0m" }

ask() {  # $1 = question, $2 = default -> answer on stdout
  local answer
  print -n -u2 -- "$1 [$2]: "
  read -r answer
  print -- "${answer:-$2}"
}

yesno() {  # $1 = question, $2 = y|n default
  local answer
  while true; do
    print -n -u2 -- "$1 [$([ "$2" = y ] && print "Y/n" || print "y/N")]: "
    read -r answer
    answer="${answer:-$2}"
    case "${answer:l}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
    esac
  done
}

choose() {  # $1 = default number, rest = option labels -> chosen number on stdout
  local default="$1"; shift
  local i=1 answer
  for opt in "$@"; do print -u2 -- "  $i) $opt"; i=$((i + 1)); done
  while true; do
    print -n -u2 -- "Choice [$default]: "
    read -r answer
    answer="${answer:-$default}"
    if [[ "$answer" == <-> ]] && (( answer >= 1 && answer <= $# )); then
      print -- "$answer"; return 0
    fi
  done
}

# ---------------------------------------------------------------- 0. preflight

[ "$(uname)" = "Darwin" ] || { warn "This installer targets macOS (launchd)."; exit 1 }

if [ -f "$CONFIG" ]; then
  dim "Found an existing config.env — its values are offered as the defaults below."
  source "$CONFIG"
fi

if ! resolve_claude_bin >/dev/null; then
  warn "The Claude Code CLI was not found on this machine."
  dim  "Install it first: https://claude.com/claude-code — then re-run ./setup.sh"
  yesno "Continue anyway?" n || exit 1
fi

# --------------------------------------------------------------- 1. the schedule

print
bold "1. When should the search run?"
dim  "Current default: $SCHEDULE (local time)"
print
case "$(choose 1 "Keep this schedule" "Choose my own days and times")" in
  2)
    print
    dim "Enter one or more slots, comma separated, as \"<Day> <HH:MM>\"."
    dim "Days are Sun Mon Tue Wed Thu Fri Sat. Example: Mon 09:00, Thu 18:30"
    while true; do
      candidate="$(ask "Schedule" "$SCHEDULE")"
      ok=1
      for part in ${(s:,:)candidate}; do
        part="${part## }"; part="${part%% }"
        [[ "$part" == (Sun|Mon|Tue|Wed|Thu|Fri|Sat)" "[0-2][0-9]:[0-5][0-9] ]] || ok=0
      done
      if [ "$ok" = 1 ]; then SCHEDULE="$candidate"; break; fi
      warn "Could not parse that. Use e.g.: Sun 08:00, Wed 15:00"
    done
    ;;
esac

print
dim "How often should launchd check whether a slot is due? Lower is more punctual,"
dim "but the check itself is a no-op that exits in milliseconds."
HEARTBEAT_SECONDS="$(ask "Heartbeat in seconds" "$HEARTBEAT_SECONDS")"
MAX_AGE_DAYS="$(ask "Only report jobs posted within the last N days" "$MAX_AGE_DAYS")"

# ---------------------------------------------------------------- 2. the profile

print
bold "2. What should it search for?"
print
if [ -f "$PROFILE" ]; then
  dim "You already have a profile.md. Its first lines:"
  head -12 "$PROFILE" | sed 's/^/    /'
  print
  profile_choice="$(choose 1 "Keep my current profile" "Use the default profile" \
                           "Answer a few questions" "Build it from my CV" "Edit it by hand")"
else
  dim "The default profile looks for JavaScript/TypeScript developer roles that are"
  dim "remote-friendly worldwide, plus French-speaking and Madagascar-local boards."
  print
  profile_choice="$(choose 1 "Use the default profile" "Answer a few questions" \
                           "Build it from my CV" "Edit it by hand")"
  profile_choice=$((profile_choice + 1))   # align with the menu above
fi

write_profile_from_answers() {
  print
  local role stacks kinds location languages remote extra
  role="$(ask      "Job title you are looking for" "JavaScript/TypeScript developer")"
  kinds="$(ask     "Kinds of role (comma separated)" "fullstack, frontend, backend, mobile")"
  stacks="$(ask    "Technologies to match" "React, Next.js, Node.js, NestJS, React Native, Vue, Angular")"
  location="$(ask  "Where you live (city, country, timezone)" "Antananarivo, Madagascar (UTC+3)")"
  languages="$(ask "Languages you can work in" "French, English")"
  remote="$(ask    "Work arrangement" "fully remote, freelance or contract; on-site only if local")"
  print
  dim "Anything else the search should know? Seniority, salary floor, industries to"
  dim "avoid, boards to skip… One line, or leave empty."
  extra="$(ask "Extra notes" "")"

  cat > "$PROFILE" <<EOF
# Search profile

## Candidate

- Role: $role
- Based in: $location
- Languages: $languages — postings in any of them are fine.

## Roles wanted

$kinds positions matching: $stacks.

## Eligibility rules

- Work arrangement: $remote.
- Jobs in the candidate's own country may be on-site, hybrid or remote.
- Jobs elsewhere must be fully remote and genuinely open to someone working from
  $location. Exclude roles that require residency or a work permit elsewhere.
  Flag "eligibility unclear" when unsure, rather than dropping the listing.
- Flag any timezone-overlap requirement.

## Sources to sweep

1. Remote job boards: RemoteOK, Remotive, Wellfound, Arc.dev.
2. General boards and LinkedIn public listings for the languages above.
3. Local job boards for $location.
4. Freelance and contract platforms: Arc.dev, Upwork public pages, Contra.

## Notes

${extra:-None.}
EOF
}

write_profile_from_cv() {
  local cv claude_bin
  claude_bin="$(resolve_claude_bin)" || {
    warn "The Claude Code CLI is needed to read a CV. Falling back to the questions."
    write_profile_from_answers; return
  }
  while true; do
    cv="$(ask "Path to your CV (PDF, Markdown or text)" "")"
    cv="${cv/#\~/$HOME}"
    [ -f "$cv" ] && break
    warn "No file at that path."
  done
  print
  dim "Reading your CV and drafting a search profile…"
  "$claude_bin" -p "Read the CV at $cv. From it, write a job-search profile to \
$PROFILE, following the structure and tone of the example at $PROJECT_DIR/profile.default.md \
(sections: Candidate, Roles wanted, Eligibility rules, Sources to sweep, Sources to never use). \
Base the role titles, technologies, seniority and languages on what the CV actually shows — \
do not invent skills. If the CV states a location, use it to pick relevant local job boards. \
Write the file and nothing else." \
    --allowedTools "Read,Write" >/dev/null || {
      warn "Could not build a profile from the CV. Falling back to the questions."
      write_profile_from_answers; return
    }
  [ -f "$PROFILE" ] || { warn "Nothing was written. Falling back to the questions."; write_profile_from_answers; return }
  print
  bold "Drafted profile:"
  sed 's/^/    /' "$PROFILE"
  print
  yesno "Keep this profile? (you can edit profile.md any time)" y || ${EDITOR:-nano} "$PROFILE"
}

case "$profile_choice" in
  1) : ;;                                            # keep current profile.md
  2) cp "$PROJECT_DIR/profile.default.md" "$PROFILE" ;;
  3) write_profile_from_answers ;;
  4) write_profile_from_cv ;;
  5) [ -f "$PROFILE" ] || cp "$PROJECT_DIR/profile.default.md" "$PROFILE"
     ${EDITOR:-nano} "$PROFILE" ;;
esac

# ----------------------------------------------------------------- 3. write config

cat > "$CONFIG" <<EOF
# Written by setup.sh. Re-run ./setup.sh to change these, or edit by hand and
# then run ./setup.sh to reinstall the agent with the new heartbeat.

SCHEDULE="$SCHEDULE"
HEARTBEAT_SECONDS=$HEARTBEAT_SECONDS
MAX_ATTEMPTS=$MAX_ATTEMPTS
MAX_AGE_DAYS=$MAX_AGE_DAYS
REPORTS_DIR="$REPORTS_DIR"
REPORT_PREFIX="$REPORT_PREFIX"
CLAUDE_BIN="$CLAUDE_BIN"
NOTIFY=$NOTIFY
EOF

mkdir -p "$PROJECT_DIR/$REPORTS_DIR" "$PROJECT_DIR/logs"
chmod +x "$PROJECT_DIR/run-search.sh"
print
dim "Wrote config.env and profile.md."

# --------------------------------------------------------------- 4. launchd agent

print
bold "3. Install the background agent?"
dim  "It wakes every $HEARTBEAT_SECONDS seconds and runs a search when a slot is due."
print
if yesno "Install the launchd agent now?" y; then
  mkdir -p "$AGENTS_DIR"
  cat > "$AGENTS_DIR/$AGENT_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>

  <!-- Aqua session: needed for notifications to reach the GUI. -->
  <key>LimitLoadToSessionType</key><string>Aqua</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>$PROJECT_DIR/run-search.sh</string>
  </array>

  <!-- A heartbeat, not a calendar trigger: StartCalendarInterval is unreliable on
       some machines. run-search.sh decides for itself whether a slot is due. -->
  <key>StartInterval</key><integer>$HEARTBEAT_SECONDS</integer>
  <key>RunAtLoad</key><true/>

  <key>StandardOutPath</key><string>$PROJECT_DIR/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$PROJECT_DIR/logs/launchd.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$UID/$AGENT_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$AGENTS_DIR/$AGENT_LABEL.plist"
  launchctl enable "gui/$UID/$AGENT_LABEL"
  dim "Agent installed and loaded."
fi

# -------------------------------------------------------------- 5. menu bar app

print
bold "4. Install a menu bar indicator of its own?"
dim  "Shows the next run, whether one is in flight, and opens the latest report."
dim  "Say no if you use MacBar — it already shows all of that as one of its"
dim  "sections, and a second app here means a second item in the menu bar."
print
if yesno "Build and install it?" n; then
  if ! command -v swiftc >/dev/null; then
    warn "swiftc not found — install Xcode Command Line Tools (xcode-select --install) and re-run."
  elif ! "$PROJECT_DIR/menubar/build.sh"; then
    # The indicator is built against the MacBar host; without it there is
    # nothing to compile, and that must not abort the rest of the setup.
    warn "Could not build the indicator. Everything else above is installed."
  else
    mkdir -p "$AGENTS_DIR"
    cat > "$AGENTS_DIR/$BAR_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$BAR_LABEL</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HOME/Applications/JobSearchBar.app/Contents/MacOS/JobSearchBar</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>JOBSEARCH_DIR</key><string>$PROJECT_DIR</string></dict>
  <!-- RunAtLoad only, no KeepAlive, so the menu's Quit item actually quits. -->
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID/$BAR_LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$AGENTS_DIR/$BAR_LABEL.plist"
    dim "Menu bar app installed and running."
  fi
fi

print
bold "Done."
print -- "  Schedule:  $SCHEDULE"
print -- "  Profile:   profile.md"
print -- "  Reports:   $REPORTS_DIR/"
print
dim "Run one now, outside the schedule:  ./run-search.sh --force"
dim "Remove everything:                  ./uninstall.sh"
