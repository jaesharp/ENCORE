#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1 ||
    die "local development-header fallback requires an Ubuntu/Debian system with apt-get and dpkg-deb"

DBUS_ROOT="$PROJECT_ROOT/deps/dbus-sysroot"
PULSE_ROOT="$PROJECT_ROOT/deps/pulse-sysroot"
GSTREAMER_ROOT="$PROJECT_ROOT/deps/gstreamer-sysroot"
PACKAGE_DIR="$PROJECT_ROOT/deps/packages"

dbus_header="$DBUS_ROOT/usr/include/dbus-1.0/dbus/dbus.h"
pulse_header="$PULSE_ROOT/usr/include/pulse/pulseaudio.h"
gstreamer_header="$GSTREAMER_ROOT/usr/include/gstreamer-1.0/gst/gst.h"
glib_header="$GSTREAMER_ROOT/usr/include/glib-2.0/glib.h"

mkdir -p "$PACKAGE_DIR" "$DBUS_ROOT" "$PULSE_ROOT" "$GSTREAMER_ROOT"

download_and_extract()
{
    package=$1
    pattern=$2
    destination=$3

    (
        cd "$PACKAGE_DIR"
        apt-get download "$package"
    )

    archive=
    for candidate in "$PACKAGE_DIR"/$pattern; do
        [ -f "$candidate" ] || continue
        archive=$candidate
    done
    [ -n "$archive" ] || die "apt-get did not download $package"
    dpkg-deb -x "$archive" "$destination"
}

if [ ! -f "$dbus_header" ] || [ ! -f "$pulse_header" ] ||
   [ ! -f "$gstreamer_header" ] || [ ! -f "$glib_header" ]; then
    require_command apt-get
    require_command dpkg-deb
    [ -f "$dbus_header" ] || download_and_extract libdbus-1-dev 'libdbus-1-dev_*_*.deb' "$DBUS_ROOT"
    [ -f "$pulse_header" ] || download_and_extract libpulse-dev 'libpulse-dev_*_*.deb' "$PULSE_ROOT"

    if [ ! -f "$gstreamer_header" ]; then
        download_and_extract libgstreamer1.0-dev 'libgstreamer1.0-dev_*_*.deb' "$GSTREAMER_ROOT"
        download_and_extract libgstreamer-plugins-base1.0-dev \
            'libgstreamer-plugins-base1.0-dev_*_*.deb' "$GSTREAMER_ROOT"
        download_and_extract liborc-0.4-dev 'liborc-0.4-dev_*_*.deb' "$GSTREAMER_ROOT"
    fi

    if [ ! -f "$glib_header" ]; then
        download_and_extract libglib2.0-dev 'libglib2.0-dev_*_*.deb' "$GSTREAMER_ROOT"
        # Newer Debian/Ubuntu releases split the actual headers out of the
        # libglib2.0-dev compatibility package. Older releases stop here.
        if [ ! -f "$glib_header" ]; then
            download_and_extract gir1.2-glib-2.0-dev \
                'gir1.2-glib-2.0-dev_*_*.deb' "$GSTREAMER_ROOT"
            download_and_extract libgio-2.0-dev 'libgio-2.0-dev_*_*.deb' "$GSTREAMER_ROOT"
        fi
    fi
fi

[ -f "$dbus_header" ] || die "DBus headers were not staged correctly"
[ -f "$pulse_header" ] || die "PulseAudio headers were not staged correctly"
[ -f "$gstreamer_header" ] || die "GStreamer headers were not staged correctly"
[ -f "$glib_header" ] || die "GLib headers were not staged correctly"

require_command gcc
require_command readlink
multiarch=$(gcc -print-multiarch)
dbus_runtime=$(readlink -f "$(gcc -print-file-name=libdbus-1.so.3)")
pulse_runtime=$(readlink -f "$(gcc -print-file-name=libpulse.so.0)")
[ -f "$dbus_runtime" ] || die "host runtime library libdbus-1.so.3 is missing"
[ -f "$pulse_runtime" ] || die "host runtime library libpulse.so.0 is missing"

for library in \
    libgstreamer-1.0.so.0 \
    libgstvideo-1.0.so.0 \
    libgstaudio-1.0.so.0 \
    libgsttag-1.0.so.0 \
    libgstbase-1.0.so.0 \
    libgobject-2.0.so.0 \
    libglib-2.0.so.0
do
    runtime=$(readlink -f "$(gcc -print-file-name="$library")")
    [ -f "$runtime" ] || die "host runtime library $library is missing"
done

mkdir -p "$DBUS_ROOT/usr/lib/$multiarch" "$PULSE_ROOT/usr/lib/$multiarch"
ln -sfn "$dbus_runtime" "$DBUS_ROOT/usr/lib/$multiarch/libdbus-1.so.3"
ln -sfn "$pulse_runtime" "$PULSE_ROOT/usr/lib/$multiarch/libpulse.so.0"

say "Local DBus, PulseAudio, and GStreamer development files are ready"
