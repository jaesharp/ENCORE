#!/usr/bin/env bash

# Build compact runtime and corresponding-source release archives from a
# completed ENCORE Wine build.
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/common.sh
. "$SCRIPT_DIR/common.sh"

release_version=${1:-$ENCORE_RELEASE_VERSION}
output_dir=${2:-$PROJECT_ROOT/dist}
case $release_version in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "release version must look like v0.1.0: $release_version" ;;
esac
[ "$release_version" = "$ENCORE_RELEASE_VERSION" ] ||
    die "release version must match $ENCORE_RELEASE_VERSION"

for command in awk cp find git grep install make mktemp readelf sed sha256sum \
    sort strip tail tar xz; do
    require_command "$command"
done

[ -x "$WINE_BUILD/wine" ] || die "missing completed Wine build: $WINE_BUILD/wine"
[ "$($WINE_BUILD/wine --version)" = wine-11.13 ] || die "the build is not Wine 11.13"
[ -f "$WINE_BUILD/include/config.h" ] || die "missing Wine configuration"
grep -Fqx "prefix = $WINE_INSTALL_PREFIX" "$WINE_BUILD/config.status" ||
    die "Wine must be configured with --prefix=$WINE_INSTALL_PREFIX"

for definition in \
    SONAME_LIBDBUS_1 SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG SONAME_LIBGNUTLS \
    SONAME_LIBGL SONAME_LIBVULKAN SONAME_LIBX11 SONAME_LIBXCOMPOSITE \
    SONAME_LIBXCURSOR SONAME_LIBXEXT SONAME_LIBXFIXES SONAME_LIBXI \
    SONAME_LIBXINERAMA SONAME_LIBXRANDR SONAME_LIBXRENDER HAVE_UDEV \
    HAVE_LINUX_NTSYNC_H
do
    grep -q "^#define $definition " "$WINE_BUILD/include/config.h" ||
        die "Wine configuration is missing required support: $definition"
done

patch_sha256=$(sha256sum "$WINE_PATCH" | awk '{print $1}')
source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$WINE_SOURCE" show -s --format=%ct HEAD)}
case $source_date_epoch in
    ''|*[!0-9]*) die "invalid SOURCE_DATE_EPOCH: $source_date_epoch" ;;
esac

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/encore-release.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
stage_dir="$work_dir/stage"
runtime_dir="$work_dir/encore-wine"
source_name=encore-wine-11.13-$ENCORE_RUNTIME_REVISION-source
source_dir="$work_dir/$source_name"
bundle_name=${ENCORE_BUNDLE_ASSET%.tar.xz}
bundle_dir="$work_dir/$bundle_name"
mkdir -p "$stage_dir" "$runtime_dir" "$source_dir" "$bundle_dir" "$output_dir"

say "Staging the installed Wine runtime"
make -C "$WINE_BUILD" install-lib DESTDIR="$stage_dir"
[ -d "$stage_dir$WINE_INSTALL_PREFIX" ] || die "Wine install-lib produced no runtime"
cp -a "$stage_dir$WINE_INSTALL_PREFIX/." "$runtime_dir/"
rm -rf "$runtime_dir/share/man" "$runtime_dir/share/applications"

for required in \
    bin/wine bin/wineserver \
    lib/wine/x86_64-unix/ntdll.so \
    lib/wine/x86_64-unix/dxgi.dll.so \
    lib/wine/x86_64-unix/winex11.so \
    lib/wine/x86_64-unix/winegstreamer.so \
    lib/wine/x86_64-unix/winepulse.so \
    lib/wine/x86_64-unix/winevulkan.so \
    lib/wine/x86_64-unix/comdlg32.so \
    share/wine/wine.inf
do
    [ -e "$runtime_dir/$required" ] || die "runtime is missing $required"
done

say "Stripping runtime debug symbols"
while IFS= read -r -d '' file; do
    if readelf -h "$file" >/dev/null 2>&1; then
        strip --strip-unneeded "$file"
    fi
done < <(find "$runtime_dir/bin" "$runtime_dir/lib/wine/x86_64-unix" -type f -print0)

mkdir -p "$runtime_dir/licenses/wine"
for license in LICENSE COPYING.LIB NOTICES.md; do
    install -m 0644 "$WINE_SOURCE/$license" "$runtime_dir/licenses/wine/$license"
done

glibc_versions="$work_dir/glibc-versions"
: >"$glibc_versions"
while IFS= read -r -d '' file; do
    readelf -h "$file" >/dev/null 2>&1 || continue
    if readelf -dW "$file" 2>/dev/null | grep -Eq '\((RPATH|RUNPATH)\)'; then
        die "runtime ELF contains RPATH or RUNPATH: ${file#"$runtime_dir/"}"
    fi
    readelf --version-info "$file" 2>/dev/null |
        grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' >>"$glibc_versions" || true
done < <(find "$runtime_dir" -type f -print0)
glibc_max=$(sed 's/^GLIBC_//' "$glibc_versions" | sort -Vu | tail -n 1)
[ -n "$glibc_max" ] || die "could not determine the runtime glibc requirement"
if [ "$(printf '%s\n' "$glibc_max" 2.35 | sort -V | tail -n 1)" != 2.35 ]; then
    die "runtime requires glibc $glibc_max, newer than the 2.35 release baseline"
fi

