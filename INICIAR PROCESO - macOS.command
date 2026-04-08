#!/bin/bash
set -e

cd "$(dirname "$0")"
exec /bin/bash "./_interno/bootstrap_macos.sh"
