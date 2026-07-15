#!/bin/sh

# Build WineASIO (low-latency audio: WineASIO -> JACK/PipeWire) and the jacklinkd
# device-recovery helper against the ENCORE Wine that is already built, and place
# the results in an ENCORE-owned directory (WINEASIO_ROOT) without touching the
# Wine tree. This is an opt-in post-build step; install.sh runs it by default for
# source builds and it is safe to run on its own.
#
# WineASIO is GPL-2.0+; its source is pinned (WINEASIO_REVISION) and the ENCORE
# WineASIO patch series lives under patches/wineasio/.

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_command cc
require_command git
require_command make

# 1. Wine must be built already (WineASIO links against this exact Wine's ABI).
wine_bin="$WINE_BUILD/wine"
[ -x "$wine_bin" ] || wine_bin="$ENCORE_RUNTIME_ROOT/bin/wine"
[ -x "$wine_bin" ] || die "ENCORE Wine is not built; run the Wine build first (install.sh / build-wine.sh)"
[ -d "$WINE_BUILD" ] || die "Wine build tree not found: $WINE_BUILD"

# 2. JACK development headers are needed to build the jacklinkd helper.
#    (WineASIO itself dlopens libjack at runtime; it does not link it at build.)
printf '#include <jack/jack.h>\nint main(void){return 0;}\n' >"$PROJECT_ROOT/.tmp-jack-probe.c" 2>/dev/null || true
if ! cc -c -o /dev/null "$PROJECT_ROOT/.tmp-jack-probe.c" 2>/dev/null; then
    rm -f "$PROJECT_ROOT/.tmp-jack-probe.c"
    die "JACK development headers (jack/jack.h) not found; install libjack-jackd2-dev / pipewire-jack-audio-connection-kit-dev (see install-dependencies.sh)"
fi
rm -f "$PROJECT_ROOT/.tmp-jack-probe.c"

# 3. Fetch WineASIO at the pinned revision (clone once, reuse thereafter).
if [ ! -d "$WINEASIO_SOURCE/.git" ]; then
    say "Cloning WineASIO $WINEASIO_VERSION"
    rm -rf "$WINEASIO_SOURCE"
    git clone "$WINEASIO_REMOTE" "$WINEASIO_SOURCE"
fi
git -C "$WINEASIO_SOURCE" fetch --quiet origin || true
git -C "$WINEASIO_SOURCE" checkout --quiet --force "$WINEASIO_REVISION"
git -C "$WINEASIO_SOURCE" reset --quiet --hard "$WINEASIO_REVISION"
git -C "$WINEASIO_SOURCE" clean -qfdx
[ "$(git -C "$WINEASIO_SOURCE" rev-parse HEAD)" = "$WINEASIO_REVISION" ] ||
    die "WineASIO source is not at the pinned revision $WINEASIO_REVISION"

# 4. Apply the ENCORE WineASIO patch series (patches/wineasio/*.patch).
patch_count=0
for wineasio_patch in "$WINEASIO_PATCH_DIR"/*.patch; do
    [ -f "$wineasio_patch" ] || continue
    say "Applying $(basename "$wineasio_patch")"
    git -C "$WINEASIO_SOURCE" apply "$wineasio_patch"
    patch_count=$((patch_count + 1))
done
[ "$patch_count" -gt 0 ] || die "no WineASIO patches found in $WINEASIO_PATCH_DIR"

# 5. Stage a private install of the built Wine so WineASIO links against a normal
#    installed layout (bin/winegcc, include/wine, lib/wine/x86_64-*). Kept under
#    build/ and reused; it does not become part of the runtime.
stage="$PROJECT_ROOT/build/wine-asio-sdk"
if [ -z "$(find "$stage" -name winegcc -type f 2>/dev/null | head -n1)" ]; then
    say "Staging the built Wine for the WineASIO ABI (one-time)"
    rm -rf "$stage"
    make -C "$WINE_BUILD" install DESTDIR="$stage" >/dev/null
fi
# Discover the install prefix from winegcc's location rather than assuming it
# (the tools land under whatever --prefix the Wine build was configured with).
winegcc_bin=$(find "$stage" -name winegcc -type f 2>/dev/null | head -n1)
[ -n "$winegcc_bin" ] || die "staged Wine install produced no winegcc under $stage"
prefix_root=$(CDPATH= cd -- "$(dirname -- "$winegcc_bin")/.." && pwd)
[ -e "$prefix_root/lib/wine/x86_64-windows" ] ||
    die "staged Wine has no lib/wine/x86_64-windows under $prefix_root"

# 6. Build WineASIO 64-bit against that Wine (Live 12 is 64-bit only).
say "Building WineASIO $WINEASIO_VERSION against ENCORE Wine"
rm -rf "$WINEASIO_SOURCE/build64"
(
    cd "$WINEASIO_SOURCE"
    PATH="$prefix_root/bin:$PATH" \
    make 64 \
        WINEBUILD_INCLUDEDIR="$prefix_root/include/wine" \
        WINEBUILD_LIBDIR="$prefix_root/lib/wine/x86_64-unix" \
        CFLAGS="-I$prefix_root/include/wine/windows"
)
[ -f "$WINEASIO_SOURCE/build64/wineasio64.dll" ] ||
    die "WineASIO build produced no wineasio64.dll"
[ -f "$WINEASIO_SOURCE/build64/wineasio64.dll.so" ] ||
    die "WineASIO build produced no wineasio64.dll.so"

# 7. Install the driver into WINEASIO_ROOT. Both the versioned and unversioned
#    names are needed: Wine resolves the builtin's canonical name (wineasio.dll,
#    from the .spec) and looks up the matching Unix half, so LoadLibrary fails
#    unless both PE names and both .so names are present.
mkdir -p "$WINEASIO_ROOT"
install -m644 "$WINEASIO_SOURCE/build64/wineasio64.dll"    "$WINEASIO_ROOT/wineasio64.dll"
install -m644 "$WINEASIO_SOURCE/build64/wineasio64.dll.so" "$WINEASIO_ROOT/wineasio64.dll.so"
install -m644 "$WINEASIO_SOURCE/build64/wineasio64.dll"    "$WINEASIO_ROOT/wineasio.dll"
install -m644 "$WINEASIO_SOURCE/build64/wineasio64.dll.so" "$WINEASIO_ROOT/wineasio.dll.so"

# 8. Build the jacklinkd JACK-link recovery helper (restores links after an audio
#    device replug; see tools/jacklinkd.c).
say "Building jacklinkd"
cc -O2 -Wall -o "$WINEASIO_ROOT/jacklinkd" "$PROJECT_ROOT/tools/jacklinkd.c" -ljack -lpthread

say "WineASIO installed to $WINEASIO_ROOT (register it into the prefix with configure-prefix.sh)"
