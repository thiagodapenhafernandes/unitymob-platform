#!/usr/bin/env bash
set -euo pipefail

REPO="${NOTIFICALEAD_REPO:-/Users/thiagodap.fernandes/worksapces/notificalead}"

cd "$REPO"
exec bash scripts/notificalead_360_snapshot.sh "$@"
