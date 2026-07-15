#!/bin/sh

# Product metadata and path discovery for supported Ableton Live installations.
# This file is sourced by ENCORE scripts and intentionally does not change shell
# options or exit the caller.

encore_ableton_profile_clear()
{
    ENCORE_ABLETON_PRODUCT=
    ENCORE_ABLETON_MAJOR=
    ENCORE_ABLETON_EDITION=
    ENCORE_ABLETON_FOLDER=
    ENCORE_ABLETON_EXE=
    ENCORE_ABLETON_WM_CLASS=
    ENCORE_ABLETON_ICON_BASENAME=
}

encore_ableton_profile_from_executable()
{
    encore_ableton_profile_clear
    _encore_ableton_exe=${1##*/}

    case $_encore_ableton_exe in
        'Ableton Live 11 Suite.exe')
            ENCORE_ABLETON_MAJOR=11
            ENCORE_ABLETON_EDITION=Suite
            ;;
        'Ableton Live 11 Standard.exe')
            ENCORE_ABLETON_MAJOR=11
            ENCORE_ABLETON_EDITION=Standard
            ;;
        'Ableton Live 11 Intro.exe')
            ENCORE_ABLETON_MAJOR=11
            ENCORE_ABLETON_EDITION=Intro
            ;;
        'Ableton Live 11 Lite.exe')
            ENCORE_ABLETON_MAJOR=11
            ENCORE_ABLETON_EDITION=Lite
            ;;
        'Ableton Live 11 Trial.exe')
            ENCORE_ABLETON_MAJOR=11
            ENCORE_ABLETON_EDITION=Trial
            ;;
        'Ableton Live 12 Suite.exe')
            ENCORE_ABLETON_MAJOR=12
            ENCORE_ABLETON_EDITION=Suite
            ;;
        'Ableton Live 12 Standard.exe')
            ENCORE_ABLETON_MAJOR=12
            ENCORE_ABLETON_EDITION=Standard
            ;;
        'Ableton Live 12 Intro.exe')
            ENCORE_ABLETON_MAJOR=12
            ENCORE_ABLETON_EDITION=Intro
            ;;
        'Ableton Live 12 Lite.exe')
            ENCORE_ABLETON_MAJOR=12
            ENCORE_ABLETON_EDITION=Lite
            ;;
        'Ableton Live 12 Trial.exe')
            ENCORE_ABLETON_MAJOR=12
            ENCORE_ABLETON_EDITION=Trial
            ;;
        *)
            unset _encore_ableton_exe
            return 1
            ;;
    esac

    ENCORE_ABLETON_PRODUCT="Ableton Live $ENCORE_ABLETON_MAJOR"
    if [ -n "$ENCORE_ABLETON_EDITION" ]; then
        ENCORE_ABLETON_PRODUCT="$ENCORE_ABLETON_PRODUCT $ENCORE_ABLETON_EDITION"
    fi
    ENCORE_ABLETON_FOLDER=${ENCORE_ABLETON_PRODUCT#Ableton }
    ENCORE_ABLETON_EXE=$_encore_ableton_exe
    ENCORE_ABLETON_WM_CLASS=$(printf '%s' "$ENCORE_ABLETON_EXE" | tr '[:upper:]' '[:lower:]')
    case $ENCORE_ABLETON_EDITION in
        Suite) ENCORE_ABLETON_ICON_BASENAME=live_suite.ico ;;
        Standard) ENCORE_ABLETON_ICON_BASENAME=live_standard.ico ;;
        Intro) ENCORE_ABLETON_ICON_BASENAME=live_intro.ico ;;
        Lite) ENCORE_ABLETON_ICON_BASENAME=live_lite.ico ;;
        Trial) ENCORE_ABLETON_ICON_BASENAME=live_trial.ico ;;
    esac

    unset _encore_ableton_exe
    return 0
}

encore_ableton_path_is_supported()
{
    _encore_ableton_path=$1
    encore_ableton_profile_from_executable "$_encore_ableton_path" || {
        unset _encore_ableton_path
        return 1
    }

    case $_encore_ableton_path in
        */Program/"$ENCORE_ABLETON_EXE") ;;
        *)
            unset _encore_ableton_path
            encore_ableton_profile_clear
            return 1
            ;;
    esac

    _encore_ableton_program_dir=${_encore_ableton_path%/*}
    _encore_ableton_live_dir=${_encore_ableton_program_dir%/*}
    if [ "${_encore_ableton_live_dir##*/}" != "$ENCORE_ABLETON_FOLDER" ]; then
        unset _encore_ableton_path _encore_ableton_program_dir
        unset _encore_ableton_live_dir
        encore_ableton_profile_clear
        return 1
    fi

    unset _encore_ableton_path _encore_ableton_program_dir
    unset _encore_ableton_live_dir
    return 0
}

encore_find_ableton_executables()
{
    _encore_ableton_root=$1
    [ -d "$_encore_ableton_root" ] || {
        unset _encore_ableton_root
        return 0
    }

    find "$_encore_ableton_root" -type f \
        \( -name 'Ableton Live 11*.exe' -o -name 'Ableton Live 12*.exe' \) \
        -print | LC_ALL=C sort | while IFS= read -r _encore_ableton_found; do
            if encore_ableton_path_is_supported "$_encore_ableton_found"; then
                printf '%s\n' "$_encore_ableton_found"
            fi
        done

    unset _encore_ableton_root
}

