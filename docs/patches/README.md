# The ENCORE Wine patch

The numbered patch series under [`patches/wine/`](../../patches/wine/) is the
complete source delta that turns an upstream Wine checkout into "ENCORE Wine" —
the runtime that runs Ableton Live 11 and 12. It is the intellectual core of the
project: everything else in the repository exists to build, apply, verify, or
configure these patches.

The default install **builds from source**: `bootstrap-wine.sh` applies the
series to the pinned checkout. The opt-in prebuilt runtime (`--prebuilt`) was
built from the series as of its `r1` snapshot; its `.encore-runtime` manifest
records that snapshot's combined SHA-256 and is checked before activation (see
[../building.md](../building.md)) — patches added since `r1` (the shibco ports,
`31` and `70`–`150`) are only in source builds until a runtime is republished.

## Canonical build facts

These values are defined here and referenced from every other document. If they
change, change them here first.

| Fact | Value | Defined in |
| --- | --- | --- |
| Pinned upstream revision | `6eb2e4c32cc9e271856146df11ed3a5c2cf29234` | `scripts/common.sh`, `install.sh` (`WINE_REVISION`) |
| Upstream remote | `https://gitlab.winehq.org/wine/wine.git` | `scripts/common.sh` (`WINE_REMOTE`) |
| Resulting version string | `wine-11.13` | verified by `build-wine.sh`, `download-wine-runtime.sh`, and `wine_build_ready()` |
| Prebuilt runtime revision | `r1` (`encore-wine-11.13-r1-…`) | `scripts/common.sh` (`ENCORE_RUNTIME_REVISION`) |
| Patch series | 16 files, `patches/wine/NN-*.patch` | `ls patches/wine/` |
| Series size | 59 Wine files, 6118 insertions, 213 deletions | `git apply --numstat patches/wine/*.patch` |
| Combined identity | `bf918c6b3750fa8ed6bfa6eeaed29063d8d02a9c269b3d516478db83670c2a1c` | `cat patches/wine/*.patch \| sha256sum` (`encore_patch_sha256` in `common.sh`) |

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
applied by `bootstrap-wine.sh` in shell-glob (lexical) order — `100` sorts before
`20`; the patches are disjoint enough that order carries no meaning. Six
subsystems (`10`–`60`) are ENCORE's original delta; the remaining ten (`31` and
`70`–`150`) are ported from **shibco/ableton-linux** (LGPL — the same license as
Wine, confirmed by the maintainer; attributed in each patch header and page) via
the `shibco-dev` integration branch. Each subsystem has its own page.

| Page | Features | Primary source |
| --- | --- | --- |
| [portal-file-picker.md](portal-file-picker.md) | Native xdg-desktop-portal file chooser | `dlls/comdlg32/*` |
| [cpu-and-threads.md](cpu-and-threads.md) | `WINE_CPU_TOPOLOGY` override; stale-thread recovery | `dlls/ntdll/unix/*`, `server/*` |
| [windowing-and-hidpi.md](windowing-and-hidpi.md) | VST3 plugin windows; HiDPI config-rounding; custom-NC decoration gate | `dlls/win32u/*`, `dlls/winex11.drv/*` |
| [windowing-nspa.md](windowing-nspa.md) | Reentrant `WM_WINDOWPOSCHANGED` suppression (HiDPI resize loop) *(shibco)* | `dlls/win32u/{window.c,ntuser_private.h}` |
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

## Full diffstat

Regenerate at any time with:

```sh
git apply --stat patches/wine/*.patch
```

The series touches 59 distinct Wine source files. Per-feature file lists live on
each feature page; the largest single subsystems are the portal file picker
(`10`, ~3100 lines across `dlls/comdlg32/*`), CPU topology + stale-thread
recovery (`20`, `dlls/ntdll/unix/*` + `server/*`), and the windowing/HiDPI work
(`30`/`31`, `dlls/win32u/*` + `dlls/winex11.drv/*`).

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
2. Regenerate the `patches/wine/` series against the new revision (each file
   must apply independently with `git apply`, and the whole set in one
   `git apply --cached` invocation — no two patches may edit the same function).
3. Confirm `build-wine.sh` still finds every required `SONAME_*` define and DLL
   artifact (it hard-fails otherwise).
4. Confirm the reported version string in `build-wine.sh` and
   `wine_build_ready()` (currently `wine-11.13`).
5. Refresh the canonical facts table above and re-verify each feature page's
   function references — hunk locations drift on rebase.
