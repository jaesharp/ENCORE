# Report the drawable's real visual in `set_dc_drawable` (`dlls/winex11.drv/{init.c,window.c}`)

> Ported from **shibco/ableton-linux** `patches/0026` (a fix to LGPL-2.1+
> Wine), regenerated against wine-11.13. Analysis condensed from that
> project's `notes/ABLETON-WINE-GL-PLUGIN-EDITOR-CRASH-BUG.md`. Patch file:
> [`patches/wine/140-gl-editor-visual.patch`](../../patches/wine/140-gl-editor-visual.patch).

Prevents a deterministic `BadMatch` X error — which wedges the whole process —
when a GL-rendered plugin editor presents onto a window whose X visual differs
from the default. Complements [opengl-srgb.md](opengl-srgb.md) for GL plugin
editors. Upstreaming candidate.

## Problem

Wine composites an OpenGL child surface onto its top-level window in
`X11DRV_client_surface_present` via a blit to a display DC. Pointing the DC at
the window (`set_dc_drawable` → the `X11DRV_SET_DRAWABLE` escape) carried **no
visual**, which the xrender driver reads as "keep the current pict format" —
the depth-24 root format on a fresh DC.

Harmless while the window is depth-24. But present a GL surface onto a
**depth-32 ARGB** top-level and `XRenderCreatePicture` fails with `BadMatch`
(a window Picture's format must match the window's visual); Xlib's default
error handler then wedges the UI — in shibco's repro (JUCE/OpenGL editors,
e.g. Chow Tape Model), the editor collapses to 1×1 and Live needs a force
quit.

## What the patch does

1. `init.c set_dc_drawable()`: query the drawable's actual visual
   (`XGetWindowAttributes`) and pass it in the escape, so the DC selects a
   pict format matching the real depth (depth-32 gets `A8R8G8B8`). Non-window
   drawables (GLX pbuffers) keep the old behavior.
2. `window.c X11DRV_ReleaseDC()` (hardening): the escape's visual field was
   **uninitialized stack garbage** — now set to the root window's default
   visual.

## Applicability to ENCORE's base

In shibco's series the depth-32 editor windows come from their native-titlebar
work (their `0014`), which ENCORE has **not** adopted — so the common trigger
is absent here. The patch is still taken as correctness hardening: the
uninitialized-escape bug is real regardless, and any path that hands a plugin
editor an ARGB visual (compositor configurations, future windowing work)
would otherwise crash the host.
