#!/usr/bin/env bash
# Stores your Anthropic API key for local builds only (Config/Secrets.xcconfig is git-ignored).
# On first launch the app moves it into the iPhone Keychain and switches to "My Anthropic API key".
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -s -p "Paste your Anthropic API key: " key; echo
[[ "$key" == sk-ant-* ]] || { echo "That does not look like an Anthropic key (sk-ant-...)."; exit 1; }
printf 'LW_ANTHROPIC_KEY = %s\n' "$key" > Config/Secrets.xcconfig
chmod 600 Config/Secrets.xcconfig
xcodegen >/dev/null && echo "Saved. Build and run the app in Xcode (▶)."
