#!/bin/zsh
# Removes the launchd agents and the menu bar app. Your config, profile, reports
# and logs are left untouched — delete the project folder if you want those gone.

set -euo pipefail

AGENT_LABEL="com.jobsearch.agent"
BAR_LABEL="com.jobsearch.menubar"
AGENTS_DIR="$HOME/Library/LaunchAgents"

for label in "$AGENT_LABEL" "$BAR_LABEL"; do
  launchctl bootout "gui/$UID/$label" 2>/dev/null || true
  rm -f "$AGENTS_DIR/$label.plist"
  print -- "Removed $label"
done

if [ -d "$HOME/Applications/JobSearchBar.app" ]; then
  rm -rf "$HOME/Applications/JobSearchBar.app"
  print -- "Removed ~/Applications/JobSearchBar.app"
fi

print -- "Done. Reports and logs were kept."
