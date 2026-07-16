# Layered-attribute sync to the scaled surface (`dlls/win32u/dce.c`)

> Ported from **shibco/ableton-linux** `patches/0015` (a fix to LGPL-2.1+
> Wine), regenerated against wine-11.13. Analysis condensed from that
> project's `notes/ABLETON-WINE-PLUGIN-TITLEBAR-BUG.md`. Patch file:
> [`patches/wine/130-layered-attr-sync.patch`](../../patches/wine/130-layered-attr-sync.patch).

Fixes translucent layered windows rendering as **opaque black rectangles** —
most visibly the soft drop shadows JUCE draws around plugin popup menus
(`DropShadower` windows). Upstreaming candidate.

## Problem

For DPI-virtualized (surface-scaled) windows, `scaled_surface_flush()`
forwarded the layered-window attributes — `color_key`, `alpha_bits`,
`alpha_mask` — to the target x11 surface **only when the window shape
changed**. A layered window that never sets a shape (JUCE's shadow windows
are plain rectangles) never gets its per-pixel alpha across; the x11 surface
then treats the content as opaque and `x11drv_surface_flush()` ORs
`0xff000000` into every pixel. Premultiplied, mostly-transparent black —
a soft shadow — becomes a solid black box around the popup.

## What the patch does

Sync the layered attributes to the scaled surface **on every flush** (a no-op
when they are unchanged), so per-pixel alpha reaches the X surface regardless
of whether a shape was ever set.

## Verification

- Compiles warning-clean (`win32u.so`).
- Behavioral: JUCE popup drop shadows render as soft translucency instead of
  black rectangles.
- Screenshot caveat from shibco: `XGetImage`-based screenshots flatten ARGB
  without blending — verify translucency on the live screen.
