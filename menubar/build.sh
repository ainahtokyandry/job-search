#!/bin/zsh
# Builds JobSearchBar.app — this section on its own, as its own menu bar app —
# and installs it into ~/Applications. Run directly, or let setup.sh call it.
#
#   ./build.sh                     into ~/Applications/JobSearchBar.app
#   ./build.sh /path/to/App.app    somewhere else
#
# The section is written against the MacBar host, which defines BarSection and
# the drawing it uses. That host is a checkout of
#
#   https://github.com/ainahtokyandry/mac-setup
#
# found in MACBAR_HOST, or beside this repository, or under $HOME/Projects. There
# is no copy of it here on purpose: one definition of the contract, so a section
# cannot drift away from the app that hosts it.
#
# Building this is optional, and normally unnecessary: MacBar shows the same
# reading as one section of a single menu bar item, next to the others. Prefer
# that unless you want the indicator without the rest.

set -euo pipefail

HERE="${0:A:h}"
APP="${1:-$HOME/Applications/JobSearchBar.app}"
MACOS="$APP/Contents/MacOS"

die() { print -u2 -- "\033[31merror:\033[0m $*"; exit 1 }

command -v swiftc >/dev/null || die "swiftc not found — install the Xcode Command Line Tools: xcode-select --install"

# ------------------------------------------------------------------- the host

find_host() {
  local candidate
  for candidate in \
    "${MACBAR_HOST:-}" \
    "${HERE:h:h}/mac-setup/menubar" \
    "$HOME/Projects/mac-setup/menubar"
  do
    [ -n "$candidate" ] || continue
    [ -f "$candidate/Support.swift" ] || continue
    print -- "${candidate:A}"
    return 0
  done
  return 1
}

HOST="$(find_host)" || die "could not find the MacBar host.
  Clone it next to this repository:
      git clone https://github.com/ainahtokyandry/mac-setup.git ${HERE:h:h}/mac-setup
  or point at an existing checkout:
      MACBAR_HOST=/path/to/mac-setup/menubar ./build.sh"

print -- "Host: $HOST"

# ---------------------------------------------------------------------- build

pkill -x JobSearchBar 2>/dev/null || true

mkdir -p "$MACOS"
swiftc -O \
  "$HOST/Support.swift" \
  "$HOST/Controller.swift" \
  "$HOST/Host.swift" \
  "$HERE/JobSearchSection.swift" \
  "$HERE/main.swift" \
  -o "$MACOS/JobSearchBar"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>JobSearchBar</string>
  <key>CFBundleIdentifier</key><string>com.jobsearch.menubar</string>
  <key>CFBundleExecutable</key><string>JobSearchBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <!-- Menu bar only: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Replacing the executable invalidates any existing signature, and an unsigned
# bundle will not launch on recent versions of macOS.
codesign --force --sign - "$APP"

print -- "Built $APP"
