#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
WINE_SOURCE_DATE_EPOCH=1783719732
WINE_REMOTE=https://gitlab.winehq.org/wine/wine.git
ENCORE_RELEASE_VERSION=v0.1.0
ENCORE_RUNTIME_REVISION=r1
ENCORE_RUNTIME_ASSET=encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz
ENCORE_SOURCE_ASSET=encore-wine-11.13-r1-source.tar.xz
ENCORE_BUNDLE_ASSET=ENCORE-v0.1.0-linux-x86_64.tar.xz
ENCORE_GLIBC_MIN=2.35
ENCORE_RUNTIME_SHA256=${ENCORE_RUNTIME_SHA256:-}
ENCORE_RELEASE_BASE_URL=${ENCORE_RELEASE_BASE_URL:-https://github.com/wowitsjack/ENCORE/releases/download/$ENCORE_RELEASE_VERSION}
ENCORE_RUNTIME_ROOT=${ENCORE_RUNTIME_ROOT:-"$PROJECT_ROOT/runtime/wine"}
WINE_SOURCE=${WINE_SOURCE:-"$PROJECT_ROOT/wine"}
WINE_BUILD=${WINE_BUILD:-"$PROJECT_ROOT/build/wine64"}
WINE_BINARY=${ENCORE_WINE:-"$WINE_BUILD/wine"}
WINE_INSTALL_PREFIX=${WINE_INSTALL_PREFIX:-/opt/encore-wine}
ENCORE_PREFIX=${ENCORE_PREFIX:-"$PROJECT_ROOT/ableton-prefix"}
WINE_PATCH="$PROJECT_ROOT/patches/encore-wine.patch"

say()
{
    printf '%s\n' "$*"
}

die()
{
    printf 'ENCORE: %s\n' "$*" >&2
    exit 1
}

require_command()
{
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

make_absolute_path()
{
    case $1 in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}
