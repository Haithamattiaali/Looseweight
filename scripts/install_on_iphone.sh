#!/usr/bin/env bash
# One step from a Mac: set the API key (first run only), build Looseweight and install it on the connected iPhone.
# Needs Xcode 26 signed in with your Apple ID (Xcode > Settings > Accounts) and the iPhone connected by cable
# or paired over Wi-Fi with Developer Mode on.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m✖ %s\033[0m\n' "$1"; exit 1; }

step "Checking tools"
xcode-select -p >/dev/null 2>&1 || fail "Install Xcode from the Mac App Store, open it once, then run this again."
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || fail "Install Homebrew first: https://brew.sh"
  brew install xcodegen
fi

step "API key"
if [[ ! -s Config/Secrets.xcconfig ]]; then
  read -r -s -p "Paste your Anthropic API key (hidden): " key; echo
  [[ "$key" == sk-ant-* ]] || fail "That does not look like an Anthropic key (sk-ant-...)."
  printf 'LW_ANTHROPIC_KEY = %s\n' "$key" > Config/Secrets.xcconfig
  chmod 600 Config/Secrets.xcconfig
  echo "Saved in Config/Secrets.xcconfig (never committed)."
else
  echo "Using the saved key. Delete Config/Secrets.xcconfig to change it."
fi

step "Finding your Apple signing team"
team="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1 || true)"
[[ -n "$team" ]] || fail "No signing certificate yet. Open Xcode > Settings > Accounts, add your Apple ID, click 'Manage Certificates' > + > Apple Development, then run this again."
echo "Team $team"

step "Finding your iPhone"
devices="$(xcrun devicectl list devices 2>/dev/null || true)"
udid="$(printf '%s\n' "$devices" | awk '/iPhone/ && /(available|connected)/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4,16}/) { print $i; exit } }')"
[[ -n "$udid" ]] || { printf '%s\n' "$devices"; fail "No iPhone found. Connect it by cable, unlock it and tap Trust."; }
echo "iPhone $udid"

step "Building (the first build takes a few minutes)"
xcodegen >/dev/null
xcodebuild -project Looseweight.xcodeproj -scheme Looseweight -configuration Debug \
  -destination "generic/platform=iOS" -derivedDataPath build/device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic build -quiet

step "Installing and opening"
app="build/device/Build/Products/Debug-iphoneos/Looseweight.app"
xcrun devicectl device install app --device "$udid" "$app"
xcrun devicectl device process launch --device "$udid" io.github.haithamattiaali.looseweight \
  || echo "Installed. If it did not open: on the iPhone go to Settings > General > VPN & Device Management, trust your Apple ID, then tap the app."

printf '\n\033[32m✔ Looseweight is on your iPhone.\033[0m\n'
