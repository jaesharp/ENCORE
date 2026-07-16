#!/bin/sh

# Sourceable display-scale detection for ENCORE.
#
# encore_detect_scale prints the primary monitor's scale factor ("1", "1.25",
# "2", ...) on stdout and returns 0, or returns 1 when no probe can answer (a
# headless session, or a compositor none of the probes understand). Probes run
# in order until one succeeds: GNOME (Mutter), KDE (KScreen), sway, Hyprland,
# and finally the generic Xft.dpi X resource.
#
# Adapted from shibco/ableton-linux's scripts/detect-scale.sh, rewritten to POSIX
# subshell-scoped helpers (no 'local', no bashisms) so it can be sourced by the
# strict `#!/bin/sh` prefix scripts. Each probe runs inside command substitution,
# so its working variables never leak into the caller.

# GNOME/Mutter: logical monitors serialize as "(x, y, scale, uint32 transform, primary, ...".
_encore_scale_gnome() {
    _egs_state=$(timeout 5 gdbus call --session \
        --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null) || return 1
    _egs_rows=$(printf '%s\n' "$_egs_state" \
        | grep -oE '\(-?[0-9]+, -?[0-9]+, [0-9]+(\.[0-9]+)?, uint32 [0-9]+, (true|false)') || return 1
    [ -n "$_egs_rows" ] || return 1
    _egs_all=$(printf '%s\n' "$_egs_rows" | awk -F', ' '{print $3}' | sort -u)
    _egs_prim=$(printf '%s\n' "$_egs_rows" | awk -F', ' '$5=="true"{print $3; exit}')
    [ -n "$_egs_prim" ] || _egs_prim=$(printf '%s\n' "$_egs_rows" | awk -F', ' 'NR==1{print $3}')
    [ -n "$_egs_prim" ] || return 1
    if [ "$(printf '%s\n' "$_egs_all" | wc -l)" -gt 1 ]; then
        printf 'ENCORE: monitors run mixed scales (%s) -- using the primary monitor (%s)\n' \
            "$(printf '%s' "$_egs_all" | tr '\n' ' ')" "$_egs_prim" >&2
    fi
    printf '%s\n' "$_egs_prim"
}

# KDE: Plasma 5 prints one "Output:" line per screen with "primary"; Plasma 6
# splits blocks and marks the primary "priority 1".
_encore_scale_kde() {
    command -v kscreen-doctor >/dev/null 2>&1 || return 1
    _eks_out=$(timeout 5 kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g') || return 1
    [ -n "$_eks_out" ] || return 1
    _eks_prim=$(printf '%s\n' "$_eks_out" | awk '
        /^Output:/ { blk++ }
        blk {
            if (match($0, /Scale: [0-9.]+/)) s[blk] = substr($0, RSTART+7, RLENGTH-7)
            if ($0 ~ / primary/ || $0 ~ /priority 1([^0-9]|$)/) p[blk] = 1
        }
        END {
            for (i = 1; i <= blk; i++) if (p[i] && s[i] != "") { print s[i]; exit }
            for (i = 1; i <= blk; i++) if (s[i] != "")          { print s[i]; exit }
        }')
    [ -n "$_eks_prim" ] || return 1
    printf '%s\n' "$_eks_prim"
}

_encore_scale_sway() {
    command -v swaymsg >/dev/null 2>&1 || return 1
    [ -n "${SWAYSOCK:-}" ] || return 1
    _esw_scale=$(timeout 5 swaymsg -t get_outputs 2>/dev/null \
        | grep -oE '"scale": *[0-9.]+' | awk 'NR==1{gsub(/[^0-9.]/,""); print}')
    [ -n "$_esw_scale" ] || return 1
    printf '%s\n' "$_esw_scale"
}

_encore_scale_hyprland() {
    command -v hyprctl >/dev/null 2>&1 || return 1
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || return 1
    _ehy_scale=$(timeout 5 hyprctl monitors 2>/dev/null \
        | grep -oE 'scale: [0-9.]+' | awk 'NR==1{print $2}')
    [ -n "$_ehy_scale" ] || return 1
    printf '%s\n' "$_ehy_scale"
}

# Generic fallback: Xft.dpi / 96 gives the effective scale on plain X sessions.
_encore_scale_xftdpi() {
    [ -n "${DISPLAY:-}" ] || return 1
    command -v xrdb >/dev/null 2>&1 || return 1
    _exd_dpi=$(timeout 5 xrdb -query 2>/dev/null | awk '$1=="Xft.dpi:"{print $2; exit}')
    [ -n "$_exd_dpi" ] || return 1
    awk -v d="$_exd_dpi" 'BEGIN{ printf "%g\n", d/96 }'
}

# Public entry point. Runs in its own subshell with `set +e` so a probe that
# exits non-zero mid-pipeline just falls through to the next one, regardless of
# the caller's shell options.
encore_detect_scale() (
    set +e
    for _eds_probe in _encore_scale_gnome _encore_scale_kde \
                      _encore_scale_sway _encore_scale_hyprland _encore_scale_xftdpi; do
        _eds_scale=$($_eds_probe) || continue
        [ -n "$_eds_scale" ] || continue
        # normalize: 1.0 -> 1, 1.250 -> 1.25
        printf '%s\n' "$_eds_scale" | awk '{ printf "%g\n", $1 }'
        exit 0
    done
    exit 1
)
