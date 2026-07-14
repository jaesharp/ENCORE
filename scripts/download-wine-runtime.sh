#!/usr/bin/env bash

# Download, verify, and atomically install the pinned ENCORE Wine runtime.
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$SCRIPT_DIR/common.sh"

for command in awk curl dirname getconf head mkdir mktemp mv rm rmdir sha256sum \
    sort tail tar uname xz; do
    require_command "$command"
done

case $(uname -m) in
    x86_64|amd64) ;;
    *) die "the prebuilt runtime currently supports only x86-64 Linux" ;;
esac

host_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
case $host_glibc in
    'glibc '[0-9]*.[0-9]*) host_glibc=${host_glibc#glibc } ;;
    *) die "the prebuilt runtime requires a glibc-based Linux distribution" ;;
esac
[ "$(printf '%s\n' "$ENCORE_GLIBC_MIN" "$host_glibc" | sort -V | head -n 1)" = \
    "$ENCORE_GLIBC_MIN" ] ||
    die "the prebuilt runtime requires glibc $ENCORE_GLIBC_MIN or newer; use --build-from-source on this system"

expected_patch=$(sha256sum "$WINE_PATCH" | awk '{print $1}')

validate_runtime()
{
    local root=$1 manifest glibc_max
    local -a records=()
    manifest=$root/.encore-runtime
    [ -x "$root/bin/wine" ] || return 1
    [ -x "$root/bin/wineserver" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/ntdll.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/dxgi.dll.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/winex11.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/winepulse.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/winegstreamer.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/winevulkan.so" ] || return 1
    [ -f "$root/lib/wine/x86_64-unix/comdlg32.so" ] || return 1
    [ -f "$root/share/wine/wine.inf" ] || return 1
    [ -f "$manifest" ] || return 1
    mapfile -t records <"$manifest"
    [ "${#records[@]}" -eq 7 ] || return 1
    [ "${records[0]}" = ENCORE_WINE_RUNTIME_V1 ] || return 1
    [ "${records[1]}" = "encore_version=$ENCORE_RELEASE_VERSION" ] || return 1
    [ "${records[2]}" = wine_version=11.13 ] || return 1
    [ "${records[3]}" = "wine_revision=$WINE_REVISION" ] || return 1
    [ "${records[4]}" = "patch_sha256=$expected_patch" ] || return 1
    [ "${records[5]}" = arch=x86_64 ] || return 1
    [[ ${records[6]} =~ ^glibc_max=([0-9]+\.[0-9]+)$ ]] || return 1
    glibc_max=${BASH_REMATCH[1]}
    [ "$(printf '%s\n' "$glibc_max" 2.35 | sort -V | tail -n 1)" = 2.35 ] ||
        return 1
    [ "$($root/bin/wine --version 2>/dev/null)" = wine-11.13 ] || return 1
}

if [ -e "$ENCORE_RUNTIME_ROOT" ] || [ -L "$ENCORE_RUNTIME_ROOT" ]; then
    validate_runtime "$ENCORE_RUNTIME_ROOT" && {
        say "Reusing verified ENCORE runtime: $ENCORE_RUNTIME_ROOT"
        exit 0
    }
    die "the runtime destination exists but is not a valid ENCORE runtime: $ENCORE_RUNTIME_ROOT"
fi

[ "${#ENCORE_RUNTIME_SHA256}" -eq 64 ] ||
    die "the release runtime checksum has not been published yet"
case $ENCORE_RUNTIME_SHA256 in
    *[!0-9a-f]*) die "the release runtime checksum is invalid" ;;
esac

cache_dir="$PROJECT_ROOT/.tmp/downloads"
runtime_parent=$(dirname -- "$ENCORE_RUNTIME_ROOT")
archive="$cache_dir/$ENCORE_RUNTIME_ASSET.part"
url="$ENCORE_RELEASE_BASE_URL/$ENCORE_RUNTIME_ASSET"
mkdir -p "$cache_dir" "$runtime_parent"

say "Downloading the prebuilt ENCORE Wine runtime"
if ! curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --retry 4 --retry-all-errors --continue-at - --max-filesize 536870912 \
    --output "$archive" "$url"; then
    die "runtime download failed; rerun the installer to resume it"
fi

actual_sha256=$(sha256sum "$archive" | awk '{print $1}')
[ "$actual_sha256" = "$ENCORE_RUNTIME_SHA256" ] || {
    rm -f "$archive"
    die "runtime checksum verification failed"
}

while IFS= read -r entry; do
    case $entry in
        encore-wine|encore-wine/*) ;;
        *) die "runtime archive contains an unsafe path: $entry" ;;
    esac
    case /$entry/ in
        */../*|*/./*) die "runtime archive contains an unsafe path: $entry" ;;
    esac
done < <(tar -tJf "$archive")

extract_dir=$(mktemp -d "$runtime_parent/.encore-wine.XXXXXX")
trap 'rm -rf "$extract_dir"' EXIT HUP INT TERM
tar -xJf "$archive" --no-same-owner --no-same-permissions -C "$extract_dir"
validate_runtime "$extract_dir/encore-wine" || die "downloaded runtime validation failed"
mv "$extract_dir/encore-wine" "$ENCORE_RUNTIME_ROOT"
rmdir "$extract_dir"
trap - EXIT HUP INT TERM
rm -f "$archive"

say "Installed prebuilt ENCORE Wine: $ENCORE_RUNTIME_ROOT/bin/wine"
