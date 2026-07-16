#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

dpi=${1:-192}
case "$dpi" in
    ''|*[!0-9]*) die "DPI must be an integer between 72 and 384" ;;
esac
[ "$dpi" -ge 72 ] && [ "$dpi" -le 384 ] || die "DPI must be between 72 and 384"

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"
ableton_binary=$(encore_resolve_ableton_executable \
    "$ENCORE_PREFIX" "${ENCORE_ABLETON-}") || exit 1
encore_ableton_profile_from_executable "$ableton_binary" || \
    die "unsupported Ableton executable: $ableton_binary"

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is running; close it before changing prefix DPI"
fi

WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
    "$WINE_BINARY" reg.exe add 'HKCU\Control Panel\Desktop' \
    /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null

# Keep per-monitor DPI awareness in step with the pixel density. Above 96 dpi Live
# must read the monitor DPI from the X server -- its Image File Execution Options
# carry dpiAwareness=2 -- otherwise it renders at the raw LogPixels and bitmap-scales
# (blurry). At 96 dpi (100%) the key is removed so Live stays DPI-unaware. The
# key is only safe because of the patched windowing (patches/wine/30 + 31).
ifeo_key="HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\$ENCORE_ABLETON_EXE"
if [ "$dpi" -gt 96 ]; then
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
        "$WINE_BINARY" reg.exe add "$ifeo_key" /v dpiAwareness /t REG_DWORD /d 2 /f >/dev/null
    say "Wine DPI set to $dpi in $ENCORE_PREFIX (per-monitor awareness on for $ENCORE_ABLETON_EXE)"
else
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
        "$WINE_BINARY" reg.exe delete "$ifeo_key" /v dpiAwareness /f >/dev/null 2>&1 || true
    say "Wine DPI set to $dpi in $ENCORE_PREFIX (per-monitor awareness off)"
fi
