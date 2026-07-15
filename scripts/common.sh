#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
WINE_SOURCE_DATE_EPOCH=1783719732
WINE_REMOTE=https://gitlab.winehq.org/wine/wine.git
ENCORE_RELEASE_VERSION=v0.1.1
ENCORE_RUNTIME_VERSION=v0.1.0
ENCORE_RUNTIME_REVISION=r1
ENCORE_RUNTIME_ASSET=encore-wine-11.13-r1-x86_64-linux-gnu.tar.xz
ENCORE_SOURCE_ASSET=encore-wine-11.13-r1-source.tar.xz
ENCORE_BUNDLE_ASSET=ENCORE-v0.1.1-linux-x86_64.tar.xz
ENCORE_GLIBC_MIN=2.35
ENCORE_RUNTIME_SHA256=${ENCORE_RUNTIME_SHA256:-b58f0acc6868b5160cb561d55ac04e4ee5feba3b4eae61388dc45692d5d05ccd}
ENCORE_RELEASE_BASE_URL=${ENCORE_RELEASE_BASE_URL:-https://github.com/wowitsjack/ENCORE/releases/download/$ENCORE_RELEASE_VERSION}
ENCORE_RUNTIME_ROOT=${ENCORE_RUNTIME_ROOT:-"$PROJECT_ROOT/runtime/wine"}
WINE_SOURCE=${WINE_SOURCE:-"$PROJECT_ROOT/wine"}
WINE_BUILD=${WINE_BUILD:-"$PROJECT_ROOT/build/wine64"}
WINE_BINARY=${ENCORE_WINE:-"$WINE_BUILD/wine"}
WINE_INSTALL_PREFIX=${WINE_INSTALL_PREFIX:-/opt/encore-wine}
ENCORE_PREFIX=${ENCORE_PREFIX:-"$PROJECT_ROOT/ableton-prefix"}
WINE_PATCH_DIR="$PROJECT_ROOT/patches/wine"

say()
{
    printf '%s\n' "$*"
}

# The ENCORE Wine patch is a set of semantic patch files under patches/wine/,
# applied in sorted (filename) order. These helpers give the apply order and the
# combined patch identity used throughout ENCORE's build and runtime verification.
encore_wine_patch_files()
{
    for _encore_wine_patch in "$WINE_PATCH_DIR"/*.patch; do
        [ -f "$_encore_wine_patch" ] || continue
        printf '%s\n' "$_encore_wine_patch"
    done
    unset _encore_wine_patch
}

encore_patch_sha256()
{
    _encore_patch_count=0
    for _encore_wine_patch in "$WINE_PATCH_DIR"/*.patch; do
        [ -f "$_encore_wine_patch" ] && _encore_patch_count=$((_encore_patch_count + 1))
    done
    [ "$_encore_patch_count" -gt 0 ] || { unset _encore_wine_patch _encore_patch_count; return 1; }
    unset _encore_wine_patch _encore_patch_count
    cat "$WINE_PATCH_DIR"/*.patch | sha256sum | awk '{print $1}'
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
