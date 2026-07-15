# Host-file drag-and-drop (user32 + win32u + winex11.drv)

## Problem

Dragging a sample from the Linux file manager into Live is an XDND
conversation that Wine translates into OLE drag-and-drop (`IDropTarget`) or,
for older targets, a `WM_DROPFILES` message carrying `CF_HDROP` data. Upstream,
this path had DPI bugs (drop coordinates computed in the wrong DPI context, so
drops landed on the wrong widget at 200% scale), lifecycle bugs (a drop target
could be entered and never left, or `DragOver` skipped entirely for
quick drops), leaks on every failure path, and an X11 race where a queued
`XdndLeave` could overtake Wine's acceptance reply — the classic
"drag into Live does nothing" symptom.

## What the patch does

### Raw coordinates + per-target mapping

The XDND position now travels as **raw physical screen coordinates**
(`drag_drop_drag_params.point`, documented in `include/ntuser.h`) instead of
being converted once in the kernel layer. A new
`WINE_DRAG_DROP_MAP_POINT` sub-call of `NtUserDragDropCall`
(`dlls/win32u/clipboard.c`) converts a raw point into virtual coordinates
**inside a specific window's DPI awareness context**
(`get_window_dpi_awareness_context` → `map_rect_raw_to_virt`). The user32 side
(`map_raw_drop_point()`) calls it once for hit-testing and again for the actual
target window, so a Live window and a system-DPI-aware plug-in window each see
coordinates correct for themselves.

### Correct OLE lifecycle (`dlls/user32/clipboard.c`)

The `data_object` now remembers which window registered the drop target
(`drop_target_hwnd`) and that window's DPI context
(`drop_target_dpi_context`). A single helper, `release_drop_target()`,
performs `IDropTarget_DragLeave` (under the target's DPI context) and clears
the state; it is called from every exit path — object release, a new drag
entering, target change, mapping failure, and after `Drop`. Behavioural fixes:

- `DragEnter` is followed by `DragOver` **even for the first position** — the
  source may drop without sending another position, and `DragEnter`'s effect
  is intentionally ignored for Windows compatibility (the comment in the code
  spells this out).
- `DragEnter`/`DragOver`/`Drop` all run under the drop target's DPI awareness
  context, with the point mapped for the *target* window.
- The `WM_DROPFILES` fallback (`drag_drop_drop`, `drag_drop_post`) determines
  client-area vs non-client (`DROPFILES.fNC`) in the target's DPI context,
  checks `GlobalLock` results, frees the `HGLOBAL` when `PostMessageW` fails,
  and reuses the remembered target window instead of re-hit-testing a stale
  point.

### Kernel-side context switching (`dlls/win32u/clipboard.c`)

`WINE_DRAG_DROP_DRAG`, `DROP`, and `POST` now run their user-mode callbacks
under the event window's DPI awareness context, matching how user32 interprets
the raw point on the way back.

### The XDND flush (`dlls/winex11.drv/event.c`)

After answering an `XdndPosition` with an `XdndStatus`, the driver now calls
`XFlush`. Sources that stream position events without waiting for a reply
could otherwise have their `XdndLeave` processed while Wine's acceptance still
sat in the output buffer — the drop would be silently cancelled.

## Key files

| File | Role |
| --- | --- |
| `dlls/user32/clipboard.c` | OLE DnD lifecycle, `CF_HDROP`/`WM_DROPFILES` synthesis (+275) |
| `dlls/win32u/clipboard.c` | DPI-context plumbing, `WINE_DRAG_DROP_MAP_POINT` |
| `dlls/winex11.drv/event.c` | `XFlush` after `XdndStatus` |
| `include/ntuser.h` | raw-coordinate contract, new enum value |

## Runtime toggles

None — this path is always active. It interacts with the DPI value chosen at
install time (see [../installer.md](../installer.md)) and with the
per-window contexts introduced in
[windowing-and-hidpi.md](windowing-and-hidpi.md).

## How to verify

At 200% scale, drag audio files from the file manager into: (1) Live's browser,
(2) an arbitrary clip slot, (3) a plug-in window's file field. Files must land
on the widget under the cursor, and repeated drag-in/drag-out cycles must not
leave Live thinking a drag is still in progress. `WINEDEBUG=+ole,+clipboard`
shows the `DragEnter`/`DragOver`/`Drop` sequence; a missing `DragLeave` after
cancel is a regression.
