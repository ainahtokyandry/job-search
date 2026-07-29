#!/bin/zsh
# Builds JobSearchBar.app from the single Swift file and installs it into
# ~/Applications. Run directly, or let setup.sh call it.

set -euo pipefail

HERE="${0:A:h}"
APP="${1:-$HOME/Applications/JobSearchBar.app}"
MACOS="$APP/Contents/MacOS"

command -v swiftc >/dev/null || {
  print -u2 "swiftc not found — install the Xcode Command Line Tools: xcode-select --install"
  exit 1
}

mkdir -p "$MACOS"
swiftc -O -o "$MACOS/JobSearchBar" "$HERE/JobSearchBar.swift"

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

print -- "Built $APP"
