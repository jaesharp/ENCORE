#!/usr/bin/env bash

# Guided ENCORE setup for Ableton Live 12 Suite.
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$ROOT/scripts"
ORIGINAL_ARGS=("$@")
WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
DEFAULT_PREFIX="$ROOT/ableton-prefix"
DEFAULT_WINE="$ROOT/build/wine64/wine"
ABLETON_RELATIVE='drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe'
DEPENDENCY_HELPER="$SCRIPTS/install-dependencies.sh"

wine_environment_explicit=0
[[ ${ENCORE_WINE+x} == x ]] && wine_environment_explicit=1
. "$SCRIPTS/load-runtime-config.sh"

interactive=0
[[ -t 0 && -t 1 ]] && interactive=1
assume_yes=0
dry_run=0
no_color=0
dependency_policy=ask
build_mode=auto
build_only=0
configure_only=0
install_desktop=1
launch_policy=ask
installer=${ABLETON_INSTALLER:-}
prefix=${ENCORE_PREFIX:-$DEFAULT_PREFIX}
wine=${ENCORE_WINE:-$DEFAULT_WINE}
ableton=${ENCORE_ABLETON:-}
dpi=${DPI:-}
scale=
jobs=${JOBS:-}
wine_explicit=0
[[ $wine_environment_explicit -eq 0 ]] || wine_explicit=1
unset wine_environment_explicit
installer_cli_set=0
ableton_cli_set=0
no_build_requested=0
adopt_prefix=0
reinstall_ableton=0
log_file=
lock_fd=
cancelled=0

usage()
{
    cat <<'EOF'
Usage: ./install.sh [options] [ABLETON_INSTALLER.exe]

Run the guided ENCORE setup. With no options in a terminal, the installer
detects your system and walks you through every choice.

Setup options:
  --installer FILE       Licensed Ableton Live 12 Suite installer
  --prefix DIR           Wine prefix (default: ./ableton-prefix)
  --ableton FILE         Existing Ableton executable inside the prefix
  --adopt-prefix         Allow use of a non-empty, unrecognized prefix
  --reinstall-ableton    Run --installer even when Ableton is already present
  --dpi N                Wine DPI from 72 to 384
  --scale PERCENT        Display scale: 100, 125, 150, 175, 200, or 250
  --jobs N               Parallel Wine build jobs
  --wine FILE            Reuse an existing ENCORE Wine build; implies --no-build
  --no-build             Skip Wine compilation and reuse --wine/default Wine
  --build-only           Build Wine, then stop before Ableton setup
  --configure-only       Configure Wine, then stop (advanced diagnostics)

Dependency and automation options:
  --install-deps         Install missing distro packages when needed
  --no-install-deps      Never install system packages
  --non-interactive      Never prompt; fail when a required choice is missing
  --yes                  Accept recommended/default confirmations
  --dry-run              Detect and print the plan without writing or downloading
  --no-desktop           Do not install the application-menu entry
  --launch               Launch Ableton after successful setup
  --no-launch            Do not launch after setup
  --no-color             Disable colored terminal output
  -h, --help             Show this help

Supported package families: Ubuntu/Debian (apt), Fedora (dnf), and
Arch/CachyOS (pacman). Ableton itself is not downloaded or bundled.
EOF
}

need_value()
{
    [[ $# -ge 2 && -n $2 ]] || {
        printf 'ENCORE: %s requires a value\n' "$1" >&2
        exit 2
    }
}

while (($#)); do
    case $1 in
        --installer)
            need_value "$1" "${2:-}"
            [[ $installer_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton installer may be supplied\n' >&2
                exit 2
            }
            installer=$2
            installer_cli_set=1
            shift
            ;;
        --installer=*)
            [[ $installer_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton installer may be supplied\n' >&2
                exit 2
            }
            installer=${1#*=}
            installer_cli_set=1
            ;;
        --prefix)
            need_value "$1" "${2:-}"
            prefix=$2
            [[ $ableton_cli_set -eq 1 ]] || ableton=
            shift
            ;;
        --prefix=*)
            prefix=${1#*=}
            [[ $ableton_cli_set -eq 1 ]] || ableton=
            ;;
        --ableton)
            need_value "$1" "${2:-}"
            ableton=$2
            ableton_cli_set=1
            shift
            ;;
        --ableton=*)
            ableton=${1#*=}
            ableton_cli_set=1
            ;;
        --adopt-prefix) adopt_prefix=1 ;;
        --reinstall-ableton) reinstall_ableton=1 ;;
        --wine)
            need_value "$1" "${2:-}"
            wine=$2
            wine_explicit=1
            no_build_requested=1
            build_mode=skip
            shift
            ;;
        --wine=*)
            wine=${1#*=}
            wine_explicit=1
            no_build_requested=1
            build_mode=skip
            ;;
        --no-build)
            no_build_requested=1
            build_mode=skip
            ;;
        --build-only)
            build_only=1
            build_mode=build
            ;;
        --configure-only)
            configure_only=1
            build_only=1
            build_mode=build
            ;;
        --dpi)
            need_value "$1" "${2:-}"
            dpi=$2
            shift
            ;;
        --dpi=*) dpi=${1#*=} ;;
        --scale)
            need_value "$1" "${2:-}"
            scale=$2
            shift
            ;;
        --scale=*) scale=${1#*=} ;;
        --jobs)
            need_value "$1" "${2:-}"
            jobs=$2
            shift
            ;;
        --jobs=*) jobs=${1#*=} ;;
        --install-deps) dependency_policy=install ;;
        --no-install-deps) dependency_policy=skip ;;
        --non-interactive) interactive=0 ;;
        --yes) assume_yes=1 ;;
        --dry-run) dry_run=1 ;;
        --no-desktop) install_desktop=0 ;;
        --launch) launch_policy=yes ;;
        --no-launch) launch_policy=no ;;
        --no-color) no_color=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf 'ENCORE: unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            [[ $installer_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton installer may be supplied\n' >&2
                exit 2
            }
            installer=$1
            installer_cli_set=1
            ;;
    esac
    shift
