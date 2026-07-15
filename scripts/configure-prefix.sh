#!/bin/sh

# Configure prefix features that Live relies on at runtime.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

ableton_binary=$(encore_resolve_ableton_executable \
    "$ENCORE_PREFIX" "${ENCORE_ABLETON-}") || exit 1
encore_ableton_profile_from_executable "$ableton_binary" || \
    die "unsupported Ableton executable: $ableton_binary"
dosdevices="$ENCORE_PREFIX/dosdevices"
root_drive=

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is running; close it before configuring the prefix"
fi

mkdir -p "$dosdevices"

for drive in "$dosdevices"/[a-z]:; do
    [ -L "$drive" ] || continue
    [ "$(readlink -- "$drive")" = / ] || continue
    root_drive=${drive##*/}
    break
done

if [ -z "$root_drive" ]; then
    for letter in z y x w v u t s r q p o n m l k j i h g f e d; do
        drive="$dosdevices/$letter:"
        [ -e "$drive" ] || [ -L "$drive" ] || {
            ln -s / "$drive"
            root_drive="$letter:"
            break
        }
    done
fi

[ -n "$root_drive" ] || die "no free Wine drive letter is available for host folders"

WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
    "$WINE_BINARY" reg.exe add \
    "HKCU\\Software\\Wine\\AppDefaults\\$ENCORE_ABLETON_EXE\\X11 Driver" \
    /v FileDialogPortal /t REG_SZ /d always /f >/dev/null

say "Native folder picker enabled for Ableton; host files are available through $root_drive"

# Route only Push 2's display helper through ENCORE's builtin libusb-1.0 bridge so
# it can reach the device's vendor bulk interface (Wine's WinUSB path cannot open
# interface 0); Live's own process keeps Ableton's bundled libusb untouched.
# See patches/wine/100-push2-libusb-bridge.patch.
WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
    "$WINE_BINARY" reg.exe add \
    "HKCU\\Software\\Wine\\AppDefaults\\Push2DisplayProcess.exe\\DllOverrides" \
    /v libusb-1.0 /t REG_SZ /d builtin /f >/dev/null

say "Push 2 display bridge enabled (Push2DisplayProcess.exe uses ENCORE's libusb-1.0)"

# Register WineASIO (low-latency audio: WineASIO -> JACK/PipeWire) if it has been
# built (scripts/build-wineasio.sh). Live then lists it under ASIO devices. The
# PE half must live in the prefix's system32; the Unix half is found at load time
# via WINEDLLPATH (set here and by the launcher). Skipped silently if not built.
wineasio_root="$PROJECT_ROOT/runtime/wineasio"
if [ -f "$wineasio_root/wineasio64.dll" ] && [ -f "$wineasio_root/wineasio64.dll.so" ]; then
    ldconfig -p 2>/dev/null | grep -q 'libjack\.so\.0' ||
        say "  note: host libjack.so.0 not found — install pipewire-jack (or JACK2) before using WineASIO"
    for name in wineasio64.dll wineasio.dll; do
        cp -f "$wineasio_root/wineasio64.dll" "$ENCORE_PREFIX/drive_c/windows/system32/$name"
    done
    if WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
        WINEDLLPATH="$wineasio_root${WINEDLLPATH:+:$WINEDLLPATH}" \
        "$WINE_BINARY" regsvr32 "$wineasio_root/wineasio64.dll.so" >/dev/null 2>&1
    then
        say "WineASIO registered (Preferences > Audio > Driver Type: ASIO > Device: WineASIO)"
    else
        say "  note: WineASIO registration did not complete; check host libjack and re-run configure-prefix.sh"
    fi
fi
