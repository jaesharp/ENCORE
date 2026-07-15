# Glossary

Terms used across the ENCORE documentation, defined once.

- **AppDefaults** — Wine registry mechanism
  (`HKCU\Software\Wine\AppDefaults\<exe>\…`) for per-application settings that
  override the global values. ENCORE uses it to enable the portal file picker
  for the imported Live executable only.
- **build stamp** — `build/wine64/.encore-build`; records the Wine revision and
  patch SHA-256 of a completed **source** build so the installer can reuse it.
- **CF_HDROP / `WM_DROPFILES`** — the Win32 clipboard format and message pair
  used to hand a list of dropped file paths to a window.
- **cpuset / affinity** — Linux mechanisms limiting which CPUs a process may run
  on (`sched_getaffinity`, cgroup cpusets). ENCORE's CPU topology override
  composes with them.
- **DPI awareness context** — per-window/thread Win32 setting for display
  scaling (unaware, system, per-monitor). Coordinates must be converted *in the
  right context* or they land in the wrong place.
- **`.encore-runtime` manifest** — the `ENCORE_WINE_RUNTIME_V1` metadata file
  inside a prebuilt runtime, recording the ENCORE runtime version, Wine version
  and revision, patch SHA-256, arch, PE arches, and max glibc. Verified before
  the runtime is activated.
- **glibc** — the GNU C library. The prebuilt runtime requires the host glibc
  to be **≥ 2.35** (older hosts must build from source).
- **`IDropTarget` / OLE drag-and-drop** — COM interface a window registers to
  receive drags (`DragEnter`/`DragOver`/`Drop`/`DragLeave`).
- **`IFileDialog` / item dialog** — the Vista-style COM file dialog API
  (`IFileDialog2`, `IShellItem`), the modern alternative to `GetOpenFileNameW`.
- **`Installation.cfg`** — a file inside a Live `Program/` folder whose `variant`
  names the edition; ENCORE checks it matches the folder and executable.
- **Learn View** — Live 12's built-in lessons pane, rendered by an embedded
  Microsoft Edge **WebView2** (Chromium) inside the prefix.
- **MWM hints** — `_MOTIF_WM_HINTS`; the X11 property telling the window manager
  which decorations a window wants.
- **ntsync** — a Linux kernel synchronisation primitive Wine can use for faster,
  more correct Windows sync objects. ENCORE builds Wine with the ntsync uAPI
  headers under `packaging/uapi` (`HAVE_LINUX_NTSYNC_H`).
- **P-core / E-core, SMT** — performance/efficiency cores on hybrid CPUs; SMT
  puts two logical CPUs on one physical core. The topology override prefers
  distinct P-cores.
- **PE / Unix split, unixlib** — modern Wine architecture: Windows-facing code
  is built as PE binaries; host-facing code lives in native `.so` "unixlibs"
  (marked `#pragma makedep unix`) called through `__wine_unix_call`.
- **portal (xdg-desktop-portal)** — DBus service (`org.freedesktop.portal.*`)
  exposing desktop facilities (file chooser, …) to sandboxed or foreign apps;
  per-desktop backends (`-gnome`, `-kde`, `-gtk`).
- **prebuilt runtime** — the verified, pinned patched-Wine tarball ENCORE
  downloads with `--prebuilt` and installs to `runtime/wine/`, avoiding a local
  compile. Produced by `package-wine-release.sh` / CI.
- **prefix (`WINEPREFIX`)** — a Wine "bottle": a directory with a fake `C:`
  drive, registry, and per-app state. ENCORE's default is `./ableton-prefix`.
- **reflink** — a copy-on-write file clone (`cp --reflink=auto`) used when
  importing the Live folder on filesystems that support it, making the copy fast
  and space-efficient.
- **reparse point** — NTFS metadata making a file/directory behave like a link
  or mount (`IO_REPARSE_TAG_MOUNT_POINT`); read via `FSCTL_GET_REPARSE_POINT`.
- **SwiftShader** — Chromium's CPU-based Vulkan/GL implementation; used by the
  Learn View because DirectComposition/GPU compositing is disabled.
- **Visual C++ redistributable** — the Microsoft VC++ runtime (`vcruntime140`,
  `msvcp140`, …) Live requires. ENCORE installs it from the `Redist/` folder
  inside your imported Live folder.
- **VST3** — Steinberg plug-in standard; Live hosts VST3 editors in windows of
  class `Vst3PlugWindow`.
- **WebView2 runtime** — Microsoft Edge WebView2 (Chromium), required by Live
  12's Learn View. ENCORE installs it from the Live 12 `Redist/` bootstrapper
  (needs internet).
- **wineserver** — the per-prefix Unix daemon implementing Windows kernel
  semantics (handles, threads, synchronisation) for all Wine processes.
- **`WINEDLLOVERRIDES`** — control over which DLLs Wine loads. ENCORE disables
  `mscoree`, `mshtml`, `winemenubuilder.exe`, and `dcomp`.
- **WoW64 (new WoW64)** — running 32-bit Windows code on a 64-bit Wine by
  building both `i386` and `x86_64` PE DLLs in one 64-bit tree
  (`--enable-archs=i386,x86_64`), with no 32-bit host libraries. Required for
  Live's 32-bit components.
- **XDND** — the X11 drag-and-drop protocol Wine translates into OLE
  drag-and-drop.
- **XID** — an X11 resource identifier; Wine exposes a window's backing X11
  window via the `__wine_x11_whole_window` property, used to parent portal
  dialogs.
- **Xwayland** — the X11 compatibility server inside a Wayland session; ENCORE's
  primary tested display path.
