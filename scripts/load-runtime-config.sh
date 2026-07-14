#!/bin/sh

# Load setup-selected runtime paths without evaluating the file as shell code.
# The caller must define ROOT before sourcing this module.

_encore_runtime_config=${ENCORE_RUNTIME_CONFIG:-"$ROOT/.encore/runtime.conf"}
_encore_runtime_header=
_encore_runtime_prefix=
_encore_runtime_wine=
_encore_runtime_ableton=
_encore_runtime_extra=
_encore_runtime_valid=1
_encore_prefix_was_set=${ENCORE_PREFIX+x}
_encore_wine_was_set=${ENCORE_WINE+x}
_encore_ableton_was_set=${ENCORE_ABLETON+x}

if [ -e "$_encore_runtime_config" ] || [ -L "$_encore_runtime_config" ]; then
    if [ ! -f "$_encore_runtime_config" ] || [ ! -r "$_encore_runtime_config" ]; then
        printf 'ENCORE: runtime configuration is not a readable file: %s\n' \
            "$_encore_runtime_config" >&2
        exit 1
    fi
    {
        IFS= read -r _encore_runtime_header || _encore_runtime_valid=0
        IFS= read -r _encore_runtime_prefix || _encore_runtime_valid=0
        IFS= read -r _encore_runtime_wine || _encore_runtime_valid=0
        IFS= read -r _encore_runtime_ableton || _encore_runtime_valid=0
        if IFS= read -r _encore_runtime_extra || [ -n "$_encore_runtime_extra" ]; then
            _encore_runtime_valid=0
        fi
    } <"$_encore_runtime_config"

    if [ "$_encore_runtime_valid" = 1 ] &&
            [ "$_encore_runtime_header" = ENCORE_RUNTIME_V1 ] &&
            [ -n "$_encore_runtime_prefix" ] &&
            [ -n "$_encore_runtime_wine" ] &&
            [ -n "$_encore_runtime_ableton" ]; then
        case $_encore_runtime_prefix in /*) ;; *) _encore_runtime_prefix=$ROOT/$_encore_runtime_prefix ;; esac
        case $_encore_runtime_wine in /*) ;; *) _encore_runtime_wine=$ROOT/$_encore_runtime_wine ;; esac
        case $_encore_runtime_ableton in /*) ;; *) _encore_runtime_ableton=$ROOT/$_encore_runtime_ableton ;; esac

        [ "$_encore_prefix_was_set" = x ] || ENCORE_PREFIX=$_encore_runtime_prefix
        [ "$_encore_wine_was_set" = x ] || ENCORE_WINE=$_encore_runtime_wine
        if [ "$_encore_ableton_was_set" != x ] && [ "$_encore_prefix_was_set" != x ]; then
            ENCORE_ABLETON=$_encore_runtime_ableton
        fi
    else
        printf 'ENCORE: invalid runtime configuration: %s (remove it, then rerun install.sh)\n' \
            "$_encore_runtime_config" >&2
        exit 1
    fi
fi

unset _encore_runtime_config _encore_runtime_header _encore_runtime_prefix
unset _encore_runtime_wine _encore_runtime_ableton _encore_runtime_extra
unset _encore_runtime_valid
unset _encore_prefix_was_set _encore_wine_was_set _encore_ableton_was_set
