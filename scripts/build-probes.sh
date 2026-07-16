#!/bin/sh

# Build the diagnostic probes under tools/probes/ into build/probes/.
#
# These are manual maintainer/tester diagnostics (see tools/probes/README.md),
# ported from shibco/ableton-linux (LGPL, the same license as Wine). They are
# not part of the install flow and nothing depends on them at runtime.
#
# Two kinds:
#   native  (fakectl, xsettle)                       — host cc, ALSA/X11 headers
#   PE      (midihot, dpispy, metricprobe, wmresize) — the mingw-w64 cross
#           compiler ENCORE's Wine build already requires; CRT-free, so no
#           mingw runtime DLLs are involved. Run them inside the prefix:
#             WINEPREFIX=$PWD/ableton-prefix build/wine64/wine build/probes/dpispy.exe
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

PROBE_SOURCE_DIR="$PROJECT_ROOT/tools/probes"
PROBE_BUILD_DIR=${PROBE_BUILD_DIR:-"$PROJECT_ROOT/build/probes"}
MINGW_CC=${MINGW_CC:-x86_64-w64-mingw32-gcc}

require_command cc
command -v "$MINGW_CC" >/dev/null 2>&1 ||
    die "$MINGW_CC not found; install the mingw-w64 x86_64 toolchain (scripts/install-dependencies.sh --install build)"
[ -f /usr/include/alsa/asoundlib.h ] || [ -f /usr/local/include/alsa/asoundlib.h ] ||
    die "ALSA headers not found (install libasound2-dev / alsa-lib-devel) — needed by fakectl"
[ -f /usr/include/X11/Xlib.h ] || [ -f /usr/local/include/X11/Xlib.h ] ||
    die "X11 headers not found (install libx11-dev / libX11-devel) — needed by xsettle"

mkdir -p "$PROBE_BUILD_DIR"

# Warnings are errors. The PE probes keep shibco's sources verbatim, and Win32
# callback signatures (window procs, midiIn callbacks) are fixed by the API, so
# unused-parameter is suppressed there — everything else still fails the build.
native_flags="-O2 -Wall -Wextra -Werror"
pe_flags="-O2 -Wall -Wextra -Werror -Wno-unused-parameter -fno-stack-protector -nostdlib \
    -DWINVER=0x0A00 -D_WIN32_WINNT=0x0A00"

build_native()      # $1 = name, rest = extra link flags
{
    name=$1; shift
    say "  cc      $name"
    # shellcheck disable=SC2086
    cc $native_flags -o "$PROBE_BUILD_DIR/$name" "$PROBE_SOURCE_DIR/$name.c" "$@"
}

build_pe()          # $1 = name, $2 = subsystem, $3 = entry, rest = libs
{
    name=$1 subsystem=$2 entry=$3; shift 3
    say "  mingw   $name.exe"
    # shellcheck disable=SC2086
    "$MINGW_CC" $pe_flags -o "$PROBE_BUILD_DIR/$name.exe" "$PROBE_SOURCE_DIR/$name.c" \
        -Wl,--subsystem,"$subsystem" -Wl,-e,"$entry" "$@" -lgcc
}

say "Building diagnostic probes into $PROBE_BUILD_DIR"
build_native fakectl -lasound
build_native xsettle -lX11
build_pe midihot     console mainCRTStartup    -lwinmm -luser32 -lkernel32
build_pe metricprobe console mainCRTStartup    -luser32 -lgdi32 -lkernel32
build_pe wmresize    console mainCRTStartup    -luser32 -lgdi32 -lkernel32
build_pe dpispy      windows WinMainCRTStartup -luser32 -lkernel32

say "Probes built in $PROBE_BUILD_DIR:"
for probe in "$PROBE_BUILD_DIR"/*; do
    say "  ${probe##*/}"
done
