#!/usr/bin/env bash

# Distro-aware runtime and build dependency handling for the ENCORE wizard.
set -Eeuo pipefail

action=check
profile=build

usage()
{
    printf 'usage: %s [--check|--print|--install] [runtime|build]\n' "$0" >&2
    exit 2
}

while (($#)); do
    case $1 in
        --check) action=check ;;
        --print) action=print ;;
        --install) action=install ;;
        runtime|build) profile=$1 ;;
        *) usage ;;
    esac
    shift
done

distro_id=unknown
distro_like=
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    distro_id=${ID:-unknown}
    distro_like=${ID_LIKE:-}
fi

desktop=${XDG_CURRENT_DESKTOP:-}
manager=${ENCORE_PACKAGE_FAMILY:-}
case $manager in
    ''|apt|dnf|pacman) ;;
    *)
        printf 'ENCORE: ENCORE_PACKAGE_FAMILY must be apt, dnf, or pacman\n' >&2
        exit 2
        ;;
esac
if [[ -z $manager ]]; then
    case " $distro_id $distro_like " in
        *' arch '*|*' cachyos '*) manager=pacman ;;
        *' fedora '*|*' rhel '*) manager=dnf ;;
        *' ubuntu '*|*' debian '*) manager=apt ;;
    esac
fi
if [[ -z $manager ]]; then
    command -v apt-get >/dev/null 2>&1 && manager=apt
    [[ -n $manager ]] || { command -v dnf5 >/dev/null 2>&1 && manager=dnf; }
    [[ -n $manager ]] || { command -v dnf >/dev/null 2>&1 && manager=dnf; }
    [[ -n $manager ]] || { command -v pacman >/dev/null 2>&1 && manager=pacman; }
fi

case $manager in
    apt)
        gnutls_runtime=libgnutls30
        alsa_runtime=libasound2
        if command -v apt-cache >/dev/null 2>&1; then
            apt-cache show libgnutls30t64 >/dev/null 2>&1 && gnutls_runtime=libgnutls30t64
            apt-cache show libasound2t64 >/dev/null 2>&1 && alsa_runtime=libasound2t64
        fi
        runtime_packages=(
            ca-certificates curl xz-utils diffutils fontconfig fonts-liberation python3
            python3-fonttools desktop-file-utils libdbus-1-3 libfreetype6
            libfontconfig1 libgl1 libvulkan1 libx11-6 libxcomposite1
            libxcursor1 libxext6 libxfixes3 libxi6 libxinerama1 libxrandr2
            libxrender1 libpulse0 libudev1 "$alsa_runtime" "$gnutls_runtime"
            xwayland xdg-desktop-portal gstreamer1.0-tools
            gstreamer1.0-plugins-base gstreamer1.0-plugins-good
            gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav
            pipewire-jack
        )
        if [[ $desktop == *KDE* ]]; then
            runtime_packages+=(xdg-desktop-portal-kde)
        elif [[ $desktop == *GNOME* ]]; then
            runtime_packages+=(xdg-desktop-portal-gnome)
        else
            runtime_packages+=(xdg-desktop-portal-gtk)
        fi
        build_packages=(
            git build-essential flex bison pkg-config xorg-dev
            gcc-mingw-w64-i686 g++-mingw-w64-i686
            gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64
            libfreetype-dev libfontconfig1-dev libgl-dev libvulkan-dev
            libxkbcommon-dev libwayland-dev libdbus-1-dev libpulse-dev
            libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
            libglib2.0-dev liborc-0.4-dev libudev-dev libasound2-dev
            libgnutls28-dev libunwind-dev libjpeg-dev libpng-dev
            libtiff-dev libxml2-dev libjack-jackd2-dev
        )
        ;;
    dnf)
        runtime_packages=(
            ca-certificates curl xz diffutils fontconfig liberation-sans-fonts python3
            python3-fonttools desktop-file-utils dbus-libs freetype libglvnd-glx
            vulkan-loader libX11 libXcomposite libXcursor libXext libXfixes
            libXi libXinerama libXrandr libXrender pulseaudio-libs systemd-libs
            alsa-lib gnutls xorg-x11-server-Xwayland xdg-desktop-portal
            gstreamer1 gstreamer1-plugin-libav
            gstreamer1-plugins-base gstreamer1-plugins-good
            gstreamer1-plugins-bad-free gstreamer1-plugins-ugly-free
            pipewire-jack-audio-connection-kit
        )
        if [[ $desktop == *KDE* ]]; then
            runtime_packages+=(xdg-desktop-portal-kde)
        elif [[ $desktop == *GNOME* ]]; then
            runtime_packages+=(xdg-desktop-portal-gnome)
        else
            runtime_packages+=(xdg-desktop-portal-gtk)
        fi
        build_packages=(
            git gcc gcc-c++ make flex bison pkgconf-pkg-config
            mingw32-gcc mingw32-gcc-c++ mingw64-gcc mingw64-gcc-c++
            libX11-devel libXext-devel libXrender-devel libXrandr-devel
            libXcursor-devel libXi-devel libXcomposite-devel libXinerama-devel
            libXfixes-devel libxkbfile-devel libXxf86vm-devel
            libxkbcommon-devel wayland-devel libglvnd-devel freetype-devel
            fontconfig-devel dbus-devel pulseaudio-libs-devel gstreamer1-devel
            gstreamer1-plugins-base-devel glib2-devel orc-devel
            systemd-devel alsa-lib-devel vulkan-loader-devel gnutls-devel
            libunwind-devel libjpeg-turbo-devel libpng-devel libtiff-devel
            libxml2-devel pipewire-jack-audio-connection-kit-devel
        )
        ;;
    pacman)
        runtime_packages=(
            ca-certificates curl xz diffutils fontconfig ttf-liberation python
            python-fonttools desktop-file-utils dbus freetype2 libglvnd
            vulkan-icd-loader libx11 libxcomposite libxcursor libxext libxfixes
            libxi libxinerama libxrandr libxrender libpulse systemd-libs
            alsa-lib gnutls xorg-xwayland xdg-desktop-portal gstreamer gst-plugins-base
            gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
            pipewire-jack
        )
        if [[ $desktop == *KDE* ]]; then
            runtime_packages+=(xdg-desktop-portal-kde)
        elif [[ $desktop == *GNOME* ]]; then
            runtime_packages+=(xdg-desktop-portal-gnome)
        else
            runtime_packages+=(xdg-desktop-portal-gtk)
        fi
        build_packages=(
            base-devel git flex bison pkgconf mingw-w64-gcc
            libx11 libxext libxrender
            libxrandr libxcursor libxi libxcomposite libxinerama libxfixes
            libxkbfile libxxf86vm libxkbcommon wayland libglvnd freetype2
            dbus libpulse glib2 orc systemd-libs alsa-lib vulkan-headers
            vulkan-icd-loader gnutls libunwind libjpeg-turbo libpng libtiff
            libxml2
        )
        ;;
    *)
        runtime_packages=()
        build_packages=()
        ;;
