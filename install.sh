#!/usr/bin/env bash

# Guided ENCORE setup for Ableton Live 12 Suite.
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$ROOT/scripts"
ORIGINAL_ARGS=("$@")
WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
ENCORE_RELEASE_VERSION=v0.1.0
ENCORE_GLIBC_MIN=2.35
DEFAULT_PREFIX="$ROOT/ableton-prefix"
SOURCE_WINE="$ROOT/build/wine64/wine"
DEFAULT_WINE="$ROOT/runtime/wine/bin/wine"
ABLETON_RELATIVE='drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe'
ABLETON_EXE_RELATIVE='Program/Ableton Live 12 Suite.exe'
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
live_source=${ABLETON_LIVE_DIR:-}
live_destination=
live_source_size_kib=0
live_required_space_kib=0
default_ableton=
prefix=${ENCORE_PREFIX:-$DEFAULT_PREFIX}
wine=${ENCORE_WINE:-$DEFAULT_WINE}
ableton=${ENCORE_ABLETON:-}
dpi=${DPI:-}
scale=
jobs=${JOBS:-}
wine_explicit=0
[[ $wine_environment_explicit -eq 0 ]] || wine_explicit=1
unset wine_environment_explicit
live_source_cli_set=0
ableton_cli_set=0
no_build_requested=0
prebuilt_requested=0
source_build_requested=0
adopt_prefix=0
replace_live=0
log_file=
lock_fd=
cancelled=0

usage()
{
    cat <<'EOF'
Usage: ./install.sh [options] [ABLETON_LIVE_FOLDER]

Run the guided ENCORE setup. With no options in a terminal, the wizard
detects your system and walks you through every choice.

Setup options:
  --live-dir DIR         Complete Windows-installed "Live 12 Suite" folder
  --prefix DIR           Wine prefix (default: ./ableton-prefix)
  --ableton FILE         Existing Ableton executable inside the prefix
  --adopt-prefix         Allow use of a non-empty, unrecognized prefix
  --replace-live         Replace Live in the prefix using --live-dir
  --dpi N                Wine DPI from 72 to 384
  --scale PERCENT        Display scale: 100, 125, 150, 175, 200, or 250
  --jobs N               Parallel jobs for an optional source build
  --wine FILE            Reuse an existing ENCORE Wine runtime
  --prebuilt             Download the verified prebuilt runtime (default)
  --build-from-source    Compile the patched Wine tree locally instead
  --no-build             Require an existing --wine/default runtime
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
Arch/CachyOS (pacman). Ableton is not downloaded or bundled. For a new
prefix, supply the complete "Live 12 Suite" folder copied from a Windows
installation, or an equivalent folder lawfully extracted from your own
licensed copy. Do not supply a downloaded installer, a lone .exe, or only
the Program folder.
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
        --live-dir)
            need_value "$1" "${2:-}"
            [[ $live_source_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton Live source folder may be supplied\n' >&2
                exit 2
            }
            live_source=$2
            live_source_cli_set=1
            shift
            ;;
        --live-dir=*)
            [[ $live_source_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton Live source folder may be supplied\n' >&2
                exit 2
            }
            live_source=${1#*=}
            live_source_cli_set=1
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
        --replace-live) replace_live=1 ;;
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
        --prebuilt)
            [[ $wine_explicit -eq 0 ]] || {
                printf 'ENCORE: --prebuilt cannot be combined with --wine\n' >&2
                exit 2
            }
            build_mode=download
            wine=$DEFAULT_WINE
            prebuilt_requested=1
            ;;
        --build-from-source)
            [[ $wine_explicit -eq 0 ]] || {
                printf 'ENCORE: --build-from-source cannot be combined with --wine\n' >&2
                exit 2
            }
            build_mode=build
            wine=$SOURCE_WINE
            source_build_requested=1
            ;;
        --build-only)
            build_only=1
            build_mode=build
            wine=$SOURCE_WINE
            ;;
        --configure-only)
            configure_only=1
            build_only=1
            build_mode=build
            wine=$SOURCE_WINE
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
            [[ $live_source_cli_set -eq 0 ]] || {
                printf 'ENCORE: only one Ableton Live source folder may be supplied\n' >&2
                exit 2
            }
            live_source=$1
            live_source_cli_set=1
            ;;
    esac
    shift
done

