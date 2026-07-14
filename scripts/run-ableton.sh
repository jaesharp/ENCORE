#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT/scripts/load-runtime-config.sh"
PREFIX=${ENCORE_PREFIX:-"$ROOT/ableton-prefix"}
default_wine="$ROOT/runtime/wine/bin/wine"
[ -x "$default_wine" ] || default_wine="$ROOT/build/wine64/wine"
WINE=${ENCORE_WINE:-"$default_wine"}
ABLETON=${ENCORE_ABLETON:-"$PREFIX/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"}

default_webview_flags='--use-gl=angle --use-angle=swiftshader --disable-gpu-compositing --disable-gpu-rasterization --disable-direct-composition --disable-features=ForceSWDCompWhenDCompFallbackRequired --edge-webview-foreground-boost-opt-out --no-sandbox'
webview_flags=${ENCORE_WEBVIEW2_FLAGS-"$default_webview_flags"}
webview_arguments=${WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS-}
if [ -n "$webview_flags" ]; then
    webview_arguments="${webview_arguments:+$webview_arguments }$webview_flags"
fi

wine_dll_overrides="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml,winemenubuilder.exe,dcomp="

if [ "${ENCORE_CPU_TOPOLOGY+x}" = x ]; then
    cpu_topology=$ENCORE_CPU_TOPOLOGY
elif [ "${WINE_CPU_TOPOLOGY+x}" = x ]; then
    cpu_topology=$WINE_CPU_TOPOLOGY
else
    cpu_topology=$("$ROOT/scripts/select-cpu-topology.sh")
fi

if [ "${ENCORE_DRY_RUN:-0}" = 1 ]; then
    printf 'WINEPREFIX=%s\n' "$PREFIX"
    printf 'WINE=%s\n' "$WINE"
    printf 'ABLETON=%s\n' "$ABLETON"
    printf 'WINEDLLOVERRIDES=%s\n' "$wine_dll_overrides"
    printf 'WINE_DISABLE_UNIX_MOUNT_REPARSE=1\n'
    printf 'ENCORE_NATIVE_VST3_DECORATIONS=%s\n' "${ENCORE_NATIVE_VST3_DECORATIONS-1}"
    printf 'ENCORE_NATIVE_VST3_DPI=%s\n' "${ENCORE_NATIVE_VST3_DPI-1}"
    printf 'ENCORE_VST3_RESIZE_REPAINT=%s\n' "${ENCORE_VST3_RESIZE_REPAINT-1}"
    printf 'ENCORE_ABLETON_MENU_THEME=%s\n' "${ENCORE_ABLETON_MENU_THEME-1}"
    printf 'WINE_CPU_TOPOLOGY=%s\n' "$cpu_topology"
    printf 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=%s\n' "$webview_arguments"
    exit 0
fi

mkdir -p "$ROOT/.tmp"
export TMPDIR="$ROOT/.tmp"
export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="$wine_dll_overrides"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINE_DISABLE_UNIX_MOUNT_REPARSE=1
export ENCORE_X11_MIN_VISIBLE_SIZE="${ENCORE_X11_MIN_VISIBLE_SIZE-800x643}"
export ENCORE_NATIVE_VST3_DECORATIONS="${ENCORE_NATIVE_VST3_DECORATIONS-1}"
export ENCORE_NATIVE_VST3_DPI="${ENCORE_NATIVE_VST3_DPI-1}"
export ENCORE_VST3_RESIZE_REPAINT="${ENCORE_VST3_RESIZE_REPAINT-1}"
export ENCORE_ABLETON_MENU_THEME="${ENCORE_ABLETON_MENU_THEME-1}"
if [ -n "$cpu_topology" ]; then
    export WINE_CPU_TOPOLOGY="$cpu_topology"
else
    unset WINE_CPU_TOPOLOGY
fi
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$webview_arguments"

exec "$WINE" "$ABLETON" "$@"