esac

packages=("${runtime_packages[@]}")
[[ $profile == runtime ]] || packages+=("${build_packages[@]}")

privilege=()
if ((EUID != 0)); then
    privilege=(sudo)
fi

print_command()
{
    local item
    case $manager in
        apt)
            printf 'sudo apt-get update\n'
            printf 'sudo apt-get install -y'
            for item in "${packages[@]}"; do printf ' %q' "$item"; done
            printf '\n'
            ;;
        dnf)
            printf 'sudo %s install -y' "$(command -v dnf5 >/dev/null 2>&1 && printf dnf5 || printf dnf)"
            for item in "${packages[@]}"; do printf ' %q' "$item"; done
            printf '\n'
            ;;
        pacman)
            printf 'sudo pacman -Syu --needed --noconfirm'
            for item in "${packages[@]}"; do printf ' %q' "$item"; done
            printf '\n'
            ;;
        *)
            printf 'Install Git, GCC/G++, Make, Flex, Bison, pkg-config, X11 development files,\n'
            printf 'DBus/PulseAudio/GStreamer development files, Fontconfig, Liberation Sans,\n'
            printf 'Python fontTools, desktop-file-utils, Xwayland, and an xdg-desktop-portal backend.\n'
            return 2
            ;;
    esac
}

apt_local_build_fallback_available()
{
    [[ $manager == apt ]] || return 1
    local command library path
    for command in apt-get dpkg-deb gcc readlink; do
        command -v "$command" >/dev/null 2>&1 || return 1
    done
    for library in \
        libdbus-1.so.3 \
        libpulse.so.0 \
        libgstreamer-1.0.so.0 \
        libgstvideo-1.0.so.0 \
        libgstaudio-1.0.so.0 \
        libgsttag-1.0.so.0 \
        libgstbase-1.0.so.0 \
        libgobject-2.0.so.0 \
        libglib-2.0.so.0
    do
        path=$(gcc -print-file-name="$library")
        [[ $path != "$library" && -f $path ]] || return 1
    done
}

