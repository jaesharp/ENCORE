# Present/resize client rects in the window's DPI context (`dlls/wined3d/swapchain.c`, `dlls/dxgi/swapchain.c`)

> Ported from **shibco/ableton-linux** `patches/0023` + `0024` (fixes to
> LGPL-2.1+ Wine), regenerated against wine-11.13. Analysis condensed from
> that project's `notes/ABLETON-WINE-PIANOTEQ-DPI-GHOST-BUG.md`. Patch file:
> [`patches/wine/150-present-dpi-context.patch`](../../patches/wine/150-present-dpi-context.patch).

Correctness hardening for **mixed-DPI processes**: swapchain presents address
physical pixels, so the rects they use must come from the window's own DPI
space, not whichever thread happens to call.

## Problem

wined3d and dxgi queried present destination rects and the
`ResizeBuffers(0,0)` auto-size in the **calling thread's** DPI context. Live
is a deliberately mixed-DPI process — per-monitor-aware windows next to
DPI-unaware plugin and CEF threads — so at any `LogPixels > 96` a rect queried
from the "wrong" thread comes back in the wrong space, and presents or
auto-resizes are mis-sized.

This matters directly to ENCORE's 125%+ display-scale support: at 100%
(`LogPixels=96`) all spaces coincide and the bug is invisible.

## What the patch does

- Query present/resize client rects **in the window's DPI context**
  (`0023`), so the sizes match the physical surface being presented to.
- Keep the new present/resize diagnostics at **trace** level (`0024`);
  inspect with `WINEDEBUG=trace+d3d`.

## What it does *not* fix

The Pianoteq "half-size ghost" flicker that motivated shibco's investigation
is a **host-configuration issue**, not a Wine bug: with Live's *Auto-Scale
Plugin Window* enabled, the editor is hosted DPI-unaware and Live's own size
negotiation never converges. The fix is to right-click the device header and
untick **Auto-Scale Plugin Window** (a standard first-launch step — see
[../troubleshooting.md](../troubleshooting.md)). This patch hardens the
present path for mixed-DPI callers; it does not remove that loop.

## Verification

- Compiles warning-clean (`dxgi.dll` and `wined3d.dll`, both PE arches).
- Behavioral checks belong to the 125% display-scale validation pass.
