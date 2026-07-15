# Wine patches

`encore-wine.patch` is the complete patch exported from Wine revision `6eb2e4c32cc9e271856146df11ed3a5c2cf29234`. It includes all locally changed or added paths used by the current build, including the portal, HiDPI/Xwayland, VST3 hosting, DXGI vblank, dynamic menu theming, cpuset-aware CPU topology, stale-thread recovery, and host-file drag-and-drop compatibility work.

The guided installer applies this patch automatically to the pinned Wine checkout. It is the complete source delta required by ENCORE.