if grep -aR -l -F "$PROJECT_ROOT" "$runtime_dir" >/dev/null 2>&1; then
    die "runtime contains an absolute build path: $PROJECT_ROOT"
fi
if find "$runtime_dir" -type f \( -name '*.a' -o -name '*.o' -o -name '*.la' \) -print -quit |
   grep -q .; then
    die "runtime contains development objects or archives"
fi

cat >"$runtime_dir/.encore-runtime" <<EOF
ENCORE_WINE_RUNTIME_V1
encore_version=$release_version
wine_version=11.13
wine_revision=$WINE_REVISION
patch_sha256=$patch_sha256
arch=x86_64
glibc_max=$glibc_max
EOF

cat >"$runtime_dir/BUILD-INFO.txt" <<EOF
ENCORE Wine runtime $release_version
Wine version: 11.13
Upstream revision: $WINE_REVISION
ENCORE patch SHA-256: $patch_sha256
Architecture: x86_64-linux-gnu
Maximum required glibc symbol: $glibc_max
NTSync: compiled in and used when /dev/ntsync is available
Source archive: $ENCORE_SOURCE_ASSET
EOF

say "Preparing complete corresponding Wine source"
tar -C "$WINE_SOURCE" --exclude=.git -cf - . | tar -C "$source_dir" -xf -
mkdir -p "$source_dir/ENCORE-BUILD/scripts" "$source_dir/ENCORE-BUILD/patches" \
    "$source_dir/ENCORE-BUILD/packaging" "$source_dir/ENCORE-BUILD/.github/workflows"
install -m 0644 "$PROJECT_ROOT/README.md" "$source_dir/ENCORE-BUILD/README.md"
install -m 0644 "$WINE_PATCH" "$source_dir/ENCORE-BUILD/patches/encore-wine.patch"
cp -a "$PROJECT_ROOT/packaging/uapi" "$source_dir/ENCORE-BUILD/packaging/"
for script in common.sh bootstrap-wine.sh build-wine.sh prepare-deps.sh \
    install-dependencies.sh package-wine-release.sh
do
    install -m 0755 "$SCRIPT_DIR/$script" "$source_dir/ENCORE-BUILD/scripts/$script"
done
install -m 0644 "$PROJECT_ROOT/.github/workflows/build-runtime.yml" \
    "$source_dir/ENCORE-BUILD/.github/workflows/build-runtime.yml"
cat >"$source_dir/ENCORE-CHANGES.txt" <<EOF
This is the complete corresponding source for ENCORE Wine $release_version.

Upstream Wine revision: $WINE_REVISION
ENCORE patch SHA-256: $patch_sha256
Build instructions and the exact patch are in ENCORE-BUILD/.
The ENCORE patch records the full modified-file delta against the revision above.
EOF

say "Preparing the turnkey ENCORE bundle"
git -C "$PROJECT_ROOT" archive --format=tar HEAD | tar -C "$bundle_dir" -xf -
mkdir -p "$bundle_dir/runtime"
cp -a "$runtime_dir" "$bundle_dir/runtime/wine"

archive_tree()
{
    local directory=$1 output=$2 parent name temporary
    parent=$(dirname -- "$directory")
    name=$(basename -- "$directory")
    temporary="$output.tmp.$$"
    tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 \
        --numeric-owner --pax-option=delete=atime,delete=ctime \
        -C "$parent" -cf - "$name" | xz -9e --threads=1 >"$temporary"
    mv "$temporary" "$output"
}

runtime_archive="$output_dir/$ENCORE_RUNTIME_ASSET"
source_archive="$output_dir/$ENCORE_SOURCE_ASSET"
bundle_archive="$output_dir/$ENCORE_BUNDLE_ASSET"
say "Compressing release archives"
archive_tree "$runtime_dir" "$runtime_archive"
archive_tree "$source_dir" "$source_archive"
archive_tree "$bundle_dir" "$bundle_archive"

relocation_dir="$work_dir/path with spaces/relocated"
mkdir -p "$relocation_dir"
tar -xJf "$runtime_archive" -C "$relocation_dir"
[ "$("$relocation_dir/encore-wine/bin/wine" --version)" = wine-11.13 ] ||
    die "relocated runtime smoke test failed"

bundle_test_dir="$work_dir/bundle test"
mkdir -p "$bundle_test_dir"
tar -xJf "$bundle_archive" -C "$bundle_test_dir"
bundle_root="$bundle_test_dir/$bundle_name"
[ "$("$bundle_root/runtime/wine/bin/wine" --version)" = wine-11.13 ] ||
    die "turnkey bundle runtime smoke test failed"
ENCORE_RUNTIME_ROOT="$bundle_root/runtime/wine" \
    "$bundle_root/scripts/download-wine-runtime.sh" >/dev/null
ENCORE_DRY_RUN=1 "$bundle_root/scripts/run-ableton.sh" |
    grep -Fqx "WINE=$bundle_root/runtime/wine/bin/wine" ||
    die "turnkey bundle launcher is not using its bundled runtime"

(
    cd "$output_dir"
    sha256sum "$ENCORE_BUNDLE_ASSET" "$ENCORE_RUNTIME_ASSET" \
        "$ENCORE_SOURCE_ASSET" >SHA256SUMS
)

say "Turnkey bundle:  $bundle_archive"
say "Runtime archive: $runtime_archive"
say "Source archive:  $source_archive"
say "Checksums:       $output_dir/SHA256SUMS"
