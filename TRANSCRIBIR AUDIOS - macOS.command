#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
chmod +x "./_interno/bootstrap_macos.sh"
exec /bin/bash "./_interno/bootstrap_macos.sh"
