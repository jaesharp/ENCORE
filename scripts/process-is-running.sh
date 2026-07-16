#!/bin/sh
set -eu

[ "$#" -eq 1 ] || {
    printf 'usage: %s EXECUTABLE\n' "$0" >&2
    exit 2
}

expected=$1
expected_base=${expected##*/}

for command_line in /proc/[0-9]*/cmdline; do
    [ -r "$command_line" ] || continue
    executable=$(tr '\000' '\n' < "$command_line" 2>/dev/null | sed -n '1p') || continue
    # Direct match: the process still carries the path it was launched with.
    [ "$executable" = "$expected" ] && exit 0
    # Wine rewrites argv[0] to the application's DOS path
    # (C:\...\Ableton Live 12 Suite.exe), so comparing only the unix path
    # false-negatives on every running Live. For Windows executables, compare
    # basenames too, across both path separators. Scoped to *.exe so a plain
    # unix basename (e.g. "bash") can never match unrelated processes.
    case $expected_base in
        *.[eE][xX][eE]) ;;
        *) continue ;;
    esac
    unix_base=${executable##*/}
    dos_base=${unix_base##*\\}
    [ "$dos_base" = "$expected_base" ] && exit 0
done

exit 1
