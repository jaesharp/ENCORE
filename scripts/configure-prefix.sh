#!/bin/sh

# Configure prefix features that Live relies on at runtime.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"
. "$SCRIPT_DIR/detect-scale.sh"

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

# High-DPI policy. Live becomes per-monitor-DPI-aware only when its Image File
# Execution Options carry dpiAwareness=2; Wine's win32u then reads the real
# monitor DPI from the X server rather than the registry LogPixels. The patched
# windowing (patches/wine/30-windowing-and-hidpi.patch + 31-windowing-nspa.patch)
# is what makes that key safe -- without it Live dies before showing a window.
#
# Two calibrated blocks, keyed off the detected display scale:
#   100    -> LogPixels 96,  no dpiAwareness   (100% / unscaled)
#   hidpi  -> LogPixels 192, dpiAwareness=2     (true 2x, and fractional scaling
#            via a compositor that renders Xwayland at native 2x then downscales)
# ENCORE_DPI_MODE selects the policy: auto (detect, default), preserve, 100, hidpi.
# The scale->block map is deliberately conservative (only calibrated scales apply
# automatically); everything else is left to an explicit ENCORE_DPI_MODE.
dpi_mode=${ENCORE_DPI_MODE:-auto}
ifeo_key="HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\$ENCORE_ABLETON_EXE"

encore_reg()
{
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all "$WINE_BINARY" reg.exe "$@" >/dev/null 2>&1
}

encore_current_dpi_block()
{
    _cdb_lp=$(WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all "$WINE_BINARY" reg.exe query \
        'HKCU\Control Panel\Desktop' /v LogPixels 2>/dev/null \
        | awk '$1=="LogPixels"{gsub(/\r/,"",$3); print tolower($3)}')
    [ -n "$_cdb_lp" ] || _cdb_lp=0x60          # wineboot default is 96 dpi
    if encore_reg query "$ifeo_key" /v dpiAwareness; then _cdb_ifeo=present; else _cdb_ifeo=absent; fi
    if [ "$_cdb_lp" = 0x60 ] && [ "$_cdb_ifeo" = absent ]; then
        printf '100\n'
    elif [ "$_cdb_lp" = 0xc0 ] && [ "$_cdb_ifeo" = present ]; then
        printf 'hidpi\n'
    else
        printf 'custom\n'
    fi
}

encore_apply_dpi_block()        # $1 = 100 | hidpi
{
    case $1 in
        100)
            encore_reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f
            encore_reg delete "$ifeo_key" /v dpiAwareness /f || true
            say "DPI: 100% (LogPixels 96, per-monitor awareness off)"
            ;;
        hidpi)
            encore_reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 192 /f
            encore_reg add "$ifeo_key" /v dpiAwareness /t REG_DWORD /d 2 /f
            say "DPI: HiDPI (LogPixels 192, dpiAwareness=2 for $ENCORE_ABLETON_EXE)"
            ;;
    esac
}

encore_block_for_scale()        # $1 = scale -> calibrated block name, or empty
{
    case $1 in
        1)                    printf '100\n' ;;
        1.25|1.5|1.75|2)      printf 'hidpi\n' ;;
        *)                    printf '\n' ;;
    esac
}

encore_check_mutter_knob()      # $1 = block, $2 = scale (optional)
{
    command -v gsettings >/dev/null 2>&1 || return 0
    _cmk_feats=$(gsettings get org.gnome.mutter experimental-features 2>/dev/null) || return 0
    case $1 in
        hidpi)
            # Only fractional scales rely on xwayland-native-scaling; integer 2x is native.
            case ${2:-} in
                *.*)
                    case $_cmk_feats in
                        *xwayland-native-scaling*) : ;;
                        *) say "  note: GNOME fractional scaling needs 'xwayland-native-scaling' in org.gnome.mutter experimental-features for Live to render crisply" ;;
                    esac
                    ;;
            esac
            ;;
        100)
            case $_cmk_feats in
                *xwayland-native-scaling*) say "  note: GNOME lists 'xwayland-native-scaling'; the 100% DPI block does not expect it" ;;
            esac
            ;;
    esac
    return 0
}

case $dpi_mode in
    100|hidpi)
        encore_apply_dpi_block "$dpi_mode"
        encore_check_mutter_knob "$dpi_mode"
        ;;
    preserve)
        say "DPI: preserving the prefix's current LogPixels/dpiAwareness (ENCORE_DPI_MODE=preserve)"
        ;;
    auto)
        if dpi_scale=$(encore_detect_scale); then
            dpi_block=$(encore_block_for_scale "$dpi_scale")
            if [ -z "$dpi_block" ]; then
                say "DPI: display scale $dpi_scale has no calibrated block (100% and HiDPI are) -- preserving; set ENCORE_DPI_MODE=100 or hidpi to force"
            else
                dpi_have=$(encore_current_dpi_block)
                if [ "$dpi_have" = "$dpi_block" ]; then
                    say "DPI: display scale $dpi_scale -> '$dpi_block' block already set"
                elif [ "$dpi_have" = custom ]; then
                    say "DPI: display scale $dpi_scale wants '$dpi_block', but the prefix holds custom LogPixels/dpiAwareness -- preserving; set ENCORE_DPI_MODE=$dpi_block to override"
                else
                    say "DPI: display scale $dpi_scale -> applying '$dpi_block' block (was '$dpi_have')"
                    encore_apply_dpi_block "$dpi_block"
                    encore_check_mutter_knob "$dpi_block" "$dpi_scale"
                fi
            fi
        else
            say "DPI: could not detect the display scale (headless or unknown compositor) -- preserving current values; set ENCORE_DPI_MODE=100 or hidpi to force"
        fi
        ;;
    *)
        die "ENCORE_DPI_MODE must be auto, preserve, 100, or hidpi (got: $dpi_mode)"
        ;;
esac