encore_ableton_icon_for_live_root()
{
    _encore_ableton_live_root=${1%/}
    _encore_ableton_profile_ready=0

    if [ -n "${ENCORE_ABLETON_FOLDER-}" ] &&
       [ "${_encore_ableton_live_root##*/}" = "$ENCORE_ABLETON_FOLDER" ]; then
        _encore_ableton_profile_ready=1
    elif [ -d "$_encore_ableton_live_root/Program" ]; then
        _encore_ableton_icon_matches=$(encore_find_ableton_executables \
            "$_encore_ableton_live_root/Program")
        _encore_ableton_icon_match=
        _encore_ableton_icon_count=0
        if [ -n "$_encore_ableton_icon_matches" ]; then
            while IFS= read -r _encore_ableton_icon_candidate; do
                [ -n "$_encore_ableton_icon_candidate" ] || continue
                _encore_ableton_icon_match=$_encore_ableton_icon_candidate
                _encore_ableton_icon_count=$((_encore_ableton_icon_count + 1))
            done <<EOF
$_encore_ableton_icon_matches
EOF
        fi
        if [ "$_encore_ableton_icon_count" -eq 1 ]; then
            encore_ableton_profile_from_executable \
                "$_encore_ableton_icon_match" || return 1
            _encore_ableton_profile_ready=1
        fi
    fi

    if [ "$_encore_ableton_profile_ready" -ne 1 ]; then
        unset _encore_ableton_live_root _encore_ableton_profile_ready
        unset _encore_ableton_icon_matches _encore_ableton_icon_match
        unset _encore_ableton_icon_count _encore_ableton_icon_candidate
        return 1
    fi

    _encore_ableton_icon_dir=$_encore_ableton_live_root/Resources/Icons
    for _encore_ableton_icon_name in "$ENCORE_ABLETON_ICON_BASENAME" \
        generic.ico live_suite.ico live_standard.ico live_intro.ico \
        live_lite.ico live_trial.ico
    do
        if [ -f "$_encore_ableton_icon_dir/$_encore_ableton_icon_name" ]; then
            printf '%s\n' \
                "$_encore_ableton_icon_dir/$_encore_ableton_icon_name"
            unset _encore_ableton_live_root _encore_ableton_profile_ready
            unset _encore_ableton_icon_matches _encore_ableton_icon_match
            unset _encore_ableton_icon_count _encore_ableton_icon_candidate
            unset _encore_ableton_icon_dir _encore_ableton_icon_name
            return 0
        fi
    done

    unset _encore_ableton_live_root _encore_ableton_profile_ready
    unset _encore_ableton_icon_matches _encore_ableton_icon_match
    unset _encore_ableton_icon_count _encore_ableton_icon_candidate
    unset _encore_ableton_icon_dir _encore_ableton_icon_name
    return 1
}

encore_resolve_ableton_executable()
{
    _encore_ableton_prefix=$1
    _encore_ableton_configured=${2-}

    if [ -n "$_encore_ableton_configured" ]; then
        if ! encore_ableton_path_is_supported "$_encore_ableton_configured"; then
            printf 'ENCORE: unsupported Ableton executable path: %s\n' \
                "$_encore_ableton_configured" >&2
            unset _encore_ableton_prefix _encore_ableton_configured
            return 1
        fi
        printf '%s\n' "$_encore_ableton_configured"
        unset _encore_ableton_prefix _encore_ableton_configured
        return 0
    fi

    _encore_ableton_candidates=$(encore_find_ableton_executables \
        "$_encore_ableton_prefix/drive_c/ProgramData/Ableton")
    _encore_ableton_selected=
    _encore_ableton_count=0
    if [ -n "$_encore_ableton_candidates" ]; then
        while IFS= read -r _encore_ableton_candidate; do
            [ -n "$_encore_ableton_candidate" ] || continue
            _encore_ableton_selected=$_encore_ableton_candidate
            _encore_ableton_count=$((_encore_ableton_count + 1))
        done <<EOF
$_encore_ableton_candidates
EOF
    fi

    case $_encore_ableton_count in
        1)
            printf '%s\n' "$_encore_ableton_selected"
            ;;
        0)
            printf 'ENCORE: no supported Ableton Live 11 or 12 executable was found in %s\n' \
                "$_encore_ableton_prefix" >&2
            unset _encore_ableton_prefix _encore_ableton_configured
            unset _encore_ableton_candidates _encore_ableton_selected
            unset _encore_ableton_count _encore_ableton_candidate
            return 1
            ;;
        *)
            printf 'ENCORE: multiple Ableton executables were found; rerun install.sh to select one\n' >&2
            unset _encore_ableton_prefix _encore_ableton_configured
            unset _encore_ableton_candidates _encore_ableton_selected
            unset _encore_ableton_count _encore_ableton_candidate
            return 1
            ;;
    esac

    unset _encore_ableton_prefix _encore_ableton_configured
    unset _encore_ableton_candidates _encore_ableton_selected
    unset _encore_ableton_count _encore_ableton_candidate
    return 0
}
