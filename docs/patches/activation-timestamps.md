# Real timestamps in `_NET_ACTIVE_WINDOW` requests (`dlls/winex11.drv/window.c`)

> Ported from **shibco/ableton-linux** `patches/0017` (a fix to LGPL-2.1+
> Wine), regenerated against wine-11.13. Analysis condensed from that
> project's `notes/ABLETON-WINE-INPUT-BUG.md`. Patch file:
> [`patches/wine/120-activation-timestamps.patch`](../../patches/wine/120-activation-timestamps.patch).

Stops a single dropped window-activation request from wedging activation for
the whole session under strict window managers. Upstreaming candidate.

## Problem

When Wine wants a window activated it sends the WM a `_NET_ACTIVE_WINDOW`
client message. winex11 sent these with **timestamp 0** — and window managers
with strict focus-stealing prevention (GNOME ≥ 50 mutter notably) silently
drop zero-timestamp requests. Wine's pending-request dedup then suppresses
every further request while the first is "in flight", and the unacknowledged
serial blocks foreground sync:

- application menus open-then-instantly-close, or not at all;
- keyboard shortcuts go inert (keyboard follows the compositor's focus);
- clicks on a not-yet-active window die in the `WM_MOUSEACTIVATE` dance.

One dropped request wedges the session.

## What the patch does

Send the **last real input timestamp** in activation requests, and re-send a
pending request when a newer input timestamp exists — so even if a WM drops
one request, the next user interaction carries a fresh, credible timestamp
and activation self-heals.

## Verification

- Compiles warning-clean (`winex11.so`).
- Behavioral: on a WM with focus-stealing prevention, menus/shortcuts keep
  working across the session instead of wedging after the first dropped
  activation.

## Note for ENCORE's targets

The hard-wedge repro is mutter-specific, but sending real timestamps is
correct EWMH behavior everywhere (MATE/Marco, KDE, Xfce included) and the
patch is inert where the WM was lenient.
