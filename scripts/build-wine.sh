#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

mode=${1:-build}
case $mode in
    build|--configure-only) ;;
    *) die "usage: $0 [--configure-only]" ;;
esac

require_command gcc
require_command grep
require_command make
require_command nice
require_command readlink
require_command sha256sum

"$SCRIPT_DIR/bootstrap-wine.sh"

system_modules='dbus-1 libpulse gstreamer-1.0 gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-tag-1.0 glib-2.0'
use_system_dependencies=0
if command -v pkg-config >/dev/null 2>&1 &&
   pkg-config --exists $system_modules
then
    use_system_dependencies=1
    say "Using system DBus, PulseAudio, GLib, and GStreamer development files"
else
    # Ubuntu/Debian fallback retained for environments where the development
    # packages cannot be installed system-wide. Fedora/Arch users normally
    # reach the system pkg-config branch through install-dependencies.sh.
    "$SCRIPT_DIR/prepare-deps.sh"
fi

mkdir -p "$WINE_BUILD" "$PROJECT_ROOT/.tmp"
export TMPDIR="$PROJECT_ROOT/.tmp"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$WINE_SOURCE_DATE_EPOCH}
encore_cppflags="-I$PROJECT_ROOT/packaging/uapi${CPPFLAGS:+ $CPPFLAGS}"

say "Configuring Wine $WINE_REVISION in $WINE_BUILD"
if [ "$use_system_dependencies" -eq 1 ]; then
    (
        cd "$WINE_BUILD"
        CPPFLAGS="$encore_cppflags" "$WINE_SOURCE/configure" \
            --prefix="$WINE_INSTALL_PREFIX" \
            --enable-win64 \
            --with-dbus \
            --with-gstreamer \
            --with-pulse
    )
else
    multiarch=$(gcc -print-multiarch)
    [ -n "$multiarch" ] || die "gcc did not report a multiarch directory"

    dbus_include="$PROJECT_ROOT/deps/dbus-sysroot/usr/include/dbus-1.0"
    dbus_arch_include="$PROJECT_ROOT/deps/dbus-sysroot/usr/lib/$multiarch/dbus-1.0/include"
    pulse_include="$PROJECT_ROOT/deps/pulse-sysroot/usr/include"
    gstreamer_root="$PROJECT_ROOT/deps/gstreamer-sysroot"
    gstreamer_include="$gstreamer_root/usr/include/gstreamer-1.0"
    glib_include="$gstreamer_root/usr/include/glib-2.0"
    glib_arch_include="$gstreamer_root/usr/lib/$multiarch/glib-2.0/include"
    orc_include="$gstreamer_root/usr/include/orc-0.4"
    dbus_libdir="$PROJECT_ROOT/deps/dbus-sysroot/usr/lib/$multiarch"
    pulse_libdir="$PROJECT_ROOT/deps/pulse-sysroot/usr/lib/$multiarch"
    dbus_library=$(readlink -f "$(gcc -print-file-name=libdbus-1.so.3)")
    pulse_library=$(readlink -f "$(gcc -print-file-name=libpulse.so.0)")

    [ -d "$dbus_include" ] || die "local DBus headers were not staged; check apt download access and rerun the build"
    [ -d "$dbus_arch_include" ] || die "missing DBus multiarch headers for $multiarch"
    [ -d "$pulse_include" ] || die "missing PulseAudio headers"
    [ -f "$gstreamer_include/gst/gst.h" ] || die "missing GStreamer headers"
    [ -f "$glib_include/glib.h" ] || die "missing GLib headers"
    [ -f "$glib_arch_include/glibconfig.h" ] || die "missing GLib multiarch headers for $multiarch"
    [ -f "$dbus_libdir/libdbus-1.so" ] || die "missing staged DBus linker library"
    [ -f "$pulse_libdir/libpulse.so" ] || die "missing staged PulseAudio linker library"

    runtime_library()
    {
        library=$(readlink -f "$(gcc -print-file-name="$1")")
        [ -f "$library" ] || die "missing host runtime library $1"
        printf '%s\n' "$library"
    }

    gstreamer_cflags="-I$gstreamer_include -I$glib_include -I$glib_arch_include"
    [ ! -d "$orc_include" ] || gstreamer_cflags="$gstreamer_cflags -I$orc_include"
    gstreamer_libs="$(runtime_library libgstvideo-1.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libgstaudio-1.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libgsttag-1.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libgstbase-1.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libgstreamer-1.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libgobject-2.0.so.0)"
    gstreamer_libs="$gstreamer_libs $(runtime_library libglib-2.0.so.0)"

    (
        cd "$WINE_BUILD"
        LIBRARY_PATH="$dbus_libdir:$pulse_libdir${LIBRARY_PATH:+:$LIBRARY_PATH}" \
        DBUS_CFLAGS="-I$dbus_include -I$dbus_arch_include" \
        DBUS_LIBS="$dbus_library" \
        PULSE_CFLAGS="-I$pulse_include -D_REENTRANT" \
        PULSE_LIBS="$pulse_library -pthread" \
        GSTREAMER_CFLAGS="$gstreamer_cflags" \
        GSTREAMER_LIBS="$gstreamer_libs" \
        CPPFLAGS="$encore_cppflags" \
        "$WINE_SOURCE/configure" \
            --prefix="$WINE_INSTALL_PREFIX" \
            --enable-win64 \
            --with-dbus \
            --with-gstreamer \
            --with-pulse
    )