done

while (($#)); do
    [[ $installer_cli_set -eq 0 ]] || {
        printf 'ENCORE: only one Ableton installer may be supplied\n' >&2
        exit 2
    }
    installer=$1
    installer_cli_set=1
    shift
done

if [[ -n $scale && -n $dpi ]]; then
    printf 'ENCORE: use either --scale or --dpi, not both\n' >&2
    exit 2
fi
if [[ $wine_explicit -eq 1 && $build_mode == auto ]]; then
    build_mode=skip
fi
if [[ $no_build_requested -eq 1 && $build_only -eq 1 ]]; then
    printf 'ENCORE: --no-build/--wine cannot be combined with --build-only\n' >&2
    exit 2
fi

if [[ $no_color -eq 0 && -z ${NO_COLOR:-} && -t 1 && ${TERM:-dumb} != dumb ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    BLUE=$'\033[34m'
    CYAN=$'\033[36m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    RESET=$'\033[0m'
else
    BOLD= DIM= BLUE= CYAN= GREEN= YELLOW= RED= RESET=
fi

say() { printf '%s\n' "$*"; }
info() { printf '%s%sinfo%s  %s\n' "$BLUE" "$BOLD" "$RESET" "$*"; }
ok() { printf '%s%sok%s    %s\n' "$GREEN" "$BOLD" "$RESET" "$*"; }
warn() { printf '%s%swarn%s  %s\n' "$YELLOW" "$BOLD" "$RESET" "$*" >&2; }
error() { printf '%s%serror%s %s\n' "$RED" "$BOLD" "$RESET" "$*" >&2; }
heading() { printf '\n%s%s%s%s\n' "$BOLD" "$CYAN" "$*" "$RESET"; }

die()
{
    local argument
    error "$*"
    [[ -z $log_file ]] || printf '%sInstall log:%s %s\n' "$DIM" "$RESET" "$log_file" >&2
    printf '%sSafe to retry:%s' "$DIM" "$RESET" >&2
    printf ' %q' "$ROOT/install.sh" >&2
    for argument in "${ORIGINAL_ARGS[@]}"; do
        printf ' %q' "$argument" >&2
    done
    printf '\n' >&2
    exit 1
}

reject_path_controls()
{
    local label=$1 value=$2
    if [[ $value == *$'\n'* || $value == *$'\r'* || $value == *$'\t'* ]]; then
        die "$label may not contain tabs or line breaks"
    fi
}

cleanup()
{
    local status=$?
    if [[ $lock_fd =~ ^[0-9]+$ ]]; then
        flock -u "$lock_fd" 2>/dev/null || true
        exec {lock_fd}>&-
    fi
    if [[ $status -eq 130 || $cancelled -eq 1 ]]; then
        warn 'Setup cancelled. Completed downloads and build work were kept for the next run.'
    fi
}
trap cleanup EXIT
trap 'cancelled=1; exit 130' INT TERM HUP

absolute_path()
{
    local value=$1
    if command -v realpath >/dev/null 2>&1; then
        # Keep the final Wine launcher symlink intact; its sibling build
        # artifacts are located relative to the link, not its target.
        realpath -ms -- "$value"
    elif [[ $value == /* ]]; then
        printf '%s\n' "$value"
    else
        printf '%s/%s\n' "$PWD" "$value"
    fi
}

clean_path_input()
{
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    if [[ ${#value} -ge 2 ]]; then
        if [[ ${value:0:1} == \" && ${value: -1} == \" ]] ||
           [[ ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
            value=${value:1:${#value}-2}
        fi
    fi
    if [[ $value == file://* ]] && command -v python3 >/dev/null 2>&1; then
        value=$(python3 - "$value" <<'PY'
import sys
from urllib.parse import unquote, urlparse

parsed = urlparse(sys.argv[1])
if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
    raise SystemExit(2)
print(unquote(parsed.path))
PY
        ) || return 1
    fi
    [[ $value != '~/'* ]] || value="${HOME:?HOME is not set}/${value:2}"
    printf '%s\n' "$value"
}

validate_integer()
{
    local label=$1 value=$2 minimum=$3 maximum=$4
    [[ $value =~ ^[0-9]+$ ]] || die "$label must be a whole number from $minimum to $maximum"
    ((value >= minimum && value <= maximum)) ||
        die "$label must be between $minimum and $maximum"
}

ask_yes_no()
{
    local prompt=$1 default=${2:-yes} answer suffix
    if [[ $assume_yes -eq 1 ]]; then
        [[ $default == yes ]]
        return
    fi
    [[ $interactive -eq 1 ]] || return 1
    [[ $default == yes ]] && suffix='[Y/n]' || suffix='[y/N]'
    while true; do
        read -r -p "$prompt $suffix " answer || return 1
        case ${answer,,} in
            '') [[ $default == yes ]]; return ;;
            y|yes) return 0 ;;
            n|no) return 1 ;;
            q|quit|cancel) cancelled=1; exit 130 ;;
            *) warn 'Please answer yes or no (or q to cancel).' ;;
        esac
    done
}

pause_for_live_to_close()
{
    while "$SCRIPTS/process-is-running.sh" "$ableton"; do
        if [[ $interactive -eq 0 || $assume_yes -eq 1 ]]; then
            die 'Ableton Live is running. Close it, then run the installer again.'
        fi
        warn 'Ableton Live must be closed before ENCORE changes the prefix.'
        read -r -p 'Close Ableton, then press Enter to check again (q to cancel): ' answer
        case ${answer,,} in q|quit|cancel) cancelled=1; exit 130 ;; esac
    done
}

detect_distro()
{
    distro_name='Unknown Linux'
    distro_id=unknown
    distro_like=
    if [[ -r /etc/os-release ]]; then
        # Values in os-release are distribution-owned shell assignments.
        # shellcheck disable=SC1091
        source /etc/os-release
        distro_name=${PRETTY_NAME:-${NAME:-Unknown Linux}}
        distro_id=${ID:-unknown}
        distro_like=${ID_LIKE:-}
    fi
}

detect_dpi()
{
    local factor=0 resolution width height
    dpi_recommendation=96
    dpi_reason='standard 100% scaling fallback'

    if command -v gsettings >/dev/null 2>&1; then
        factor=$(gsettings get org.gnome.desktop.interface scaling-factor 2>/dev/null |
            grep -oE '[0-9]+' | tail -n 1 || true)
        if [[ $factor =~ ^[2-4]$ ]]; then
            dpi_recommendation=$((96 * factor))
            dpi_reason="GNOME reports ${factor}00% display scaling"
            return
        fi
    fi

    if command -v xrandr >/dev/null 2>&1 && [[ -n ${DISPLAY:-} ]]; then
        resolution=$(xrandr --current 2>/dev/null |
            awk '/ connected primary / {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) {print $i; exit}}')
        if [[ -z $resolution ]]; then
            resolution=$(xrandr --current 2>/dev/null |
                awk '/ connected / {for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) {print $i; exit}}')
        fi
        resolution=${resolution%%+*}
        if [[ $resolution =~ ^([0-9]+)x([0-9]+)$ ]]; then
            width=${BASH_REMATCH[1]}
            height=${BASH_REMATCH[2]}
            if ((width >= 3000 && height >= 1700)); then
                dpi_recommendation=192
                dpi_reason="a ${width}x${height} HiDPI display was detected"
            elif ((width >= 2400 && height >= 1350)); then
                dpi_recommendation=144
                dpi_reason="a ${width}x${height} high-resolution display was detected"
            fi
        fi
    fi
}

choose_dpi()
{
    local choice custom
    detect_dpi
    heading 'Display scaling'
    say "Wine needs a DPI value so Ableton is readable and correctly sized."
    say "Recommendation: ${BOLD}${dpi_recommendation} DPI${RESET} because $dpi_reason."
    say 'If different monitors use different scaling, choose the scale used by the monitor where Live normally opens.'
    say
    say '  1) 100%  :  96 DPI'
    say '  2) 125%  : 120 DPI'
    say '  3) 150%  : 144 DPI'
    say '  4) 175%  : 168 DPI'
    say '  5) 200%  : 192 DPI'
    say '  6) 250%  : 240 DPI'
    say '  7) Custom DPI'

    while true; do
        read -r -p "Choose a scale [recommended: $dpi_recommendation DPI]: " choice
        [[ -n $choice ]] || { dpi=$dpi_recommendation; return; }
        case $choice in
            1|100|100%) dpi=96; return ;;
            2|125|125%) dpi=120; return ;;
            3|150|150%) dpi=144; return ;;
            4|175|175%) dpi=168; return ;;
            5|200|200%) dpi=192; return ;;
            6|250|250%) dpi=240; return ;;
            7|custom)
                read -r -p 'Custom DPI (72–384): ' custom
                if [[ $custom =~ ^[0-9]+$ ]] && ((custom >= 72 && custom <= 384)); then
                    dpi=$custom
                    return
                fi
                warn 'Enter a whole number between 72 and 384.'
                ;;
            q|Q|quit|cancel) cancelled=1; exit 130 ;;
            *) warn 'Choose 1–7, a percentage, or press Enter for the recommendation.' ;;
        esac
    done
}

scale_to_dpi()
{
    scale=${scale%%%}
    case $scale in
        100) dpi=96 ;;
        125) dpi=120 ;;
        150) dpi=144 ;;
        175) dpi=168 ;;
        200) dpi=192 ;;
        250) dpi=240 ;;
        *) die '--scale must be 100, 125, 150, 175, 200, or 250' ;;
    esac
}

detect_build_jobs()
{
    local cpus memory_kib memory_jobs fast_jobs
    cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')
    [[ $cpus =~ ^[0-9]+$ && $cpus -gt 0 ]] || cpus=2
    memory_kib=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '4194304')
    [[ $memory_kib =~ ^[0-9]+$ ]] || memory_kib=4194304
    memory_jobs=$((memory_kib / 2097152))
    ((memory_jobs >= 1)) || memory_jobs=1
    fast_jobs=$cpus
    ((fast_jobs <= memory_jobs)) || fast_jobs=$memory_jobs
    ((fast_jobs <= 8)) || fast_jobs=8
    ((fast_jobs >= 1)) || fast_jobs=1
    balanced_jobs=2
    ((balanced_jobs <= fast_jobs)) || balanced_jobs=$fast_jobs
    detected_cpus=$cpus
    detected_memory_gib=$(((memory_kib + 1048575) / 1048576))
    detected_fast_jobs=$fast_jobs
}

choose_jobs()
{
    local choice custom
    detect_build_jobs
    heading 'Build speed'
    say "This computer reports ${detected_cpus} logical CPUs and about ${detected_memory_gib} GiB of memory."
    say 'Building Wine can make the fans spin up. Balanced mode is the safe default.'
    say
    say '  1) Quiet     : 1 build job (slowest, least heat)'
    say "  2) Balanced  : $balanced_jobs build jobs (recommended)"
    say "  3) Fast      : $detected_fast_jobs build jobs (more CPU and fan noise)"
    say '  4) Custom'
    while true; do
        read -r -p 'Choose build mode [2]: ' choice
        case ${choice:-2} in
            1|quiet) jobs=1; return ;;
            2|balanced) jobs=$balanced_jobs; return ;;
            3|fast) jobs=$detected_fast_jobs; return ;;
            4|custom)
                read -r -p 'Number of parallel jobs (1–64): ' custom
                if [[ $custom =~ ^[0-9]+$ ]] && ((custom >= 1 && custom <= 64)); then
                    jobs=$custom
                    return
                fi
                warn 'Enter a whole number between 1 and 64.'
                ;;
            q|Q|quit|cancel) cancelled=1; exit 130 ;;
            *) warn 'Choose 1–4 or press Enter for Balanced.' ;;
        esac
    done
}

find_installers()
{
    local directory candidate
    installer_candidates=()
    for directory in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
        [[ -d $directory ]] || continue
        while IFS= read -r -d '' candidate; do
            installer_candidates+=("$candidate")
            ((${#installer_candidates[@]} < 8)) || return
        done < <(find "$directory" -maxdepth 3 -type f \
            \( -iname '*ableton*live*12*.exe' -o -iname '*ableton*live*12*.msi' \) \
            -print0 2>/dev/null)
    done
}

choose_installer()
{
    local choice entered index
    find_installers
    heading 'Ableton installer'
    say 'ENCORE does not download Ableton. Choose the installer from your licensed Ableton account.'
    if ((${#installer_candidates[@]})); then
        say 'I found these likely installers:'
        for index in "${!installer_candidates[@]}"; do
            printf '  %d) %s\n' "$((index + 1))" "${installer_candidates[index]}"
        done
        say "  $(( ${#installer_candidates[@]} + 1 ))) Enter another path"
        while true; do
            read -r -p 'Choose an installer: ' choice
            case $choice in
                q|Q|quit|cancel) cancelled=1; exit 130 ;;
            esac
            if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#installer_candidates[@]})); then
                installer=${installer_candidates[choice - 1]}
                return
            fi
            if [[ $choice == $(( ${#installer_candidates[@]} + 1 )) ]]; then
                break
            fi
            warn 'Choose one of the listed numbers.'
        done
    fi

    while true; do
        read -r -p 'Path to the Ableton Live 12 installer (you can drag the file here): ' entered
        case ${entered,,} in q|quit|cancel) cancelled=1; exit 130 ;; esac
        entered=$(clean_path_input "$entered") || {
            warn 'That file URL could not be read.'
            continue
        }
        entered=$(absolute_path "$entered")
        if [[ -f $entered ]]; then
            installer=$entered
            case ${installer,,} in
                *.exe|*.msi) ;;
                *)
                    warn 'The selected file is not named .exe or .msi.'
                    ask_yes_no 'Use it anyway?' no || continue
                    ;;
            esac
            return
        fi
        warn "File not found: $entered"
    done
}

wine_build_ready()
{
    local candidate=$1 build_dir stamp expected_hash definition config
    [[ -x $candidate ]] || return 1
    [[ $("$candidate" --version 2>/dev/null) == wine-11.13 ]] || return 1
    build_dir=$(dirname -- "$candidate")
    [[ -x $build_dir/server/wineserver ]] || return 1
    [[ -f $build_dir/dlls/dxgi/dxgi.dll.so ]] || return 1
    [[ -f $build_dir/dlls/winex11.drv/winex11.so ]] || return 1
    [[ -f $build_dir/dlls/winegstreamer/winegstreamer.so ]] || return 1
    [[ -f $build_dir/dlls/winepulse.drv/winepulse.so ]] || return 1
    [[ -f $build_dir/dlls/winevulkan/winevulkan.so ]] || return 1
    [[ -f $build_dir/dlls/comdlg32/comdlg32.so ]] || return 1

    config=$build_dir/include/config.h
    [[ -f $config ]] || return 1
    for definition in \
        SONAME_LIBDBUS_1 SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG SONAME_LIBGNUTLS \
        SONAME_LIBGL SONAME_LIBVULKAN SONAME_LIBX11 SONAME_LIBXCOMPOSITE \
        SONAME_LIBXCURSOR SONAME_LIBXEXT SONAME_LIBXFIXES SONAME_LIBXI \
        SONAME_LIBXINERAMA SONAME_LIBXRANDR SONAME_LIBXRENDER HAVE_UDEV
    do
        grep -q "^#define $definition " "$config" || return 1
    done

    stamp="$build_dir/.encore-build"
    [[ -f $stamp ]] || return 1
    expected_hash=$(sha256sum "$ROOT/patches/encore-wine.patch" | awk '{print $1}')
    grep -Fqx "wine_revision=$WINE_REVISION" "$stamp" || return 1
    grep -Fqx "patch_sha256=$expected_hash" "$stamp" || return 1
}

dependency_profile=build
dependency_command=
dependency_action=none

inspect_dependencies()
{
    [[ -x $DEPENDENCY_HELPER ]] || die "missing dependency helper: $DEPENDENCY_HELPER"
    [[ $build_mode == skip ]] && dependency_profile=runtime || dependency_profile=build
    if "$DEPENDENCY_HELPER" --check "$dependency_profile" >/dev/null 2>&1; then
        dependency_action=none
    else
        dependency_command=$("$DEPENDENCY_HELPER" --print "$dependency_profile" 2>/dev/null || true)
        case $dependency_policy in
            install) dependency_action=install ;;
            skip) dependency_action=blocked ;;
            ask)
                if [[ $interactive -eq 1 ]]; then
                    heading 'System packages'
                    warn 'Some required build or runtime packages are missing.'
                    [[ -z $dependency_command ]] || {
                        say 'ENCORE can run this distro-native package command:'
                        printf '%s\n' "$dependency_command"
                    }
                    if [[ $dependency_command == *'pacman -Syu'* ]]; then
                        warn 'Arch and CachyOS require a full system upgrade here; pacman partial upgrades are unsupported.'
                    fi
                    if ask_yes_no 'Install the missing system packages?' yes; then
                        dependency_action=install
                    else
                        dependency_action=blocked
                    fi
                else
                    dependency_action=blocked
                fi
                ;;
        esac
    fi
}

run_logged()
{
    local label=$1
    shift
    heading "$label"
    printf '[%s] %s\n' "$(date '+%F %T')" "$label" >>"$log_file"
    set +e
    "$@" 2>&1 | tee -a "$log_file"
    local status=${PIPESTATUS[0]}
    set -e
    ((status == 0)) || die "$label failed (exit $status). The completed earlier stages were kept."
    ok "$label complete"
}

install_ableton()
{
    mkdir -p "$prefix"
    WINEPREFIX="$prefix" WINEDEBUG=${WINEDEBUG:--all} "$wine" "$installer"
}

verify_external_wine()
{
    [[ -x $wine ]] || die "Wine executable not found: $wine"
    local version
    version=$("$wine" --version 2>/dev/null || true)
    [[ $version == wine-11.13 ]] ||
        die "Expected ENCORE's Wine 11.13 build, but $wine reports ${version:-no version}"
    wine_build_ready "$wine" ||
        die "Wine 11.13 was found, but its ENCORE build artifacts or build stamp are incomplete: $wine"
}

verify_installation()
{
    local -a runtime_config=()
    local runtime_file=$ROOT/.encore/runtime.conf
    local saved_prefix saved_wine saved_ableton

    [[ -x $wine ]] || die "Wine verification failed: $wine"
    [[ -f $ableton ]] || die "Ableton verification failed: $ableton"
    [[ -f $prefix/drive_c/windows/Fonts/ENCOREArial.ttf ]] ||
        die 'WebView font verification failed'
    [[ -f $runtime_file ]] || die "Launcher configuration verification failed: $runtime_file"
    mapfile -t runtime_config <"$runtime_file"
    saved_prefix=$(runtime_config_path "$prefix")
    saved_wine=$(runtime_config_path "$wine")
    saved_ableton=$(runtime_config_path "$ableton")
    [[ ${#runtime_config[@]} -eq 4 &&
        ${runtime_config[0]} == ENCORE_RUNTIME_V1 &&
        ${runtime_config[1]} == "$saved_prefix" &&
        ${runtime_config[2]} == "$saved_wine" &&
        ${runtime_config[3]} == "$saved_ableton" ]] ||
        die "Launcher configuration is invalid: $runtime_file"
    if [[ $install_desktop -eq 1 ]]; then
        local desktop=${XDG_DATA_HOME:-$HOME/.local/share}/applications/encore.desktop
        [[ -f $desktop ]] || die "Desktop entry verification failed: $desktop"
        if command -v desktop-file-validate >/dev/null 2>&1; then
            desktop-file-validate "$desktop" || die 'Desktop entry validation failed'
        fi
    fi
}

offer_github_star()
{
    [[ $interactive -eq 1 && $assume_yes -eq 0 ]] || return 0
    "$SCRIPTS/offer-github-star.sh" ||
        warn 'The optional GitHub star prompt failed; ENCORE itself is installed correctly.'
}

show_banner()
{
    printf '\n%s%s' "$BOLD" "$CYAN"
    cat <<'EOF'
  _____ _   _  ____ ___  ____  _____
 | ____| \ | |/ ___/ _ \|  _ \| ____|
 |  _| |  \| | |  | | | | |_) |  _|
 | |___| |\  | |__| |_| |  _ <| |___
 |_____|_| \_|\____\___/|_| \_\_____|
EOF
    printf '%s\n' "$RESET"
    say 'Guided Ableton Live 12 setup for Linux'
    say "${DIM}No Ableton files are downloaded or bundled by ENCORE.${RESET}"
}

show_system_summary()
{
    detect_distro
    heading 'System check'
    say "  Linux distribution: $distro_name"
    say "  Desktop:           ${XDG_CURRENT_DESKTOP:-not reported}"
    say "  Session:           ${XDG_SESSION_TYPE:-not reported}"
    say "  Project folder:    $ROOT"

    [[ $(uname -s) == Linux ]] || die 'ENCORE currently supports Linux only'
    case $(uname -m) in
        x86_64|amd64) ;;
        *) die "ENCORE requires an x86-64 computer; detected $(uname -m)" ;;
    esac
    ((EUID != 0)) || die 'Do not run ENCORE with sudo. It asks for sudo only when installing system packages.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'HOME is not set to a usable home directory'
    [[ $dry_run -eq 1 || -w $ROOT ]] || die "The project folder is not writable: $ROOT"

    case " $distro_id $distro_like " in
        *' ubuntu '*|*' debian '*|*' fedora '*|*' arch '*|*' cachyos '*)
            ok "Supported package family detected ($distro_id)"
            ;;
        *)
            warn 'This distribution is not in the tested apt/dnf/pacman set.'
            warn 'You may continue if the required packages are already installed.'
            ;;
    esac

    if [[ ${XDG_SESSION_TYPE:-} != wayland || -z ${DISPLAY:-} ]]; then
        warn 'ENCORE is tested with a Wayland session and Xwayland available.'
    fi
    if [[ ${XDG_CURRENT_DESKTOP:-} != *GNOME* ]]; then
        warn 'GNOME is the best-tested desktop. KDE and other desktops are currently experimental.'
    fi
}

normalize_configuration()
{
    local canonical_prefix canonical_ableton

    [[ -n $prefix ]] || die 'The Wine prefix path may not be empty'
    [[ -n $wine ]] || die 'The Wine executable path may not be empty'
    reject_path_controls 'Wine prefix path' "$prefix"
    reject_path_controls 'Wine executable path' "$wine"
    [[ -z $ableton ]] || reject_path_controls 'Ableton executable path' "$ableton"
    [[ -z $installer ]] || reject_path_controls 'Ableton installer path' "$installer"
    prefix=$(absolute_path "$prefix")
    wine=$(absolute_path "$wine")
    if [[ -n $ableton ]]; then
        ableton=$(absolute_path "$ableton")
    else
        ableton="$prefix/$ABLETON_RELATIVE"
    fi
    canonical_prefix=$(readlink -m -- "$prefix") ||
        die "Could not resolve the Wine prefix path: $prefix"
    canonical_ableton=$(readlink -m -- "$ableton") ||
        die "Could not resolve the Ableton executable path: $ableton"
    case $canonical_ableton in
        "$canonical_prefix"/*) ;;
        *) die "The Ableton executable must be inside the selected Wine prefix: $prefix" ;;
    esac
    [[ -z $installer ]] || installer=$(absolute_path "$(clean_path_input "$installer")")
}

prefix_has_content()
{
    [[ -d $prefix ]] || return 1
    [[ -n $(find "$prefix" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) ]]
}

prefix_is_recognized()
{
    if [[ -f $prefix/.encore-prefix ]] &&
       grep -Fqx 'ENCORE_PREFIX_V1' "$prefix/.encore-prefix"; then
        return 0
    fi
    [[ -f $ableton && ${ableton##*/} == 'Ableton Live 12 Suite.exe' ]]
}

inspect_prefix_safety()
{
    prefix_has_content || return 0
    prefix_is_recognized && return 0
    [[ $adopt_prefix -eq 0 ]] || return 0

    if [[ $interactive -eq 0 ]]; then
        die "The selected prefix is non-empty and not recognized as ENCORE: $prefix. Use --adopt-prefix only if this is intentional."
    fi

    heading 'Existing prefix safety'
    warn "The selected prefix is non-empty but does not contain Ableton or an ENCORE marker: $prefix"
    if ask_yes_no 'Adopt this folder as the ENCORE prefix?' no; then
        adopt_prefix=1
    else
        die 'Choose an empty folder with --prefix, or rerun with --adopt-prefix after checking its contents.'
    fi
}

mark_prefix()
{
    local marker temporary
    mkdir -p "$prefix"
    marker="$prefix/.encore-prefix"
    temporary="$marker.tmp.$$"
    printf 'ENCORE_PREFIX_V1\n' >"$temporary"
    mv -f "$temporary" "$marker"
}

save_runtime_config()
{
    local directory=$ROOT/.encore
    local destination=$ROOT/.encore/runtime.conf
    local temporary
    local saved_prefix saved_wine saved_ableton

    mkdir -p "$directory" || return 1
    saved_prefix=$(runtime_config_path "$prefix") || return 1
    saved_wine=$(runtime_config_path "$wine") || return 1
    saved_ableton=$(runtime_config_path "$ableton") || return 1
    temporary=$(mktemp "$directory/.runtime.conf.XXXXXX") || return 1
    if ! (
        umask 077
        printf 'ENCORE_RUNTIME_V1\n%s\n%s\n%s\n' \
            "$saved_prefix" "$saved_wine" "$saved_ableton" >"$temporary"
    ); then
        rm -f "$temporary"
        return 1
    fi
    if ! chmod 0600 "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if ! mv -f "$temporary" "$destination"; then
        rm -f "$temporary"
        return 1
    fi
}

runtime_config_path()
{
    case $1 in
        "$ROOT"/*) printf '%s\n' "${1#"$ROOT"/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

prepare_choices()
{
    local existing_live=0 reuse_decided=0
    [[ -f $ableton ]] && existing_live=1

    [[ $build_only -eq 1 ]] || inspect_prefix_safety

    if [[ $reinstall_ableton -eq 1 && -z $installer ]]; then
        die '--reinstall-ableton requires --installer FILE'
    fi

    if [[ $existing_live -eq 1 && -n $installer && $reinstall_ableton -eq 0 ]]; then
        heading 'Existing Ableton installation'
        ok "Found Ableton Live at $ableton"
        if [[ $interactive -eq 1 ]]; then
            if ask_yes_no 'Reuse it and skip the Ableton installer?' yes; then
                installer=
                reuse_decided=1
            else
                reinstall_ableton=1
            fi
        else
            info 'Reusing it so this command can be safely retried; use --reinstall-ableton to override.'
            installer=
            reuse_decided=1
        fi
    fi

    if [[ $build_only -eq 0 && -z $installer ]]; then
        if [[ $existing_live -eq 1 ]]; then
            if [[ $interactive -eq 1 && $reuse_decided -eq 0 ]]; then
                heading 'Existing Ableton installation'
                ok "Found Ableton Live at $ableton"
                if ! ask_yes_no 'Reuse this installation?' yes; then
                    choose_installer
                fi
            fi
        elif [[ $interactive -eq 1 ]]; then
            choose_installer
        else
            die 'Ableton is not installed. Supply --installer "/path/to/Ableton installer.exe".'
        fi
    fi

    if [[ -n $installer && ! -f $installer ]]; then
        die "Ableton installer not found: $installer"
    fi

    if [[ $build_mode == auto ]]; then
        if wine_build_ready "$wine"; then
            build_mode=skip
        else
            build_mode=build
        fi
    fi

    if [[ $build_mode == build ]]; then
        if [[ -z $jobs ]]; then
            if [[ $interactive -eq 1 && $assume_yes -eq 0 ]]; then
                choose_jobs
            else
                detect_build_jobs
                jobs=$balanced_jobs
            fi
        fi
        validate_integer 'Build jobs' "$jobs" 1 64
    else
        verify_external_wine
    fi

    if [[ $build_only -eq 0 ]]; then
        if [[ -n $scale ]]; then
            scale_to_dpi
        elif [[ -z $dpi ]]; then
            if [[ $interactive -eq 1 && $assume_yes -eq 0 ]]; then
                choose_dpi
            else
                detect_dpi
                dpi=$dpi_recommendation
            fi
        fi
        validate_integer 'DPI' "$dpi" 72 384
    fi

    inspect_dependencies
    if [[ $dependency_action == blocked && $dry_run -eq 0 ]]; then
        [[ -z $dependency_command ]] || printf '\nInstall command:\n%s\n\n' "$dependency_command" >&2
        die 'Required system packages are missing. Rerun with --install-deps or install the command above.'
    fi
}

show_plan()
{
    local dependency_description
    case $dependency_action in
        install) dependency_description='install with the system package manager' ;;
        blocked) dependency_description='missing (dry-run cannot install them)' ;;
        *) dependency_description='already available' ;;
    esac
    heading 'Setup plan'
    say "  Distribution:      $distro_name"
    say "  Wine:              $([[ $build_mode == build ]] && printf 'build/resume ENCORE Wine' || printf 'reuse %s' "$wine")"
    [[ $build_mode != build ]] || say "  Build jobs:         $jobs"
    say "  Dependencies:       $dependency_description"
    if [[ $build_only -eq 1 ]]; then
        say "  Final action:       $([[ $configure_only -eq 1 ]] && printf 'configure Wine only' || printf 'build Wine only')"
    else
        say "  Wine prefix:        $prefix"
        say "  Ableton:            $ableton"
        say "  Ableton installer:  ${installer:-reuse existing installation}"
        say "  Display scaling:    $dpi DPI ($((dpi * 100 / 96))% approximate)"
        say "  Application menu:   $([[ $install_desktop -eq 1 ]] && printf 'install/update entry' || printf 'skip')"
    fi
    say "  Log folder:         $ROOT/logs"

    if [[ $build_mode == build ]]; then
        local available_kib
        available_kib=$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 {print $4}')
        if [[ $available_kib =~ ^[0-9]+$ ]] && ((available_kib < 15728640)); then
            warn 'Less than 15 GiB is free. The Wine build and Ableton prefix may run out of space.'
        else
            info 'Allow roughly 15–25 GiB and expect the first Wine build to take a while.'
        fi
    fi

    if [[ $dry_run -eq 1 ]]; then
        ok 'Dry run complete. Nothing was changed.'
        exit 0
    fi
    if [[ $interactive -eq 1 && $assume_yes -eq 0 ]]; then
        ask_yes_no 'Start this setup?' yes || { cancelled=1; exit 130; }
    fi
}

start_mutating_run()
{
    local lock_file owner
    command -v flock >/dev/null 2>&1 || die 'flock is required to safely serialize installation (normally provided by util-linux)'
    mkdir -p "$ROOT/.tmp" "$ROOT/logs"
    lock_file="$ROOT/.tmp/install.lock"
    exec {lock_fd}<>"$lock_file" || die 'Could not open the installer lock'
    if ! flock -n "$lock_fd"; then
        owner=$(sed -n '1p' "$lock_file" 2>/dev/null || true)
        [[ $owner =~ ^[0-9]+$ ]] &&
            die "Another ENCORE installer is running as process $owner"
        die 'Another ENCORE installer is already running'
    fi
    : >"$lock_file"
    printf '%s\n' "$$" >"$lock_file"
    log_file="$ROOT/logs/install-$(date '+%Y%m%d-%H%M%S').log"
    touch "$log_file"
    info "Detailed log: $log_file"
}

stage_number=1
run_stage()
{
    local label=$1
    shift
    run_logged "$stage_number. $label" "$@"
    stage_number=$((stage_number + 1))
}

main()
{
    show_banner
    show_system_summary
    normalize_configuration
    prepare_choices
    show_plan
    start_mutating_run

    if [[ $dependency_action == install ]]; then
        run_stage 'Install system packages' "$DEPENDENCY_HELPER" --install "$dependency_profile"
    else
        ok 'System packages are ready'
    fi
    "$DEPENDENCY_HELPER" --check "$dependency_profile" >>"$log_file" 2>&1 ||
        die 'Dependency verification still fails after package setup.'

    if [[ $build_mode == build ]]; then
        export JOBS=$jobs
        wine=$DEFAULT_WINE
        export ENCORE_WINE=$wine
        if [[ $configure_only -eq 1 ]]; then
            run_stage 'Configure ENCORE Wine' "$SCRIPTS/build-wine.sh" --configure-only
        else
            run_stage 'Build ENCORE Wine' "$SCRIPTS/build-wine.sh"
        fi
    else
        ok "Reusing Wine: $wine"
    fi

    if [[ $build_only -eq 1 ]]; then
        ok "$([[ $configure_only -eq 1 ]] && printf 'Wine configuration' || printf 'Wine build') finished successfully"
        say "Log: $log_file"
        return
    fi

    export ENCORE_PREFIX=$prefix ENCORE_WINE=$wine ENCORE_ABLETON=$ableton
    pause_for_live_to_close
    run_stage 'Register the ENCORE prefix' mark_prefix

    if [[ -n $installer ]]; then
        run_stage 'Run the Ableton installer' install_ableton
        [[ -f $ableton ]] ||
            die "The Ableton installer finished, but Live was not found at $ableton"
        pause_for_live_to_close
    else
        ok 'Reusing the existing Ableton installation'
    fi

    run_stage 'Enable host files and native folder picking' "$SCRIPTS/configure-prefix.sh"
    run_stage 'Apply display scaling' "$SCRIPTS/set-dpi.sh" "$dpi"
    run_stage 'Install the Learn View font fallback' "$SCRIPTS/install-webview-font.sh"
    run_stage 'Save launcher paths' save_runtime_config
    if [[ $install_desktop -eq 1 ]]; then
        run_stage 'Install the application-menu entry' "$SCRIPTS/install-desktop.sh"
    else
        info 'Application-menu entry skipped by request'
    fi

    verify_installation
    heading 'Setup complete'
    ok 'ENCORE and Ableton Live 12 Suite are ready.'
    say "  Prefix: $prefix"
    say "  DPI:    $dpi"
    say "  Log:    $log_file"
    say
    say "Launch later with: $ROOT/scripts/launch-ableton.sh"

    local launch_now=0
    case $launch_policy in
        yes) launch_now=1 ;;
        ask)
            if [[ $interactive -eq 1 ]] && ask_yes_no 'Launch Ableton now?' yes; then
                launch_now=1
            fi
            ;;
    esac
    if [[ $launch_now -eq 1 ]]; then
        "$ROOT/scripts/launch-ableton.sh" &
        disown || true
        ok 'Ableton launch requested'
    fi

    offer_github_star
}

main
