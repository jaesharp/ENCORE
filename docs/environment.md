# Environment variable reference

ENCORE is configured largely through environment variables. `ENCORE_*` are
ENCORE's own knobs (read by the scripts, and a few directly by the patched Wine);
`WINE_*` and standard Wine variables are consumed by Wine at runtime. Unless
noted, launcher defaults are applied by `scripts/run-ableton.sh`. "Consumer =
patch" means the value is read via `getenv()` inside the `patches/wine/` series;
those are documented in depth on the linked feature pages.

## Precedence

For the launcher paths (prefix / Wine / Ableton):
**command-line option > environment variable > `.encore/runtime.conf`**.
`load-runtime-config.sh` fills a path variable from `runtime.conf` only when it
isn't already set.

## Path selection

| Variable | Default | Consumer | Effect |
| --- | --- | --- | --- |
| `ENCORE_PREFIX` | `./ableton-prefix` | scripts | Wine prefix directory. |
| `ENCORE_WINE` | `./runtime/wine/bin/wine`, falling back to `./build/wine64/wine` | scripts | ENCORE Wine executable (prebuilt runtime, else source build). |
| `ENCORE_ABLETON` | resolved from the prefix via `ableton-profile.sh` | scripts | Live executable; auto-detected for the installed edition (Live 11/12). |
| `ENCORE_RUNTIME_ROOT` | `./runtime/wine` | scripts | Where the prebuilt runtime is installed/validated. |
| `ENCORE_RUNTIME_CONFIG` | `<repo>/.encore/runtime.conf` | scripts | Override the runtime-config path the launcher reads. |

## Launcher runtime toggles

All read by `run-ableton.sh`; the VST3/menu/min-size ones are acted on inside
the patch.

| Variable | Default | Consumer | Effect |
| --- | --- | --- | --- |
| `ENCORE_NATIVE_VST3_DECORATIONS` | `1` | patch | Real title bars/decorations for VST3 plug-in windows. See [windowing-and-hidpi.md](patches/windowing-and-hidpi.md). |
| `ENCORE_NATIVE_VST3_DPI` | `1` | patch | Per-monitor DPI awareness for VST3 windows. |
| `ENCORE_VST3_RESIZE_REPAINT` | `1` | patch | Repaint VST3 windows on resize. |
| `ENCORE_ABLETON_MENU_THEME` | `1` | patch | Sample Live's menu-bar colour and theme the Win32 bar. See [menu-theming.md](patches/menu-theming.md). |
| `ENCORE_X11_MIN_VISIBLE_SIZE` | `800x643` | patch | Minimum visible size hint (`WxH`, logical px). |
| `ENCORE_CPU_TOPOLOGY` | *(computed)* | scripts → `WINE_CPU_TOPOLOGY` | Overrides the CPU topology; else `WINE_CPU_TOPOLOGY`, else `select-cpu-topology.sh`. See [cpu-and-threads.md](patches/cpu-and-threads.md). |
| `ENCORE_WEBVIEW2_FLAGS` | see below | scripts → `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` | Complete override of the launcher's WebView2/Chromium flags; empty disables them. |
| `ENCORE_DRY_RUN` | `0` | scripts | `1` prints the full computed environment and exits without launching. |
| `ENCORE_LIVE_GPU` | `0` | launcher | `1` opts out of forcing Live's GDI backend (leaves `Options.txt`'s `-_ForceGdiBackend` unset). Default `0` forces GDI, because Live's GPU/GL renderer misrenders the session view under Wine. |

Default `ENCORE_WEBVIEW2_FLAGS`:

```
--use-gl=angle --use-angle=swiftshader --disable-gpu-compositing
--disable-gpu-rasterization --disable-direct-composition
--disable-features=ForceSWDCompWhenDCompFallbackRequired
--edge-webview-foreground-boost-opt-out --no-sandbox
```

## Prefix-configuration and diagnostic variables

| Variable | Default | Consumer | Effect |
| --- | --- | --- | --- |
| `ENCORE_DPI_MODE` | `auto` | `configure-prefix.sh` | DPI policy. `auto` detects the display scale (`detect-scale.sh`) and applies the calibrated block: `100` = LogPixels 96 + awareness off; `hidpi` = LogPixels 192 + IFEO `dpiAwareness=2`. `preserve` leaves the prefix untouched; `100`/`hidpi` force a block. Uncalibrated scales and custom prefix values are preserved under `auto`. The installer runs this stage with `preserve` — its own display-scaling stage (`set-dpi.sh`) follows and is authoritative there. |
| `ENCORE_CHECK_TIMEOUT` | `180` | `check-live-audio.sh` | Seconds to wait for Live to open the audio driver before failing. |

