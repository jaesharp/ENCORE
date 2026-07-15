#!/bin/sh
set -eu

[ "$#" -eq 1 ] || {
    printf 'usage: %s EXECUTABLE\n' "$0" >&2
    exit 2
}

expected=$1
for command_line in /proc/[0-9]*/cmdline; do
    [ -r "$command_line" ] || continue
    executable=$(tr '\000' '\n' < "$command_line" 2>/dev/null | sed -n '1p') || continue
    [ "$executable" = "$expected" ] && exit 0
done

exit 1
