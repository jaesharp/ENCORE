#!/bin/sh
set -eu

stable_logical_limit=8
host_cpu_limit=1024

if [ "$#" -gt 2 ]; then
    printf 'usage: %s [online-logical-cpu-count [allowed-cpu-list]]\n' "$0" >&2
    exit 2
fi

if [ "$#" -ge 1 ]; then
    online_cpus=$1
else
    online_cpus=
    if command -v getconf >/dev/null 2>&1; then
        online_cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
    fi
fi

case $online_cpus in
    ''|*[!0-9]*|0)
        [ "$#" -eq 0 ] && exit 0
        printf 'invalid online logical CPU count: %s\n' "$online_cpus" >&2
        exit 2
        ;;
esac

if [ "$#" -eq 2 ]; then
    allowed_list=$2
elif [ "$#" -eq 1 ]; then
    allowed_list="0-$((online_cpus - 1))"
else
    allowed_list=
    if [ -r /proc/self/status ] && command -v awk >/dev/null 2>&1; then
        allowed_list=$(awk '/^Cpus_allowed_list:/ { print $2; exit }' \
            /proc/self/status 2>/dev/null || true)
    fi
    [ -n "$allowed_list" ] || exit 0
fi

analysis=$(awk -v list="$allowed_list" -v online="$online_cpus" -v host_limit="$host_cpu_limit" 'BEGIN {
    range_count = split(list, ranges, ",")
    if (!range_count) exit 1

    for (i = 1; i <= range_count; ++i) {
        part_count = split(ranges[i], limits, "-")
        if (part_count > 2 || limits[1] !~ /^[0-9]+$/ ||
            (part_count == 2 && limits[2] !~ /^[0-9]+$/)) exit 1
        first = limits[1] + 0
        last = part_count == 2 ? limits[2] + 0 : first
        if (last < first || last > 1048575) exit 1

        for (cpu = first; cpu <= last; ++cpu) {
            if (seen[cpu]) exit 1
            seen[cpu] = 1
            ++total
            if (cpu < host_limit) ++supported
        }
    }

    dense = total == online
    if (dense) {
        for (cpu = 0; cpu < online; ++cpu) {
            if (!seen[cpu]) {
                dense = 0
                break
            }
        }
    }
    printf "%u %u\n", supported, dense
}' 2>/dev/null) || {
    [ "$#" -eq 0 ] && exit 0
    printf 'invalid allowed CPU list: %s\n' "$allowed_list" >&2
    exit 2
}

set -- $analysis
supported_cpus=$1
dense_native_set=$2

[ "$supported_cpus" -gt 0 ] || exit 0
if [ "$supported_cpus" -gt "$stable_logical_limit" ]; then
    printf '%s\n' "$stable_logical_limit"
elif [ "$dense_native_set" -eq 0 ]; then
    printf '%s\n' "$supported_cpus"
fi