## Wine variables ENCORE sets or honours

| Variable | Value ENCORE uses | Consumer | Effect |
| --- | --- | --- | --- |
| `WINE_CPU_TOPOLOGY` | computed / your override | patch | Proton-compatible CPU topology override. See [cpu-and-threads.md](patches/cpu-and-threads.md). |
| `WINE_DISABLE_UNIX_MOUNT_REPARSE` | `1` | patch | Stop reporting Unix mount points as reparse points. See [runtime-fixes.md](patches/runtime-fixes.md). |
| `WINE_FORCE_PORTAL` | *(unset)* | patch | `1` forces the xdg-desktop-portal file chooser regardless of `FileDialogPortal`. See [portal-file-picker.md](patches/portal-file-picker.md). |
| `WINEDLLOVERRIDES` | appends `mscoree,mshtml,winemenubuilder.exe,dcomp=` | Wine | Disables Mono/Gecko/menu-builder and DirectComposition. Your value comes first; ENCORE's are appended. |
| `WINEPREFIX` | `<prefix>` | Wine | Standard prefix selector. |
| `WINEDEBUG` | `-all` (unless set) | Wine | Standard debug channel control. |
| `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` | your value + ENCORE flags | Wine WebView2 | Extra Chromium arguments; ENCORE's are appended. |

## WineASIO variables (when built)

Set by the launcher only when `runtime/wineasio/` is present; override in the
environment before launch. See [wineasio.md](wineasio.md).

| Variable | Default | Effect |
| --- | --- | --- |
| `WINEASIO_NUMBER_INPUTS` / `_OUTPUTS` | `2` | ASIO input/output channel counts exposed to Live. |
| `WINEASIO_FIXED_BUFFERSIZE` | `on` | Lock the buffer size to the backend's. |
| `WINEASIO_PREFERRED_BUFFERSIZE` | `256` | Buffer size in frames; raise to `512` if you hear crackles. |
| `WINEASIO_CONNECT_TO_HARDWARE` | `on` | Auto-connect WineASIO's ports to the hardware ports. |
| `WINEDLLPATH` | `runtime/wineasio` prepended | Where Wine finds the WineASIO Unix builtin; ENCORE prepends its directory. |

## Runtime download and build overrides

Read from `scripts/common.sh` (mostly for advanced/CI use):

| Variable | Default | Effect |
| --- | --- | --- |
| `ENCORE_RUNTIME_SHA256` | pinned in `common.sh` | Expected SHA-256 of the prebuilt runtime archive. |
| `ENCORE_RELEASE_BASE_URL` | GitHub release URL for `ENCORE_RELEASE_VERSION` | Where `download-wine-runtime.sh` fetches the runtime. |
| `WINE_INSTALL_PREFIX` | `/opt/encore-wine` | `--prefix` the source build configures against. |
| `WINE_SOURCE` / `WINE_BUILD` | `./wine` / `./build/wine64` | Source checkout / build tree for source builds. |
| `SOURCE_DATE_EPOCH` | `WINE_SOURCE_DATE_EPOCH` | Reproducible-build timestamp for source builds. |

## Install-time variables

| Variable | Corresponding flag | Effect |
| --- | --- | --- |
| `DPI` | `--dpi` | Default Wine DPI. |
| `JOBS` | `--jobs` | Default parallel build jobs (source build). |
| `NO_COLOR` / `TERM` | `--no-color` | Standard colour suppression. |
| `ENCORE_PACKAGE_FAMILY` | *(auto-detected)* | Force `apt`, `dnf`, or `pacman`. |
| `ENCORE_GITHUB_REPOSITORY` | `wowitsjack/ENCORE` | Repository for the optional star prompt. |

## Inspecting effective settings

```sh
ENCORE_DRY_RUN=1 scripts/run-ableton.sh
```

Prints `WINEPREFIX`, `WINE`, `ABLETON`, `WINEDLLOVERRIDES`,
`WINE_DISABLE_UNIX_MOUNT_REPARSE`, every `ENCORE_*` toggle, `WINE_CPU_TOPOLOGY`,
and `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`, then exits.
