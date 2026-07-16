#!/bin/sh

# Remove what ENCORE's install.sh added. ENCORE builds and runs entirely inside
# the project directory, so the only file it writes elsewhere is the application-
# menu entry; the Wine build, runtime, and prefix all live under the project and
# are removed only when you ask for them. To remove ENCORE completely, delete the
# project directory after running this.
#
# Ported from shibco/ableton-linux scripts/uninstall.sh, adapted to ENCORE's
# project-local layout and common.sh helpers.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

remove_prefix=0
remove_build=0
assume_yes=0
for arg in "$@"; do
    case $arg in
        --prefix) remove_prefix=1 ;;
        --build)  remove_build=1 ;;
        --all)    remove_prefix=1; remove_build=1 ;;
        -y|--yes) assume_yes=1 ;;
        -h|--help)
            cat <<EOF
usage: ${0##*/} [--prefix] [--build] [--all] [-y|--yes]

  (default)   remove the application-menu entry -- the only file ENCORE installs
              outside the project directory
  --prefix    also remove the Wine prefix ($ENCORE_PREFIX); this deletes your
              Live installation AND its authorization
  --build     also remove the built Wine/WineASIO under the project (runtime/,
              build/, wine/) -- a full rebuild is needed to reinstall afterwards
  --all       both --prefix and --build
  -y, --yes   do not prompt for confirmation
EOF
            exit 0 ;;
        *) die "unknown option: $arg (try --help)" ;;
    esac
done

confirm()       # $1 = prompt; auto-yes with --yes, defaults to No otherwise
{
    [ "$assume_yes" -eq 0 ] || return 0
    printf '%s [y/N] ' "$1" >&2
    read -r _confirm_reply || return 1
    case $_confirm_reply in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# 1. Application-menu entry (install-desktop.sh writes exactly this file).
apps_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/applications
desktop_entry="$apps_dir/encore.desktop"
if [ -e "$desktop_entry" ]; then
    rm -f -- "$desktop_entry"
    say "removed $desktop_entry"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$apps_dir" 2>/dev/null || true
    fi
else
    say "no application-menu entry at $desktop_entry"
fi

# 2. Wine prefix (Live install + authorization) and any dead Wine menu entries
#    that point into it (Live's own installer can leave winemenubuilder shortcuts).
if [ "$remove_prefix" -eq 1 ]; then
    if [ -d "$ENCORE_PREFIX" ]; then
        if confirm "Delete the Wine prefix $ENCORE_PREFIX? This removes Live AND its authorization."; then
            find "$apps_dir" -maxdepth 3 -name '*.desktop' -type f 2>/dev/null | while IFS= read -r entry; do
                if grep -qF -- "$ENCORE_PREFIX" "$entry" 2>/dev/null; then
                    rm -f -- "$entry" && say "removed dead Wine menu entry: $entry"
                fi
            done
            rm -rf -- "$ENCORE_PREFIX"
            say "removed $ENCORE_PREFIX"
        else
            say "kept $ENCORE_PREFIX"
        fi
    else
        say "no Wine prefix at $ENCORE_PREFIX"
    fi
fi

# 3. Built Wine/WineASIO under the project (a rebuild is needed to reinstall).
if [ "$remove_build" -eq 1 ]; then
    if confirm "Delete the built Wine/WineASIO under the project? A full rebuild is needed afterwards."; then
        for dir in "$WINE_BUILD" "$ENCORE_RUNTIME_ROOT" "$WINEASIO_ROOT" \
                   "$WINEASIO_SOURCE" "$WINE_SOURCE" "$PROJECT_ROOT/logs" "$PROJECT_ROOT/.tmp"; do
            [ -e "$dir" ] || continue
            rm -rf -- "$dir"
            say "removed $dir"
        done
    else
        say "kept the built Wine/WineASIO"
    fi
fi

say "done. To remove ENCORE entirely, delete the project directory: $PROJECT_ROOT"
