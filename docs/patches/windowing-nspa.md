# Reentrant `WM_WINDOWPOSCHANGED` suppression (win32u)

`patches/wine/31-windowing-nspa.patch` — the second half of the high-DPI
windowing work, ported from **shibco/ableton-linux** (NSPA patches 0003/0004,
LGPL — the same license as Wine). The first half, the custom-NC decoration
gate, lives in [windowing-and-hidpi.md](windowing-and-hidpi.md) (patch `30`).

## Problem

Live's main window is custom-non-client: it sizes itself from inside its own
`WM_WINDOWPOSCHANGED` handler. At high display scale the round trip through the
WM stops converging: Live's autosize handler re-drives `SetWindowPos` from
inside the handler, Wine sends another `WM_WINDOWPOSCHANGED` for the nested
call, and the cycle repeats forever. The visible symptoms are the main window
continuously resizing by a small amount and one core pinned (80–99%) while Live
is otherwise idle.

## What the patch does

`set_window_pos` (`dlls/win32u/window.c`) tracks the `WM_WINDOWPOSCHANGED` send
in flight on the current thread — two new fields on `user_thread_info`
(`dlls/win32u/ntuser_private.h`):

- `reentrant_wpchanged_hwnd` — the window a send is currently inside;
- `reentrant_wpchanged_depth` — the nesting depth of sends.

Before sending `WM_WINDOWPOSCHANGED`, it computes whether this call is a
**nested, size-only re-entry on the same top-level window**: the thread is
already inside a send for this exact `hwnd`, the window is not a child, the
flags carry `SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER`,
and none of `SWP_NOSIZE`/`SWP_SHOWWINDOW`/`SWP_HIDEWINDOW` are set. If so the
message is dropped — the geometry has still been applied; only the re-notify
that would re-enter the application's handler is suppressed, which breaks the
feedback loop after the first round.

The state is **per-thread**, not process-global, so two windows resizing on
different threads can never suppress each other's notifications (a cross-thread
race in the original NSPA formulation).

## Key files

| File | Role |
| --- | --- |
| `dlls/win32u/window.c` | detection + suppression around the `WM_WINDOWPOSCHANGED` send in `set_window_pos` |
| `dlls/win32u/ntuser_private.h` | the two per-thread tracking fields on `user_thread_info` |

## Why this is a separate patch from `30`

`bootstrap-wine.sh` stages the whole series with one `git apply --cached
patches/wine/*.patch`, which cannot stage two patches that modify the same
function. The custom-NC gate belongs in `get_mwm_decorations`, which patch `30`
already rewrites — so the gate is folded there, and this patch carries only the
`set_window_pos` suppression (disjoint functions, same file).

## Runtime toggles

None. The suppression is inert unless an application actually re-enters
`SetWindowPos` with a size-only request from inside its own
`WM_WINDOWPOSCHANGED` handler.

## Caveats

- An application that *legitimately* re-enters with a size-only `SetWindowPos`
  on the same window from its handler loses exactly one notification per
  nesting level; the position/size itself is always applied.
- Both this patch and the patch-`30` gate matter only once the prefix runs
  with the HiDPI matched-set (`LogPixels` + IFEO `dpiAwareness=2` — applied by
  `scripts/set-dpi.sh` / `configure-prefix.sh`); at 96 DPI the loop does not
  trigger.

## How to verify

At true 200% (X server at 192 DPI — e.g. `Xvfb :50 -dpi 192` — with
`LogPixels=192` and the Live executable's IFEO `dpiAwareness=2` set, fresh
`wineserver`): launch Live and watch the main window geometry (`xwininfo` /
`xdotool getwindowgeometry` in a loop). Healthy: zero unsolicited geometry
changes over 45s and idle-level CPU. Without the patch the window churns
continuously and a core pins.
