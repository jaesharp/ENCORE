# The ENCORE Wine patch

`patches/encore-wine.patch` is the complete source delta that turns an upstream
Wine checkout into "ENCORE Wine" — the runtime that runs Ableton Live 11 and 12.
It is the intellectual core of the project: everything else in the repository
exists to build, apply, download, verify, or configure this patch.

The default install downloads a **prebuilt runtime** built from exactly this
patch; its `.encore-runtime` manifest records the patch's SHA-256 and is checked
before activation (see [../building.md](../building.md)). A source build applies
the patch locally via `bootstrap-wine.sh`.

## Canonical build facts

These values are defined here and referenced from every other document. If they
change, change them here first.

| Fact | Value | Defined in |
| --- | --- | --- |
| Pinned upstream revision | `6eb2e4c32cc9e271856146df11ed3a5c2cf29234` | `scripts/common.sh`, `install.sh` (`WINE_REVISION`) |
| Upstream remote | `https://gitlab.winehq.org/wine/wine.git` | `scripts/common.sh` (`WINE_REMOTE`) |
| Resulting version string | `wine-11.13` | verified by `build-wine.sh`, `download-wine-runtime.sh`, and `wine_build_ready()` |
| Prebuilt runtime revision | `r1` (`encore-wine-11.13-r1-…`) | `scripts/common.sh` (`ENCORE_RUNTIME_REVISION`) |
| Patch size | 40 files, 4549 insertions, 163 deletions | `git apply --stat patches/encore-wine.patch` |

## Scope boundary

This document set describes **the pinned patch as it exists in this repository**.
It is not upstream Wine documentation and it does not track upstream Wine. When
the patch is rebased onto a newer Wine revision, function names, hunk locations,
and behaviour can change; treat these pages as a snapshot tied to the revision
above and re-verify against source when the revision moves.

## The PE / Unix split

Several features (most visibly the [portal file picker](portal-file-picker.md))
are split across Wine's PE/Unix boundary, and the same pattern recurs:

- The **PE side** runs as Windows code inside the emulated process. It marshals
  Win32 structures into flat parameter blocks and calls across the boundary with
  `WINE_UNIX_CALL` / `__wine_unix_call`.
- The **Unix side** is a native `.so` built from a source file that opens with
  `#pragma makedep unix`. It may link or `dlopen` real Linux libraries
  (libdbus, etc.) and talk to the host system.
- The two sides share a private `unixlib.h` that defines the parameter structs
  and a function-index `enum`; the Unix side exports a matching
  `__wine_unix_call_funcs[]` table.

Knowing this pattern makes the portal code (and any future host-integration
feature) much easier to read.

## Feature index

The patch set lives as a numbered series in [`patches/wine/`](../../patches/wine/),
applied in order by `bootstrap-wine.sh`. The first six subsystems (`10`–`60`) are
ENCORE's original delta; nine further patches (`70`–`150`) are ported from
**shibco/ableton-linux** (LGPL Wine fixes, attributed in each patch header and
page) via the `shibco-dev` integration branch. Each subsystem has its own page.

