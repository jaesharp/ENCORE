#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

require_command sed

template="$PROJECT_ROOT/packaging/encore.desktop.in"
applications_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/applications
destination="$applications_dir/encore.desktop"
[ -f "$template" ] || die "missing desktop template: $template"

reject_control_characters()
{
    value=$1
    newline='
'
    carriage_return=$(printf '\r')
    tab=$(printf '\t')
    case $value in
        *"$newline"*|*"$carriage_return"*|*"$tab"*)
            die "desktop entry paths may not contain tabs or line breaks"
            ;;
    esac
}

escape_desktop_string()
{
    reject_control_characters "$1"
    printf '%s' "$1" | sed 's/\\/\\\\/g'
}

quote_exec_argument()
{
    reject_control_characters "$1"
    value=$(printf '%s' "$1" | sed \
        -e 's/\\/\\\\\\\\/g' \
        -e 's/"/\\\\"/g' \
        -e 's/`/\\\\`/g' \
        -e 's/\$/\\\\$/g' \
        -e 's/%/%%/g')
    printf '"%s"' "$value"
}

escape_sed()
{
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

launcher="$PROJECT_ROOT/scripts/launch-ableton.sh"
desktop_prefix=$(make_absolute_path "$ENCORE_PREFIX")
configured_ableton=${ENCORE_ABLETON-}
if [ -n "$configured_ableton" ]; then
    configured_ableton=$(make_absolute_path "$configured_ableton")
fi
ableton_binary=$(encore_resolve_ableton_executable \
    "$desktop_prefix" "$configured_ableton") || exit 1
encore_ableton_profile_from_executable "$ableton_binary" || \
    die "unsupported Ableton executable: $ableton_binary"
live_root=$(dirname -- "$(dirname -- "$ableton_binary")")
icon=$(encore_ableton_icon_for_live_root "$live_root" 2>/dev/null || true)
[ -n "$icon" ] || icon="$PROJECT_ROOT/assets/branding/encore-logo.png"

exec_value="/bin/sh $(quote_exec_argument "$launcher")"
exec_escaped=$(escape_sed "$exec_value")
try_exec_escaped=$(escape_sed "$(escape_desktop_string "$launcher")")
icon_escaped=$(escape_sed "$(escape_desktop_string "$icon")")
name_escaped=$(escape_sed "$(escape_desktop_string "$ENCORE_ABLETON_PRODUCT (ENCORE)")")
comment_escaped=$(escape_sed "$(escape_desktop_string "Run $ENCORE_ABLETON_PRODUCT with ENCORE")")
wm_class_escaped=$(escape_sed "$(escape_desktop_string "$ENCORE_ABLETON_WM_CLASS")")

render_desktop_entry()
{
    sed \
        -e "s|@NAME@|$name_escaped|g" \
        -e "s|@COMMENT@|$comment_escaped|g" \
        -e "s|@EXEC@|$exec_escaped|g" \
        -e "s|@TRY_EXEC@|$try_exec_escaped|g" \
        -e "s|@ICON@|$icon_escaped|g" \
        -e "s|@STARTUP_WM_CLASS@|$wm_class_escaped|g" \
        "$template"
}

if [ "${1:-}" = --dry-run ]; then
    render_desktop_entry
    exit 0
fi
[ "$#" -eq 0 ] || die "usage: $0 [--dry-run]"

mkdir -p "$applications_dir"
temporary=$(mktemp "$applications_dir/.encore.XXXXXX.desktop")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
render_desktop_entry >"$temporary"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$temporary"
fi
chmod 0644 "$temporary"
mv "$temporary" "$destination"
trap - EXIT HUP INT TERM

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir"
fi
say "Installed $destination"
