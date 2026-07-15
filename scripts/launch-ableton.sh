#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT/scripts/load-runtime-config.sh"
. "$ROOT/scripts/ableton-profile.sh"
PREFIX=${ENCORE_PREFIX:-"$ROOT/ableton-prefix"}
ABLETON=$(encore_resolve_ableton_executable "$PREFIX" "${ENCORE_ABLETON-}") || exit 1
LOG="$ROOT/logs/ableton-dock.log"
PROCESS_CHECK="$ROOT/scripts/process-is-running.sh"

if [ "${ENCORE_DRY_RUN:-0}" = 1 ]; then
    exec "$SCRIPT_DIR/run-ableton.sh"
fi

mkdir -p "$ROOT/logs"

if "$PROCESS_CHECK" "$ABLETON"; then
    exit 0
fi

exec "$SCRIPT_DIR/run-ableton.sh" >>"$LOG" 2>&1