| Page | Features | Primary source |
| --- | --- | --- |
| [portal-file-picker.md](portal-file-picker.md) | Native xdg-desktop-portal file chooser | `dlls/comdlg32/*` |
| [cpu-and-threads.md](cpu-and-threads.md) | `WINE_CPU_TOPOLOGY` override; stale-thread recovery | `dlls/ntdll/unix/*`, `server/*` |
| [windowing-and-hidpi.md](windowing-and-hidpi.md) | VST3 plugin windows; HiDPI config-rounding | `dlls/win32u/*`, `dlls/winex11.drv/*` |
| [drag-and-drop.md](drag-and-drop.md) | Host-file drag-and-drop | `dlls/user32/clipboard.c`, `dlls/win32u/clipboard.c` |
| [menu-theming.md](menu-theming.md) | Dynamic menu-bar theming | `dlls/win32u/menu.c` |
| [runtime-fixes.md](runtime-fixes.md) | DXGI vblank pacing; msvcp `basic_istream`; mount-reparse | `dlls/dxgi`, `dlls/msvcp*`, `dlls/ntdll/unix/file.c` |
| [audio-endpoint-friendlyname.md](audio-endpoint-friendlyname.md) | mmdevapi endpoint FriendlyName re-wrap crash fix *(shibco)* | `dlls/mmdevapi/devenum.c` |
| [midi-hotplug.md](midi-hotplug.md) | MIDI controller hotplug re-subscribe *(shibco)* | `dlls/winealsa.drv/alsamidi.c` |
| [opengl-srgb.md](opengl-srgb.md) | EGL sRGB-capable pixel formats *(shibco)* | `dlls/win32u/opengl.c`, `dlls/winex11.drv/opengl.c` |
| [push2-display.md](push2-display.md) | Ableton Push 2 display over host USB (libusb-1.0 bridge) *(shibco)* | `dlls/libusb-1.0/*` |
| [shared-session-coherence.md](shared-session-coherence.md) | Shared-session view coherence (menu freezes, VST3 window creation) *(shibco)* | `dlls/win32u/winstation.c`, `server/mapping.c` |
| [activation-timestamps.md](activation-timestamps.md) | Real `_NET_ACTIVE_WINDOW` timestamps (activation wedge) *(shibco)* | `dlls/winex11.drv/window.c` |
| [layered-attr-sync.md](layered-attr-sync.md) | Layered-attribute sync (black popup shadows) *(shibco)* | `dlls/win32u/dce.c` |
| [gl-editor-visual.md](gl-editor-visual.md) | Real drawable visual in `set_dc_drawable` (GL editor BadMatch) *(shibco)* | `dlls/winex11.drv/{init.c,window.c}` |
| [present-dpi-context.md](present-dpi-context.md) | Present/resize rects in the window's DPI context *(shibco)* | `dlls/{wined3d,dxgi}/swapchain.c` |

## Full diffstat by subsystem

Regenerate at any time with:

```sh
git apply --stat patches/encore-wine.patch
```

Summary of the 40 files:

- **comdlg32 (portal file picker):** `Makefile.in`, `cdlg.h`, `cdlg32.c`,
  `filedlg.c` (+678), `itemdlg.c` (+714), `portal_dbus.c` (+1193, new),
  `unixlib.c` (new), `unixlib.h` (new), plus `include/wine/appdefaults.h` (new)
  and its `include/Makefile.in` registration.
- **ntdll + wineserver (CPU topology, threads, mounts):**
  `dlls/ntdll/unix/{file.c,server.c,system.c,thread.c,unix_private.h}`,
  `server/{process.c,process.h,protocol.def,ptrace.c,request_handlers.h,request_trace.h,thread.c,thread.h,trace.c}`,
  `include/wine/server_protocol.h`.
- **win32u + winex11.drv + user32 (windows, DnD, menus):**
  `dlls/win32u/{clipboard.c,menu.c,message.c,window.c}`,
  `dlls/winex11.drv/{event.c,window.c,x11drv.h}`,
  `dlls/user32/clipboard.c`, `dlls/user32/tests/menu.c`, `include/ntuser.h`.
- **Rendering / runtime fixes:** `dlls/dxgi/output.c` + `dlls/dxgi/tests/dxgi.c`,
  `dlls/msvcp140/msvcp140.spec` + `dlls/msvcp140/tests/msvcp140.c`,
  `dlls/msvcp90/ios.c`.

## Applying the patch

The installer applies the patch for you (see [../installer.md](../installer.md));
`scripts/bootstrap-wine.sh` does the work. Notable properties of that script:

- It clones Wine with `--filter=blob:none` into a temporary path and moves it
  into place only on success, so an interrupted clone never leaves a
  half-populated `wine/` tree.
- It detaches to the pinned revision, fetching it first if the local checkout
  does not have it.
- It applies the patch **idempotently**: if the tree is already patched
  (`git apply --reverse --check` succeeds) it verifies, via a throwaway git
  index, that the working tree matches the patch exactly and then exits 0. It
  refuses to proceed if the tree has changes that are not exactly the ENCORE
  patch.

## Rebasing onto a newer Wine revision

When moving to a newer upstream Wine:

1. Update `WINE_REVISION` in `scripts/common.sh` **and** `install.sh` (they must
   match — `wine_build_ready()` compares the build stamp against `install.sh`'s
   value).
2. Regenerate `patches/encore-wine.patch` against the new revision.
3. Confirm `build-wine.sh` still finds every required `SONAME_*` define and DLL
   artifact (it hard-fails otherwise).
4. Confirm the reported version string in `build-wine.sh` and
   `wine_build_ready()` (currently `wine-11.13`).
5. Refresh the canonical facts table above and re-verify each feature page's
   function references — hunk locations drift on rebase.
