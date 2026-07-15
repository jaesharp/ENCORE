#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

require_command fc-match
require_command cmp
require_command cp
require_command python3
require_command sed
require_command tr

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"
ableton_binary=$(encore_resolve_ableton_executable \
    "$ENCORE_PREFIX" "${ENCORE_ABLETON-}") || exit 1

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is running; close it before installing the WebView font fallback"
fi

python3 -c 'import fontTools.ttLib' >/dev/null 2>&1 || \
    die "Python fontTools is required; rerun ./install.sh --install-deps"

font_key='HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
font_value='Arial (TrueType)'
managed_filename=ENCOREArial.ttf
font_dir="$ENCORE_PREFIX/drive_c/windows/Fonts"
destination="$font_dir/$managed_filename"
generator="$SCRIPT_DIR/make-webview-fallback-font.py"

source_font=$(fc-match --format='%{file}\n' 'Liberation Sans:style=Regular' | sed -n '1p')
[ -f "$source_font" ] || \
    die "Liberation Sans Regular is required; rerun ./install.sh --install-deps"

mkdir -p "$font_dir"
temporary=$(mktemp "$font_dir/.ENCOREArial.XXXXXX")
backup=
published=0
committed=0
cleanup()
{
    trap - EXIT HUP INT TERM
    rm -f "$temporary"
    if [ "$published" -eq 1 ] && [ "$committed" -eq 0 ]; then
        rm -f "$destination"
        if [ -n "$backup" ] && [ -f "$backup" ]; then
            mv "$backup" "$destination"
        fi
    else
        [ -z "$backup" ] || rm -f "$backup"
    fi
    temporary=
    backup=
    published=0
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

python3 "$generator" "$source_font" "$temporary"
python3 "$generator" --verify "$source_font" "$temporary"
chmod 0644 "$temporary"

existing=$(
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
        "$WINE_BINARY" reg.exe query "$font_key" /v "$font_value" 2>/dev/null | \
        sed -n 's/^.*REG_SZ[[:space:]]*//p' | tr -d '\r'
)

if [ "$existing" = "$managed_filename" ] && \
   [ -f "$destination" ] && cmp -s "$temporary" "$destination"
then
    say "WebView font fallback is already installed"
    exit 0
fi
if [ -n "$existing" ] && [ "$existing" != "$managed_filename" ]; then
    case "$existing" in
        [Zz]:\\*)
            say "Replacing host-path Arial registration: $existing"
            ;;
        *)
            case "$existing" in
                *:\\*)
                    registered_font=$(
                        WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
                            "$WINE_BINARY" winepath.exe -u "$existing" 2>/dev/null | \
                            tr -d '\r' | sed -n '1p'
                    )
                    ;;
                *) registered_font="$font_dir/$existing" ;;
            esac
            if [ -f "$registered_font" ] && \
               python3 "$generator" --has-family "$registered_font" Arial
            then
                say "Existing Arial registration retained: $existing"
                exit 0
            fi
            say "Replacing stale or invalid Arial registration: $existing"
            ;;
    esac
fi

if [ -f "$destination" ]; then
    backup=$(mktemp "$font_dir/.ENCOREArial.backup.XXXXXX")
    cp -p "$destination" "$backup"
fi
trap '' HUP INT TERM
mv "$temporary" "$destination"
published=1
trap 'exit 1' HUP INT TERM

trap '' HUP INT TERM
if WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
   "$WINE_BINARY" reg.exe add "$font_key" /v "$font_value" \
   /t REG_SZ /d "$managed_filename" /f >/dev/null
then
    committed=1
    register_status=0
else
    register_status=$?
fi
trap 'exit 1' HUP INT TERM
if [ "$register_status" -ne 0 ]; then
    die "could not register the WebView font fallback"
fi
cleanup
trap - EXIT HUP INT TERM

say "Installed the WebView font fallback in $ENCORE_PREFIX"
