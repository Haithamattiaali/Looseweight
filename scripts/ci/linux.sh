#!/usr/bin/env bash
# Linux job: core engine tests (runs inside the swift:6.4 container).
set -euo pipefail
cd "$(dirname "$0")/../.."
swift --version
cd Packages/LooseweightKit
swift test