fi

if grep '^DISABLED_SUBDIRS = ' "$WINE_BUILD/Makefile" | tr ' ' '\n' |
   grep -qx 'dlls/winegstreamer'; then
    die "Wine configuration disabled winegstreamer"
fi
grep -q '^ac_cv_func_gst_pad_new=yes$' "$WINE_BUILD/config.log" ||
    die "Wine configuration did not link against GStreamer"
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

[ "$mode" = --configure-only ] && exit 0

jobs=${JOBS:-2}
case $jobs in
    ''|*[!0-9]*) die "JOBS must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || die "JOBS must be greater than zero"

say "Building Wine with $jobs parallel jobs"
if command -v ionice >/dev/null 2>&1; then
    ionice -c 2 -n 7 nice -n 5 make -C "$WINE_BUILD" -j"$jobs"
else
    nice -n 5 make -C "$WINE_BUILD" -j"$jobs"
fi

[ -x "$WINE_BINARY" ] || die "build completed without $WINE_BINARY"
[ -x "$WINE_BUILD/server/wineserver" ] || die "build completed without wineserver"
version=$("$WINE_BINARY" --version)
[ "$version" = wine-11.13 ] || die "unexpected Wine version: $version"
for artifact in \
    "$WINE_BUILD/dlls/dxgi/dxgi.dll.so" \
    "$WINE_BUILD/dlls/winex11.drv/winex11.so" \
    "$WINE_BUILD/dlls/winegstreamer/winegstreamer.so" \
    "$WINE_BUILD/dlls/winepulse.drv/winepulse.so" \
    "$WINE_BUILD/dlls/winevulkan/winevulkan.so" \
    "$WINE_BUILD/dlls/comdlg32/comdlg32.so"
do
    [ -f "$artifact" ] || die "build completed without $artifact"
done
grep -q '^#define SONAME_LIBDBUS_1 "libdbus-1.so.3"' "$WINE_BUILD/include/config.h" ||
    die "build was configured without DBus support"

patch_sha256=$(sha256sum "$WINE_PATCH" | awk '{print $1}')
stamp="$WINE_BUILD/.encore-build"
temporary_stamp="$stamp.tmp.$$"
trap 'rm -f "$temporary_stamp"' EXIT HUP INT TERM
{
    printf 'wine_revision=%s\n' "$WINE_REVISION"
    printf 'patch_sha256=%s\n' "$patch_sha256"
} >"$temporary_stamp"
mv "$temporary_stamp" "$stamp"
trap - EXIT HUP INT TERM

say "Wine build complete: $version"
