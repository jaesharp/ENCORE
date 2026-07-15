# Wine patches

ENCORE patches Wine (revision `6eb2e4c32cc9e271856146df11ed3a5c2cf29234`) with a
set of semantic patch files in `patches/wine/`, applied in **sorted (filename)
order** to the pinned checkout by `scripts/bootstrap-wine.sh`. Together they are
the complete source delta ENCORE requires — the xdg-desktop-portal file picker,
HiDPI/Xwayland and VST3 window handling, DXGI vblank, dynamic menu theming,
cpuset-aware CPU topology, stale-thread recovery, host-file drag-and-drop, and
assorted runtime fixes.

Splitting the delta into per-subsystem files keeps each area independently
reviewable while producing exactly the same patched tree as one combined patch
(the files touch disjoint sets of Wine sources, so apply order does not affect
the result). The combined SHA-256 of the sorted files — `encore_patch_sha256`
in `scripts/common.sh` — is ENCORE's patch identity, recorded in build stamps
and the prebuilt-runtime `.encore-runtime` manifest and verified on every
install.
