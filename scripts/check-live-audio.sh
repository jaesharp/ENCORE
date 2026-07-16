#!/bin/sh

# Check that Live opens the WineASIO audio driver without crashing (the classic
# failure is ASE_NoClock on a sample-rate mismatch). Run after Live is installed
# and WineASIO is registered (scripts/build-wineasio.sh + configure-prefix.sh),
# with a desktop session available. Exit 0 = the driver opened and no FatalError
# was logged.
#
# Ported from shibco/ableton-linux scripts/check-live-audio.sh, adapted to
# ENCORE's launcher, prefix layout, and process/wineserver helpers.
set -u

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

timeout_seconds=${ENCORE_CHECK_TIMEOUT:-180}

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"
ableton_binary=$(encore_resolve_ableton_executable "$ENCORE_PREFIX" "${ENCORE_ABLETON-}") || exit 1
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || die "needs a desktop session (DISPLAY/WAYLAND_DISPLAY unset)"

# Newest Live Log.txt in the prefix (any Wine user dir, any Live version). Glob
# expansion is lexically sorted, so the last existing match is the highest dir.
live_log=
for _log in "$ENCORE_PREFIX"/drive_c/users/*/AppData/Roaming/Ableton/"Live "*/Preferences/Log.txt; do
    [ -f "$_log" ] && live_log=$_log
done
[ -n "$live_log" ] || die "no Live Log.txt under $ENCORE_PREFIX -- launch Live once first"

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is already running; close it before the audio check"
fi

base=$(wc -l < "$live_log")
say "== launching Live (log baseline: line $base; timeout ${timeout_seconds}s) =="
setsid nohup "$SCRIPT_DIR/launch-ableton.sh" >/dev/null 2>&1 &

verdict=
elapsed=0
while [ "$elapsed" -lt "$timeout_seconds" ]; do
    sleep 5
    elapsed=$((elapsed + 5))
    new=$(tail -n +"$((base + 1))" "$live_log" 2>/dev/null) || new=
    if printf '%s' "$new" | grep -qaE "FatalError|Uncaught exception"; then verdict=fatal; break; fi
    if printf '%s' "$new" | grep -qa "Open: finished"; then verdict=opened; break; fi
    if ! "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then verdict=died; break; fi
done

new=$(tail -n +"$((base + 1))" "$live_log" 2>/dev/null) || new=
say "-- audio driver lines Live logged:"
printf '%s\n' "$new" | grep -aiE "ASIO|SampleRate|FatalError|Uncaught" | tail -n 12 | sed 's/^/   /'

# Shut down the wineserver this check started (sibling of the wine loader for the
# packaged runtime, or under server/ for the in-tree build).
wineserver="$(dirname -- "$WINE_BINARY")/wineserver"
[ -x "$wineserver" ] || wineserver="$(dirname -- "$WINE_BINARY")/server/wineserver"
if [ -x "$wineserver" ]; then
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all "$wineserver" -k >/dev/null 2>&1 || true
fi

case "$verdict" in
    opened)
        rate=$(printf '%s' "$new" | grep -ao "Used SampleRate: [0-9]*" | tail -n 1)
        say "OK: Live opened the audio driver cleanly (${rate:-rate unknown})"
        exit 0
        ;;
    fatal)
        die "FAIL: Live hit a FatalError while opening the audio driver (ASE_NoClock on a sample-rate mismatch is the classic cause)"
        ;;
    died)
        die "FAIL: Live exited before opening the audio driver"
        ;;
    *)
        die "FAIL: Live never finished opening the driver within ${timeout_seconds}s (a hung 'Open: started' means the JACK graph never came up -- check 'pw-metadata -n settings' for a forced clock rate)"
        ;;
esac