check_requirements()
{
    local missing=() command module portal_file source_font gst_registry
    local file_chooser_portal=
    local runtime_commands=(
        python3 fc-match desktop-file-validate Xwayland gst-inspect-1.0
        awk basename cmp cp curl df dirname du find flock getconf grep head mkdir
        mktemp mv readlink rm rmdir sed sha256sum sleep sort tail tar tee tr uname xz
    )
    local build_commands=(
        git gcc g++ make flex bison pkg-config awk grep sed nice readlink sha256sum
        i686-w64-mingw32-gcc i686-w64-mingw32-g++
        x86_64-w64-mingw32-gcc x86_64-w64-mingw32-g++
    )

    for command in "${runtime_commands[@]}"; do
        command -v "$command" >/dev/null 2>&1 || missing+=("command:$command")
    done
    PYTHONDONTWRITEBYTECODE=1 python3 -c 'import fontTools.ttLib' >/dev/null 2>&1 ||
        missing+=(python:fontTools)
    source_font=
    command -v fc-match >/dev/null 2>&1 &&
        source_font=$(fc-match --format='%{file}\n' 'Liberation Sans:style=Regular' 2>/dev/null | sed -n '1p')
    [[ -n $source_font && -f $source_font ]] || missing+=(font:Liberation-Sans)
    [[ -f /usr/share/dbus-1/services/org.freedesktop.portal.Desktop.service ]] ||
        missing+=(service:xdg-desktop-portal)
    for portal_file in /usr/share/xdg-desktop-portal/portals/*.portal; do
        [[ -f $portal_file ]] || continue
        if grep -Eq '^Interfaces=.*org\.freedesktop\.impl\.portal\.FileChooser(;|$)' "$portal_file"; then
            file_chooser_portal=$portal_file
            break
        fi
    done
    [[ -n $file_chooser_portal ]] || missing+=(portal:FileChooser-backend)
    if command -v gst-inspect-1.0 >/dev/null 2>&1 &&
       command -v mktemp >/dev/null 2>&1 && command -v rm >/dev/null 2>&1; then
        gst_registry=$(mktemp /tmp/encore-gstreamer-registry.XXXXXX)
        for module in decodebin wavparse flacparse opusdec mpg123audiodec avdec_aac; do
            GST_REGISTRY=$gst_registry gst-inspect-1.0 "$module" >/dev/null 2>&1 ||
                missing+=("gstreamer:$module")
        done
        rm -f "$gst_registry"
    fi

    if [[ $profile == build ]]; then
        for command in "${build_commands[@]}"; do
            command -v "$command" >/dev/null 2>&1 || missing+=("command:$command")
        done
        if command -v pkg-config >/dev/null 2>&1; then
            for module in \
                x11 xext xrender xrandr xcursor xi xcomposite xinerama xfixes \
                gl freetype2 fontconfig vulkan gnutls libudev alsa
            do
                pkg-config --exists "$module" || missing+=("pkg-config:$module")
            done
            if ! apt_local_build_fallback_available; then
                for module in dbus-1 libpulse gstreamer-1.0 gstreamer-video-1.0 \
                    gstreamer-audio-1.0 gstreamer-tag-1.0 glib-2.0; do
                    pkg-config --exists "$module" || missing+=("pkg-config:$module")
                done
            fi
        fi
    fi

    if ((${#missing[@]})); then
        printf 'Missing requirements:\n' >&2
        printf '  %s\n' "${missing[@]}" >&2
        return 1
    fi
}

install_packages()
{
    [[ -n $manager ]] || {
        print_command >&2 || true
        exit 1
    }
    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || {
            printf 'ENCORE: sudo is required to install system packages\n' >&2
            exit 1
        }
    fi
    case $manager in
        apt)
            "${privilege[@]}" apt-get update
            "${privilege[@]}" apt-get install -y "${packages[@]}"
            ;;
        dnf)
            local dnf_command=dnf
            command -v dnf5 >/dev/null 2>&1 && dnf_command=dnf5
            "${privilege[@]}" "$dnf_command" install -y "${packages[@]}"
            ;;
        pacman)
            # Arch and CachyOS do not support partial upgrades.
            "${privilege[@]}" pacman -Syu --needed --noconfirm "${packages[@]}"
            ;;
    esac
}

case $action in
    check) check_requirements ;;
    print) print_command ;;
    install)
        install_packages
        check_requirements
        ;;
esac