while (($#)); do
    [[ $live_source_cli_set -eq 0 ]] || {
        printf 'ENCORE: only one Ableton Live source folder may be supplied\n' >&2
        exit 2
    }
    live_source=$1
    live_source_cli_set=1
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
if [[ $prebuilt_requested -eq 1 &&
      ($source_build_requested -eq 1 || $no_build_requested -eq 1 ||
       $build_only -eq 1 || $wine_explicit -eq 1) ]]; then
    printf 'ENCORE: --prebuilt cannot be combined with a source build, --no-build, or --wine\n' >&2
    exit 2
fi
if [[ $source_build_requested -eq 1 &&
      ($no_build_requested -eq 1 || $wine_explicit -eq 1) ]]; then
    printf 'ENCORE: --build-from-source cannot be combined with --no-build or --wine\n' >&2
    exit 2
fi
if [[ $build_only -eq 1 && $build_mode != build ]]; then
    printf 'ENCORE: --build-only/--configure-only cannot be combined with --prebuilt\n' >&2
    exit 2
fi
if [[ $build_only -eq 1 && $replace_live -eq 1 ]]; then
    printf 'ENCORE: --replace-live cannot be combined with --build-only/--configure-only\n' >&2
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
            die 'Ableton Live is running. Close it, then run ENCORE setup again.'
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

live_source_error=

validate_live_source()
{
    local candidate=$1 marker
    local -a required_files=(
        "$ABLETON_EXE_RELATIVE"
        'Program/Ableton Live Engine.dll'
        'Program/Installation.cfg'
        'Resources/GUI.alp'
        'Resources/Graphics.alp'
        'Resources/Icons/live_suite.ico'
        'Redist/vc_redist.exe'
        'Redist/MicrosoftEdgeWebview2Setup.exe'
        'Legal/Third-party License Information.txt'
    )
    live_source_error=

    if [[ -f $candidate ]]; then
        case ${candidate,,} in
            *.exe|*.msi)
                live_source_error='That path is an executable or installer. Select the outer "Live 12 Suite" folder from an installed Windows copy.'
                ;;
            *.zip|*.7z|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.xz)
                live_source_error='That path is an archive. ENCORE needs the complete already-installed "Live 12 Suite" folder after it has been extracted.'
                ;;
            *)
                live_source_error='That path is a file. Select the outer "Live 12 Suite" folder, not an individual file.'
                ;;
        esac
        return 1
    fi
    if [[ ! -d $candidate ]]; then
        live_source_error="Ableton Live source folder not found: $candidate"
        return 1
    fi
    if [[ ${candidate%/} == */Program &&
          -s $candidate/'Ableton Live 12 Suite.exe' ]]; then
        live_source_error='Select the parent "Live 12 Suite" folder, not Program by itself. The parent must also contain Resources, Redist, and Legal.'
        return 1
    fi
    if find "$candidate" -maxdepth 1 -type f \
       \( -iname '*Ableton*Installer*.exe' -o -iname '*Ableton*Installer*.msi' \) \
       -print -quit 2>/dev/null | grep -q .; then
        live_source_error='That looks like a downloaded Ableton installer package. ENCORE needs the complete folder produced by a Windows installation.'
        return 1
    fi
    for marker in Program Resources Redist Legal; do
        if [[ ! -d $candidate/$marker || -L $candidate/$marker ]]; then
            live_source_error="That is not a complete installed Live folder: missing or linked $marker/. Select the outer \"Live 12 Suite\" folder."
            return 1
        fi
    done
    for marker in "${required_files[@]}"; do
        if [[ ! -f $candidate/$marker || -L $candidate/$marker || ! -s $candidate/$marker ]]; then
            live_source_error="That is not a complete installed Live folder: missing, empty, or linked $marker."
            return 1
        fi
    done
    if find "$candidate" -mindepth 1 \
       \( -type l -o \( ! -type f ! -type d \) \) \
       -print -quit 2>/dev/null | grep -q .; then
        live_source_error='The installed Live folder must be self-contained and may not contain symbolic links or special files.'
        return 1
    fi
    if ! grep -Eq '"variant"[[:space:]]*:[[:space:]]*"Suite"' \
       "$candidate/Program/Installation.cfg"; then
        live_source_error='Program/Installation.cfg is not an Ableton Live Suite installation.'
        return 1
    fi
}

