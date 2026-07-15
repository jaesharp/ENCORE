#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_command awk
require_command sha256sum
[ -d "$WINE_PATCH_DIR" ] || die "missing patch directory: $WINE_PATCH_DIR"
encore_patch_sha256 >/dev/null 2>&1 || die "no ENCORE Wine patches found in $WINE_PATCH_DIR"

corresponding_source_marker="$WINE_SOURCE/.encore-corresponding-source"
if [ -e "$corresponding_source_marker" ] || [ -L "$corresponding_source_marker" ]; then
    [ -f "$corresponding_source_marker" ] && [ -r "$corresponding_source_marker" ] ||
        die "invalid corresponding-source marker: $corresponding_source_marker"
    marker_header=
    marker_revision=
    marker_patch=
    marker_extra=
    marker_valid=1
    {
        IFS= read -r marker_header || marker_valid=0
        IFS= read -r marker_revision || marker_valid=0
        IFS= read -r marker_patch || marker_valid=0
        if IFS= read -r marker_extra || [ -n "$marker_extra" ]; then
            marker_valid=0
        fi
    } <"$corresponding_source_marker"
    expected_patch_sha256=$(encore_patch_sha256)
    [ "$marker_valid" = 1 ] &&
        [ "$marker_header" = ENCORE_CORRESPONDING_WINE_SOURCE_V1 ] &&
        [ "$marker_revision" = "wine_revision=$WINE_REVISION" ] &&
        [ "$marker_patch" = "patch_sha256=$expected_patch_sha256" ] ||
        die "the corresponding-source marker does not match this ENCORE release"
    [ -x "$WINE_SOURCE/configure" ] && [ -f "$WINE_SOURCE/configure.ac" ] ||
        die "the corresponding Wine source tree is incomplete: $WINE_SOURCE"
    say "Using packaged corresponding Wine source at $WINE_SOURCE"
    exit 0
fi

require_command git
require_command mktemp
require_command rm

if [ ! -e "$WINE_SOURCE" ]; then
    source_parent=$(dirname -- "$WINE_SOURCE")
    source_name=$(basename -- "$WINE_SOURCE")
    temporary_source="$source_parent/.${source_name}.clone.$$"
    mkdir -p "$source_parent"
    [ ! -e "$temporary_source" ] || die "temporary clone path already exists: $temporary_source"
    cleanup_clone()
    {
        rm -rf -- "$temporary_source"
    }
    trap cleanup_clone EXIT HUP INT TERM
    say "Cloning Wine into $WINE_SOURCE"
    git clone --filter=blob:none "$WINE_REMOTE" "$temporary_source"
    mv "$temporary_source" "$WINE_SOURCE"
    trap - EXIT HUP INT TERM
fi

[ "$(git -C "$WINE_SOURCE" rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ] ||
    die "$WINE_SOURCE is not a Git checkout"

source_matches_patch()
(
    temporary_index=$(mktemp "${TMPDIR:-/tmp}/encore-wine-index.XXXXXX")
    rm -f "$temporary_index"
    trap 'rm -f "$temporary_index"' EXIT HUP INT TERM
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" read-tree HEAD || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" apply --cached "$WINE_PATCH_DIR"/*.patch || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" update-index --refresh >/dev/null 2>&1 || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" diff-files --quiet || exit 1
    [ -z "$(GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" ls-files --others --exclude-standard)" ]
)

head=$(git -C "$WINE_SOURCE" rev-parse HEAD)
if [ "$head" != "$WINE_REVISION" ]; then
    if [ -n "$(git -C "$WINE_SOURCE" status --porcelain)" ]; then
        die "Wine is at $head with local changes; expected clean revision $WINE_REVISION"
    fi
    if ! git -C "$WINE_SOURCE" cat-file -e "$WINE_REVISION^{commit}" 2>/dev/null; then
        say "Fetching pinned Wine revision"
        git -C "$WINE_SOURCE" fetch --filter=blob:none origin
    fi
    git -C "$WINE_SOURCE" switch --detach "$WINE_REVISION"
fi

if git -C "$WINE_SOURCE" apply --reverse --check "$WINE_PATCH_DIR"/*.patch >/dev/null 2>&1; then
    source_matches_patch || die "Wine contains changes beyond the ENCORE patch"
    say "Wine source is already patched at $WINE_REVISION"
    exit 0
fi

if [ -n "$(git -C "$WINE_SOURCE" status --porcelain)" ]; then
    die "Wine has changes that do not exactly match the ENCORE patch"
fi

git -C "$WINE_SOURCE" apply --check "$WINE_PATCH_DIR"/*.patch
git -C "$WINE_SOURCE" apply "$WINE_PATCH_DIR"/*.patch
say "Applied ENCORE patch set to Wine $WINE_REVISION"
