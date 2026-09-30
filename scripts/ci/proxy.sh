#!/usr/bin/env bash
# Proxy job: type check and unit tests for the Cloudflare Worker.
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ ! -f proxy/package.json ]; then
  echo "No proxy yet — skipping."
  exit 0
fi
cd proxy
npm ci
npm run typecheck
npm test