find_live_sources()
{
    local directory executable candidate canonical
    local -A seen=()
    live_source_candidates=()
    for directory in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
        [[ -d $directory ]] || continue
        while IFS= read -r -d '' executable; do
            candidate=$(dirname -- "$(dirname -- "$executable")")
            validate_live_source "$candidate" || continue
            canonical=$(readlink -f -- "$candidate" 2>/dev/null || printf '%s' "$candidate")
            [[ -z ${seen[$canonical]+x} ]] || continue
            seen[$canonical]=1
            live_source_candidates+=("$candidate")
            ((${#live_source_candidates[@]} < 8)) || return
        done < <(find "$directory" -maxdepth 10 -type f \
            -ipath "*/Live 12 Suite/$ABLETON_EXE_RELATIVE" -print0 2>/dev/null)
    done
}

choose_live_source()
{
    local choice entered index
    find_live_sources
    heading 'Ableton Live source'
    say 'Select the complete "Live 12 Suite" application folder from an installed'
    say 'Windows copy, normally C:\ProgramData\Ableton\Live 12 Suite, or the same'
    say 'complete application folder extracted another way from your licensed copy.'
    say 'It must contain Program, Resources, Redist, and Legal.'
    say 'Do not select a downloaded installer, a lone .exe, or Program by itself.'
    if ((${#live_source_candidates[@]})); then
        say 'I found these complete Live folders:'
        for index in "${!live_source_candidates[@]}"; do
            printf '  %d) %s\n' "$((index + 1))" "${live_source_candidates[index]}"
        done
        say "  $(( ${#live_source_candidates[@]} + 1 ))) Enter another path"
        while true; do
            read -r -p 'Choose a Live folder: ' choice
            case $choice in
                q|Q|quit|cancel) cancelled=1; exit 130 ;;
            esac
            if [[ $choice =~ ^[0-9]+$ ]] &&
               ((choice >= 1 && choice <= ${#live_source_candidates[@]})); then
                live_source=${live_source_candidates[choice - 1]}
                return
            fi
            if [[ $choice == $(( ${#live_source_candidates[@]} + 1 )) ]]; then
                break
            fi
            warn 'Choose one of the listed numbers.'
        done
    fi

    while true; do
        read -r -p 'Path to the complete "Live 12 Suite" folder (you can drag the folder here): ' entered
        case ${entered,,} in q|quit|cancel) cancelled=1; exit 130 ;; esac
        entered=$(clean_path_input "$entered") || {
            warn 'That file URL could not be read.'
            continue
        }
        entered=$(absolute_path "$entered")
        if validate_live_source "$entered"; then
            live_source=$entered
            return
        fi
        warn "$live_source_error"
    done
}

wine_build_ready()
{
    local candidate=$1 build_dir stamp expected_hash definition config
    local runtime_root manifest glibc_max
    local -a runtime_records=() configured_pe_archs=()
    [[ -x $candidate ]] || return 1
    [[ $("$candidate" --version 2>/dev/null) == wine-11.13 ]] || return 1
    expected_hash=$(sha256sum "$ROOT/patches/encore-wine.patch" | awk '{print $1}')

    build_dir=$(dirname -- "$candidate")
    runtime_root=$(dirname -- "$build_dir")
    manifest=$runtime_root/.encore-runtime
    if [[ ${build_dir##*/} == bin && -f $manifest ]]; then
        [[ -x $runtime_root/bin/wineserver ]] || return 1
        for config in \
            lib/wine/x86_64-unix/ntdll.so \
            lib/wine/x86_64-unix/winex11.so \
            lib/wine/x86_64-unix/winegstreamer.so \
            lib/wine/x86_64-unix/winepulse.so \
            lib/wine/x86_64-unix/winevulkan.so \
            lib/wine/x86_64-unix/comdlg32.so \
            lib/wine/x86_64-windows/ntdll.dll \
            lib/wine/x86_64-windows/wow64.dll \
            lib/wine/x86_64-windows/wow64cpu.dll \
            lib/wine/x86_64-windows/wow64win.dll \
            lib/wine/x86_64-windows/dxgi.dll \
            lib/wine/i386-windows/ntdll.dll \
            lib/wine/i386-windows/kernel32.dll \
            lib/wine/i386-windows/dxgi.dll \
            lib/wine/i386-windows/cmd.exe \
            lib/wine/i386-windows/wineboot.exe \
            share/wine/wine.inf
        do
            [[ -f $runtime_root/$config ]] || return 1
        done
        [[ ! -e $runtime_root/lib/wine/i386-unix ]] || return 1
        mapfile -t runtime_records <"$manifest"
        [[ ${#runtime_records[@]} -eq 8 ]] || return 1
        [[ ${runtime_records[0]} == ENCORE_WINE_RUNTIME_V1 ]] || return 1
        [[ ${runtime_records[1]} == "encore_version=$ENCORE_RELEASE_VERSION" ]] || return 1
        [[ ${runtime_records[2]} == wine_version=11.13 ]] || return 1
        [[ ${runtime_records[3]} == "wine_revision=$WINE_REVISION" ]] || return 1
        [[ ${runtime_records[4]} == "patch_sha256=$expected_hash" ]] || return 1
        [[ ${runtime_records[5]} == arch=x86_64 ]] || return 1
        [[ ${runtime_records[6]} == pe_archs=i386,x86_64 ]] || return 1
        [[ ${runtime_records[7]} =~ ^glibc_max=([0-9]+\.[0-9]+)$ ]] || return 1
        glibc_max=${BASH_REMATCH[1]}
        [[ $(printf '%s\n' "$glibc_max" 2.35 | sort -V | tail -n 1) == 2.35 ]] ||
            return 1
        return 0
    fi

    build_dir=$(dirname -- "$candidate")
    [[ -x $build_dir/server/wineserver ]] || return 1
    [[ -f $build_dir/dlls/winex11.drv/winex11.so ]] || return 1
    [[ -f $build_dir/dlls/winegstreamer/winegstreamer.so ]] || return 1
    [[ -f $build_dir/dlls/winepulse.drv/winepulse.so ]] || return 1
    [[ -f $build_dir/dlls/winevulkan/winevulkan.so ]] || return 1
    [[ -f $build_dir/dlls/comdlg32/comdlg32.so ]] || return 1
    [[ -f $build_dir/dlls/ntdll/x86_64-windows/ntdll.dll ]] || return 1
    [[ -f $build_dir/dlls/wow64/x86_64-windows/wow64.dll ]] || return 1
    [[ -f $build_dir/dlls/wow64cpu/x86_64-windows/wow64cpu.dll ]] || return 1
    [[ -f $build_dir/dlls/wow64win/x86_64-windows/wow64win.dll ]] || return 1
    [[ -f $build_dir/dlls/dxgi/x86_64-windows/dxgi.dll ]] || return 1
    [[ -f $build_dir/dlls/ntdll/i386-windows/ntdll.dll ]] || return 1
    [[ -f $build_dir/dlls/kernel32/i386-windows/kernel32.dll ]] || return 1
    [[ -f $build_dir/dlls/dxgi/i386-windows/dxgi.dll ]] || return 1
    [[ -f $build_dir/programs/cmd/i386-windows/cmd.exe ]] || return 1
    [[ -f $build_dir/programs/wineboot/i386-windows/wineboot.exe ]] || return 1

    grep -Fqx 'HOST_ARCH = x86_64' "$build_dir/Makefile" || return 1
    read -r -a configured_pe_archs <<<"$(sed -n 's/^PE_ARCHS = *//p' "$build_dir/Makefile")"
    [[ ${#configured_pe_archs[@]} -eq 2 &&
       ${configured_pe_archs[0]} == i386 &&
       ${configured_pe_archs[1]} == x86_64 ]] || return 1

    config=$build_dir/include/config.h
    [[ -f $config ]] || return 1
    for definition in \
        SONAME_LIBDBUS_1 SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG SONAME_LIBGNUTLS \
        SONAME_LIBGL SONAME_LIBVULKAN SONAME_LIBX11 SONAME_LIBXCOMPOSITE \
        SONAME_LIBXCURSOR SONAME_LIBXEXT SONAME_LIBXFIXES SONAME_LIBXI \
        SONAME_LIBXINERAMA SONAME_LIBXRANDR SONAME_LIBXRENDER HAVE_UDEV \
        HAVE_LINUX_NTSYNC_H
    do
        grep -q "^#define $definition " "$config" || return 1
    done

    stamp="$build_dir/.encore-build"
    [[ -f $stamp ]] || return 1
    grep -Fqx "wine_revision=$WINE_REVISION" "$stamp" || return 1
    grep -Fqx "patch_sha256=$expected_hash" "$stamp" || return 1
}

prebuilt_host_ready()
{
    local host_glibc
    [[ $(uname -m) == x86_64 ]] || return 1
    host_glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null || true)
    [[ $host_glibc =~ ^glibc\ ([0-9]+\.[0-9]+)$ ]] || return 1
    [[ $(printf '%s\n' "$ENCORE_GLIBC_MIN" "${BASH_REMATCH[1]}" |
        sort -V | head -n 1) == "$ENCORE_GLIBC_MIN" ]]
}

dependency_profile=build
dependency_command=
dependency_action=none

inspect_dependencies()
{
    [[ -x $DEPENDENCY_HELPER ]] || die "missing dependency helper: $DEPENDENCY_HELPER"
    [[ $build_mode == build ]] && dependency_profile=build || dependency_profile=runtime
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

initialize_wine_prefix()
{
    mkdir -p "$prefix"
    if ! WINEPREFIX="$prefix" WINEDEBUG=${WINEDEBUG:--all} \
         "$wine" wineboot.exe -u; then
        warn 'Wine requested a second prefix initialization pass.'
        if ! WINEPREFIX="$prefix" WINEDEBUG=${WINEDEBUG:--all} \
             "$wine" wineboot.exe -u; then
            error 'Wine prefix initialization failed twice.'
            return 1
        fi
    fi
    [[ -f $prefix/user.reg && -f $prefix/system.reg ]] || {
        error 'Wine did not finish initializing the prefix.'
        return 1
    }
}

import_live_files()
(
    set -Eeuo pipefail
    local destination_parent staging backup=
    local backup_moved=0 new_published=0 committed=0 status cleanup_failed
    destination_parent=$(dirname -- "$live_destination")
    mkdir -p "$destination_parent"
    staging=$(mktemp -d "$destination_parent/.encore-live-staging.XXXXXX")

    cleanup_import()
    {
        status=$?
        trap - EXIT HUP INT TERM
        set +e
        cleanup_failed=0
        if [[ -n ${staging:-} && -e $staging ]]; then
            if ! rm -rf -- "$staging"; then
                error "Could not remove incomplete staged copy: $staging"
                cleanup_failed=1
            fi
        fi
        if [[ $backup_moved -eq 1 && $committed -eq 0 && -e $backup ]]; then
            if [[ $new_published -eq 1 && -e $live_destination ]]; then
                if ! rm -rf -- "$live_destination"; then
                    error "Could not remove the incomplete replacement: $live_destination"
                    cleanup_failed=1
                fi
            fi
            if [[ ! -e $live_destination ]]; then
                if ! mv -- "$backup" "$live_destination"; then
                    error "Could not restore the previous Live folder from $backup"
                    cleanup_failed=1
                fi
            elif [[ -e $backup ]]; then
                error "The previous Live folder is still safe at $backup"
                cleanup_failed=1
            fi
        fi
        if [[ $status -eq 0 && $cleanup_failed -ne 0 ]]; then
            status=1
        fi
        exit "$status"
    }
    trap cleanup_import EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    say "Copying the complete installed Live folder from $live_source"
    cp -a --reflink=auto --no-preserve=ownership -- "$live_source/." "$staging/"
    if ! validate_live_source "$staging"; then
        error "The staged Live copy failed validation: $live_source_error"
        return 1
    fi

    if [[ -e $live_destination || -L $live_destination ]]; then
        if [[ $replace_live -ne 1 ]]; then
            error "Ableton Live already exists at $live_destination"
            return 1
        fi
        backup=$(mktemp -d "$destination_parent/.encore-live-backup.XXXXXX")
        rmdir -- "$backup"
        trap '' HUP INT TERM
        if mv -- "$live_destination" "$backup"; then
            backup_moved=1
        else
            trap 'exit 129' HUP
            trap 'exit 130' INT
            trap 'exit 143' TERM
            return 1
        fi
    fi

    if mv -- "$staging" "$live_destination"; then
        staging=
        new_published=1
    else
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        return 1
    fi
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if ! validate_live_source "$live_destination"; then
        error "The imported Live folder failed validation: $live_source_error"
        return 1
    fi
    [[ -s $ableton ]] || {
        error "The imported Ableton executable was not found at $ableton"
        return 1
    }

    committed=1
    if [[ $backup_moved -eq 1 ]]; then
        rm -rf -- "$backup"
        backup=
    fi
    trap - EXIT HUP INT TERM
)

vc_runtime_ready()
{
    local filename path
    for filename in vcruntime140.dll vcruntime140_1.dll msvcp140.dll msvcp140_1.dll; do
        path="$prefix/drive_c/windows/system32/$filename"
        [[ -s $path ]] || return 1
        grep -aFq 'Wine placeholder DLL' "$path" && return 1
    done
    return 0
}

webview2_ready()
{
    local application_dir="$prefix/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"
    local executable version_dir
    local -a executables
    [[ -d $application_dir ]] || return 1
    executables=("$application_dir"/*/msedgewebview2.exe)
    for executable in "${executables[@]}"; do
        [[ -s $executable ]] || continue
        version_dir=${executable%/*}
        [[ -s $version_dir/msedge.dll &&
           -s $version_dir/icudtl.dat &&
           -s $version_dir/Installer/setup.exe ]] || continue
        return 0
    done
    return 1
}

install_vc_runtime()
{
    local setup="$live_destination/Redist/vc_redist.exe" status=0
    if vc_runtime_ready; then
        say 'Microsoft Visual C++ runtime is already installed'
        return 0
    fi
    [[ -s $setup ]] || {
        error "Visual C++ setup is missing from the imported Live folder: $setup"
        return 1
    }
    WINEPREFIX="$prefix" WINEDEBUG=${WINEDEBUG:--all} \
        "$wine" "$setup" /install /quiet /norestart || status=$?
    case $status in
        0|102|194) ;;
        *)
            error "Visual C++ setup failed with exit status $status"
            return "$status"
            ;;
    esac
    vc_runtime_ready || {
        error 'Visual C++ setup finished, but the required runtime files were not installed.'
        return 1
    }
}

install_webview2_runtime()
{
    local setup="$live_destination/Redist/MicrosoftEdgeWebview2Setup.exe"
    local attempt status=0
    if webview2_ready; then
        say 'Microsoft Edge WebView2 Runtime is already installed'
        return 0
    fi
    [[ -s $setup ]] || {
        error "WebView2 setup is missing from the imported Live folder: $setup"
        return 1
    }
    say 'WebView2 setup may download the runtime and requires an internet connection.'
    WINEPREFIX="$prefix" WINEDEBUG=${WINEDEBUG:--all} \
        "$wine" "$setup" /silent /install || status=$?
    for attempt in {1..90}; do
        webview2_ready && return 0
        sleep 2
    done
    webview2_ready && return 0
    if [[ $status -ne 0 ]]; then
        error "WebView2 setup failed with exit status $status"
        return "$status"
    fi
    error 'WebView2 did not finish installing. Check the internet connection, then rerun ENCORE.'
    return 1
}

verify_external_wine()
{
    [[ -x $wine ]] || die "Wine executable not found: $wine"
    local version
    version=$("$wine" --version 2>/dev/null || true)
    [[ $version == wine-11.13 ]] ||
        die "Expected ENCORE's Wine 11.13 build, but $wine reports ${version:-no version}"
    wine_build_ready "$wine" ||
        die "Wine 11.13 was found, but its ENCORE runtime manifest or build artifacts are incomplete: $wine"
}

verify_installation()
{
    local -a runtime_config=()
    local runtime_file=$ROOT/.encore/runtime.conf
    local saved_prefix saved_wine saved_ableton

    [[ -x $wine ]] || die "Wine verification failed: $wine"
    validate_live_source "$live_destination" ||
        die "Ableton verification failed: $live_source_error"
    [[ -s $ableton ]] || die "Ableton verification failed: $ableton"
    vc_runtime_ready || die 'Visual C++ runtime verification failed'
    webview2_ready || die 'WebView2 Runtime verification failed'
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
    local canonical_prefix canonical_ableton canonical_live_destination cleaned_source

    [[ -n $prefix ]] || die 'The Wine prefix path may not be empty'
    [[ -n $wine ]] || die 'The Wine executable path may not be empty'
    reject_path_controls 'Wine prefix path' "$prefix"
    reject_path_controls 'Wine executable path' "$wine"
    [[ -z $ableton ]] || reject_path_controls 'Ableton executable path' "$ableton"
    [[ -z $live_source ]] || reject_path_controls 'Ableton Live source folder' "$live_source"
    prefix=$(absolute_path "$prefix")
    wine=$(absolute_path "$wine")
    default_ableton="$prefix/$ABLETON_RELATIVE"
    if [[ -n $ableton ]]; then
        ableton=$(absolute_path "$ableton")
    else
        ableton=$default_ableton
    fi
    canonical_prefix=$(readlink -m -- "$prefix") ||
        die "Could not resolve the Wine prefix path: $prefix"
    canonical_ableton=$(readlink -m -- "$ableton") ||
        die "Could not resolve the Ableton executable path: $ableton"
    case $canonical_ableton in
        "$canonical_prefix"/*) ;;
        *) die "The Ableton executable must be inside the selected Wine prefix: $prefix" ;;
    esac
    [[ ${ableton##*/} == 'Ableton Live 12 Suite.exe' ]] ||
        die 'The Ableton executable must be named "Ableton Live 12 Suite.exe"'
    [[ $(basename -- "$(dirname -- "$ableton")") == Program ]] ||
        die 'The Ableton executable must be inside its Live 12 Suite/Program folder.'
    live_destination=$(dirname -- "$(dirname -- "$ableton")")
    canonical_live_destination=$(readlink -m -- "$live_destination") ||
        die "Could not resolve the Ableton Live folder: $live_destination"
    case $canonical_live_destination in
        "$canonical_prefix"/*) ;;
        *) die 'The complete Ableton Live folder must be a child of the selected Wine prefix.' ;;
    esac
    if [[ -n $live_source ]]; then
        cleaned_source=$(clean_path_input "$live_source") ||
            die 'The Ableton Live source file URL could not be read.'
        [[ -n $cleaned_source ]] || die 'The Ableton Live source folder may not be empty'
        live_source=$(absolute_path "$cleaned_source")
    fi
}

validate_import_paths()
{
    local canonical_source canonical_destination canonical_ableton canonical_default_ableton
    canonical_ableton=$(readlink -m -- "$ableton") ||
        die "Could not resolve the Ableton executable path: $ableton"
    canonical_default_ableton=$(readlink -m -- "$default_ableton") ||
        die "Could not resolve the standard Ableton destination: $default_ableton"
    [[ $canonical_ableton == "$canonical_default_ableton" ]] ||
        die '--live-dir imports only into the standard prefix location. Omit --ableton when importing a Live folder.'
    canonical_source=$(readlink -f -- "$live_source" 2>/dev/null) ||
        die "Could not resolve the Ableton Live source folder: $live_source"
    canonical_destination=$(readlink -m -- "$live_destination") ||
        die "Could not resolve the Ableton Live destination: $live_destination"
    case $canonical_source in
        "$canonical_destination"|"$canonical_destination"/*)
            die 'The Live source folder cannot be the destination or be inside it.'
            ;;
    esac
    case $canonical_destination in
        "$canonical_source"/*)
            die 'The Live destination cannot be inside the selected source folder.'
            ;;
    esac
}

inspect_live_import_space()
{
    local probe available_kib staging_overhead_kib prerequisite_overhead_kib=0
    live_source_size_kib=$(du -sk -- "$live_source" 2>/dev/null | awk 'NR == 1 {print $1}')
    [[ $live_source_size_kib =~ ^[0-9]+$ && $live_source_size_kib -gt 0 ]] ||
        die "Could not measure the Ableton Live source folder: $live_source"
    probe=$(dirname -- "$live_destination")
    while [[ ! -e $probe && $probe != / ]]; do
        probe=$(dirname -- "$probe")
    done
    available_kib=$(df -Pk -- "$probe" 2>/dev/null | awk 'NR == 2 {print $4}')
    [[ $available_kib =~ ^[0-9]+$ ]] ||
        die "Could not measure free space for the Wine prefix: $prefix"
    staging_overhead_kib=$((live_source_size_kib / 20))
    ((staging_overhead_kib >= 524288)) || staging_overhead_kib=524288
    if [[ ! -e $live_destination && ! -L $live_destination ]]; then
        prerequisite_overhead_kib=3145728
    fi
    live_required_space_kib=$((live_source_size_kib + staging_overhead_kib + prerequisite_overhead_kib))
    if ((available_kib < live_required_space_kib)); then
        die "Not enough free space for Live and its Wine prerequisites. Need about $(((live_required_space_kib + 1048575) / 1048576)) GiB, but only $(((available_kib + 1048575) / 1048576)) GiB is available."
    fi
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
    local existing_live=0 incomplete_live=0 reuse_decided=0

    if [[ $build_only -eq 0 ]]; then
        inspect_prefix_safety
        if [[ -e $live_destination || -L $live_destination ]]; then
            if validate_live_source "$live_destination"; then
                existing_live=1
            else
                incomplete_live=1
            fi
        fi

        if [[ $replace_live -eq 1 && -z $live_source ]]; then
            die '--replace-live requires --live-dir DIR'
        fi

        if [[ $existing_live -eq 1 && -n $live_source && $replace_live -eq 0 ]]; then
            heading 'Existing Ableton installation'
            ok "Found a complete Ableton Live installation at $live_destination"
            if [[ $interactive -eq 1 ]]; then
                if ask_yes_no 'Reuse it and ignore the supplied source folder?' yes; then
                    live_source=
                    reuse_decided=1
                else
                    replace_live=1
                fi
            else
                info 'Reusing it for a safe retry; use --replace-live to replace it explicitly.'
                live_source=
                reuse_decided=1
            fi
        fi

        if [[ $incomplete_live -eq 1 ]]; then
            heading 'Incomplete Ableton folder'
            warn "The existing folder is incomplete: $live_destination"
            warn "$live_source_error"
            if [[ $interactive -eq 0 && $replace_live -eq 0 ]]; then
                die 'Refusing to merge into an incomplete Live folder. Rerun with --replace-live and --live-dir DIR.'
            fi
            if [[ -z $live_source ]]; then
                if [[ $interactive -eq 1 ]]; then
                    choose_live_source
                else
                    die 'Ableton is not installed. Supply --live-dir "/path/to/Live 12 Suite".'
                fi
            fi
            if [[ $replace_live -eq 0 ]]; then
                ask_yes_no 'Replace the incomplete folder with the selected complete copy?' no ||
                    die 'The incomplete Live folder was left unchanged.'
                replace_live=1
            fi
        fi

        if [[ -z $live_source ]]; then
            if [[ $existing_live -eq 1 ]]; then
                if [[ $interactive -eq 1 && $reuse_decided -eq 0 ]]; then
                    heading 'Existing Ableton installation'
                    ok "Found a complete Ableton Live installation at $live_destination"
                    if ! ask_yes_no 'Reuse this installation?' yes; then
                        choose_live_source
                        replace_live=1
                    fi
                fi
            elif [[ $interactive -eq 1 ]]; then
                choose_live_source
            else
                die 'Ableton is not installed. Supply --live-dir "/path/to/Live 12 Suite".'
            fi
        fi

        if [[ -n $live_source ]]; then
            validate_live_source "$live_source" || die "$live_source_error"
            validate_import_paths
            inspect_live_import_space
        fi
    else
        live_source=
        replace_live=0
    fi

    if [[ $build_mode == auto ]]; then
        if wine_build_ready "$wine"; then
            build_mode=skip
        else
            build_mode=download
            wine=$DEFAULT_WINE
        fi
    fi

    if [[ $build_mode == download ]] && ! prebuilt_host_ready; then
        die "The prebuilt runtime requires x86-64 glibc $ENCORE_GLIBC_MIN or newer. Use --build-from-source on this system."
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
    elif [[ $build_mode == skip ]]; then
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
    local dependency_description wine_description
    case $dependency_action in
        install) dependency_description='install with the system package manager' ;;
        blocked) dependency_description='missing (dry-run cannot install them)' ;;
        *) dependency_description='already available' ;;
    esac
    case $build_mode in
        build) wine_description='build/resume ENCORE Wine from source' ;;
        download) wine_description='download the verified prebuilt ENCORE Wine runtime' ;;
        *) wine_description="reuse $wine" ;;
    esac
    heading 'Setup plan'
    say "  Distribution:      $distro_name"
    say "  Wine:              $wine_description"
    [[ $build_mode != build ]] || say "  Build jobs:         $jobs"
    say "  Dependencies:       $dependency_description"
    if [[ $build_only -eq 1 ]]; then
        say "  Final action:       $([[ $configure_only -eq 1 ]] && printf 'configure Wine only' || printf 'build Wine only')"
    else
        say "  Wine prefix:        $prefix"
        say "  Ableton:            $ableton"
        say "  Ableton source:     ${live_source:-reuse existing prefix copy}"
        if [[ -n $live_source ]]; then
            say "  Import size:        about $(((live_source_size_kib + 1048575) / 1048576)) GiB"
            say "  Free space needed:  about $(((live_required_space_kib + 1048575) / 1048576)) GiB"
            say "  Existing Live:      $([[ $replace_live -eq 1 ]] && printf 'replace safely' || printf 'not present')"
        fi
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
    if [[ -n $live_source ]]; then
        info 'Live is imported by copying the complete installed folder. WebView2 may download its runtime afterward.'
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
    exec {lock_fd}<>"$lock_file" || die 'Could not open the setup lock'
    if ! flock -n "$lock_fd"; then
        owner=$(sed -n '1p' "$lock_file" 2>/dev/null || true)
        [[ $owner =~ ^[0-9]+$ ]] &&
            die "Another ENCORE setup is running as process $owner"
        die 'Another ENCORE setup is already running'
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

    case $build_mode in
        build)
            export JOBS=$jobs
            wine=$SOURCE_WINE
            export ENCORE_WINE=$wine
            if [[ $configure_only -eq 1 ]]; then
                run_stage 'Configure ENCORE Wine' "$SCRIPTS/build-wine.sh" --configure-only
            else
                run_stage 'Build ENCORE Wine from source' "$SCRIPTS/build-wine.sh"
            fi
            ;;
        download)
            run_stage 'Download verified ENCORE Wine runtime' "$SCRIPTS/download-wine-runtime.sh"
            wine=$DEFAULT_WINE
            verify_external_wine
            ;;
        *)
            ok "Reusing Wine: $wine"
            ;;
    esac

    if [[ $build_only -eq 1 ]]; then
        ok "$([[ $configure_only -eq 1 ]] && printf 'Wine configuration' || printf 'Wine build') finished successfully"
        say "Log: $log_file"
        return
    fi

    export ENCORE_PREFIX=$prefix ENCORE_WINE=$wine ENCORE_ABLETON=$ableton
    pause_for_live_to_close
    run_stage 'Register the ENCORE prefix' mark_prefix

    if [[ -n $live_source ]]; then
        run_stage 'Import Ableton Live files' import_live_files
        [[ -s $ableton ]] ||
            die "The Ableton Live files were imported, but Live was not found at $ableton"
    else
        ok 'Reusing Ableton Live already in the prefix'
    fi

    run_stage 'Initialize the Wine prefix' initialize_wine_prefix
    run_stage 'Install the Visual C++ runtime' install_vc_runtime
    run_stage 'Install the WebView2 Runtime' install_webview2_runtime

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
